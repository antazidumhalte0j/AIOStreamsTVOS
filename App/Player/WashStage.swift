import UIKit

/**
 * "Background from artwork"'s wash, drawn by the app beneath everything (patches/web/0050, the page's
 * `tvos-wash`). The page faded each new wash in over the last on a canvas behind the whole page, and
 * while that ran WebKit made the canvas a layer the screen's size at 2x, and every part of the page
 * over it layers of their own: resting on card after card started fade after fade, which lagged and
 * ended the page's process for memory. Here the fade costs the page nothing.
 *
 * The wash is the one the app already makes for the page (ArtWash, `/wash`, patch 0043), from its
 * cache: a 320x180 picture stretched to cover the screen, as the page's canvas was. Once it's drawn
 * the app says so, and the page clears its background over it.
 */
@MainActor
final class WashStage {
    let view = UIView()
    /// Tells the page a wash is drawn, or couldn't be, so it draws its own.
    var reply: (Message) -> Void = { _ in }
    /// The wash shown, for the keyboard's box to be drawn the same (SearchKeyboard's `KeyboardLook`).
    private(set) var image: UIImage?

    private var shown: UIImageView?
    private var owner: Int?
    private var src: String?

    /// As the page's own (art-wash.tsx's `FADE_MS`, ease-out).
    private static let fadeSeconds: TimeInterval = 0.6

    init() {
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isHidden = true
    }

    /// The page's `tvos-wash`: the wash of the art at `src`, or none.
    func handle(_ message: Message) {
        let id = Int(message.number("id") ?? 0)
        guard let src = message.text("src") else {
            if owner == nil || owner == id {
                if shown != nil { ArtLog.note("wash #\(id) put away") }
                clear()
            }
            return
        }
        owner = id
        guard src != self.src || shown == nil else { return drawn(id, src, true) }
        ArtLog.note("wash #\(id) asked for new art")
        self.src = src
        guard let address = URL(string: src) else { return drawn(id, src, false) }
        ArtWash.make(address) { made in
            let image = made.flatMap { UIImage(data: $0.png)?.preparingForDisplay() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.owner == id, self.src == src else { return }
                guard let image else { return self.drawn(id, src, false) }
                self.show(image)
                self.drawn(id, src, true)
            }
        }
    }

    /// The page reloaded, or its process ended.
    func reset() { clear() }

    private func clear() {
        owner = nil
        src = nil
        image = nil
        view.isHidden = true
        shown?.removeFromSuperview()
        shown = nil
    }

    private func drawn(_ id: Int, _ src: String, _ drawn: Bool) {
        ArtLog.note(drawn ? "wash #\(id) drawn" : "wash #\(id) COULDN'T be drawn: the page draws its own")
        reply(["type": "tvos-wash", "id": id, "src": src, "drawn": drawn])
    }

    private func show(_ image: UIImage) {
        self.image = image
        view.isHidden = false
        let next = UIImageView(image: image)
        next.frame = view.bounds
        next.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Stretched to cover, as the page's canvas was (`object-cover`); smoothed as a canvas is.
        next.contentMode = .scaleAspectFill
        next.layer.magnificationFilter = .linear
        view.addSubview(next)
        guard let last = shown, !UIAccessibility.isReduceMotionEnabled else {
            shown?.removeFromSuperview()
            shown = next
            return
        }
        shown = next
        next.alpha = 0
        UIView.animate(withDuration: Self.fadeSeconds, delay: 0, options: [.curveEaseOut]) {
            next.alpha = 1
        } completion: { [weak last] _ in
            last?.removeFromSuperview()
        }
    }
}
