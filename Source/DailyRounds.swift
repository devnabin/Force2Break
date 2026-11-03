import Foundation

/// Today's completed rounds, saved so quitting the app does not lose them.
/// A new calendar day starts again at zero. A round belongs to the day its
/// break finished.
struct DailyRounds: Equatable {
    private(set) var day: String
    private(set) var rounds: Int

    init(day: String, rounds: Int = 0) {
        self.day = day
        self.rounds = max(0, rounds)
    }

    /// A local calendar day such as "2026-11-02".
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Starts a new day at zero. Returns true when the day changed.
    @discardableResult
    mutating func roll(to today: String) -> Bool {
        guard today != day else { return false }
        day = today
        rounds = 0
        return true
    }

    /// Counts one completed round. Returns true when this also started a new day.
    @discardableResult
    mutating func recordRound(today: String) -> Bool {
        let newDay = roll(to: today)
        rounds += 1
        return newDay
    }
}
