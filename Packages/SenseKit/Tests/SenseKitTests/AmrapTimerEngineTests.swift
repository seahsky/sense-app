import XCTest
@testable import SenseKit

final class AmrapTimerEngineTests: XCTestCase {
    func testIdleStateHasNoActiveIntervalAndZeroElapsed() {
        let engine = AmrapTimerEngine(capSeconds: 1200)

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.activeInterval)
        XCTAssertEqual(engine.elapsed, 0)
        XCTAssertEqual(engine.remaining, 1200)
    }

    func testStartBeginsRunningWithCorrectActiveInterval() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)

        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.activeInterval?.lowerBound, start)
        XCTAssertEqual(engine.activeInterval?.upperBound, start.addingTimeInterval(1200))
    }

    func testStartIsIgnoredWhenNotIdle() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.start(at: start.addingTimeInterval(50))

        XCTAssertEqual(engine.activeInterval?.lowerBound, start)
    }

    func testPauseIsIgnoredWhenIdle() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        engine.pause(at: .now)

        XCTAssertEqual(engine.phase, .idle)
    }

    func testPauseFreezesElapsedRegardlessOfWallClock() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.pause(at: start.addingTimeInterval(300))

        XCTAssertEqual(engine.phase, .paused)
        XCTAssertEqual(engine.elapsed, 300, accuracy: 0.001)
        XCTAssertEqual(engine.remaining, 900, accuracy: 0.001)
    }

    func testResumeShiftsVirtualStartByThePausedDuration() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.pause(at: start.addingTimeInterval(300))
        engine.resume(at: start.addingTimeInterval(420)) // paused for 120s

        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.activeInterval?.lowerBound, start.addingTimeInterval(120))
    }

    func testResumeIsIgnoredWhenNotPaused() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.resume(at: start.addingTimeInterval(10))

        XCTAssertEqual(engine.activeInterval?.lowerBound, start)
    }

    func testFinishFreezesElapsedPermanently() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.finish(at: start.addingTimeInterval(1000))

        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.elapsed, 1000, accuracy: 0.001)
        XCTAssertEqual(engine.remaining, 200, accuracy: 0.001)
    }

    func testFinishFromPausedFreezesAtThePauseElapsed() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.pause(at: start.addingTimeInterval(600))
        engine.finish(at: start.addingTimeInterval(9000))

        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.elapsed, 600, accuracy: 0.001)
    }

    func testElapsedClampsToCapSecondsPastTheBuzzer() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        let start = Date(timeIntervalSince1970: 1_000_000)
        engine.start(at: start)
        engine.finish(at: start.addingTimeInterval(1500))

        XCTAssertEqual(engine.elapsed, 1200)
        XCTAssertEqual(engine.remaining, 0)
    }

    func testResetReturnsToIdle() {
        let engine = AmrapTimerEngine(capSeconds: 1200)
        engine.start(at: .now)
        engine.finish(at: .now)
        engine.reset()

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.activeInterval)
        XCTAssertEqual(engine.elapsed, 0)
        XCTAssertEqual(engine.remaining, 1200)
    }
}
