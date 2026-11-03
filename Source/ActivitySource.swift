import CoreGraphics
import IOKit.pwr_mgt

/// Reads only accumulated interaction counts from the current login session.
/// No keyboard characters, pointer locations, or event contents are requested.
enum ActivitySource {
    // kCGAnyInputEventType, documented for keyboard, mouse, and tablet input:
    // https://developer.apple.com/documentation/coregraphics/cgeventsource/counterforeventtype(_:eventtype:)
    private static let anyInput = CGEventType(rawValue: UInt32.max)!

    static func interactionCount() -> UInt64 {
        UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: anyInput))
    }

    /// True while any app keeps the display awake, as video players, video
    /// calls, and presentations do. Only system-wide assertion counts are read.
    static func displayKeptAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let counts = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (counts["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
