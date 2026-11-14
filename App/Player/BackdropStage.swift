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

    /// The art in its box, and the one fading out under it.
    private var shown: UIImageView?
    private var leaving: UIImageView?
    /// Which of the page's backdrops this is (the page numbers each hero and title page it mounts).
    private var owner: Int?
    private var src: String?
    /// The art's box (`frame`) and the part of it shown (`clip`), in the container's points.
    private var box = CGRect.zero
    private var clip = CGRect.zero
    /// Decoded art by address, the newest last: Back to a title or the hero coming round finds it ready.
    private var decoded: [(src: String, image: UIImage)] = []
    private static let keep = 3

    /// As the page's own layers fade (`duration-700`, and 400 ms from nothing).
    private static let fadeSeconds: TimeInterval = 0.7
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
            // Only the backdrop that asked puts itself away: the next page's can ask first.
            if owner == nil || owner == id { clear() }
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
        let fade = wasShown && message.flag("quick") != true && src != self.src
        self.src = src
        if let image = decoded.first(where: { $0.src == src })?.image {
            show(image, fade: fade)
            drawn(id, src)
            return
        }
        load(src) { [weak self] image in
            guard let self, self.owner == id, self.src == src else { return }
            guard let image else { return }
            self.remember(src, image)
            self.show(image, fade: fade)
            self.drawn(id, src)
        }
    }

    /// The page reloaded, or its process ended: nothing of its stays.
    func reset() {
        clear()
        decoded.removeAll()
    }

    private func clear() {
        owner = nil
        src = nil
        view.isHidden = true
        leaving?.removeFromSuperview()
        leaving = nil
        shown?.removeFromSuperview()
        shown = nil
    }

    private func drawn(_ id: Int, _ src: String) {
        reply(["type": "tvos-backdrop", "id": id, "src": src, "drawn": true])
    }

    private func show(_ image: UIImage, fade: Bool) {
        view.frame = clip
        view.isHidden = false
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
        if let shown, shown.image === image {
            shown.frame = placed
            return
        }
        let next = UIImageView(image: image)
        next.frame = placed
        next.contentMode = .scaleToFill
        view.addSubview(next)
        leaving?.removeFromSuperview()
        leaving = nil
        guard fade, let last = shown else {
            shown?.removeFromSuperview()
            shown = next
            return
        }
        leaving = last
        shown = next
        next.alpha = 0
        UIView.animate(withDuration: Self.fadeSeconds, delay: 0, options: [.curveEaseOut]) {
            next.alpha = 1
        } completion: { [weak self, weak last] _ in
            last?.removeFromSuperview()
            if self?.leaving === last { self?.leaving = nil }
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
