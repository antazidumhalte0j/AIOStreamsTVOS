import Foundation
import QuartzCore

/**
 * The last few things that happened to the art the app draws beneath the page, the backdrop and the
 * wash, and the page's marks for them, with their times: a flash or hard edges as a backdrop is
 * replaced last only a moment, so the app menu's lines on what's drawn now can't catch them.
 */
@MainActor
enum ArtLog {
    private static var lines: [String] = []
    private static let kept = 40
    private static var last: CFTimeInterval = 0

    static func note(_ text: String) {
        let now = CACurrentMediaTime()
        let gap = last == 0 ? 0 : Int(((now - last) * 1000).rounded())
        last = now
        lines.append("+\(gap) ms \(text)")
        if lines.count > kept { lines.removeFirst(lines.count - kept) }
    }

    /// For the app menu, oldest first, each with the time since the one before.
    static var report: [String] { lines }
}
