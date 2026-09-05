import Foundation

/// What started an attempt. Not the same question as ``SessionSource``, which
/// records which device recorded it; this records which affordance the athlete
/// touched, and it exists because a wrist-mounted trigger can fire without the
/// athlete meaning it and a Start button cannot.
///
/// Both rules in ``UnattendedStart`` are scoped to one of these two values, which
/// is the only reason the distinction is carried through the app at all. An
/// attempt begun on the Start screen had the athlete's eyes on it and is never
/// torn down behind their back, however empty it is.
public enum StartTrigger: String, Equatable, Sendable {
    /// The athlete pressed Start on the watch app's own Start screen.
    case startButton
    /// A tap on a watch-face complication, which reached the app as a
    /// ``SenseDeepLink``.
    case complication
}

/// The `sense://` URL a complication hands the watch app.
///
/// This is the whole cross-process contract. A widget extension has neither the
/// `com.apple.developer.healthkit` entitlement nor `WKBackgroundModes =
/// workout-processing`, and `CMBatchedSensorManager` produces nothing without an
/// active `HKWorkoutSession`, so the extension can only ever hand the app an
/// instruction. One value type, built here and parsed here, is what stops the two
/// halves of that instruction from drifting apart.
///
/// It is a URL rather than an `AppIntent` because Apple's interactivity guidance
/// lists no watchOS widget family as supporting interactive widgets, and says
/// verbatim that an interaction whose job is to open the app should use `Link` and
/// `widgetURL(_:)`. `ForegroundContinuableIntent` is
/// `@available(watchOSApplicationExtension, unavailable)`, so an intent route has
/// no graceful fallback on this platform either.
public enum SenseDeepLink: Equatable, Sendable {
    /// Start an attempt of `variant` from a standing start.
    case startSession(variant: CindyVariant)

    /// The URL scheme, registered in `SenseWatch/Info.plist` under
    /// `CFBundleURLTypes`. `SenseDeepLinkTests` reads that file off the source tree
    /// and asserts the scheme it declares contains this constant, so renaming
    /// either half of the pair fails the suite rather than the wrist.
    public static let scheme = "sense"

    /// The only host this build answers to. A future `sense://history` from a newer
    /// complication must not be able to make an older app do something arbitrary.
    public static let startHost = "start"

    /// The query item carrying ``CindyVariant/rawValue`` — a raw value, not a
    /// display name, because the string crosses a process boundary and is never
    /// read by a human.
    public static let variantQueryName = "variant"

    /// The URL to hand `widgetURL(_:)`.
    public var url: URL {
        switch self {
        case .startSession(let variant):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = Self.startHost
            components.queryItems = [URLQueryItem(name: Self.variantQueryName, value: variant.rawValue)]
            // A literal that cannot be assembled is a programming error, not a
            // runtime condition: failing loudly in the extension's own tests beats
            // shipping a complication whose tap silently does nothing.
            guard let url = components.url else {
                preconditionFailure("SenseDeepLink could not build a URL for \(variant.rawValue)")
            }
            return url
        }
    }

    /// Returns nil for anything this build does not recognise.
    ///
    /// Deliberately stricter than ``SessionPayload/makeSession(source:)``, which
    /// falls back to `.rx` on an unknown raw value. (`SessionPayload.init(dictionary:)`
    /// is not the contrast: it carries the raw string through untouched and fails
    /// only on malformed JSON.) That leniency is right where it sits:
    /// a payload arriving from the other device already has a finished score
    /// attached, so mislabelling it costs one wrong word on a history row. Here a
    /// wrong guess is a wrong clock — Baby Cindy is a 12:00 cap and every other
    /// variant is 20:00 — so an unrecognised variant must land the athlete on the
    /// Start screen with the chip in reach, never on a silently wrong countdown.
    /// The asymmetry is the point; do not harmonise the two.
    ///
    /// Scheme and host are compared case-insensitively, because RFC 3986 makes both
    /// case-insensitive and nothing is bought by disagreeing with it. The variant
    /// value is not: it is written by `CindyVariant.rawValue` in the extension and
    /// never typed by anyone, so tolerating case there would only widen what a
    /// stale or hand-crafted URL is allowed to mean.
    ///
    /// Unknown *extra* query items are ignored, so the URL can gain fields without
    /// breaking an older build that has already shipped to a wrist. A *repeated*
    /// `variant` item is not: `?variant=rx&variant=babyCindy` names two clocks, and
    /// taking the first of them is the same wrong guess this initialiser refuses to
    /// make about an unknown one. Exactly one, or nothing.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host?.lowercased() == Self.startHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let variantItems = (components.queryItems ?? []).filter { $0.name == Self.variantQueryName }
        guard variantItems.count == 1,
              let raw = variantItems[0].value,
              let variant = CindyVariant(rawValue: raw)
        else { return nil }

        self = .startSession(variant: variant)
    }
}
