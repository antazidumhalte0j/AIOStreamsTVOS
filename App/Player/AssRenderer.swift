import AetherHost
import CoreGraphics
import Foundation
import SwiftLibass

/**
 * libass drawing an ASS/SSA track, as mpv drew them: the file's styles,
 * positioning, animation, karaoke, drawings and fonts, which the overlay's own
 * text drawing doesn't attempt.
 *
 * The engine hands over the track's header (`[Script Info]` and
 * `[V4+ Styles]`) and its events as Matroska event lines
 * (`ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text`), which is
 * what libass's `ass_process_chunk` reads, so events go in as they arrive.
 *
 * Every libass call runs on one serial queue; the rest is the main thread's.
 * Renders are coalesced: while one runs, only the latest request waits.
 */
final class AssRenderer: @unchecked Sendable {
    /// Where libass draws, in pixels: the screen, with the picture inside it.
    struct Layout: Equatable {
        var frameWidth: Int32
        var frameHeight: Int32
        /// The picture's edges from the frame's: negative when the picture runs off it (crop).
        var top: Int32
        var bottom: Int32
        var left: Int32
        var right: Int32
        /// Cues not placed by the script may use the whole frame, so they stay on screen when cropped.
        var useMargins: Bool
        /// The page's subtitle scale, as mpv's `sub-scale` applies it to ASS, on dialogue only.
        var fontScale: Double
        /// The page's subtitle height, as mpv gives libass its `sub-pos` (`100 - sub-pos`): percent of the
        /// picture that dialogue without a position of its own moves up from the bottom, 0 leaving it.
        var linePosition: Double

        /// The video's own size, as it's stored (anamorphic too), as mpv and the Android app give libass its
        /// storage size: `\blur`, and borders and shadows with `ScaledBorderAndShadow: no`, scale from it.
        /// 0 when not known yet: the picture's size on screen stands in.
        var videoWidth: Int32
        var videoHeight: Int32

        /// The page's look, when it forces its style on the file's (mpv's `sub-ass-override=force`); nil keeps the file's.
        var forced: ForcedStyle?

        var pictureWidth: Int32 { frameWidth - left - right }
        var pictureHeight: Int32 { frameHeight - top - bottom }
    }

    /**
     * The page's look as libass's override style, as the Android app's ExoPlayer path and mpv force it:
     * font, sizes, colours, border and blur, on dialogue only. libass leaves an event placed by the script
     * (`\pos`, `\move` and the like) its own style, so signs keep theirs where the script put them.
     */
    struct ForcedStyle: Equatable {
        /// A family libass finds: the device's through CoreText, or one of the app's (`SubtitleFonts.files`).
        var fontName: String
        var bold: Bool
        /// ASS's colours: `RRGGBBAA`, the alpha byte as transparency.
        var color: UInt32
        var outlineColor: UInt32
        /// The box's colour with a box; the shadow's otherwise, as ASS draws the shadow in it.
        var backColor: UInt32
        var boxed: Bool
        /// In units of a 720-line screen, the page's and the text drawing's own.
        var fontSize: Double
        var outline: Double
        var shadow: Double
        var margin: Double
    }

    enum Output {
        /// What's drawn still stands.
        case unchanged
        /// Nothing to draw now.
        case empty
        /// One picture of everything showing, and where it goes in the frame, in pixels.
        case frame(CGImage, CGRect)
    }

    private let queue = DispatchQueue(label: "io.github.aiostreams.ass", qos: .userInteractive)

    // Queue only, after `init`.
    private var library: OpaquePointer?
    private var renderer: OpaquePointer?
    private var track: UnsafeMutablePointer<ASS_Track>?
    private var applied: Layout?

    // Main thread only.
    /// The file's fonts libass has now, by name and size, so the next episode's same set isn't added again.
    private var fontKeys: [String] = []
    private var generation = 0
    /// Events given to the track, so a re-published cue list adds only what's new.
    private var seen = Set<String>()
    private var busy = false
    private var pending: Job?

    private struct Job {
        let milliseconds: Int64
        let layout: Layout
        let generation: Int
        let completion: (Output) -> Void
    }

    init() {
        start(fonts: [])
    }

    deinit {
        stop()
    }

