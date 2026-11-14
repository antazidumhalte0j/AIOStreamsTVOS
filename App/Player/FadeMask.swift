import UIKit

/**
 * A mask that shows only `clip` of a view `size` points big, its bottom and start fading out over the
 * given fractions of the clip's height and width: the page's soft holes (a trailer's or a backdrop's,
 * fading into the artwork wash), for when the app draws the wash beneath the page and the page's own
 * background, which the holes were cut in, is clear (WashStage). The two fades multiply, as the
 * page's masks do (`mask-composite: intersect`) and as its two hole edges over the background did.
 */
enum FadeMask {
    /// Drawn at a quarter of the size: the fades are smooth, and stretched back they look the same.
    private static let scale: CGFloat = 0.25

    static func layer(size: CGSize, clip: CGRect, bottom: CGFloat, start: CGFloat, rtl: Bool) -> CALayer {
        let layer = CALayer()
        // A layer of its own, not a view's, fades its contents in by itself (Core Animation's implicit
        // actions): as a mask, what it covers would vanish and come back each time it's made.
        layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contents = image(size: size, clip: clip, bottom: bottom, start: start, rtl: rtl)
        CATransaction.commit()
        return layer
    }

    private static func image(size: CGSize, clip: CGRect, bottom: CGFloat, start: CGFloat, rtl: Bool) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // In points, from the top left, as the views are laid out.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        let shown = UIColor.white.cgColor
        let gone = UIColor.white.withAlphaComponent(0).cgColor
        func gradient(_ colors: [CGColor]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])
        }
        context.saveGState()
        context.clip(to: clip)
        let down = clip.height * min(max(bottom, 0), 1)
        if down > 0, let fade = gradient([shown, gone]) {
            // Whole above the fade, then out to nothing at the bottom.
            context.drawLinearGradient(
                fade, start: CGPoint(x: 0, y: clip.maxY - down), end: CGPoint(x: 0, y: clip.maxY),
                options: [.drawsBeforeStartLocation]
            )
        } else {
            context.setFillColor(shown)
            context.fill(clip)
        }
        let side = clip.width * min(max(start, 0), 1)
        if side > 0, let fade = gradient([gone, shown]) {
            // Kept only where the start's fade lets it be: in from nothing at the start edge.
            context.setBlendMode(.destinationIn)
            let edge = rtl ? clip.maxX : clip.minX
            context.drawLinearGradient(
                fade, start: CGPoint(x: edge, y: 0), end: CGPoint(x: rtl ? edge - side : edge + side, y: 0),
                options: [.drawsAfterEndLocation]
            )
        }
        context.restoreGState()
        return context.makeImage()
    }
}
