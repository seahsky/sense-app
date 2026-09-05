import AppIntents
import SenseKit

/// The widget kind string, in one place.
///
/// `AppIntentConfiguration(kind:)` and any future
/// `RelevantIntentManager.updateRelevantIntents` push both need this exact
/// literal, and a mismatch between them is not a compile error — it is a Smart
/// Stack entry that silently never appears. One constant is what stops that.
enum ComplicationKind {
    static let startCindy = "SenseStartCindy"
}

/// Which Cindy one instance of the complication starts.
///
/// **Why the parameter is a `String` and not `CindyVariant`.** Do not "fix" this.
/// An `AppEnum` has to be declared in the target that extracts the metadata, and
/// conforming the imported `SenseKit.CindyVariant` retroactively is not a warning
/// to silence, it is a hard build failure. Reproduced verbatim at
/// `ExtractAppIntentsMetadata`:
///
/// - `error: Type '(CindyVariant)' cases not found, enums implemented in an
///   imported framework or library are not supported`
/// - `error: The property 'allCases' must be implemented when conforming to
///   'AppIntents.AppEnum', and a compile-time static value must be provided`
/// - `error: The property 'typeDisplayRepresentation' must have a compile-time
///   static value and cannot be computed or dynamic`
///
/// Rewriting the statics as stored `static var`s does not help. The usual
/// workaround is a local mirror enum, which duplicates all five cases inside an
/// extension target the SenseKit test bundle cannot import, so nothing at all
/// guards the drift between the mirror and the real type.
///
/// A `String` raw value needs no mirror. It round-trips through
/// `CindyVariant(rawValue:)`, and it costs no configuration UI, because watchOS
/// has none: the athlete never sees a parameter editor, only the rows
/// `StartCindyProvider.recommendations()` puts in the face gallery.
///
/// `isDiscoverable` is false so this never surfaces in Shortcuts or Spotlight. It
/// configures a complication and does nothing on its own, and an entry that runs
/// no action is worse than no entry. Metadata extraction stays confined to this
/// target — verified that SenseWatch and SenseApp both still report "Metadata
/// extraction skipped. No AppIntents.framework dependency found."
struct StartCindyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Start Cindy"
    static var description = IntentDescription("Which Cindy this complication starts.")
    static var isDiscoverable: Bool { false }

    /// Defaulted, not optional. watchOS gives the athlete no way to edit a
    /// complication's configuration once it is on a face, so "unconfigured" must
    /// not be a state that can exist on a wrist — a complication restored from a
    /// backup, synced from another watch, or added outside a recommendation has
    /// to be a working Rx launcher, not a dead tile.
    ///
    /// The default is the literal `"rx"` rather than `CindyVariant.rx.rawValue`
    /// on purpose: `@Parameter(default:)` is read by the metadata extractor at
    /// build time, which needs a compile-time static value and cannot evaluate a
    /// property on an imported type. ``variant`` below is where the string
    /// becomes a `CindyVariant` again, and `SenseDeepLinkTests` is what keeps the
    /// two spellings of "rx" honest.
    @Parameter(title: "Variant", default: "rx")
    var variantRawValue: String

    init() {}

    init(variant: CindyVariant) { self.variantRawValue = variant.rawValue }

    /// Falls back to `.rx` rather than failing, because this is read on the render
    /// path where there is nothing to report an error to. A raw value this build
    /// does not recognise can only come from a newer complication configuration
    /// surviving a downgrade, and Rx is the variant the tile is named after.
    ///
    /// This leniency is deliberately *not* mirrored in `SenseDeepLink(url:)`,
    /// which rejects an unknown variant outright: there, a wrong guess is a wrong
    /// clock on a running workout.
    var variant: CindyVariant { CindyVariant(rawValue: variantRawValue) ?? .rx }
}
