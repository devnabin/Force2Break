import Foundation

/// Standalone tests; compile with Source/DailyRounds.swift and Source/SessionEngine.swift.
@main
enum DailyRoundsTests {
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }

        // Day keys follow the local calendar day.
        expect(DailyRounds.dayKey(for: date(2026, 11, 2, 0, 0), calendar: calendar) == "2026-11-02",
               "Midnight belongs to the new day")
        expect(DailyRounds.dayKey(for: date(2026, 11, 2, 23, 59), calendar: calendar) == "2026-11-02",
               "Late evening belongs to the same day")
        expect(DailyRounds.dayKey(for: date(2026, 12, 31, 23, 59), calendar: calendar) == "2026-12-31"
               && DailyRounds.dayKey(for: date(2027, 1, 1, 0, 1), calendar: calendar) == "2027-01-01",
               "The year boundary is a new day")

        // Same day: counting keeps going, including after a "relaunch".
        var log = DailyRounds(day: "2026-11-02")
        for round in 1...3 {
            expect(!log.recordRound(today: "2026-11-02") && log.rounds == round,
                   "Rounds on the same day keep counting")
        }
        let saved = (log.day, log.rounds)
        var relaunched = DailyRounds(day: saved.0, rounds: saved.1)
        expect(!relaunched.roll(to: "2026-11-02") && relaunched.rounds == 3,
               "Reopening the app on the same day keeps the count")

        // New day: back to zero.
        expect(relaunched.roll(to: "2026-11-03") && relaunched.rounds == 0 && relaunched.day == "2026-11-03",
               "Reopening the app on a new day starts at zero")
        expect(!relaunched.roll(to: "2026-11-03"), "Rolling to the same day twice does nothing")

        // A round finishing just after midnight is the new day's first round.
        var lateNight = DailyRounds(day: "2026-11-02", rounds: 7)
        expect(lateNight.recordRound(today: "2026-11-03") && lateNight.rounds == 1,
               "A round finishing after midnight counts as round 1 of the new day")

        // Bad saved values are made safe.
        expect(DailyRounds(day: "2026-11-02", rounds: -4).rounds == 0, "Negative saved counts become zero")

        // The engine can be restored from a saved count, only while ready.
        var engine = SessionEngine()
        expect(engine.restoreCompletedRounds(3) && engine.completedRounds == 3 && engine.currentRound == 3,
               "A saved count restores the round number")
        expect(engine.start(now: Date()) && engine.isLongBreak,
               "After 3 saved rounds, the next round gets the 10-minute break")
        expect(!engine.restoreCompletedRounds(0) && engine.completedRounds == 3,
               "The count cannot change during a round")
        engine.reset()
        expect(!engine.restoreCompletedRounds(-1) && engine.completedRounds == 3,
               "A negative count is rejected")
        expect(engine.restoreCompletedRounds(0) && engine.upcomingRound == 1 && engine.activeBreakMinutes == nil,
               "A new day restores to zero")

        // Daily summary: rounds and focus time of completed rounds.
        var summary = DailyRounds(day: "2026-11-02")
        expect(summary.summary == "Today: no rounds yet", "An empty day says no rounds yet")
        summary.recordRound(today: "2026-11-02", focusMinutes: 20)
        expect(summary.summary == "Today: 1 round · 20m focused", "One round uses the singular")
        summary.recordRound(today: "2026-11-02", focusMinutes: 25)
        summary.recordRound(today: "2026-11-02", focusMinutes: 15)
        expect(summary.focusMinutes == 60 && summary.summary == "Today: 3 rounds · 1h 0m focused",
               "Mixed focus times add up, shown in hours and minutes")
        for _ in 1...3 { summary.recordRound(today: "2026-11-02", focusMinutes: 20) }
        expect(summary.summary == "Today: 6 rounds · 2h 0m focused", "Six 20-minute rounds are 2 hours")
        summary.recordRound(today: "2026-11-02", focusMinutes: 10)
        expect(summary.summary == "Today: 7 rounds · 2h 10m focused", "Minutes past the hour are shown")

        let reopened = DailyRounds(day: summary.day, rounds: summary.rounds, focusMinutes: summary.focusMinutes)
        expect(reopened == summary, "Saved rounds and focus time come back after reopening")
        var nextDay = reopened
        expect(nextDay.roll(to: "2026-11-03") && nextDay.summary == "Today: no rounds yet",
               "A new day clears both rounds and focus time")
        expect(nextDay.recordRound(today: "2026-11-04", focusMinutes: 25) == true
               && nextDay.summary == "Today: 1 round · 25m focused",
               "A round finishing on a new day starts that day's summary")
        expect(DailyRounds(day: "2026-11-02", rounds: 1, focusMinutes: -5).focusMinutes == 0,
               "Negative saved focus time becomes zero")

        print("DailyRounds: \(assertions) assertions passed.")
    }
}
