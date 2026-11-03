import Foundation

/// Today's completed rounds and focus time, saved so quitting the app does not lose them.
/// A new calendar day starts again at zero. A round belongs to the day its
/// break finished.
struct DailyRounds: Equatable {
    private(set) var day: String
    private(set) var rounds: Int
    /// Focus minutes of today's completed rounds only.
    private(set) var focusMinutes: Int

    init(day: String, rounds: Int = 0, focusMinutes: Int = 0) {
        self.day = day
        self.rounds = max(0, rounds)
        self.focusMinutes = max(0, focusMinutes)
    }

    /// The menu line, for example "Today: 6 rounds · 2h 0m focused".
    var summary: String {
        guard rounds > 0 else { return "Today: no rounds yet" }
        let time = focusMinutes < 60 ? "\(focusMinutes)m" : "\(focusMinutes / 60)h \(focusMinutes % 60)m"
        return "Today: \(rounds) round\(rounds == 1 ? "" : "s") · \(time) focused"
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
        focusMinutes = 0
        return true
    }

    /// Counts one completed round. Returns true when this also started a new day.
    @discardableResult
    mutating func recordRound(today: String, focusMinutes minutes: Int = 0) -> Bool {
        let newDay = roll(to: today)
        rounds += 1
        focusMinutes += max(0, minutes)
        return newDay
    }
}
