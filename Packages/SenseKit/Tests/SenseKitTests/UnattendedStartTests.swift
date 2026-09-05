import XCTest
@testable import SenseKit

final class UnattendedStartTests: XCTestCase {
    // MARK: - Abandoning an attempt nobody is watching

    func testAStartButtonAttemptIsNeverAbandoned() {
        // The athlete watched this one begin. Ten minutes of an empty score is
        // their business, and neither rule may reach it.
        XCTAssertFalse(
            UnattendedStart.shouldAbandonUnattended(trigger: .startButton, elapsed: 600, hasAssertedARep: false)
        )
        XCTAssertFalse(
            UnattendedStart.shouldDiscardOnEnd(trigger: .startButton, hasAssertedARep: false)
        )
    }

    func testAnUntouchedComplicationAttemptIsAbandonedAtTheWindow() {
        // The boundary is inclusive, so the Task that sleeps for exactly
        // `abandonAfter` and then asks fires on its first ask rather than never.
        XCTAssertTrue(
            UnattendedStart.shouldAbandonUnattended(
                trigger: .complication,
                elapsed: UnattendedStart.abandonAfter,
                hasAssertedARep: false
            )
        )
    }

    func testAnUntouchedComplicationAttemptSurvivesInsideTheWindow() {
        XCTAssertFalse(
            UnattendedStart.shouldAbandonUnattended(trigger: .complication, elapsed: 119, hasAssertedARep: false)
        )
    }

    func testOneAssertedRepKeepsAComplicationAttemptAlive() {
        // One tap is the athlete saying they are here. After that the attempt is
        // theirs, and the app has no business ending it however long the gaps get.
        XCTAssertFalse(
            UnattendedStart.shouldAbandonUnattended(trigger: .complication, elapsed: 600, hasAssertedARep: true)
        )
    }

    func testTheAbandonWindowIsTwoMinutes() {
        // Pinned because it is a taste call, not a derived number: two minutes is
        // long enough that a real attempt is never killed (a Cindy round runs
        // 60-70 seconds) and short enough that a pocket tap never becomes a
        // phantom 20:00 in Health. Changing it should be a deliberate edit here.
        XCTAssertEqual(UnattendedStart.abandonAfter, 120)
    }

    // MARK: - Discarding an attempt the athlete has ended

    func testAnUntouchedComplicationAttemptIsDiscardedOnEnd() {
        XCTAssertTrue(UnattendedStart.shouldDiscardOnEnd(trigger: .complication, hasAssertedARep: false))
    }

    func testAComplicationAttemptWithRepsGoesToSummary() {
        XCTAssertFalse(UnattendedStart.shouldDiscardOnEnd(trigger: .complication, hasAssertedARep: true))
    }

    // MARK: - What "nobody touched this" means

    func testTheDetectorAloneCannotTakeAnAttemptOutOfTheRules() {
        // The rules take a bare `Bool`, so nothing in their own signature says where
        // it comes from. It is always `RoundRepTracker.hasAssertedARep`, and this is
        // the case that keeps that honest: `detectedRepAllowance` returns 0 until
        // the athlete opens the movement block themselves, so a watch counting on
        // its own can never claim somebody was here.
        let tracker = RoundRepTracker(variant: .rx)
        XCTAssertEqual(tracker.logDetectedReps(3), 0)
        XCTAssertFalse(tracker.hasAssertedARep)
        XCTAssertTrue(
            UnattendedStart.shouldAbandonUnattended(
                trigger: .complication,
                elapsed: UnattendedStart.abandonAfter,
                hasAssertedARep: tracker.hasAssertedARep
            )
        )

        tracker.logRep()
        XCTAssertTrue(tracker.hasAssertedARep)
        XCTAssertFalse(
            UnattendedStart.shouldDiscardOnEnd(trigger: .complication, hasAssertedARep: tracker.hasAssertedARep)
        )
    }

    func testCorrectingAMiscountBackToZeroStillCountsAsHavingBeenThere() {
        // The case that made `hasAssertedARep` exist. `totalRepsLogged` is
        // `events.count`, and the undo button and a backwards Digital Crown both
        // drive it back down — so an athlete who logs three reps, decides they
        // miscounted, and takes all three back would score 0+0 on a count. Ending
        // there must still reach the Summary screen with Save and Discard, because
        // they were plainly at their watch.
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logReps(3, source: .crown)
        for _ in 0..<3 { tracker.undoLastRep() }

        XCTAssertEqual(tracker.totalRepsLogged, 0)
        XCTAssertTrue(tracker.hasAssertedARep)
        XCTAssertFalse(
            UnattendedStart.shouldDiscardOnEnd(trigger: .complication, hasAssertedARep: tracker.hasAssertedARep)
        )
        XCTAssertFalse(
            UnattendedStart.shouldAbandonUnattended(
                trigger: .complication,
                elapsed: 600,
                hasAssertedARep: tracker.hasAssertedARep
            )
        )
    }

    func testResettingATrackerDoesNotTakeBackHavingBeenThere() {
        // `reset()` clears the events for the same reason undo removes one, and it
        // must not hand the attempt back to the abandon rule either.
        let tracker = RoundRepTracker(variant: .rx)
        tracker.logRep()
        tracker.reset()

        XCTAssertEqual(tracker.totalRepsLogged, 0)
        XCTAssertTrue(tracker.hasAssertedARep)
    }
}
