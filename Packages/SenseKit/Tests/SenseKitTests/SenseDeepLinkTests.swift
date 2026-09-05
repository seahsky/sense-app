import XCTest
@testable import SenseKit

final class SenseDeepLinkTests: XCTestCase {
    // MARK: - Round trip

    func testEveryVariantRoundTripsThroughTheURL() {
        // The extension builds the URL in one process and the watch app parses it
        // in another, so nothing but this loop keeps the two agreeing about a
        // string. Driven off `allCases` so a sixth variant cannot be added without
        // being carried across the boundary.
        for variant in CindyVariant.allCases {
            let link = SenseDeepLink.startSession(variant: variant)
            XCTAssertEqual(SenseDeepLink(url: link.url), link, "round trip failed for \(variant.rawValue)")
        }
    }

    func testTheBuiltURLIsTheStringTheWatchAppIsRegisteredFor() {
        // Pinned as a literal, not rebuilt from the constants, because the whole
        // point is to catch the day the shape of the URL changes underneath the
        // complication already on somebody's watch face.
        XCTAssertEqual(
            SenseDeepLink.startSession(variant: .rx).url.absoluteString,
            "sense://start?variant=rx"
        )
        XCTAssertEqual(
            SenseDeepLink.startSession(variant: .babyCindy).url.absoluteString,
            "sense://start?variant=babyCindy"
        )
    }

    // MARK: - Rejection

    func testUnknownVariantIsRejectedRatherThanDefaultingToRx() {
        // `SessionPayload.makeSession` answers an unknown raw value with `?? .rx`,
        // and that is right there — the payload already carries a finished score.
        // Here the same leniency would hand a Baby Cindy athlete a 20:00 clock for
        // a 12:00 workout. Rejecting sends them to the Start screen with the chip
        // in reach instead.
        XCTAssertNil(parse("sense://start?variant=murph"))
        XCTAssertNil(parse("sense://start?variant=fran"))
    }

    func testMissingVariantIsRejected() {
        XCTAssertNil(parse("sense://start"))
        XCTAssertNil(parse("sense://start?src=complication"))
    }

    func testEmptyVariantValueIsRejected() {
        XCTAssertNil(parse("sense://start?variant="))
    }

    func testForeignSchemeIsRejected() {
        XCTAssertNil(parse("https://start?variant=rx"))
        XCTAssertNil(parse("shortcuts://start?variant=rx"))
    }

    func testForeignHostIsRejected() {
        // A future complication build must not be able to make an older app do
        // something it was never taught. An unrecognised host is a newer
        // instruction, and the honest answer to one of those is nothing at all.
        XCTAssertNil(parse("sense://history?variant=rx"))
        XCTAssertNil(parse("sense://settings?variant=rx"))
    }

    // MARK: - Leniency, where it is safe

    func testSchemeAndHostComparisonIsCaseInsensitive() {
        // RFC 3986 makes both case-insensitive, and disagreeing with it buys
        // nothing.
        XCTAssertEqual(parse("SENSE://START?variant=rx"), SenseDeepLink.startSession(variant: .rx))
        XCTAssertEqual(parse("Sense://Start?variant=babyCindy"), SenseDeepLink.startSession(variant: .babyCindy))
    }

    func testVariantValueComparisonIsCaseSensitive() {
        // The value is written by `CindyVariant.rawValue` in the extension and is
        // never typed by a person, so accepting other spellings would only widen
        // what a stale or hand-crafted URL is allowed to mean.
        XCTAssertNil(parse("sense://start?variant=RX"))
        XCTAssertNil(parse("sense://start?variant=babycindy"))
    }

    func testUnknownQueryItemsAreIgnored() {
        // So a later build can add fields to the URL without bricking the
        // complication already sitting on a watch face.
        XCTAssertEqual(
            parse("sense://start?variant=rx&src=complication&v=2"),
            SenseDeepLink.startSession(variant: .rx)
        )
    }

    func testContradictoryVariantItemsAreRejected() {
        // Tolerating extra items is not the same as tolerating a repeated one. A
        // URL that names two clocks is not a URL this build can honour, and taking
        // the first of them would be the same wrong guess `testUnknownVariantIs...`
        // above exists to prevent — silently, and with a 20:00 on a 12:00 workout.
        XCTAssertNil(parse("sense://start?variant=rx&variant=babyCindy"))
        XCTAssertNil(parse("sense://start?variant=rx&variant=rx"))
    }

    // MARK: - Consequences

    func testBabyCindyURLCarriesTheTwelveMinuteCap() {
        // Ties the string contract to the thing that actually goes wrong when it
        // breaks: the athlete gets the wrong clock, and finds out at 12:01.
        guard case .startSession(let variant)? = parse("sense://start?variant=babyCindy") else {
            XCTFail("sense://start?variant=babyCindy must parse")
            return
        }
        XCTAssertEqual(variant, .babyCindy)
        XCTAssertEqual(variant.timeCapSeconds, 720)
    }

    func testSchemeMatchesTheOneRegisteredInTheWatchInfoPlist() throws {
        // `SenseWatch/Info.plist` hand-registers the scheme under
        // `CFBundleURLTypes`, and that file is the half nothing else can check: the
        // watch app is not in this test bundle's dependency graph, so a rename
        // there would otherwise ship green and fail on a wrist.
        //
        // So the plist is read off the source tree via `#filePath` rather than out
        // of a built bundle. That couples the test to the repo layout, which is the
        // price of the test existing at all — asserting the Swift constant against
        // a Swift literal would guard nothing but itself.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SenseKitTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SenseKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // repo root
        let plistURL = repoRoot.appendingPathComponent("SenseWatch/Info.plist")

        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        XCTAssertTrue(
            schemes.contains(SenseDeepLink.scheme),
            "SenseWatch/Info.plist registers \(schemes), which does not include SenseDeepLink.scheme"
        )
    }

    // MARK: - Helpers

    /// Parses a literal the way the watch app's `.onOpenURL` does.
    ///
    /// The `preconditionFailure` is deliberate. A malformed literal would otherwise
    /// become a `nil` URL, then a `nil` link, and would satisfy the very
    /// `XCTAssertNil` under test — a rejection test that passes because the test
    /// itself is broken is worse than no test.
    private func parse(_ string: String) -> SenseDeepLink? {
        guard let url = URL(string: string) else {
            preconditionFailure("Test URL literal is malformed: \(string)")
        }
        return SenseDeepLink(url: url)
    }
}
