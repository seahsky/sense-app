import XCTest
@testable import SenseKit

final class RestDetectionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testWorkingImmediatelyAfterARep() {
        let state = RestDetection.state(
            lastRepAt: start.addingTimeInterval(30),
            sessionStartedAt: start,
            now: start.addingTimeInterval(33)
        )
        XCTAssertEqual(state, .working)
        XCTAssertFalse(state.isResting)
    }

    func testRestingOnceTheThresholdElapses() {
        let lastRep = start.addingTimeInterval(30)
        let state = RestDetection.state(
            lastRepAt: lastRep,
            sessionStartedAt: start,
            now: start.addingTimeInterval(30 + RestDetection.defaultThreshold)
        )
        XCTAssertEqual(state, .resting(since: lastRep))
        XCTAssertTrue(state.isResting)
    }

    func testRestBeginsAtTheLastRepNotAtTheThreshold() {
        // The displayed rest timer should read "how long since I last moved",
        // which is what an athlete pacing rounds actually wants — not "how long
        // since the app decided I was resting".
        let lastRep = start.addingTimeInterval(30)
        let now = start.addingTimeInterval(50)
        let state = RestDetection.state(lastRepAt: lastRep, sessionStartedAt: start, now: now)
        XCTAssertEqual(state.restDuration(at: now) ?? 0, 20, accuracy: 0.001)
    }

    func testBoundaryIsInclusive() {
        let lastRep = start
        let exactly = RestDetection.state(
            lastRepAt: lastRep,
            sessionStartedAt: start,
            now: start.addingTimeInterval(12),
            threshold: 12
        )
        XCTAssertTrue(exactly.isResting)

        let justBefore = RestDetection.state(
            lastRepAt: lastRep,
            sessionStartedAt: start,
            now: start.addingTimeInterval(11.999),
            threshold: 12
        )
        XCTAssertFalse(justBefore.isResting)
    }

    func testFallsBackToSessionStartBeforeTheFirstRep() {
        // Start the clock, then stand there. That is rest, and the app should say so.
        let state = RestDetection.state(
            lastRepAt: nil,
            sessionStartedAt: start,
            now: start.addingTimeInterval(20)
        )
        XCTAssertEqual(state, .resting(since: start))

        let early = RestDetection.state(lastRepAt: nil, sessionStartedAt: start, now: start.addingTimeInterval(3))
        XCTAssertEqual(early, .working)
    }

    func testWorkingStateHasNoRestDuration() {
        XCTAssertNil(WorkoutActivityState.working.restDuration(at: start))
    }

    func testRestDurationNeverGoesNegative() {
        // Clock skew or a rep logged with a future date must not produce a
        // negative timer on screen.
        let state = WorkoutActivityState.resting(since: start.addingTimeInterval(10))
        XCTAssertEqual(state.restDuration(at: start) ?? -1, 0, accuracy: 0.001)
    }

    func testCustomThreshold() {
        let lastRep = start
        XCTAssertTrue(
            RestDetection.state(lastRepAt: lastRep, sessionStartedAt: start, now: start.addingTimeInterval(9), threshold: 8).isResting
        )
        XCTAssertFalse(
            RestDetection.state(lastRepAt: lastRep, sessionStartedAt: start, now: start.addingTimeInterval(9), threshold: 15).isResting
        )
    }
}