    /// A new library and renderer with the file's fonts. Queue only, or `init`.
    private func start(fonts: [FontAttachment]) {
        library = ass_library_init()
        renderer = library.flatMap { ass_renderer_init($0) }
        applied = nil
        guard let library, let renderer else {
            NSLog("[subtitles] libass did not start")
            return
        }
        // libass's errors in the log, as the Android app keeps them (levels 0 and 1); its notes, as each
        // font it picks, would fill it.
        ass_set_message_cb(library, { level, format, arguments, _ in
            guard level <= 1, let format, let arguments else { return }
            var text = [CChar](repeating: 0, count: 512)
            let message = text.withUnsafeMutableBufferPointer { buffer -> String in
                _ = vsnprintf(buffer.baseAddress, buffer.count, format, arguments)
                return String(cString: buffer.baseAddress!)
            }
            NSLog("[subtitles] libass: %@", message)
        }, nil)
        // Fonts a script carries in its own [Fonts] section.
        ass_set_extract_fonts(library, 1)
        // The fonts the file carries as attachments, as mpv gives libass a Matroska's: the signs and
        // typesetting of anime releases name families only these have; and the app's own faces, which the
        // page's style can force (Casual, Cursive), as tvOS has none of its own. libass copies the bytes.
        let all = fonts.map { (name: $0.filename, data: $0.data) } + SubtitleFonts.fileData
        for font in all {
            var bytes = [CChar](repeating: 0, count: font.data.count)
            bytes.withUnsafeMutableBytes { target in _ = font.data.copyBytes(to: target) }
            font.name.withCString { name in
                let name = strdup(name)
                defer { free(name) }
                bytes.withUnsafeMutableBufferPointer { buffer in
                    ass_add_font(library, name, buffer.baseAddress, Int32(buffer.count))
                }
            }
        }
        // tvOS's own fonts through CoreText, with Helvetica Neue in place of a family neither has,
        // and CoreText's fallback for characters the chosen font lacks.
        ass_set_fonts(renderer, nil, "Helvetica Neue", Int32(ASS_FONTPROVIDER_CORETEXT.rawValue), nil, 0)
        // The font scale only sizes what looks like dialogue, so signs and other typesetting keep
        // the size and place the script gave them.
        ass_set_selective_style_override_enabled(renderer, Int32(ASS_OVERRIDE_BIT_SELECTIVE_FONT_SCALE.rawValue))
    }

    /// Frees the track, renderer and library, in that order: libass lets go of fonts only with all three gone.
    private func stop() {
        if let track { ass_free_track(track) }
        if let renderer { ass_renderer_done(renderer) }
        if let library { ass_library_done(library) }
        track = nil
        renderer = nil
        library = nil
    }

    // MARK: The fonts

    /**
     * The playing file's attached fonts. A different set from the last
     * file's starts libass over with them, dropping the track: returns true
     * then, and the caller loads the track again. The same set keeps all.
     */
    @discardableResult
    func setFonts(_ fonts: [FontAttachment]) -> Bool {
        let keys = fonts.map { "\($0.filename)|\($0.data.count)" }
        guard keys != fontKeys else { return false }
        fontKeys = keys
        generation += 1
        seen.removeAll()
        let total = fonts.reduce(0) { $0 + $1.data.count }
        NSLog("[subtitles] \(fonts.count) attached fonts for libass (\(total / 1024) KB)")
        queue.async { [self] in
            stop()
            start(fonts: fonts)
        }
        return true
    }

    // MARK: The track

