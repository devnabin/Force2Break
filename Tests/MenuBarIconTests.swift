// UPDATE 2026-11-03: New tests for the "F1B" round label and the filling ring icon.
import AppKit

/// Standalone tests; compile this file with Source/MenuBarIcon.swift.
@main
enum MenuBarIconTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        assertions += 1
        if !condition() { fatalError("\(message) (\(file):\(line))") }
    }

    static func main() {
        expect(MenuBarIcon.roundLabel(1) == "F1B", "Round 1 reads F1B")
        expect(MenuBarIcon.roundLabel(2) == "F2B", "Round 2 reads F2B")
        expect(MenuBarIcon.roundLabel(12) == "F12B", "Two-digit rounds keep the same pattern")
        expect(MenuBarIcon.roundLabel(0) == "F1B", "Rounds never show as 0")

        for progress in [-1.0, 0, 0.25, 0.5, 0.999, 1, 2] {
            let ring = MenuBarIcon.ring(progress: progress)
            expect(ring.isTemplate, "The ring adapts to light and dark menu bars")
            expect(ring.size == NSSize(width: 15, height: 15), "The ring fits the menu bar")
            expect(ring.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil, "The ring draws at \(progress)")
        }
        expect(MenuBarIcon.ring(progress: 0.5).accessibilityDescription == "Focus 50% done",
               "VoiceOver hears how far focus has come")
        for name in ["moon.zzz", "phone.fill", "leaf.fill"] {
            expect(MenuBarIcon.symbol(name, description: name)?.isTemplate == true, "\(name) exists on this macOS")
        }
        print("MenuBarIcon: \(assertions) assertions passed.")
    }
}
