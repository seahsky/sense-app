import XCTest
@testable import SenseKit

final class CindySessionTests: XCTestCase {
    func testScoreStringFormatting() {
        let session = CindySession(
            durationSeconds: 1200,
            completedRounds: 17,
            partialReps: 8
        )

        XCTAssertEqual(session.scoreString, "17+8")
    }

    func testTotalRepsUsesVariantRepsPerRound() {
        let session = CindySession(
            variant: .rx,
            durationSeconds: 1200,
            completedRounds: 3,
            partialReps: 7
        )

        XCTAssertEqual(session.totalReps, 3 * 30 + 7)
    }

    func testVariantAndSourceRoundTripThroughRawValues() {
        let session = CindySession(
            variant: .weightedVest,
            durationSeconds: 1200,
            completedRounds: 0,
            partialReps: 0,
            source: .manual
        )

        XCTAssertEqual(session.variant, .weightedVest)
        XCTAssertEqual(session.source, .manual)
        XCTAssertEqual(session.variantRawValue, "weightedVest")
        XCTAssertEqual(session.sourceRawValue, "manual")
    }

    func testUnknownRawValuesFallBackToSafeDefaults() {
        let session = CindySession(
            durationSeconds: 1200,
            completedRounds: 0,
            partialReps: 0
        )
        session.variantRawValue = "not-a-real-variant"
        session.sourceRawValue = "not-a-real-source"

        XCTAssertEqual(session.variant, .rx)
        XCTAssertEqual(session.source, .manual)
    }

    func testSessionPayloadRoundTripsThroughADictionary() {
        let original = CindySession(
            variant: .scaled,
            durationSeconds: 987,
            completedRounds: 9,
            partialReps: 11,
            averageHeartRate: 162.5,
            activeEnergyBurned: 210,
            notes: "felt strong",
            source: .watch
        )

        let dictionary = SessionPayload(session: original).asDictionary()
        let decoded = SessionPayload(dictionary: dictionary)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, original.id)
        XCTAssertEqual(decoded?.variantRawValue, "scaled")
        XCTAssertEqual(decoded?.completedRounds, 9)
        XCTAssertEqual(decoded?.partialReps, 11)
        XCTAssertEqual(decoded?.averageHeartRate, 162.5)
        XCTAssertEqual(decoded?.notes, "felt strong")

        let rebuilt = decoded?.makeSession(source: .iPhone)
        XCTAssertEqual(rebuilt?.scoreString, "9+11")
        XCTAssertEqual(rebuilt?.source, .iPhone)
    }

    func testSessionPayloadOmitsNilOptionalsRatherThanEncodingNull() {
        let session = CindySession(
            durationSeconds: 500,
            completedRounds: 2,
            partialReps: 3,
            averageHeartRate: nil,
            activeEnergyBurned: nil
        )

        let dictionary = SessionPayload(session: session).asDictionary()

        // A JSON `null` would decode through JSONSerialization as NSNull, which is
        // not a valid WCSession user-info value — this asserts the key is absent
        // entirely rather than present-but-null.
        XCTAssertNil(dictionary["averageHeartRate"])
        XCTAssertNil(dictionary["activeEnergyBurned"])
    }
}
