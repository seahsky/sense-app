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

// MARK: - Rep provenance and timestamps
//
// Added with automatic rep detection: the tracker stores rep *events* rather than
// a bare count, so rest detection has a timestamp to work from and correction can
// tell the app's guesses apart from the athlete's assertions.

extension RoundRepTrackerTests {
    func testLoggedRepRecordsItsSourceAndTime() {
        let tracker = RoundRepTracker(variant: .rx)
        let when = Date(timeIntervalSince1970: 1_000_000)

        tracker.logRep(at: when, source: .detected)

        XCTAssertEqual(tracker.events.count, 1)
        XCTAssertEqual(tracker.events.first?.source, .detected)
        XCTAssertEqual(tracker.lastRepAt, when)
        XCTAssertEqual(tracker.totalRepsLogged, 1)
    }

    func testDefaultSourceIsManualSoExistingCallSitesAreUnchanged() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep()
        XCTAssertEqual(tracker.events.first?.source, .manual)
        XCTAssertTrue(tracker.events.first?.source.isUserConfirmed ?? false)
    }

    func testLastRepAtIsNilBeforeAnyRep() {
        XCTAssertNil(RoundRepTracker(variant: .rx).lastRepAt)
    }

    func testLogRepsAddsABurstAtOneInstant() {
        let tracker = RoundRepTracker(variant: .rx)
        let when = Date(timeIntervalSince1970: 1_000_000)

        tracker.logReps(3, at: when, source: .crown)

        XCTAssertEqual(tracker.totalRepsLogged, 3)
        XCTAssertEqual(tracker.scoreString, "0+3")
        XCTAssertTrue(tracker.events.allSatisfy { $0.date == when && $0.source == .crown })
    }

    func testLogRepsIgnoresNonPositiveCounts() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logReps(0)
        tracker.logReps(-5)
        XCTAssertEqual(tracker.totalRepsLogged, 0)
    }

    func testUndoTrailingDetectedRepsRemovesOnlyTheAppsGuesses() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep(source: .manual)
        tracker.logRep(source: .manual)
        tracker.logRep(source: .detected)
        tracker.logRep(source: .detected)

        XCTAssertEqual(tracker.trailingDetectedRepCount, 2)
        XCTAssertEqual(tracker.undoTrailingDetectedReps(), 2)
        XCTAssertEqual(tracker.totalRepsLogged, 2)
        XCTAssertTrue(tracker.events.allSatisfy { $0.source == .manual })
    }

    func testUndoTrailingDetectedRepsStopsAtAManualRep() {
        // Reaching back past a rep the athlete confirmed would silently rewrite
        // history they already asserted.
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep(source: .detected)
        tracker.logRep(source: .manual)
        tracker.logRep(source: .detected)

        XCTAssertEqual(tracker.undoTrailingDetectedReps(), 1)
        XCTAssertEqual(tracker.totalRepsLogged, 2)
        XCTAssertEqual(tracker.events.map(\.source), [.detected, .manual])
    }

    func testUndoTrailingDetectedRepsIsANoOpWhenTheLastRepIsManual() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep(source: .manual)
        XCTAssertEqual(tracker.undoTrailingDetectedReps(), 0)
        XCTAssertEqual(tracker.totalRepsLogged, 1)
    }

    func testUndoLastRepRemovesTheMostRecentEventRegardlessOfSource() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep(source: .manual)
        tracker.logRep(source: .detected)

        tracker.undoLastRep()

        XCTAssertEqual(tracker.events.map(\.source), [.manual])
        XCTAssertNotNil(tracker.lastRepAt)
    }

    func testResetClearsEventsAndTimestamp() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logReps(7)
        tracker.reset()

        XCTAssertTrue(tracker.events.isEmpty)
        XCTAssertNil(tracker.lastRepAt)
        XCTAssertEqual(tracker.scoreString, "0+0")
    }

    func testRepsRemainingInCurrentMovement() {
        let tracker = RoundRepTracker(variant: .rx)
        XCTAssertEqual(tracker.repsRemainingInCurrentMovement, 5)

        tracker.logReps(3)
        XCTAssertEqual(tracker.repsRemainingInCurrentMovement, 2)

        tracker.logReps(2) // closes out the pull-ups
        XCTAssertEqual(tracker.currentMovement, .pushUp)
        XCTAssertEqual(tracker.repsRemainingInCurrentMovement, 10)
    }
}

// MARK: - Boundary-gated automatic detection
//
// The contract: the detector may do the bulk of a movement but never the rep that
// closes it, so the sequence can never advance without the athlete.

