import Foundation

/// A deterministic focus/break state machine with no timers or UI dependencies.
///
/// The caller owns the clock and invokes `tick(now:)` when its timer fires and
/// immediately after wake. Supply a logical Date derived from ContinuousClock
/// elapsed time so sleep counts, while wall-clock corrections cannot shorten a
/// session. Dates supplied to this engine must all use the same clock origin.
struct SessionEngine {
    enum Phase: String, Equatable {
        case ready
        case focusing
        case breaking
    }

    enum Transition: Equatable {
        case focusEnded
        case breakEnded
    }

    static let focusOptions = [10, 15, 20, 25]
    static let breakOptions = [2, 3, 4, 5]
    static let defaultFocusMinutes = 20
    static let defaultBreakMinutes = 3
    static let longBreakMinutes = 10
    static let longBreakCadence = 4

    private(set) var focusMinutes: Int
    private(set) var breakMinutes: Int
    private(set) var phase: Phase = .ready
    private(set) var deadline: Date?
    private(set) var phaseStartedAt: Date?
    private(set) var phaseDuration: TimeInterval?
    private(set) var completedRounds = 0

    /// A round consists of focus followed by a naturally completed break.
    /// Ready displays the completed round; an active phase displays its round.
    var currentRound: Int { phase == .ready ? completedRounds : upcomingRound }
    var upcomingRound: Int { completedRounds + 1 }
    var isLongBreak: Bool {
        phase != .ready && upcomingRound.isMultiple(of: Self.longBreakCadence)
    }

    // A cycle keeps its break length even if the saved settings change.
    private(set) var activeBreakMinutes: Int?

    /// Invalid persisted settings safely fall back to the respective defaults.
    init(focusMinutes: Int = 20, breakMinutes: Int = 3) {
        self.focusMinutes = Self.focusOptions.contains(focusMinutes)
            ? focusMinutes : Self.defaultFocusMinutes
        self.breakMinutes = Self.breakOptions.contains(breakMinutes)
            ? breakMinutes : Self.defaultBreakMinutes
    }

    /// Updates the next cycle's settings atomically without changing this cycle.
    @discardableResult
    mutating func updateSettings(focusMinutes: Int, breakMinutes: Int) -> Bool {
        guard Self.focusOptions.contains(focusMinutes),
              Self.breakOptions.contains(breakMinutes) else {
            return false
        }
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        return true
    }

    /// Starts only from ready. Repeated clicks cannot extend an active session.
    @discardableResult
    mutating func start(now: Date) -> Bool {
        guard phase == .ready else { return false }
        activeBreakMinutes = upcomingRound.isMultiple(of: Self.longBreakCadence)
            ? Self.longBreakMinutes : breakMinutes
        begin(.focusing, duration: TimeInterval(focusMinutes * 60), now: now)
        return true
    }

    /// Advances at most one phase and emits each transition exactly once.
    ///
    /// If a focus timer is detected late (for example after system sleep), a
    /// complete break begins at detection time. Time spent asleep cannot silently
    /// consume the break. When a break ends, the engine waits for another click.
    @discardableResult
    mutating func tick(now: Date) -> Transition? {
        guard let deadline, now >= deadline else { return nil }

        switch phase {
        case .ready:
            return nil
        case .focusing:
            let duration = TimeInterval((activeBreakMinutes ?? breakMinutes) * 60)
            begin(.breaking, duration: duration, now: now)
            return .focusEnded
        case .breaking:
            completedRounds += 1
            reset()
            return .breakEnded
        }
    }

    /// Countdown for display: a positive fraction of a second displays as 1.
    func remainingSeconds(now: Date) -> Int {
        guard let deadline else { return 0 }
        return Int(ceil(max(0, deadline.timeIntervalSince(now))))
    }

    /// Explicitly abandons the current cycle, preserving settings and completed
    /// rounds. An abandoned fourth round therefore retries its long break.
    /// The normal break UI should not expose this as a skip action.
    mutating func reset() {
        phase = .ready
        deadline = nil
        phaseStartedAt = nil
        phaseDuration = nil
        activeBreakMinutes = nil
    }

    private mutating func begin(_ phase: Phase, duration: TimeInterval, now: Date) {
        self.phase = phase
        phaseStartedAt = now
        phaseDuration = duration
        deadline = now.addingTimeInterval(duration)
    }
}
