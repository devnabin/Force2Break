import Foundation

/// Standalone tests; run with:
/// swiftc Source/SessionEngine.swift Tests/SessionEngineTests.swift -o /tmp/fore2break-tests
/// /tmp/fore2break-tests
@main
enum SessionEngineTests {
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
        let origin = Date(timeIntervalSince1970: 1_700_000_000)

        var engine = SessionEngine()
        expect(engine.focusMinutes == 20 && engine.breakMinutes == 3,
               "Defaults must be 20 minutes of focus and 3 minutes of break")
        expect(engine.phase == .ready && engine.deadline == nil,
               "Opening the app must wait for the circle click")
        expect(engine.tick(now: origin) == nil, "Ready must not advance itself")
        expect(engine.remainingSeconds(now: origin) == 0, "Ready has no countdown")
        expect(SessionEngine.focusOptions == [10, 15, 20, 25],
               "Focus choices must match the four-button popup")

        let invalid = SessionEngine(focusMinutes: -1, breakMinutes: 99)
        expect(invalid.focusMinutes == 20 && invalid.breakMinutes == 3,
               "Invalid saved values must fall back safely")
        let partial = SessionEngine(focusMinutes: 10, breakMinutes: 99)
        expect(partial.focusMinutes == 10 && partial.breakMinutes == 3,
               "A valid saved setting must survive an invalid companion")
        let removedOption = SessionEngine(focusMinutes: 30, breakMinutes: 4)
        expect(removedOption.focusMinutes == 20 && removedOption.breakMinutes == 4,
               "A previously saved 30-minute focus must fall back to the default")

        for focus in SessionEngine.focusOptions {
            for rest in SessionEngine.breakOptions {
                expect(engine.updateSettings(focusMinutes: focus, breakMinutes: rest),
                       "Every advertised settings combination must be accepted")
                expect(engine.focusMinutes == focus && engine.breakMinutes == rest,
                       "Selected settings must be stored")
            }
        }
        expect(!engine.updateSettings(focusMinutes: 12, breakMinutes: 2),
               "An unsupported focus length must be rejected")
        expect(engine.focusMinutes == 25 && engine.breakMinutes == 5,
               "Invalid updates must not partially change settings")
        expect(!engine.updateSettings(focusMinutes: 30, breakMinutes: 2),
               "The removed 30-minute focus length must be rejected")
        expect(!engine.updateSettings(focusMinutes: 10, breakMinutes: 1),
               "An unsupported break length must be rejected")

        engine = SessionEngine()
        expect(engine.start(now: origin), "The ready circle must start focus")
        expect(engine.phase == .focusing, "Click must enter focus")
        expect(engine.deadline == origin.addingTimeInterval(1_200),
               "Focus must end 20 minutes from the click")
        expect(engine.phaseStartedAt == origin && engine.phaseDuration == 1_200,
               "Phase timing metadata must describe the running focus")
        expect(engine.remainingSeconds(now: origin) == 1_200, "Initial countdown")
        expect(engine.remainingSeconds(now: origin.addingTimeInterval(1_199.1)) == 1,
               "Countdown must round up the final fraction of a second")
        expect(engine.remainingSeconds(now: origin.addingTimeInterval(1_300)) == 0,
               "An overdue phase must never show a negative countdown")
        expect(!engine.start(now: origin.addingTimeInterval(100)),
               "Repeated clicks must not restart focus")
        expect(engine.deadline == origin.addingTimeInterval(1_200),
               "Repeated clicks must not extend the deadline")
        expect(engine.tick(now: origin.addingTimeInterval(1_199.999)) == nil,
               "A focus phase must not finish early")
        expect(engine.tick(now: origin.addingTimeInterval(1_200)) == .focusEnded,
               "Focus must finish at its exact deadline")
        expect(engine.phase == .breaking, "Focus completion must enter break")
        expect(engine.deadline == origin.addingTimeInterval(1_380),
               "The default break must last a full 3 minutes")
        expect(engine.phaseStartedAt == origin.addingTimeInterval(1_200)
               && engine.phaseDuration == 180, "Break timing metadata")
        expect(!engine.start(now: origin.addingTimeInterval(1_201)),
               "Clicking during a break must not bypass the break")
        expect(engine.tick(now: origin.addingTimeInterval(1_200)) == nil,
               "Focus completion must be emitted only once")
        expect(engine.tick(now: origin.addingTimeInterval(1_379.999)) == nil,
               "The break must not end early")
        expect(engine.tick(now: origin.addingTimeInterval(1_380)) == .breakEnded,
               "The break must end at its exact deadline")
        expect(engine.phase == .ready && engine.deadline == nil,
               "Break completion must restore the ready circle")
        expect(engine.phaseStartedAt == nil && engine.phaseDuration == nil,
               "Ready must clear active timing metadata")
        expect(engine.tick(now: origin.addingTimeInterval(10_000)) == nil,
               "Further time passing must not start another cycle")
        expect(engine.start(now: origin.addingTimeInterval(10_001)),
               "A new circle click must start the next cycle")