final class BoundaryGatedDetectionTests: XCTestCase {
    func testAllowanceStopsOneShortOfTheBoundary() {
        let tracker = RoundRepTracker(variant: .rx)
        XCTAssertEqual(tracker.repsRemainingInCurrentMovement, 5)
        XCTAssertEqual(tracker.detectedRepAllowance, 4, "5 pull-ups means at most 4 detected")

        tracker.logReps(4, source: .detected)
        XCTAssertEqual(tracker.detectedRepAllowance, 0)
        XCTAssertTrue(tracker.isAwaitingBoundaryRep)
    }

    func testDetectorCannotCloseAMovement() {
        let tracker = RoundRepTracker(variant: .rx)

        XCTAssertEqual(tracker.logDetectedReps(99), 4, "clamped to the allowance")
        XCTAssertEqual(tracker.currentMovement, .pullUp, "still on pull-ups")
        XCTAssertEqual(tracker.repsInCurrentMovement, 4)

        // Further detection is refused outright rather than queued: a queue would
        // let the athlete's boundary tap release a burst of stale guesses.
        XCTAssertEqual(tracker.logDetectedReps(5), 0)
        XCTAssertEqual(tracker.totalRepsLogged, 4)
    }

    func testAthleteTapAdvancesTheMovement() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logDetectedReps(10)
        XCTAssertEqual(tracker.currentMovement, .pullUp)

        tracker.logRep(source: .manual)

        XCTAssertEqual(tracker.currentMovement, .pushUp)
        XCTAssertEqual(tracker.detectedRepAllowance, 9, "10 push-ups means at most 9 detected")
    }

    func testDetectorCannotCloseARoundEither() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logReps(29, source: .manual) // one air squat short of a full round

        XCTAssertTrue(tracker.isAwaitingBoundaryRep)
        XCTAssertEqual(tracker.logDetectedReps(4), 0)
        XCTAssertEqual(tracker.completedRounds, 0, "the round must not close on a guess")

        tracker.logRep(source: .manual)
        XCTAssertEqual(tracker.completedRounds, 1)
    }

    func testAWholeRoundCostsExactlyThreeAthleteTaps() {
        // The point of the feature, expressed as a test: 30 taps become 3.
        let tracker = RoundRepTracker(variant: .rx)
        var taps = 0

        for _ in 0..<3 {
            tracker.logDetectedReps(99)
            tracker.logRep(source: .manual)
            taps += 1
        }

        XCTAssertEqual(taps, 3)
        XCTAssertEqual(tracker.completedRounds, 1)
        XCTAssertEqual(tracker.scoreString, "1+0")
    }

    func testUndercountingIsCorrectedByTappingUntilItAdvances() {
        // The detector misses two of five. The athlete does not need to know that
        // — they just keep tapping until the movement changes.
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logDetectedReps(3) // caught 3 of the 5 the athlete performed

        tracker.logRep(source: .manual)
        XCTAssertEqual(tracker.currentMovement, .pullUp, "still owed one")
        tracker.logRep(source: .manual)
        XCTAssertEqual(tracker.currentMovement, .pushUp)
        XCTAssertEqual(tracker.totalRepsLogged, 5)
    }

    func testOvercountingIsCorrectedWithoutLosingAssertedReps() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep(source: .manual)
        tracker.logDetectedReps(3)
        XCTAssertEqual(tracker.totalRepsLogged, 4)

        XCTAssertEqual(tracker.undoTrailingDetectedReps(), 3)
        XCTAssertEqual(tracker.totalRepsLogged, 1)
        XCTAssertEqual(tracker.events.map(\.source), [.manual])
    }

    func testAllowanceIsZeroWhenNothingIsOwed() {
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logReps(5, source: .manual)
        XCTAssertEqual(tracker.repsRemainingInCurrentMovement, 10)
        XCTAssertEqual(tracker.detectedRepAllowance, 9)
        XCTAssertFalse(tracker.isAwaitingBoundaryRep)
    }

    func testDetectedFraction() {
        let tracker = RoundRepTracker(variant: .rx)
        XCTAssertEqual(tracker.detectedRepFraction, 0, accuracy: 1e-9, "no reps means no claim")

        tracker.logDetectedReps(3)
        tracker.logRep(source: .manual)
        XCTAssertEqual(tracker.detectedRepFraction, 0.75, accuracy: 1e-9)
    }

    func testLogDetectedRepsUsesDetectedProvenance() {
        let tracker = RoundRepTracker(variant: .rx)
        let when = Date(timeIntervalSince1970: 1_000_000)
        tracker.logDetectedReps(2, at: when)
        XCTAssertTrue(tracker.events.allSatisfy { $0.source == .detected && $0.date == when })
        XCTAssertEqual(tracker.lastRepAt, when, "detected reps count as activity for rest detection")
    }
}
