import UIKit

/**
 * A mask that shows only `clip` of a view `size` points big, its bottom and start fading out over the
 * given fractions of the clip's height and width: the page's soft holes (a trailer's or a backdrop's,
 * fading into the artwork wash), for when the app draws the wash beneath the page and the page's own
 * background, which the holes were cut in, is clear (WashStage). The two fades multiply, as the
 * page's masks do (`mask-composite: intersect`) and as its two hole edges over the background did.
 *
 * Made of Core Animation's own gradients: the bottom fade in the clip, itself masked by the start
 * fade, so the two multiply. Nothing is drawn by hand, and the fades are smooth at any size.
 */
enum FadeMask {
    static func layer(size: CGSize, clip: CGRect, bottom: CGFloat, start: CGFloat, rtl: Bool) -> CALayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let shown = UIColor.black.cgColor
        let gone = UIColor.black.withAlphaComponent(0).cgColor

        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.actions = still

        // Whole down to where the bottom fade starts, then out to nothing at the clip's bottom.
        let down = CAGradientLayer()
        down.actions = still
        down.frame = clip
        let b = min(max(bottom, 0), 1)
        down.colors = [shown, shown, b > 0 ? gone : shown]
        down.locations = [0, NSNumber(value: Double(1 - b)), 1]
        down.startPoint = CGPoint(x: 0.5, y: 0)
        down.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(down)

        // In from nothing at the start edge over its fraction of the width, then whole.
        let s = min(max(start, 0), 1)
        if s > 0 {
            let side = CAGradientLayer()
            side.actions = still
            side.frame = down.bounds
            side.colors = [gone, shown, shown]
            side.locations = [0, NSNumber(value: Double(s)), 1]
            side.startPoint = CGPoint(x: rtl ? 1 : 0, y: 0.5)
            side.endPoint = CGPoint(x: rtl ? 0 : 1, y: 0.5)
            down.mask = side
        }
        return layer
    }

    /// No implicit fades as a mask is made or moved: what it covers would vanish and come back.
    private static let still: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
        "colors": NSNull(), "locations": NSNull(), "mask": NSNull(), "sublayers": NSNull(),
    ]

    /// For the app menu: the mask's alpha in the middle of `clip`, near its bottom and near its start.
    static func sample(_ mask: CALayer?, clip: CGRect, rtl: Bool) -> String {
        guard let mask, clip.width >= 4, clip.height >= 4 else { return "no mask" }
        let w = 64, h = 36
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return "unreadable" }
        // The clip drawn into the small bitmap, top left first, as the views are laid out.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: CGFloat(w) / clip.width, y: -CGFloat(h) / clip.height)
        context.translateBy(x: -clip.minX, y: -clip.minY)
        mask.render(in: context)
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func alpha(_ x: Int, _ y: Int) -> String {
            String(format: "%.2f", Double(pixels[(y * w + x) * 4 + 3]) / 255)
        }
        let startX = rtl ? w - 2 : 1
        return "mask alpha middle \(alpha(w / 2, h / 2)), near the bottom \(alpha(w / 2, h - 2)), near the start \(alpha(startX, h / 4))"
    }
}
