import WidgetKit
import SwiftUI
import SenseKit
import SenseUI

/// What one rendered tile knows: when it was made, and which Cindy its tap starts.
struct StartCindyEntry: TimelineEntry {
    let date: Date
    let variant: CindyVariant
}

/// One entry, `.never`.
///
/// **Why there is no data here.** The complication shows no score, no staleness
/// count and no personal record, and that is a storage boundary rather than an
/// omission. The watch's SwiftData store lives in the app's own container, a
/// widget extension is a separate process, and this repo has no App Group.
/// HealthKit is not a back door either: `WorkoutSessionManager` writes duration,
/// heart rate, active energy and per-movement metadata, and never the
/// rounds-plus-reps score, so even a HealthKit read entitlement this extension
/// does not have would not surface the number an athlete would want to see.
///
/// So the only honest content is what the tap will start, which the configuration
/// already carries — and with nothing to go stale, a refresh policy of `.never`
/// spends no reload budget and no battery. Apple's HIG warns that a complication
/// without meaningful data is less likely to keep a prominent slot; that cost is
/// taken deliberately, and the rectangular sub-line is built as a slot so the day
/// an App Group arrives for some other reason, a real last-score line drops in
/// with no relayout. See docs/adr/0003.
struct StartCindyProvider: AppIntentTimelineProvider {
    /// On watchOS this function IS the configuration UI. Apple: "watchOS doesn't
    /// offer a dedicated user interface to configure data that appears on a
    /// complication. Use intent recommendations in watchOS to offer preconfigured
    /// complications." It is also a protocol requirement with no default
    /// implementation (WidgetKit.swiftinterface:1117 — only `relevance()` has one,
    /// at :1128, and that is watchOS 11), so an `AppIntentConfiguration` widget
    /// has to write this either way. `return []` and five real rows cost the same
    /// line count, and one of the two is useless.
    ///
    /// Driven by `CindyVariant.allCases`, so a sixth variant appears in the face
    /// gallery the moment it is added to SenseKit and nothing here has to be
    /// remembered. The order is the enum's own, Rx first, rather than the
    /// athlete's history: ordering by history would need the extension to read the
    /// session store, which needs the App Group ADR 0003 declines.
    func recommendations() -> [AppIntentRecommendation<StartCindyIntent>] {
        CindyVariant.allCases.map { variant in
            AppIntentRecommendation(
                intent: StartCindyIntent(variant: variant),
                description: Text(variant.displayName)
            )
        }
    }

    /// Rx, because the default configuration really is Rx. Rendering a distinct
    /// "no data" state here would invent a second visual nobody sees for more than
    /// a frame, and it would be a lie about what the tile does.
    func placeholder(in context: Context) -> StartCindyEntry {
        // Second registration point, in case this runs before the bundle's own
        // `init()` has taken effect. Nothing documents an order between the two,
        // and `register()` is idempotent, so the pair is cheap insurance against a
        // silent fallback to the system face.
        SenseFont.register()
        return StartCindyEntry(date: .now, variant: .rx)
    }

    func snapshot(for configuration: StartCindyIntent, in context: Context) async -> StartCindyEntry {
        StartCindyEntry(date: .now, variant: configuration.variant)
    }

    func timeline(for configuration: StartCindyIntent, in context: Context) async -> Timeline<StartCindyEntry> {
        Timeline(entries: [StartCindyEntry(date: .now, variant: configuration.variant)], policy: .never)
    }
}

struct StartCindyComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ComplicationKind.startCindy,
            intent: StartCindyIntent.self,
            provider: StartCindyProvider()
        ) { entry in
            StartCindyEntryView(entry: entry)
        }
        .configurationDisplayName("Start Cindy")
        .description("One tap into a Cindy AMRAP.")
        // The only four families that exist on watchOS. Every `system*` case of
        // WidgetFamily is @available(watchOS, unavailable), so this list is
        // exhaustive rather than a selection.
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
