import UIKit

/**
 * Liquid glass drawn by tvOS, beneath the page (patches/web/0073, the page's `tvos-glass`). WebKit's
 * `backdrop-filter` takes no SVG filter, so the page's own liquid glass, a lens drawn by one, is
 * Chromium's only. With Theme > Glass surface on Liquid glass, the floating rail's panel and the
 * corner menu's button draw no fill or blur of their own and say where they are, and a
 * `UIGlassEffect` view is put there, between the backdrop and the page: the glass bends and blurs
 * the backdrop, the artwork wash and a trailer behind it, all drawn by the app. Page content under
 * a panel (the first column, as the rail opens over it) is in the page, above the glass, so it
 * isn't seen through it; the rail's shade darkens it then.
 *
 * Only on tvOS 26 and later, where `UIGlassEffect` is; the page offers Liquid glass only then
 * (`liquidGlass` on the bridge). The rail is fixed on the screen, so it follows no scroll; as it
 * changes size (opening, 200 ms) it says so each frame it does.
 *
 * With Glass panels on too, the settings cards, the settings tab groups and the pill tabs over the
 * artwork get glass here as well (patches/web/0074, `tvos-glass-panels`): they sit over nothing of
 * the page but the wash. They scroll with the page, so they follow WebKit's scroll view here, frame
 * by frame, as the backdrop does, each clipped to the part its scrolling list leaves in sight; one
 * in a sticky or fixed part of the page stays put, and the page measures them all again once a
 * scroll comes to rest, as anything changes, and every frame while something animates.
 */
@MainActor
final class GlassStage {
    /// The panes, over the backdrop and the video, beneath the web view.
    let view = UIView()
    /// The page, whose measure the frames are in.
    weak var web: UIView?

    /// One pane for each of the page's glass surfaces, by the id the page gives it.
    private var panes: [Int: UIVisualEffectView] = [:]

