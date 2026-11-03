import CoreGraphics

/// Reads only accumulated interaction counts from the current login session.
/// No keyboard characters, pointer locations, or event contents are requested.
enum ActivitySource {
    // kCGAnyInputEventType, documented for keyboard, mouse, and tablet input:
    // https://developer.apple.com/documentation/coregraphics/cgeventsource/counterforeventtype(_:eventtype:)
    private static let anyInput = CGEventType(rawValue: UInt32.max)!

    static func interactionCount() -> UInt64 {
        UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: anyInput))
    }
}