        // The process can miss many timer callbacks or sleep through a deadline.
        var late = SessionEngine(focusMinutes: 10, breakMinutes: 2)
        late.start(now: origin)
        let wake = origin.addingTimeInterval(7_200)
        expect(late.tick(now: wake) == .focusEnded,
               "A missed focus deadline must be detected after wake")
        expect(late.phase == .breaking && late.deadline == wake.addingTimeInterval(120),
               "Waking late must still require a complete visible break")
        expect(late.tick(now: wake.addingTimeInterval(119)) == nil,
               "A late focus deadline must not consume the break")
        expect(late.tick(now: wake.addingTimeInterval(3_600)) == .breakEnded,
               "A break whose own deadline passed during sleep must end on wake")
        expect(late.phase == .ready, "Wake after break must still wait for a click")

        // Settings apply to the next clicked cycle, including its break length.
        var edited = SessionEngine(focusMinutes: 15, breakMinutes: 4)
        edited.start(now: origin)
        expect(edited.updateSettings(focusMinutes: 25, breakMinutes: 5),
               "Settings may be saved while focus runs")
        expect(edited.deadline == origin.addingTimeInterval(900),
               "Saving settings must not reset an active focus deadline")
        edited.tick(now: origin.addingTimeInterval(900))
        expect(edited.deadline == origin.addingTimeInterval(1_140),
               "An active cycle must retain its original 4-minute break")
        expect(edited.updateSettings(focusMinutes: 25, breakMinutes: 2),
               "A valid break-time settings edit must be accepted")
        expect(edited.deadline == origin.addingTimeInterval(1_140),
               "Saving settings during break must not change its deadline")
        edited.tick(now: origin.addingTimeInterval(1_140))
        edited.start(now: origin.addingTimeInterval(1_141))
        expect(edited.deadline == origin.addingTimeInterval(2_641),
               "The next click must use the newly selected 25-minute focus")
        edited.tick(now: origin.addingTimeInterval(2_641))
        expect(edited.deadline == origin.addingTimeInterval(2_761),
               "The next cycle must use the newly selected 2-minute break")
        edited.reset()
        expect(edited.phase == .ready && edited.deadline == nil,
               "Explicit reset must clear the active cycle")
        expect(edited.focusMinutes == 25 && edited.breakMinutes == 2,
               "Reset must preserve selected settings")
        expect(edited.tick(now: origin.addingTimeInterval(9_999)) == nil,
               "Reset must leave no stale deadline")

        checkRoundCadence(origin: origin)
        checkAbandonedRounds(origin: origin)
        checkLongBreakSettingsAndSleep(origin: origin)

