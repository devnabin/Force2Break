import Foundation

/// Standalone tests; compile this file with Source/AwayDetector.swift.
@main
enum AwayDetectorTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool,
                       _ message: String,
                       file: StaticString = #filePath,
                       line: UInt = #line) {
        assertions += 1
        if !condition() {
            fatalError("\(message) (\(file):\(line))")
        }
    }

    static func main() {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let threshold: TimeInterval = 300

        // Idle below the threshold stays present; reaching it is away.
        var detector = AwayDetector()
        detector.reset(activityCount: 10, now: origin)
        for second in stride(from: 0.0, to: threshold, by: 0.2) {
            expect(detector.observe(activityCount: 10, now: origin + second, threshold: threshold) == .present,
                   "Idle shorter than the threshold must not count as away")
        }
        expect(detector.observe(activityCount: 10, now: origin + threshold, threshold: threshold) == .away,
               "Idle for the full threshold must count as away")
        expect(detector.observe(activityCount: 10, now: origin + threshold + 60, threshold: threshold) == .away,
               "Away must persist while there is no input")

        // Regular activity keeps resetting the idle clock.
        detector.reset(activityCount: 0, now: origin)
        for minute in 1...60 {
            expect(detector.observe(activityCount: UInt64(minute), now: origin + Double(minute * 60), threshold: threshold) == .present,
                   "Input every minute must keep the user present")
        }

        // Idle almost to the threshold, then activity, restarts the idle clock.
        detector.reset(activityCount: 5, now: origin)
        expect(detector.observe(activityCount: 6, now: origin + 299, threshold: threshold) == .present,
               "Input just before the threshold must keep the user present")
        expect(detector.observe(activityCount: 6, now: origin + 500, threshold: threshold) == .present,
               "The idle clock must restart at the last input")
        expect(detector.observe(activityCount: 6, now: origin + 599, threshold: threshold) == .away,
               "Idle measured from the last input must reach away")

        // Wake from sleep: input arrives before the first poll after a long gap.
        detector.reset(activityCount: 20, now: origin)
        expect(detector.observe(activityCount: 21, now: origin + 1800, threshold: threshold) == .returned,
               "A long gap ending in input must report a return, not presence")

        // Counter wrap is still a change.
        detector.reset(activityCount: UInt64.max, now: origin)
        expect(detector.observe(activityCount: 0, now: origin + 1, threshold: threshold) == .present,
               "A wrapped counter must count as activity")
        expect(detector.observe(activityCount: 0, now: origin + 300, threshold: threshold) == .present,
               "Idle must be measured from the wrapped input")

        // Video or presentation keeping the display awake counts as presence.
        detector.reset(activityCount: 1, now: origin)
        for second in stride(from: 0.2, through: 1800, by: 0.2) {
            expect(detector.observe(activityCount: 1, now: origin + second, threshold: threshold, presenceHeld: true) == .present,
                   "Watching a video without input must not count as away")
        }
        // ...but cannot hide a sleep gap.
        expect(detector.observe(activityCount: 1, now: origin + 1800 + 900, threshold: threshold, presenceHeld: true) == .away,
               "A long sleep gap must count as away even with a presence assertion")

        // An unavailable counter never ends focus and never arms the detector.
        var unavailable = AwayDetector()
        unavailable.reset(activityCount: nil, now: origin)
        expect(unavailable.observe(activityCount: nil, now: origin + 3600, threshold: threshold) == .present,
               "An unavailable counter must keep the user present")
        expect(unavailable.observe(activityCount: 3, now: origin + 3601, threshold: threshold) == .present,
               "The first available reading starts tracking instead of reporting away")
        expect(unavailable.observe(activityCount: 3, now: origin + 3601 + threshold, threshold: threshold) == .away,
               "Tracking must work once the counter is available")

        print("AwayDetector: \(assertions) assertions passed.")
    }
}
