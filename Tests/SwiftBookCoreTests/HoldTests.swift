import Testing

@testable import SwiftBookCore

@Suite struct HoldTests {
    @Test func countsCapturesAsAnIdleMachineWouldTakeThem() {
        #expect(Hold(duration: .zero).captures == 0)
        #expect(Hold(duration: .seconds(1)).captures == 20)
        #expect(Hold(duration: .milliseconds(70)).captures == 2)
    }

    @Test func needsBothTheTimeAndTheCaptures() {
        let hold = Hold(duration: .seconds(1))
        // Idle: captures every 50 ms, so both arrive together.
        #expect(hold.isSatisfied(stable: .seconds(1), identical: 20))
        // Loaded: the time passed, but captures came slower, so it waits on.
        #expect(!hold.isSatisfied(stable: .seconds(1), identical: 5))
        #expect(hold.isSatisfied(stable: .seconds(4), identical: 20))
        // Enough captures can't make up for too little time.
        #expect(!hold.isSatisfied(stable: .milliseconds(500), identical: 40))
        // No hold: any run of identical captures will do.
        #expect(Hold(duration: .zero).isSatisfied(stable: .zero, identical: 1))
    }

    @Test func givesHeldStoriesALongerCeiling() {
        #expect(Hold(duration: .zero).timeout(otherwise: .seconds(2)) == .seconds(2))
        #expect(Hold(duration: .seconds(1)).timeout(otherwise: .seconds(2)) == Hold.ceiling)
    }
}
