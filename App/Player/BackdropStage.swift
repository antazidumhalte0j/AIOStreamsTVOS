import UIKit

/**
 * The backdrop the page shows, the hero's or a title page's, drawn by the app at the screen's
 * full 4K in a view beneath the page (patches/web/0048, the page's `tvos-backdrop`). WebKit's
 * process, which holds the page's pictures, is ended for memory long before the app runs short:
 * a 3840-wide backdrop is 33 MB decoded, and the hero fading from one to the next held two or
 * three at once. Here it counts against the app instead.
 *
 * The page keeps its own copy at 1920 over this one until it's told the app's is drawn; then it
 * cuts a hole in its background over the art and hides its copy. Its text, shades and edges stay
 * drawn over the art by the page, as before. As the page scrolls it shows its copy again and puts
 * this away (`src: null`), as a view here can't follow a scroll frame by frame, and asks again
 * once it has held still.
 */
@MainActor
final class BackdropStage {
    /// Clips the art to the part of it the page shows; beneath the web view.
    let view = UIView()
    /// The page, whose measure the frames are in.
    weak var web: UIView?
    /// Tells the page a backdrop is drawn, so it can hide its own.
    var reply: (Message) -> Void = { _ in }
    /**
     * WebKit's scroll view for the page. WebKit runs its smooth scrolls here in the app's process,
     * and the page hears of them a frame or more later, longer while its thread is busy (a title
     * page mounting its rows as it scrolls): the art stayed where it was until the page put it
     * away. It follows the scroll from here meanwhile.
     */
    weak var scrollView: UIScrollView? {
        didSet {
            scrollWatch = scrollView?.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
                let y = scrollView.contentOffset.y
                MainActor.assumeIsolated { self?.scrolled(to: y) }
            }
        }
    }
    private var scrollWatch: NSKeyValueObservation?
    /// New art is on its way from the server, which the wash waits for (WashStage's `waitForArt`).
    var awaitingArt: Bool { loading != nil }
    /// New art began to show, or won't: the wash for the same title changes with it.
    var artShown: () -> Void = {}
    /// Where the page was scrolled to as the art was placed, in the scroll view's points.
    private var placedAt: CGFloat?

    /// The art in its box, and the one fading out under it.
    private var shown: UIImageView?
    private var leaving: UIImageView?
    /// Which of the page's backdrops this is (the page numbers each hero and title page it mounts).
    private var owner: Int?
    private var src: String?
    /// The art's box (`frame`) and the part of it shown (`clip`), in the container's points.
    private var box = CGRect.zero
    private var clip = CGRect.zero
    /// How the art's bottom and start fade into the wash beneath, when the app draws that too.
    private var edges: (bottom: CGFloat, start: CGFloat, rtl: Bool, frame: CGFloat)?
    /// What the mask in place was made for, so a new title with the same box keeps it.
    private var maskKey: String?
    /// The art `shown` holds, and the art on its way from the server.
    private var shownSrc: String?
    private var loading: String?
    /// Decoded art by address, the newest last: Back to a title or the hero coming round finds it ready.
    private var decoded: [(src: String, image: UIImage)] = []
    private static let keep = 3

    /// As the page's own layers fade (`duration-700`, and 400 ms from nothing).
    private static let fadeSeconds: TimeInterval = 0.7
    /// Putting the art away as the page scrolls: the two frames or so WebKit takes to show its own copy.
    private static let clearSeconds: TimeInterval = 2.0 / 60
    /// The art put away, held those frames, where it was and the scroll it was placed at.
    private var leavingGhost: UIView?
    private var ghostAt: (frame: CGRect, scroll: CGFloat) = (.zero, 0)
    /// The width the app draws a backdrop down to: the 4K screen's.
    private static let width = 3840

    init() {
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isHidden = true
    }

    /// The page's `tvos-backdrop`: a backdrop to draw where it says, or `src: null` to put it away.
    func handle(_ message: Message) {
        let id = Int(message.number("id") ?? 0)
        // The page hid its copy (patches/web/0057): the art, drawn unseen till now, shows a frame on,
        // as WebKit draws the page without the copy. Before that frame, they're both drawn.
        if message.flag("revealed") == true {
            guard owner == id, awaitingReveal else { return }
            awaitingReveal = false
            ArtLog.note("backdrop #\(id) shown as the page hid its copy")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.frameSeconds) { [weak self] in
                guard let self, self.owner == id, !self.awaitingReveal else { return }
                self.applyAlpha(animated: false)
            }
            return
        }
        guard let src = message.text("src"), let frame = message.object("frame"),
              let clip = message.object("clip"), let web, let container = view.superview else {
            // Only the backdrop that asked puts itself away: the next page's can ask first.
            let mine = owner == nil || owner == id
            ArtLog.note("backdrop #\(id) put away\(mine ? "" : " (ignored: #\(owner ?? 0) holds it)")")
            if mine { clear() }
            return
        }
        var scale: CGFloat = 1
        if let page = message.number("pageWidth"), page.isFinite, page > 0, web.bounds.width > 0 {
            scale = web.bounds.width / CGFloat(page)
        }
        func rect(_ object: Message) -> CGRect {
            func number(_ key: String) -> CGFloat {
                guard let value = object.number(key), value.isFinite else { return 0 }
                return CGFloat(min(max(value, -100_000), 100_000)) * scale
            }
            return container.convert(
                CGRect(x: number("x"), y: number("y"), width: max(0, number("width")), height: max(0, number("height"))),
                from: web
            )
        }
        let wasShown = owner == id && !view.isHidden && shown != nil
        owner = id
        box = rect(frame)
        self.clip = rect(clip)
        // Over the app's own wash the page's background is clear, so the art's edges fade here.
        let fadeIn = message.object("fade")
        // The backdrop frame's own fade in from its start, in the page's pixels (patches/web/0055).
        let frameFade: CGFloat = {
            guard let value = message.number("frameFade"), value.isFinite, value > 0 else { return 0 }
            return CGFloat(min(value, 10_000)) * scale
        }()
        edges = fadeIn.map {
            (bottom: CGFloat($0.number("bottom") ?? 0), start: CGFloat($0.number("start") ?? 0),
             rtl: message.flag("rtl") == true, frame: frameFade)
        }
        let fade = wasShown && message.flag("quick") != true && src != self.src
        ArtLog.note("backdrop #\(id) asked: \(src == self.src ? "same art" : "new art \(Self.short(src))")"
            + ", \(edges.map { _ in "with fades" } ?? "NO fades"), \(wasShown ? "over the last" : "from nothing")"
            + "\(fade ? ", to crossfade" : "")\(message.flag("hidden") == true ? ", hidden" : "")")
        self.src = src
        // A trailer playing in its place (patches/web/0051): the art fades off it, as the page's did, and
        // back once it ends, kept meanwhile so the page needn't bring its own copy back.
        pageHidden = message.flag("hidden") == true
        // From nothing, the page's copy shows over it: unseen until the page has hidden the copy.
        if message.flag("quick") == true && !wasShown { awaitingReveal = true }
        applyAlpha(animated: wasShown)
        if let image = decoded.first(where: { $0.src == src })?.image {
            show(image, src: src, fade: fade)
            drawn(id, src)
            return
        }
        // Asked again while it loads (the page asks again as its wash is drawn): the load on its way
        // shows it, where the page now says, with the crossfade the first ask began. A second load
        // made a second copy, shown at once over the crossfade, which cut it short: a flash.
        if loading == src { return }
        loading = src
        load(src) { [weak self] image in
            guard let self else { return }
            if self.loading == src { self.loading = nil }
            guard self.owner == id, self.src == src else { return self.artShown() }
            guard let image else {
                ArtLog.note("backdrop #\(id) art failed to load")
                return self.artShown()
            }
            ArtLog.note("backdrop #\(id) art loaded")
            self.remember(src, image)
            self.show(image, src: src, fade: fade)
            self.drawn(id, src)
        }
    }

    /// The page scrolled: the art moves with it, frame by frame, until the page puts it away.
    private func scrolled(to y: CGFloat) {
        if let ghost = leavingGhost {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ghost.frame = ghostAt.frame.offsetBy(dx: 0, dy: -(y - ghostAt.scroll))
            CATransaction.commit()
        }
        guard !view.isHidden, let placedAt else { return }
        let moved = y - placedAt
        guard abs(moved) >= 0.5 || view.frame.origin.y != clip.minY else { return }
        if abs(moved) >= 0.5, abs(view.frame.origin.y - clip.minY) < 0.5 {
            ArtLog.note("backdrop following WebKit's scroll ahead of the page")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = clip.offsetBy(dx: 0, dy: -moved)
        CATransaction.commit()
    }

    /// The end of an address, enough to tell titles apart in the log.
    private static func short(_ src: String) -> String {
        let path = URLComponents(string: src)?.path ?? src
        return "…" + String(path.suffix(28))
    }

    /// For the app menu: what's drawn, where, and how its edges fade.
    var summary: String {
        guard !view.isHidden, shown != nil else { return "none" }
        let fades = edges.map {
            "fades bottom \($0.bottom), start \($0.start)" + ($0.frame > 0 ? ", frame \(Int($0.frame)) pt" : "")
        } ?? "no fades"
        let place = "\(Int(clip.minX)),\(Int(clip.minY)) \(Int(clip.width))x\(Int(clip.height))"
        let mask = FadeMask.sample(view.layer.mask, clip: CGRect(origin: .zero, size: clip.size),
                                   rtl: edges?.rtl == true)
        return "shown at \(place), \(fades), \(mask), alpha \(String(format: "%.2f", view.alpha)), \(decoded.count) decoded"
    }

    /// A red wash over the art, from the app menu: the art on screen that isn't red is the page's
    /// own copy. Over the art and under its mask, so it fades as the art does.
    var tinted = false {
        didSet {
            tint.frame = view.bounds
            tint.isHidden = !tinted
            view.bringSubviewToFront(tint)
        }
    }
    private lazy var tint: UIView = {
        let tint = UIView(frame: view.bounds)
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Solid, so even where the art fades out it's red, not art: what shows art there is the page's.
        tint.backgroundColor = .red
        tint.isUserInteractionEnabled = false
        tint.isHidden = true
        view.addSubview(tint)
        return tint
    }()

    /// The page reloaded, or its process ended: nothing of its stays.
    func reset() {
        clear()
        decoded.removeAll()
    }

    private func clear() {
        owner = nil
        src = nil
        edges = nil
        maskKey = nil
        let pictures = [leaving, shown].compactMap { $0 }
        if !pictures.isEmpty { ArtLog.note("backdrop art put away") }
        leaving = nil
        shown = nil
        shownSrc = nil
        loading = nil
        placedAt = nil
        awaitingReveal = false
        pageHidden = false
        // Held on a copy of the view, over the frame WebKit takes to show the page as it is
        // now (its copy back, the hole closed): gone at once, what's beneath showed through the hole
        // for that frame. The view itself is free at once for the next ask.
        if !view.isHidden, view.alpha > 0, !pictures.isEmpty, let container = view.superview {
            let ghost = UIView(frame: view.frame)
            ghost.isUserInteractionEnabled = false
            ghost.clipsToBounds = true
            ghost.alpha = CGFloat(view.layer.presentation()?.opacity ?? Float(view.alpha))
            // A layer masks one layer at a time: off the view first.
            let mask = view.layer.mask
            view.layer.mask = nil
            ghost.layer.mask = mask
            for picture in pictures { ghost.addSubview(picture) }
            container.insertSubview(ghost, aboveSubview: view)
            // Held whole for the frames WebKit takes to show its copy again, moving with the scroll,
            // then gone at once. Faded out over a tenth of a second, it and the copy were both drawn
            // that long, doubling the art where both fade out: a lighter flash at its edges.
            leavingGhost?.removeFromSuperview()
            leavingGhost = ghost
            // Its frame already follows the scroll to now, so it moves on from where the scroll is.
            ghostAt = (frame: ghost.frame, scroll: scrollView?.contentOffset.y ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearSeconds) { [weak self, weak ghost] in
                ghost?.removeFromSuperview()
                if let self, self.leavingGhost === ghost { self.leavingGhost = nil }
            }
        } else {
            for picture in pictures { picture.removeFromSuperview() }
        }
        view.layer.mask = nil
        view.isHidden = true
        view.layer.removeAnimation(forKey: "opacity")
        view.alpha = 1
        // No art coming now: a wash waiting on it changes at once.
        artShown()
    }

    private func drawn(_ id: Int, _ src: String) {
        reply(["type": "tvos-backdrop", "id": id, "src": src, "drawn": true])
    }

    private func show(_ image: UIImage, src: String, fade: Bool) {
        view.frame = clip
        view.isHidden = false
        // Asked only once the page has held still, so this is where its measure was taken.
        placedAt = scrollView?.contentOffset.y
        if tinted { tint.frame = view.bounds }
        // Made again only when its size or fades change: each new title asks again with the same.
        // How far in from the clip's start edge the frame starts: its fade is measured from there.
        let frameAt = edges?.rtl == true ? clip.maxX - box.maxX : box.minX - clip.minX
        let maskKey = edges.map { "\(clip.size) \($0.bottom) \($0.start) \($0.rtl) \($0.frame) \(frameAt)" }
        if maskKey != self.maskKey || (maskKey != nil && view.layer.mask == nil) {
            ArtLog.note("backdrop mask \(maskKey == nil ? "taken OFF" : "made for \(Int(clip.width))x\(Int(clip.height))")")
            self.maskKey = maskKey
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer.mask = edges.map {
                FadeMask.layer(size: clip.size, clip: CGRect(origin: .zero, size: clip.size),
                               bottom: $0.bottom, start: $0.start, rtl: $0.rtl,
                               frameEdge: $0.frame > 0 ? (x: frameAt, width: $0.frame) : nil)
            }
            CATransaction.commit()
        }
        // The art covers its box from the top, as the page's `object-cover object-top`.
        let size = image.size
        let fill = max(box.width / max(size.width, 1), box.height / max(size.height, 1))
        let drawn = CGSize(width: size.width * fill, height: size.height * fill)
        let placed = CGRect(
            x: box.minX + (box.width - drawn.width) / 2 - clip.minX,
            y: box.minY - clip.minY,
            width: drawn.width,
            height: drawn.height
        )
        // The same art, already shown or fading in: only moved, whichever copy of it this is.
        if let shown, shownSrc == src {
            shown.frame = placed
            return
        }
        shownSrc = src
        let crossfade = fade && shown != nil && !cuts
        ArtLog.note("backdrop art shown \(crossfade ? "crossfading" : "at once")\(cuts && fade ? " (cuts on)" : "")")
        leaving?.removeFromSuperview()
        leaving = nil
        defer {
            if tinted { view.bringSubviewToFront(tint) }
            artShown()
        }
        guard let shown else {
            let next = UIImageView(image: image)
            next.frame = placed
            next.contentMode = .scaleToFill
            view.addSubview(next)
            shown = next
            return
        }
        // One picture view, dissolving from a snapshot of the last art into the new. Two pictures
        // stacked under the fade mask, the new one fading in over the old, flashed lighter at the
        // art's edges as a title changed with "Background from artwork" on (not with the art
        // tinted solid red, so in the pictures themselves).
        guard crossfade else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shown.image = image
            shown.frame = placed
            CATransaction.commit()
            return
        }
        UIView.transition(with: shown, duration: Self.fadeSeconds,
                          options: [.transitionCrossDissolve, .curveEaseOut, .beginFromCurrentState]) {
            shown.image = image
            shown.frame = placed
        }
    }

    /// From the app menu: a new title's art replaces the last at once, to tell the crossfade's part in a flash.
    var cuts = false

    /// A trailer plays in the art's place (the page's `hidden`).
    private var pageHidden = false
    /// Drawn from nothing while the page's copy still shows over it, waiting for the page to hide it.
    private var awaitingReveal = false
    /// About one frame of the screen's.
    private static let frameSeconds: TimeInterval = 1.0 / 60

    /// Seen only once the page has hidden its copy, and not while a trailer plays in its place.
    private func applyAlpha(animated: Bool) {
        let alpha: CGFloat = pageHidden || awaitingReveal ? 0 : 1
        guard view.alpha != alpha else { return }
        if animated {
            UIView.animate(withDuration: Self.fadeSeconds, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) { [view] in
                view.alpha = alpha
            }
        } else {
            view.layer.removeAnimation(forKey: "opacity")
            view.alpha = alpha
        }
    }

    private func remember(_ src: String, _ image: UIImage) {
        decoded.removeAll { $0.src == src }
        decoded.append((src, image))
        if decoded.count > Self.keep { decoded.removeFirst(decoded.count - Self.keep) }
    }

    /// The art at up to the screen's width, decoded off the main thread, asked of the server at that width.
    private func load(_ src: String, done: @escaping (UIImage?) -> Void) {
        guard var parts = URLComponents(string: src) else { return done(nil) }
        if let items = parts.queryItems,
           let asked = items.first(where: { $0.name == "maxWidth" }).flatMap({ Int($0.value ?? "") }),
           asked < Self.width {
            parts.queryItems = items.map { $0.name == "maxWidth" ? URLQueryItem(name: "maxWidth", value: String(Self.width)) : $0 }
        }
        guard let address = parts.url else { return done(nil) }
        ImageFit.fit(address, width: Self.width) { data, _ in
            let image = data.flatMap { UIImage(data: $0)?.preparingForDisplay() }
            DispatchQueue.main.async { done(image) }
        }
    }
}
