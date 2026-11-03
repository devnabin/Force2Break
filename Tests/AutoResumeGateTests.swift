/// Standalone tests; compile this file with Source/AutoResumeGate.swift.
@main
enum AutoResumeGateTests {
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
        var gate = AutoResumeGate()
        expect(!gate.isArmed, "Opening the app must not arm automatic restart")
        expect(!gate.consume(activityCount: 1),
               "Interaction at initial startup must not start focus")
        expect(!gate.consume(activityCount: nil), "Unavailable initial polls do nothing")

        expect(gate.arm(activityCount: 100), "A completed break must arm from a snapshot")
        expect(gate.isArmed, "A valid snapshot must leave the gate armed")
        for _ in 0..<20 {
            expect(!gate.consume(activityCount: 100),
                   "Pre-break interaction and idle polling must not restart focus")
        }
        expect(gate.isArmed, "An idle desktop must remain armed and idle")
        expect(!gate.consume(activityCount: nil), "An unavailable poll must be ignored")
        expect(gate.isArmed, "An unavailable poll must not consume the gate")
        expect(!gate.consume(activityCount: 100),
               "Returning availability with no interaction must still remain idle")
        expect(gate.consume(activityCount: 101),
               "The first fresh interaction after the break must restart focus")
        expect(!gate.isArmed, "A consumed gate must disarm immediately")
        expect(!gate.consume(activityCount: 101), "The same signal cannot restart twice")
        expect(!gate.consume(activityCount: 105), "Later interaction cannot restart twice")

        expect(gate.arm(activityCount: 105), "The next completed break may arm again")
        expect(!gate.consume(activityCount: 105), "Rearming must capture the new baseline")
        expect(gate.consume(activityCount: 109),
               "Several interactions between polls must count as a single restart")
        expect(!gate.consume(activityCount: 110), "A batch of interactions remains one-shot")

        expect(gate.arm(activityCount: UInt64.max), "A maximum counter is a valid snapshot")
        expect(!gate.consume(activityCount: UInt64.max), "An unchanged maximum stays idle")
        expect(gate.consume(activityCount: 0), "UInt64 wrapping must count as new activity")
        expect(!gate.isArmed, "A wrap-triggered restart is also one-shot")

        // Every explicit lifecycle cancellation uses the same pure operation.
        for reason in ["manual Start", "settings edit", "emergency release", "quit"] {
            gate.arm(activityCount: 200)
            gate.cancel()
            expect(!gate.isArmed, "\(reason) must disarm automatic restart")
            expect(!gate.consume(activityCount: 201),
                   "Interaction after \(reason) must not start a stale cycle")
            gate.cancel()
            expect(!gate.isArmed, "Cancellation must be idempotent")
        }

        expect(!gate.arm(activityCount: nil),
               "A break without an available baseline must not arm")
        expect(!gate.consume(activityCount: 300),
               "Availability returning alone must not invent a completed-break baseline")
        gate.arm(activityCount: 300)
        expect(!gate.arm(activityCount: nil),
               "An unavailable replacement baseline must clear an older armed cycle")
        expect(!gate.isArmed && !gate.consume(activityCount: 301),
               "An unavailable arm must leave no stale automatic restart")

        gate.arm(activityCount: 400)
        gate.arm(activityCount: 405)
        expect(!gate.consume(activityCount: 405),
               "Rearming must replace the old cycle's interaction baseline")
        expect(gate.consume(activityCount: 406),
               "Only activity after the replacement snapshot may restart focus")

        for interaction in ["click", "key", "pointer movement", "scroll"] {
            gate.arm(activityCount: 500)
            expect(gate.consume(activityCount: 501),
                   "An aggregate change from a \(interaction) must restart focus")
            expect(!gate.isArmed && !gate.consume(activityCount: 502),
                   "A \(interaction) restart must remain one-shot")
        }
        let largeAggregate = UInt64(UInt32.max) + 20
        expect(gate.arm(activityCount: largeAggregate),
               "Aggregated source counts must support values beyond UInt32")
        expect(!gate.consume(activityCount: largeAggregate),
               "A large unchanged aggregate must remain idle")
        expect(gate.consume(activityCount: 21),
               "An individual UInt32 source wrapping must still count as interaction")

        print("AutoResumeGate: \(assertions) assertions passed.")
    }
}
