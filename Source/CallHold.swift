import Foundation

/// Postpones a due break while a call is in progress, once and for a limited time.
///
/// When focus ends during a call, the break waits until the call ends or
/// `maximumDelay` passes, whichever is first. Once released, a later call cannot
/// hold the same break again. The caller resets the hold when focus starts.
struct CallHold {
    static let maximumDelay: TimeInterval = 15 * 60

    private var startedAt: Date?
    private var released = false

    var isHolding: Bool { startedAt != nil && !released }

    /// Call only while focus is due to end. Returns true to keep the break waiting.
    mutating func shouldHold(callInProgress: Bool, now: Date) -> Bool {
        guard !released else { return false }
        guard callInProgress else { return release() }
        let start = startedAt ?? now
        startedAt = start
        guard now.timeIntervalSince(start) < Self.maximumDelay else { return release() }
        return true
    }

    /// Time left before the break starts anyway, for display.
    func remainingDelay(now: Date) -> TimeInterval {
        guard let startedAt, !released else { return 0 }
        return max(0, Self.maximumDelay - now.timeIntervalSince(startedAt))
    }

    mutating func reset() {
        startedAt = nil
        released = false
    }

    private mutating func release() -> Bool {
        released = true
        return false
    }
}