    /// Starts a new track from its header, dropping the old one's events.
    func load(header: String) {
        generation += 1
        seen.removeAll()
        // MKV CodecPrivate is often NUL-terminated, and libass reads it as a C string.
        let bytes = Array(header.replacingOccurrences(of: "\0", with: "").utf8)
        queue.async { [self] in
            if let track { ass_free_track(track) }
            track = library.flatMap { ass_new_track($0) }
            guard let track else { return }
            bytes.withUnsafeBufferPointer { buffer in
                buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                    ass_process_codec_private(track, $0, Int32(buffer.count))
                }
            }
            // Many files number every event 0, so ReadOrder can't tell repeats apart; `seen` does.
            ass_set_check_readorder(track, 0)
        }
    }

    func unload() {
        generation += 1
        seen.removeAll()
        queue.async { [self] in
            if let track { ass_free_track(track) }
            track = nil
        }
    }

    /// Gives the track the cues' events it hasn't had. A cue may hold several, one per line.
    func add(_ cues: [SubtitleCueEvent]) {
        var fresh: [(bytes: [UInt8], start: Int64, duration: Int64)] = []
        for cue in cues {
            for line in cue.text.split(separator: "\n", omittingEmptySubsequences: true) {
                let key = "\(cue.start)|\(cue.end)|\(line)"
                guard seen.insert(key).inserted else { continue }
                let start = Int64((cue.start * 1000).rounded())
                let duration = max(0, Int64((cue.end * 1000).rounded()) - start)
                fresh.append((Array(line.utf8), start, duration))
            }
        }
        guard !fresh.isEmpty else { return }
        queue.async { [self] in
            guard let track else { return }
            for event in fresh {
                event.bytes.withUnsafeBufferPointer { buffer in
                    buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                        ass_process_chunk(track, $0, Int32(buffer.count), event.start, event.duration)
                    }
                }
            }
        }
    }

    // MARK: Drawing

    /// Draws the track at `milliseconds`; `completion` gets the result on the main thread,
    /// unless the track has been replaced in the meantime.
    func render(at milliseconds: Int64, layout: Layout, completion: @escaping (Output) -> Void) {
        pending = Job(milliseconds: milliseconds, layout: layout, generation: generation, completion: completion)
        if !busy { runPending() }
    }

    private func runPending() {
        guard let job = pending else {
            busy = false
            return
        }
        pending = nil
        busy = true
        queue.async { [self] in
            let output = draw(at: job.milliseconds, layout: job.layout)
            DispatchQueue.main.async { [self] in
                if job.generation == generation { job.completion(output) }
                runPending()
            }
        }
    }

    /// Queue only.
    private func draw(at milliseconds: Int64, layout: Layout) -> Output {
        guard let renderer, let track else { return .empty }
        guard layout.frameWidth > 0, layout.frameHeight > 0,
              layout.pictureWidth > 0, layout.pictureHeight > 0 else { return .empty }
        if applied != layout {
            applied = layout
            ass_set_frame_size(renderer, layout.frameWidth, layout.frameHeight)
            // The video's own size; libass works the pixel aspect out from it and the picture's place.
            let stored = layout.videoWidth > 0 && layout.videoHeight > 0
            ass_set_storage_size(renderer, stored ? layout.videoWidth : layout.pictureWidth,
                                 stored ? layout.videoHeight : layout.pictureHeight)
            ass_set_margins(renderer, layout.top, layout.bottom, layout.left, layout.right)
            ass_set_use_margins(renderer, layout.useMargins ? 1 : 0)
            ass_set_font_scale(renderer, layout.fontScale)
            ass_set_line_position(renderer, layout.linePosition)
            override(layout.forced, renderer: renderer)
        }
        var changed: Int32 = 0
        let started = DispatchTime.now().uptimeNanoseconds
        let images = ass_render_frame(renderer, track, milliseconds, &changed)
        if changed == 0 { return .unchanged }
        let rendered = DispatchTime.now().uptimeNanoseconds
        let composed = Self.compose(images)
        noteTiming(render: rendered - started, compose: DispatchTime.now().uptimeNanoseconds - rendered,
                   pixels: composed.map { Int($0.rect.width * $0.rect.height) } ?? 0)
        guard let composed else { return .empty }
        return .frame(composed.image, composed.rect)
    }

    /// Queue only. The font scale always sizes dialogue alone; forced, the page's look goes on it too.
    private func override(_ forced: ForcedStyle?, renderer: OpaquePointer) {
        var bits = ASS_OVERRIDE_BIT_SELECTIVE_FONT_SCALE.rawValue
        if let forced {
            bits |= ASS_OVERRIDE_BIT_FONT_NAME.rawValue | ASS_OVERRIDE_BIT_FONT_SIZE_FIELDS.rawValue
                | ASS_OVERRIDE_BIT_COLORS.rawValue | ASS_OVERRIDE_BIT_BORDER.rawValue
            // The Android app also forces the blur (ASS_OVERRIDE_BIT_BLUR), which libass 0.17.3 doesn't have.
            // libass reads the override style as set for a 288-line script, the page's sizes being 720 lines'.
            let units = 288.0 / 720.0
            var style = ASS_Style()
            style.FontSize = forced.fontSize * units
            style.PrimaryColour = forced.color
            style.SecondaryColour = forced.color
            style.OutlineColour = forced.outlineColor
            style.BackColour = forced.backColor
            style.Bold = forced.bold ? 1 : 0
            style.ScaleX = 1
            style.ScaleY = 1
            // mpv's outline-and-shadow and background box.
            style.BorderStyle = forced.boxed ? 4 : 1
            style.Outline = forced.outline * units
            style.Shadow = forced.shadow * units
            style.Alignment = 2
            let margin = Int32((forced.margin * units).rounded())
            style.MarginL = margin
            style.MarginR = margin
            style.MarginV = margin
            // libass keeps its own copy of the name.
            forced.fontName.withCString { name in
                style.FontName = UnsafeMutablePointer(mutating: name)
                ass_set_selective_style_override(renderer, &style)
            }
        }
        ass_set_selective_style_override_enabled(renderer, Int32(bits))
    }

    // MARK: Timings

    /// Queue only: the slowest frame since the last report, and how many went over a frame's time.
    private var slowest: (render: UInt64, compose: UInt64, pixels: Int) = (0, 0, 0)
    private var slowFrames = 0
    private var reportedAt: UInt64 = 0

    /**
     * Logs the frames libass and the blend took longer than a 24 Hz frame over (`[subtitles] slow`), at
     * most every 10 s, so heavy typesetting shows in the log as which part costs, before any of it
     * moves to the GPU, as the Android app counts its renders and blends.
     */
    private func noteTiming(render: UInt64, compose: UInt64, pixels: Int) {
        guard render + compose > Self.slowNanos else { return }
        slowFrames += 1
        if render + compose > slowest.render + slowest.compose { slowest = (render, compose, pixels) }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - reportedAt > 10_000_000_000 else { return }
        reportedAt = now
        NSLog("[subtitles] slow: \(slowFrames) frames over \(Self.slowNanos / 1_000_000) ms; slowest libass \(slowest.render / 1_000_000) ms, blend \(slowest.compose / 1_000_000) ms, \(slowest.pixels / 1000)k pixels")
        slowFrames = 0
        slowest = (0, 0, 0)
    }

    private static let slowNanos: UInt64 = 42_000_000

    /**
     * Lays libass's pieces (shadows, outlines, then fills, each an alpha mask
     * in one colour) over each other into one premultiplied RGBA picture.
     */
    private static func compose(_ first: UnsafeMutablePointer<ASS_Image>?) -> (image: CGImage, rect: CGRect)? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var node = first
        while let image = node?.pointee {
            if image.w > 0, image.h > 0, image.color & 0xff != 0xff {
                minX = min(minX, Int(image.dst_x))
                minY = min(minY, Int(image.dst_y))
                maxX = max(maxX, Int(image.dst_x) + Int(image.w))
                maxY = max(maxY, Int(image.dst_y) + Int(image.h))
            }
            node = image.next
        }
        guard minX < maxX, minY < maxY else { return nil }
        let width = maxX - minX
        let height = maxY - minY
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)

        node = first
        while let image = node?.pointee {
            defer { node = image.next }
            let w = Int(image.w), h = Int(image.h)
            guard w > 0, h > 0, let bitmap = image.bitmap else { continue }
            // RGBA, with the alpha byte as transparency.
            let color = image.color
            let opacity = 255 - (color & 0xff)
            guard opacity > 0 else { continue }
            let red = (color >> 24) & 0xff
            let green = (color >> 16) & 0xff
            let blue = (color >> 8) & 0xff
            let stride = Int(image.stride)
            let x0 = Int(image.dst_x) - minX
            let y0 = Int(image.dst_y) - minY
            for y in 0..<h {
                let source = bitmap + y * stride
                var target = pixels + (y0 + y) * rowBytes + x0 * 4
                for x in 0..<w {
                    let coverage = UInt32(source[x])
                    if coverage != 0 {
                        let alpha = (coverage * opacity + 127) / 255
                        let rest = 255 - alpha
                        target[0] = UInt8((red * alpha + UInt32(target[0]) * rest + 127) / 255)
                        target[1] = UInt8((green * alpha + UInt32(target[1]) * rest + 127) / 255)
                        target[2] = UInt8((blue * alpha + UInt32(target[2]) * rest + 127) / 255)
                        target[3] = UInt8(alpha + (UInt32(target[3]) * rest + 127) / 255)
                    }
                    target += 4
                }
            }
        }
        guard let picture = context.makeImage() else { return nil }
        return (picture, CGRect(x: minX, y: minY, width: width, height: height))
    }
}

/// One cue's events, as the engine timed them, in seconds of the source's clock.
struct SubtitleCueEvent {
    let text: String
    let start: Double
    let end: Double
}