    /// WebKit's scroll view for the page, whose scroll the panels follow.
    weak var scrollView: UIScrollView? {
        didSet {
            scrollWatch = scrollView?.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
                let y = scrollView.contentOffset.y
                MainActor.assumeIsolated {
                    self?.lastScrolled = CACurrentMediaTime()
                    self?.follow(y)
                }
            }
        }
    }
    private var scrollWatch: NSKeyValueObservation?
    private var lastScrolled: CFTimeInterval = 0
    /// The scroll view's offset less the page's own scroll position, learned while it's still.
    private var scrollInset: CGFloat = 0

    /// The glass panels over the artwork (`tvos-glass-panels`), beneath the rail's panes.
    private let panelsView = UIView()
    /// A panel: the part of it in sight, clipping its glass, which is the whole panel.
    private struct Panel {
        let holder: UIView
        let glass: UIVisualEffectView
    }
    private var panels: [Panel] = []
    /// Each shown panel's place as the page measured it, and whether it stays put as the page scrolls.
    private var places: [(clip: CGRect, pinned: Bool)] = []
    /// Where the page was scrolled to as it measured, in the scroll view's points.
    private var measuredAt: CGFloat?
    /// Panels kept for reuse beyond those shown.
    private static let spare = 8

    /// As the page's shell fades off a trailer or a video (`transition-opacity duration-300`).
    private static let fadeSeconds: TimeInterval = 0.3

    /// tvOS draws Liquid glass (`UIGlassEffect`, tvOS 26).
    nonisolated static var available: Bool {
        if #available(tvOS 26.0, *) { return true }
        return false
    }

    init() {
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        panelsView.isUserInteractionEnabled = false
        panelsView.frame = view.bounds
        panelsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(panelsView)
    }

    /**
     * The page's `tvos-glass-panels` (patches/web/0074): the settings cards, settings tab groups and
     * pill tabs in or near the screen, each with the part its scrolling ancestors leave in sight and
     * whether a sticky or fixed ancestor holds it; none puts them all away.
     */
    func handlePanels(_ message: Message) {
        let list = (message["panels"] as? [Any])?.compactMap { $0 as? Message } ?? []
        guard #available(tvOS 26.0, *), let web, !list.isEmpty else { return clearPanels() }
        var scale: CGFloat = 1
        if let page = message.number("pageWidth"), page.isFinite, page > 0, web.bounds.width > 0 {
            scale = web.bounds.width / CGFloat(page)
        }
        func rect(_ object: Message?) -> CGRect {
            guard let object else { return .zero }
            func number(_ key: String) -> CGFloat {
                guard let value = object.number(key), value.isFinite else { return 0 }
                return CGFloat(min(max(value, -100_000), 100_000)) * scale
            }
            return panelsView.convert(
                CGRect(x: number("x"), y: number("y"), width: max(0, number("width")), height: max(0, number("height"))),
                from: web
            )
        }
        if let y = message.number("scrollY"), y.isFinite {
            measuredAt = pageScroll(CGFloat(min(max(y, -1_000_000), 1_000_000)) * scale)
        } else {
            measuredAt = scrollView?.contentOffset.y
        }
        places.removeAll(keepingCapacity: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in list.enumerated() {
            let frame = rect(item.object("frame"))
            let clip = rect(item.object("clip"))
            let radius: CGFloat = {
                guard let value = item.number("radius"), value.isFinite, value > 0 else { return 0 }
                return min(CGFloat(value) * scale, min(frame.width, frame.height) / 2)
            }()
            if index == panels.count {
                let holder = UIView()
                holder.isUserInteractionEnabled = false
                holder.clipsToBounds = true
                let glass = UIVisualEffectView(effect: UIGlassEffect())
                glass.isUserInteractionEnabled = false
                glass.clipsToBounds = true
                glass.layer.cornerCurve = .continuous
                holder.addSubview(glass)
                panelsView.addSubview(holder)
                panels.append(Panel(holder: holder, glass: glass))
            }
            let panel = panels[index]
            panel.holder.isHidden = false
            panel.holder.frame = clip
            panel.glass.frame = frame.offsetBy(dx: -clip.minX, dy: -clip.minY)
            panel.glass.layer.cornerRadius = radius
            places.append((clip, item.flag("pinned") == true))
        }
        // Those not shown now are hidden, a few kept for the next page's.
        for panel in panels.dropFirst(list.count) { panel.holder.isHidden = true }
        if panels.count > list.count + Self.spare {
            for panel in panels[(list.count + Self.spare)...] { panel.holder.removeFromSuperview() }
            panels.removeLast(panels.count - list.count - Self.spare)
        }
        CATransaction.commit()
        // On to where the scroll is now, if it moved since the page measured.
        if let y = scrollView?.contentOffset.y { follow(y) }
    }

    /// The page scrolled: the panels it doesn't pin move with it, frame by frame.
    private func follow(_ y: CGFloat) {
        guard let measuredAt, !places.isEmpty else { return }
        let moved = y - measuredAt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, place) in places.enumerated() where !place.pinned && index < panels.count {
            panels[index].holder.frame.origin.y = place.clip.minY - moved
        }
        CATransaction.commit()
    }

    /// The page's scroll position (in the scroll view's points) as WebKit's scroll view has it.
    private func pageScroll(_ points: CGFloat) -> CGFloat {
        if let scrollView, CACurrentMediaTime() - lastScrolled > 0.25 {
            scrollInset = scrollView.contentOffset.y - points
        }
        return points + scrollInset
    }

    private func clearPanels() {
        places.removeAll()
        measuredAt = nil
        for panel in panels { panel.holder.isHidden = true }
    }

    /// The page's `tvos-glass`: a surface's frame and corner radius, or none to take its pane away.
    func handle(_ message: Message) {
        let id = Int(message.number("id") ?? 0)
        guard let frame = message.object("frame"), let web else { return remove(id) }
        guard #available(tvOS 26.0, *) else { return }
        var scale: CGFloat = 1
        if let page = message.number("pageWidth"), page.isFinite, page > 0, web.bounds.width > 0 {
            scale = web.bounds.width / CGFloat(page)
        }
        func number(_ object: Message, _ key: String) -> CGFloat {
            guard let value = object.number(key), value.isFinite else { return 0 }
            return CGFloat(min(max(value, -100_000), 100_000)) * scale
        }
        let rect = view.convert(
            CGRect(x: number(frame, "x"), y: number(frame, "y"),
                   width: max(0, number(frame, "width")), height: max(0, number(frame, "height"))),
            from: web
        )
        let radius: CGFloat = {
            guard let value = message.number("radius"), value.isFinite, value > 0 else { return 0 }
            return min(CGFloat(value) * scale, min(rect.width, rect.height) / 2)
        }()
        let hidden = message.flag("hidden") == true
        let pane = panes[id] ?? {
            let pane = UIVisualEffectView(effect: UIGlassEffect())
            pane.isUserInteractionEnabled = false
            pane.clipsToBounds = true
            pane.layer.cornerCurve = .continuous
            pane.alpha = 0
            view.addSubview(pane)
            panes[id] = pane
            return pane
        }()
        // Placed as the page lays out, a frame at a time while it resizes: no animation of its own.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pane.frame = rect
        pane.layer.cornerRadius = radius
        CATransaction.commit()
        let alpha: CGFloat = hidden ? 0 : 1
        if pane.alpha != alpha {
            UIView.animate(withDuration: Self.fadeSeconds, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) { pane.alpha = alpha }
        }
    }

    private func remove(_ id: Int) {
        panes.removeValue(forKey: id)?.removeFromSuperview()
    }

    /// The page reloaded, or its process ended: none of its panes stay.
    func reset() {
        for pane in panes.values { pane.removeFromSuperview() }
        panes.removeAll()
        clearPanels()
    }

    /// For the app menu: the rail's panes, where, and how many panels.
    var summary: String {
        let rail = panes.sorted { $0.key < $1.key }.map { id, pane in
            let f = pane.frame
            return "\(id) at \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))" + (pane.alpha < 1 ? " hidden" : "")
        }
        let shown = places.count
        let pinned = places.filter { $0.pinned }.count
        let parts = rail + (shown > 0 ? ["\(shown) panels (\(pinned) pinned)"] : [])
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }
}
