import Foundation

/// Detects when the user has stepped away during focus, using only the same
/// aggregate interaction counter as `AutoResumeGate`. No input contents are read.
///
/// The caller polls `observe` while focusing and calls `reset` when focus starts.
/// A gap with no input that reaches `threshold` means the user was away long
/// enough to count as a rest. The gap is measured before new activity is
/// recorded, so returning from system sleep is detected even when the wake-up
/// input arrives before the first poll.
struct AwayDetector {
    enum Observation: Equatable {
        /// Still active (or idle for less than the threshold).
        case present
        /// Idle for at least the threshold and still idle.
        case away
        /// Idle for at least the threshold, then input arrived before this poll.
        case returned
    }

    private var lastCount: UInt64?
    private var lastActivityAt: Date?

    mutating func reset(activityCount: UInt64?, now: Date) {
        lastCount = activityCount
        lastActivityAt = activityCount == nil ? nil : now
    }

    /// - Parameter presenceHeld: true while something signals the user is
    ///   watching without touching input, such as a playing video keeping the
    ///   display awake. It counts as activity, but cannot hide a long sleep gap.
    mutating func observe(activityCount: UInt64?, now: Date, threshold: TimeInterval,
                          presenceHeld: Bool = false) -> Observation {
        // An unavailable counter must never end focus.
        guard let activityCount else { return .present }
        guard let lastActivityAt else {
            reset(activityCount: activityCount, now: now)
            return .present
        }
        let changed = activityCount != lastCount
        if now.timeIntervalSince(lastActivityAt) >= threshold {
            return changed ? .returned : .away
        }
        if changed || presenceHeld {
            lastCount = activityCount
            self.lastActivityAt = now
        }
        return .present
    }
}
