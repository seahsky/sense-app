import XCTest
@testable import CindyKit

final class TrendAnalyticsTests: XCTestCase {
    private func makeSession(
        rounds: Int,
        reps: Int,
        variant: CindyVariant = .rx,
        duration: TimeInterval = 1200,
        date: Date = .now
    ) -> CindySession {
        CindySession(
            date: date,
            variant: variant,
            durationSeconds: duration,
            completedRounds: rounds,
            partialReps: reps
        )
    }

    func testPersonalRecordPicksHighestScoreWithinVariant() {
        let low = makeSession(rounds: 12, reps: 4)
        let high = makeSession(rounds: 14, reps: 2)
        let mid = makeSession(rounds: 14, reps: 0)
        let otherVariant = makeSession(rounds: 20, reps: 0, variant: .babyCindy)

        let pr = TrendAnalytics.personalRecord(among: [low, high, mid, otherVariant], variant: .rx)

        XCTAssertEqual(pr?.scoreString, "14+2")
    }

    func testPersonalRecordReturnsNilWhenNoSessionsForVariant() {
        let session = makeSession(rounds: 10, reps: 0, variant: .rx)
        let pr = TrendAnalytics.personalRecord(among: [session], variant: .hardCindy)

        XCTAssertNil(pr)
    }

    func testIsPersonalRecordTrueForFirstSessionOfAVariant() {
        let session = makeSession(rounds: 10, reps: 0)

        XCTAssertTrue(TrendAnalytics.isPersonalRecord(session, among: []))
    }

    func testIsPersonalRecordTrueWhenTyingOrBeatingTheBest() {
        let previousBest = makeSession(rounds: 14, reps: 2)
        let tying = makeSession(rounds: 14, reps: 2)
        let beating = makeSession(rounds: 15, reps: 0)

        XCTAssertTrue(TrendAnalytics.isPersonalRecord(tying, among: [previousBest]))
        XCTAssertTrue(TrendAnalytics.isPersonalRecord(beating, among: [previousBest]))
    }

    func testIsPersonalRecordFalseWhenBelowTheBest() {
        let previousBest = makeSession(rounds: 14, reps: 2)
        let worse = makeSession(rounds: 13, reps: 29)

        XCTAssertFalse(TrendAnalytics.isPersonalRecord(worse, among: [previousBest]))
    }

    func testAveragePaceSecondsPerRound() {
        let session = makeSession(rounds: 10, reps: 5, duration: 1200)

        XCTAssertEqual(TrendAnalytics.averagePaceSecondsPerRound(for: session), 120)
    }

    func testAveragePaceIsNilWithZeroCompletedRounds() {
        let session = makeSession(rounds: 0, reps: 8, duration: 1200)

        XCTAssertNil(TrendAnalytics.averagePaceSecondsPerRound(for: session))
    }

    func testProjectedFinalRoundsLinearProjection() {
        let projected = TrendAnalytics.projectedFinalRounds(
            elapsedSeconds: 600,
            capSeconds: 1200,
            completedRounds: 7
        )

        XCTAssertEqual(projected, 14, accuracy: 0.0001)
    }

    func testProjectedFinalRoundsIsZeroWithNoElapsedTime() {
        let projected = TrendAnalytics.projectedFinalRounds(
            elapsedSeconds: 0,
            capSeconds: 1200,
            completedRounds: 0
        )

        XCTAssertEqual(projected, 0)
    }

    func testSessionComparableOrdersByRoundsThenPartialReps() {
        let fewerRounds = makeSession(rounds: 12, reps: 29)
        let moreRounds = makeSession(rounds: 13, reps: 0)
        XCTAssertTrue(fewerRounds < moreRounds)

        let fewerReps = makeSession(rounds: 12, reps: 10)
        let moreReps = makeSession(rounds: 12, reps: 29)
        XCTAssertTrue(fewerReps < moreReps)
    }
}