        print("SessionEngine: \(assertions) assertions passed.")
    }

    static func checkRoundCadence(origin: Date) {
        expect(SessionEngine.longBreakMinutes == 10 && SessionEngine.longBreakCadence == 4,
               "Every fourth completed round must have a 10-minute break")

        // Explicit schedules verify both the fourth and eighth round for every
        // selectable short break, rather than deriving the expected cadence.
        for focusMinutes in SessionEngine.focusOptions {
        for shortMinutes in SessionEngine.breakOptions {
            var engine = SessionEngine(focusMinutes: focusMinutes, breakMinutes: shortMinutes)
            expect(engine.focusMinutes == focusMinutes && engine.breakMinutes == shortMinutes,
                   "Every selectable focus and break pair must be accepted")
            var start = origin
            let short = TimeInterval(shortMinutes * 60)
            let expectedBreaks = [short, short, short, 600, short, short, short, 600,
                                  short, short, short, 600]

            for (index, breakSeconds) in expectedBreaks.enumerated() {
                let round = index + 1
                expect(engine.completedRounds == index && engine.currentRound == index
                       && engine.upcomingRound == round,
                       "Ready must show completed rounds and the next round number")
                expect(!engine.isLongBreak && engine.activeBreakMinutes == nil,
                       "Ready must not retain a completed round's long-break state")
                expect(engine.start(now: start), "Each explicit Start must begin its round")
                expect(engine.currentRound == round && engine.completedRounds == index,
                       "Starting focus must not count a round as complete")
                expect(engine.isLongBreak == (breakSeconds == 600)
                       && engine.activeBreakMinutes == Int(breakSeconds / 60),
                       "The round must snapshot its scheduled break at Start")

                let focusEnd = start.addingTimeInterval(TimeInterval(focusMinutes * 60))
                expect(engine.tick(now: focusEnd.addingTimeInterval(-0.001)) == nil,
                       "Focus must last its full selected duration")
                expect(engine.tick(now: focusEnd) == .focusEnded,
                       "Each round must finish focus before its break")
                expect(engine.phaseDuration == breakSeconds
                       && engine.deadline == focusEnd.addingTimeInterval(breakSeconds),
                       "Scheduled breaks must use their exact full duration")
                expect(engine.completedRounds == index && engine.currentRound == round,
                       "Entering a break must not count its round as complete")
                let breakEnd = focusEnd.addingTimeInterval(breakSeconds)
                expect(engine.tick(now: breakEnd.addingTimeInterval(-0.001)) == nil,
                       "Neither short nor long breaks may end early")
                expect(engine.remainingSeconds(now: breakEnd.addingTimeInterval(-0.001)) == 1,
                       "Every break must display the final fraction of a second")
                expect(engine.tick(now: breakEnd) == .breakEnded,
                       "A natural break deadline must complete the round")
                expect(engine.phase == .ready && engine.completedRounds == round
                       && engine.currentRound == round && engine.upcomingRound == round + 1,
                       "Natural completion must increment the round exactly once")
                expect(engine.tick(now: breakEnd) == nil && engine.completedRounds == round,
                       "Repeated completion ticks must not count a second round")
                engine.reset()
                expect(engine.completedRounds == round,
                       "An idle reset must preserve the completed total")
                start = breakEnd.addingTimeInterval(1)
            }
        }
        }

        // Changing focus time between rounds must not shift the long-break cadence.
        var mixed = SessionEngine(focusMinutes: 25, breakMinutes: 3)
        var start = origin
        for round in 1...8 {
            let focusMinutes = SessionEngine.focusOptions[(round - 1) % SessionEngine.focusOptions.count]
            expect(mixed.updateSettings(focusMinutes: focusMinutes, breakMinutes: 3),
                   "Focus time may change between rounds")
            expect(mixed.start(now: start), "Each mixed-focus round must start")
            let focusEnd = start.addingTimeInterval(TimeInterval(focusMinutes * 60))
            expect(mixed.tick(now: focusEnd) == .focusEnded, "Mixed-focus round must finish focus")
            let expected = round.isMultiple(of: 4) ? 600.0 : 180.0
            expect(mixed.isLongBreak == round.isMultiple(of: 4) && mixed.phaseDuration == expected,
                   "Every fourth round must get 10 minutes regardless of focus changes")
            let breakEnd = focusEnd.addingTimeInterval(expected)
            expect(mixed.tick(now: breakEnd) == .breakEnded && mixed.completedRounds == round,
                   "Mixed-focus break must complete its round")
            start = breakEnd.addingTimeInterval(1)
        }
    }

    /// Completes three ordinary rounds to reach the fourth-round boundary.
    static func completeThreeRounds(_ engine: inout SessionEngine, from origin: Date) -> Date {
        var start = origin
        for completed in 1...3 {
            expect(engine.start(now: start), "Preparation round must start")
            let focusEnd = start.addingTimeInterval(TimeInterval(engine.focusMinutes * 60))
            expect(engine.tick(now: focusEnd) == .focusEnded,
                   "Preparation round must finish focus")
            let breakEnd = focusEnd.addingTimeInterval(TimeInterval(engine.breakMinutes * 60))
            expect(engine.tick(now: breakEnd) == .breakEnded
                   && engine.completedRounds == completed,
                   "Preparation must count only naturally completed rounds")
            start = breakEnd.addingTimeInterval(1)
        }
        return start
    }

    static func checkAbandonedRounds(origin: Date) {
        var first = SessionEngine()
        first.start(now: origin)
        first.reset()
        expect(first.completedRounds == 0 && first.currentRound == 0 && first.upcomingRound == 1,
               "Abandoning the first focus must not invent a completed round")
        first.start(now: origin)
        first.tick(now: origin.addingTimeInterval(1_200))
        first.reset()
        expect(first.completedRounds == 0 && !first.isLongBreak,
               "Abandoning an ordinary break must not count its round")

        var fourth = SessionEngine(focusMinutes: 10, breakMinutes: 3)
        var start = completeThreeRounds(&fourth, from: origin)
        fourth.start(now: start)
        expect(fourth.currentRound == 4 && fourth.isLongBreak,
               "The focus after three completions must belong to long-break round four")
        fourth.reset()
        expect(fourth.completedRounds == 3 && fourth.currentRound == 3
               && fourth.upcomingRound == 4 && !fourth.isLongBreak,
               "Abandoning fourth-round focus must preserve the long-break boundary")
        start = start.addingTimeInterval(1)
        fourth.start(now: start)
        expect(fourth.currentRound == 4 && fourth.activeBreakMinutes == 10,
               "Restarting an abandoned fourth focus must retain its 10-minute break")
        let focusEnd = start.addingTimeInterval(600)
        fourth.tick(now: focusEnd)
        fourth.reset() // The app's emergency release uses this same abandonment.
        expect(fourth.completedRounds == 3 && fourth.activeBreakMinutes == nil,
               "Emergency release during a long break must not complete the round")
        expect(fourth.tick(now: focusEnd.addingTimeInterval(5_000)) == nil
               && fourth.completedRounds == 3,
               "An abandoned break's stale deadline must never increment the total")
        start = focusEnd.addingTimeInterval(5_001)
        fourth.start(now: start)
        expect(fourth.currentRound == 4 && fourth.isLongBreak,
               "An abandoned fourth break must retry on the next cycle")
        fourth.tick(now: start.addingTimeInterval(600))
        expect(fourth.phaseDuration == 600,
               "Retrying the fourth round must still require the full long break")
        fourth.tick(now: start.addingTimeInterval(1_200))
        expect(fourth.completedRounds == 4 && fourth.currentRound == 4
               && fourth.upcomingRound == 5,
               "Only a naturally finished retry may advance to round five")
    }

    static func checkLongBreakSettingsAndSleep(origin: Date) {
        var engine = SessionEngine(focusMinutes: 10, breakMinutes: 2)
        let start = completeThreeRounds(&engine, from: origin)
        engine.start(now: start)
        let focusDeadline = engine.deadline
        expect(engine.updateSettings(focusMinutes: 25, breakMinutes: 5),
               "New settings may be saved during fourth-round focus")
        expect(engine.deadline == focusDeadline && engine.activeBreakMinutes == 10
               && engine.completedRounds == 3,
               "Saving settings must preserve the active fourth-round snapshot")

        let wake = start.addingTimeInterval(7_200)
        expect(engine.tick(now: wake) == .focusEnded && engine.isLongBreak,
               "Waking after fourth-round focus must enter its long break")
        expect(engine.phaseDuration == 600 && engine.deadline == wake.addingTimeInterval(600),
               "A missed fourth-round focus deadline must require a full 10-minute break")
        expect(engine.updateSettings(focusMinutes: 15, breakMinutes: 4),
               "Settings may be saved during a long break")
        expect(engine.activeBreakMinutes == 10 && engine.deadline == wake.addingTimeInterval(600),
               "Short-break edits must never shorten an active long break")
        expect(engine.tick(now: wake.addingTimeInterval(599.999)) == nil
               && engine.completedRounds == 3,
               "A long break cannot count as completed before its full deadline")
        expect(engine.tick(now: wake.addingTimeInterval(600)) == .breakEnded
               && engine.completedRounds == 4,
               "A natural long-break completion must count one round")
        expect(engine.focusMinutes == 15 && engine.breakMinutes == 4,
               "The long-break override must not replace saved short-break settings")
        let fifthStart = wake.addingTimeInterval(601)
        engine.start(now: fifthStart)
        expect(engine.currentRound == 5 && !engine.isLongBreak
               && engine.activeBreakMinutes == 4 && engine.phaseDuration == 900,
               "Round five must return to the latest saved focus and short break")
        engine.tick(now: fifthStart.addingTimeInterval(900))
        expect(engine.phaseDuration == 240,
               "The first round after a long break must use its selected short duration")
    }
}
