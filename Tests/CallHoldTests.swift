import Foundation

/// Standalone tests; compile this file with Source/CallHold.swift.
@main
enum CallHoldTests {
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
        let origin = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let limit = CallHold.maximumDelay
        expect(limit == 900, "A call may delay a break by at most 15 minutes")

        var hold = CallHold()
        expect(!hold.shouldHold(callInProgress: false, now: origin),
               "No call must never delay the break")
        expect(!hold.shouldHold(callInProgress: true, now: origin + 1),
               "A call starting after release must not delay the same break")

        hold.reset()
        for second in stride(from: 0.0, to: limit, by: 0.2) {
            expect(hold.shouldHold(callInProgress: true, now: origin + second),
                   "An ongoing call must delay the break until the limit")
        }
        expect(hold.isHolding && hold.remainingDelay(now: origin + 600) == 300,
               "The remaining delay must count down from the first hold")
        expect(!hold.shouldHold(callInProgress: true, now: origin + limit),
               "A call must not delay the break past the limit")
        expect(!hold.isHolding && hold.remainingDelay(now: origin + limit) == 0,
               "A released hold must report no remaining delay")

        hold.reset()
        expect(hold.shouldHold(callInProgress: true, now: origin),
               "Each new focus may be held once")
        expect(!hold.shouldHold(callInProgress: false, now: origin + 120),
               "Ending the call must release the break immediately")
        expect(!hold.shouldHold(callInProgress: true, now: origin + 121),
               "A second call must not hold a released break")

        print("CallHold: \(assertions) assertions passed.")
    }
}
