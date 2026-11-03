/// A one-shot gate for restarting focus after a completed break.
///
/// At break completion, the caller takes a fresh aggregate interaction counter
/// snapshot and arms the gate. Polling that same counter does nothing until its
/// value changes. The counter may include clicks, keys, pointer movement, and
/// scrolling. No input contents or event details are retained here.
///
/// The app must cancel the gate on manual Start, settings edits, emergency
/// release, and quit. Opening the app alone must never arm it.
struct AutoResumeGate {
    private var baselineActivityCount: UInt64?

    var isArmed: Bool { baselineActivityCount != nil }

    /// Captures activity up to break completion so it cannot restart focus.
    /// An unavailable snapshot leaves the gate safely unarmed.
    @discardableResult
    mutating func arm(activityCount: UInt64?) -> Bool {
        baselineActivityCount = activityCount
        return isArmed
    }

    /// Returns true once, on the first counter change after arming.
    ///
    /// Inequality also detects counter wrapping, including an individual source
    /// counter wrapping and making the aggregate decrease.
    /// Unavailable polls are ignored without consuming an armed gate. The caller
    /// must supply fresh snapshots from the same counter source used by `arm`.
    @discardableResult
    mutating func consume(activityCount: UInt64?) -> Bool {
        guard let baselineActivityCount,
              let activityCount,
              activityCount != baselineActivityCount else {
            return false
        }
        cancel()
        return true
    }

    mutating func cancel() {
        baselineActivityCount = nil
    }
}
