// UPDATE 2026-11-03: New file for the menu bar icon and label — the ring fills up during focus, and the label reads like "F1B" for round 1.
import AppKit

/// Draws the menu bar icon and builds the round label shown beside the time.
enum MenuBarIcon {
    /// "F1B" for round 1, "F2B" for round 2, and so on. Rounds start at 1.
    static func roundLabel(_ round: Int) -> String { "F\(max(1, round))B" }

    /// A ring whose inside fills clockwise from the top as `progress` goes 0 → 1.
    /// It is a template image, so macOS colors it to match the menu bar.
    static func ring(progress: Double) -> NSImage {
        let fraction = min(1, max(0, progress))
        let size: CGFloat = 15
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.4
            ring.stroke()
            guard fraction > 0 else { return true }
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = size / 2 - 3
            if fraction >= 1 {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            } else {
                let pie = NSBezierPath()
                pie.move(to: center)
                pie.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * fraction, clockwise: true)
                pie.close()
                pie.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Focus \(Int((fraction * 100).rounded()))% done"
        return image
    }

    /// A built-in SF Symbol used as a template menu bar icon.
    static func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
