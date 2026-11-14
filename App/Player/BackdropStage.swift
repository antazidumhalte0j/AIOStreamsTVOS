import UIKit

/**
 * The backdrop the page shows, the hero's or a title page's, drawn by the app at the screen's
 * full 4K in a view beneath the page (patches/web/0048, the page's `tvos-backdrop`). WebKit's
 * process, which holds the page's pictures, is ended for memory long before the app runs short:
 * a 3840-wide backdrop is 33 MB decoded, and the hero fading from one to the next held two or
 * three at once. Here it counts against the app instead.
 *
 * The art is drawn here all the time, and follows the page's scroll here, frame by frame, from
 * WebKit's scroll view: WebKit scrolls the page in this process. The page loads no copy of its own
 * (only one the app can't load), and its background is clear, as the page's colour is drawn here
 * beneath it all (`tvos-page-color`), so the art shows through with no hole cut for it. The page's
 * text, shades and edges stay drawn over the art by the page. Swapped with a copy of the page's as
 * the page moved, the two were both drawn for a moment, which flashed at the art's edges.
 */
@MainActor
final class BackdropStage {
    /// Clips the art to its box; beneath the web view.
    let view = UIView()
    /// The page, whose measure the frames are in.
    weak var web: UIView?
    /// Tells the page a backdrop is drawn, or couldn't be.
    var reply: (Message) -> Void = { _ in }
    /// WebKit's scroll view for the page, whose scroll the art follows.
    weak var scrollView: UIScrollView? {
        didSet {
            scrollWatch = scrollView?.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
                let y = scrollView.contentOffset.y
                MainActor.assumeIsolated {
                    self?.lastScrolled = CACurrentMediaTime()
                    self?.scrolled(to: y)
                }
            }
        }
    }
    private var scrollWatch: NSKeyValueObservation?
    /// New art is on its way from the server, which the wash waits for (WashStage's `waitForArt`).
    var awaitingArt: Bool { loading != nil }
    /// New art began to show, or won't: the wash for the same title changes with it.
    var artShown: () -> Void = {}

    /// The art in its box.
    private var shown: UIImageView?
    /// Which of the page's backdrops this is (the page numbers each hero and title page it mounts).
    private var owner: Int?
    private var src: String?
    /// The art's box (`frame`) and the part of it within the page's art (`clip`), in the container's points.
    private var box = CGRect.zero
    private var clip = CGRect.zero
    /// How the art's bottom and start fade into the wash beneath, and the frame's own fade in.
    private var edges: (bottom: CGFloat, start: CGFloat, rtl: Bool, frame: CGFloat)?
    /// What the mask in place was made for, so a new title with the same box keeps it.
    private var maskKey: String?
    /// The art `shown` holds, and the art on its way from the server.
    private var shownSrc: String?
    private var loading: String?
    /// Decoded art by address, the newest last: Back to a title or the hero coming round finds it ready.
    private var decoded: [(src: String, image: UIImage)] = []
    private static let keep = 3
    /// A trailer plays in the art's place (the page's `hidden`).
    private var pageHidden = false
    /// Fading in from nothing at its next showing.
    private var appearing = false

    /// Where the page was scrolled to as the art was placed, and as it last measured, in the scroll view's points.
    private var placedAt: CGFloat?
    private var measuredAt: CGFloat?
    /// The scroll view's offset less the page's own scroll position, learned while it's still.
    private var scrollInset: CGFloat = 0
    private var lastScrolled: CFTimeInterval = 0
    /// The art put away, fading or held, where it was and the scroll it was placed at.
    private var leavingGhost: UIView?
    private var ghostAt: (frame: CGRect, scroll: CGFloat) = (.zero, 0)

    /// As the page's own layers fade (`duration-700`): a new title's art, and off a trailer.
    private static let fadeSeconds: TimeInterval = 0.7
    /// As the page's own layers fade in from nothing (`animate-in`, 400 ms).
    private static let appearSeconds: TimeInterval = 0.4
    /// As a page leaves, under the next one's art coming in.
    private static let leaveSeconds: TimeInterval = 0.3
    /// Put away otherwise (the page reloaded): held about the two frames WebKit takes to draw anew.
    private static let clearSeconds: TimeInterval = 2.0 / 60
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
        guard let src = message.text("src"), let frame = message.object("frame"),
              let clip = message.object("clip"), let web, let container = view.superview else {
            // Only the backdrop that asked puts itself away: the next page's can ask first. Its page
            // closing, it fades out over the next page's art coming in.
            if owner == nil || owner == id { clear(fadeOut: message.flag("fade") == true) }
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
        // The page's background is clear over the art, so its edges fade here, as the page's masks did.
        let frameFade: CGFloat = {
            guard let value = message.number("frameFade"), value.isFinite, value > 0 else { return 0 }
            return CGFloat(min(value, 10_000)) * scale
        }()
        edges = message.object("fade").map {
            (bottom: CGFloat($0.number("bottom") ?? 0), start: CGFloat($0.number("start") ?? 0),
             rtl: message.flag("rtl") == true, frame: frameFade)
        }
        let fade = wasShown && message.flag("quick") != true && src != self.src
        self.src = src
        // A trailer playing in its place: the art fades off it, and back once it ends.
        pageHidden = message.flag("hidden") == true
        if !wasShown { appearing = true }
        // Where the page was scrolled to as it measured, which the art follows the scroll on from.
        if let y = message.number("scrollY"), y.isFinite {
            measuredAt = pageScroll(CGFloat(min(max(y, -1_000_000), 1_000_000)) * scale)
        } else {
            measuredAt = nil
        }
        applyAlpha(animated: wasShown)
        if let image = decoded.first(where: { $0.src == src })?.image {
            show(image, src: src, fade: fade)
            drawn(id, src)
            return
        }
        // Asked again while it loads: the load on its way shows it, where the page now says, with the
        // crossfade the first ask began. A second load made a second copy, shown at once over the
        // crossfade, which cut it short: a flash.
        if loading == src { return }
        loading = src
        load(src) { [weak self] image in
            guard let self else { return }
            if self.loading == src { self.loading = nil }
            guard self.owner == id, self.src == src else { return self.artShown() }
            guard let image else {
                // The page loads and draws its own copy in its place.
                self.reply(["type": "tvos-backdrop", "id": id, "src": src, "failed": true])
                return self.artShown()
            }
            self.remember(src, image)
            self.show(image, src: src, fade: fade)
            self.drawn(id, src)
        }
    }

    /// The page's scroll position (in the scroll view's points) as WebKit's scroll view has it.
    private func pageScroll(_ points: CGFloat) -> CGFloat {
        if let scrollView, CACurrentMediaTime() - lastScrolled > 0.25 {
            scrollInset = scrollView.contentOffset.y - points
        }
        return points + scrollInset
    }

    /// The page scrolled: the art moves with it, frame by frame.
    private func scrolled(to y: CGFloat) {
        if let ghost = leavingGhost {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ghost.frame = ghostAt.frame.offsetBy(dx: 0, dy: -(y - ghostAt.scroll))
            CATransaction.commit()
        }
        guard !view.isHidden, let placedAt else { return }
        let moved = y - placedAt
        guard abs(view.frame.origin.y - (clip.minY - moved)) >= 0.25 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = clip.offsetBy(dx: 0, dy: -moved)
        CATransaction.commit()
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

    /// The page reloaded, or its process ended: nothing of its stays.
    func reset() {
        clear()
        decoded.removeAll()
    }

    /// `fadeOut`: its page closed, so it fades out over the next page's art; else held two frames.
    private func clear(fadeOut: Bool = false) {
        owner = nil
        src = nil
        edges = nil
        maskKey = nil
        let picture = shown
        shown = nil
        shownSrc = nil
        loading = nil
        placedAt = nil
        measuredAt = nil
        appearing = false
        pageHidden = false
        // On a copy of the view, moving with the scroll, so the view itself is free at once for the next ask.
        if let picture, !view.isHidden, view.alpha > 0, let container = view.superview {
            let ghost = UIView(frame: view.frame)
            ghost.isUserInteractionEnabled = false
            ghost.clipsToBounds = true
            ghost.alpha = CGFloat(view.layer.presentation()?.opacity ?? Float(view.alpha))
            // A layer masks one layer at a time: off the view first.
            let mask = view.layer.mask
            view.layer.mask = nil
            ghost.layer.mask = mask
            ghost.addSubview(picture)
            container.insertSubview(ghost, aboveSubview: view)
            leavingGhost?.removeFromSuperview()
            leavingGhost = ghost
            // Its frame already follows the scroll to now, so it moves on from where the scroll is.
            ghostAt = (frame: ghost.frame, scroll: scrollView?.contentOffset.y ?? 0)
            let gone: () -> Void = { [weak self, weak ghost] in
                ghost?.removeFromSuperview()
                if let self, self.leavingGhost === ghost { self.leavingGhost = nil }
            }
            if fadeOut {
                UIView.animate(withDuration: Self.leaveSeconds, delay: 0, options: [.curveEaseIn]) {
                    ghost.alpha = 0
                } completion: { _ in gone() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearSeconds, execute: gone)
            }
        } else {
            picture?.removeFromSuperview()
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
        // Where the page measured from; then on to where the scroll is now, if it moved since.
        placedAt = measuredAt ?? scrollView?.contentOffset.y
        if let y = scrollView?.contentOffset.y { scrolled(to: y) }
        // From nothing: faded in, as the page's own layers came in.
        if appearing {
            appearing = false
            if !pageHidden {
                view.layer.removeAnimation(forKey: "opacity")
                view.alpha = 0
                UIView.animate(withDuration: Self.appearSeconds, delay: 0, options: [.curveEaseOut]) { [view] in
                    view.alpha = 1
                }
            }
        }
        // Made again only when its size or fades change: each new title asks again with the same.
        // How far in from the clip's start edge the frame starts: its fade is measured from there.
        let frameAt = edges?.rtl == true ? clip.maxX - box.maxX : box.minX - clip.minX
        let maskKey = edges.map { "\(clip.size) \($0.bottom) \($0.start) \($0.rtl) \($0.frame) \(frameAt)" }
        if maskKey != self.maskKey || (maskKey != nil && view.layer.mask == nil) {
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
        // The same art, already shown or dissolving in: only moved, whichever copy of it this is.
        if let shown, shownSrc == src {
            shown.frame = placed
            return
        }
        shownSrc = src
        defer { artShown() }
        guard let shown else {
            let next = UIImageView(image: image)
            next.frame = placed
            next.contentMode = .scaleToFill
            view.addSubview(next)
            shown = next
            return
        }
        // One picture view, dissolving from a snapshot of the last art into the new.
        guard fade else {
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

    /// Unseen while a trailer plays in its place, faded off it and back.
    private func applyAlpha(animated: Bool) {
        let alpha: CGFloat = pageHidden ? 0 : 1
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
