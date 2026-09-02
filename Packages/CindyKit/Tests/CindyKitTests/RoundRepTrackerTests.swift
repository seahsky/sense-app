import XCTest
@testable import CindyKit

final class RoundRepTrackerTests: XCTestCase {
    func testInitialState() {
        let tracker = RoundRepTracker(variant: .rx)

        XCTAssertEqual(tracker.completedRounds, 0)
        XCTAssertEqual(tracker.currentStepIndex, 0)
        XCTAssertEqual(tracker.repsInCurrentMovement, 0)
        XCTAssertEqual(tracker.currentMovement, .pullUp)
        XCTAssertEqual(tracker.partialReps, 0)
        XCTAssertEqual(tracker.scoreString, "0+0")
    }

    func testLoggingWithinFirstMovement() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<4 { tracker.logRep() }

        XCTAssertEqual(tracker.currentStepIndex, 0)
        XCTAssertEqual(tracker.repsInCurrentMovement, 4)
        XCTAssertEqual(tracker.currentMovement, .pullUp)
        XCTAssertEqual(tracker.scoreString, "0+4")
    }

    func testMovementAdvancesWhenRepTargetIsReached() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<5 { tracker.logRep() } // 5th pull-up completes that movement

        XCTAssertEqual(tracker.currentStepIndex, 1)
        XCTAssertEqual(tracker.repsInCurrentMovement, 0)
        XCTAssertEqual(tracker.currentMovement, .pushUp)
        XCTAssertEqual(tracker.scoreString, "0+5")
    }

    func testRoundCompletesAndScoreFormatsAsRoundsPlusReps() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<30 { tracker.logRep() } // 5 + 10 + 15 = one full round

        XCTAssertEqual(tracker.completedRounds, 1)
        XCTAssertEqual(tracker.currentStepIndex, 0)
        XCTAssertEqual(tracker.repsInCurrentMovement, 0)
        XCTAssertEqual(tracker.currentMovement, .pullUp)
        XCTAssertEqual(tracker.scoreString, "1+0")
    }

    func testPartialRepsAreMovementOrderedIntoTheNextRound() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<38 { tracker.logRep() } // 1 round (30) + 5 pull-ups + 3 push-ups

        XCTAssertEqual(tracker.completedRounds, 1)
        XCTAssertEqual(tracker.currentStepIndex, 1)
        XCTAssertEqual(tracker.repsInCurrentMovement, 3)
        XCTAssertEqual(tracker.currentMovement, .pushUp)
        XCTAssertEqual(tracker.partialReps, 8)
        XCTAssertEqual(tracker.scoreString, "1+8")
    }

    func testMultipleRoundsAccumulate() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<75 { tracker.logRep() } // 2 full rounds (60) + 5 + 10 into round 3

        XCTAssertEqual(tracker.completedRounds, 2)
        XCTAssertEqual(tracker.partialReps, 15)
        XCTAssertEqual(tracker.currentMovement, .airSquat)
        XCTAssertEqual(tracker.scoreString, "2+15")
    }

    func testUndoLastRepWithinAMovement() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<38 { tracker.logRep() }
        tracker.undoLastRep()

        XCTAssertEqual(tracker.completedRounds, 1)
        XCTAssertEqual(tracker.currentStepIndex, 1)
        XCTAssertEqual(tracker.repsInCurrentMovement, 2)
        XCTAssertEqual(tracker.scoreString, "1+7")
    }

    func testUndoLastRepReversesARoundCompletion() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<30 { tracker.logRep() }
        XCTAssertEqual(tracker.scoreString, "1+0")

        tracker.undoLastRep()

        XCTAssertEqual(tracker.completedRounds, 0)
        XCTAssertEqual(tracker.currentStepIndex, 2)
        XCTAssertEqual(tracker.repsInCurrentMovement, 14)
        XCTAssertEqual(tracker.currentMovement, .airSquat)
        XCTAssertEqual(tracker.scoreString, "0+29")
    }

    func testUndoLastRepIsNoOpWhenNoRepsLogged() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.undoLastRep()

        XCTAssertEqual(tracker.completedRounds, 0)
        XCTAssertEqual(tracker.scoreString, "0+0")
    }

    func testReset() {
        let tracker = RoundRepTracker(variant: .rx)
        for _ in 0..<12 { tracker.logRep() }
        tracker.reset()

        XCTAssertEqual(tracker.completedRounds, 0)
        XCTAssertEqual(tracker.currentStepIndex, 0)
        XCTAssertEqual(tracker.repsInCurrentMovement, 0)
        XCTAssertEqual(tracker.scoreString, "0+0")
    }
}
