import WidgetKit
import SwiftUI
import SenseKit
import SenseUI

/// The per-family layout, the one `widgetURL`, the container background, and the
/// spoken strings.
///
/// Four families, four different amounts of room, and only one of them — 162×69 pt
/// rectangular — is big enough for the display face to clear
/// `SenseFont.minimumDisplaySize`. The other three are single-glyph slots, so they
/// carry the mark and push the variant word out to `widgetLabel`, which the system
/// draws along the bezel where a face has room for it.
struct StartCindyEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let entry: StartCindyEntry

    /// Always-on changes exactly one thing, and this is it.
    ///
    /// Apple's HIG asks for a consistent layout when Always On begins. On a
    /// workout app that is not a style note: the arm falls between rounds, so
    /// anything that restages does it in the athlete's peripheral vision every
    /// 60-70 seconds. So the ring thickens to hold its contrast against the dimmed
    /// frame, and nothing moves, nothing is dropped, and the disc does not shrink.
    /// `SenseMotif`'s rule of dropping the web entirely in always-on does not carry
    /// over here, because on this complication the web IS the content.
    private var stroke: CGFloat { isLuminanceReduced ? 2.5 : 2 }

    var body: some View {
        content
            // Exactly one, at the root of the hierarchy. Apple documents the
            // behaviour of a second `widgetURL` in the same hierarchy as
            // undefined, and there is no `Link` anywhere below: three of the four
            // families are single-glyph slots, and nothing in the SDK says the
            // system creates separate tap regions inside an accessory family on
            // watchOS.
            //
            // The URL is built through SenseDeepLink rather than assembled here,
            // so the string this extension emits and the string the watch app
            // parses are the same code. Two processes cannot drift over a literal
            // neither of them owns.
            .widgetURL(SenseDeepLink.startSession(variant: entry.variant).url)
            // Never actually drawn on a watch complication —
            // `showsWidgetContainerBackground` is false for every accessory family
            // from watchOS 10 — but omitting it makes WidgetKit replace the whole
            // view with a developer warning tile. The string "Please adopt
            // containerBackground API" is in the shipped watchOS 26.5 binary. So:
            // declare it unconditionally, paint nothing.
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            // 42×42 pt at 40mm. Five arcs on a 37.8 pt ring gives each arc 14.3 pt
            // of length, the same figure as the disc's diameter, which is what
            // makes the mark read as one drawing rather than a dot inside a
            // dotted circle. No text inside the dial: Apple's own default text
            // size for this slot is 12 pt at 40mm, below
            // SenseFont.minimumDisplaySize, so any word here would be either
            // off-brand or illegible.
            ZStack {
                AccessoryWidgetBackground()
                CindyMark(arcs: 5, ringFraction: 0.90, discFraction: 0.34, stroke: stroke)
            }
            // `widgetLabel` takes StringProtocol, LocalizedStringKey,
            // LocalizedStringResource or a ViewBuilder closure. It does NOT take a
            // `Text` — `.widgetLabel(Text("CINDY"))` fails with "requires that
            // 'Text' conform to 'StringProtocol'", which reads as a type error
            // about the wrong thing. WidgetKit renders this along the bezel only
            // on Infograph's top circular slot, so it is free where it appears and
            // silently absent everywhere else. The system owns its font, so Zilla
            // Slab cannot reach it and does not need to.
            .widgetLabel(Self.faceLabel(for: entry.variant))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenLabel(for: entry.variant))

        case .accessoryCorner:
            // 32×32 pt, and the image shrinks again once a label attaches. Four
            // arcs rather than five because the slot is 24% smaller and each arc
            // shortens with it; at five they read as noise. Corner is the best
            // family this app has, because the curved word comes free and the
            // image stays a pure mark.
            ZStack {
                AccessoryWidgetBackground()
                CindyMark(arcs: 4, ringFraction: 0.86, discFraction: 0.38, stroke: stroke)
            }
            .widgetLabel(Self.faceLabel(for: entry.variant))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenLabel(for: entry.variant))

        case .accessoryRectangular:
            // 162×69 pt, and the only family where the app has a voice: at 22 pt
            // the display face gives 14.3 pt of cap height against the HIG
            // default's 11.6, and "CINDY" measures 67.0 pt against the shipped
            // TTF, so the mark-plus-word row occupies 102 of the 162 pt box.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    CindyMark(arcs: 5, ringFraction: 0.88, discFraction: 0.36, stroke: stroke)
                        .frame(width: 28, height: 28)
                    Text("CINDY")
                        .font(SenseFont.display(size: 22))
                        .foregroundStyle(SenseColor.ink)
                        .widgetAccentable()
                }
                Text(Self.subLine(for: entry.variant))
                    // System font with tabular digits, never the display face.
                    // Zilla Slab's figures are old-style: 3/4/5/7/9 hang below the
                    // baseline, 6/8 rise above cap height, 0/1/2 sit at x-height,
                    // and `.monospacedDigit()` fixes only the advance, not the
                    // shape. A time cap set in it would look like a typo.
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(SenseColor.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cindy")
            .accessibilityValue(Self.spokenValue(for: entry.variant))

        case .accessoryInline:
            // No mark, no colour, no custom font, and no AccessoryWidgetBackground
            // (it renders as an empty view here). The system owns all of it, and on
            // some faces it curves the row. The ladder is load-bearing rather than
            // decorative: at 15 pt SF Compact a 16-character rung already overflows
            // the inline band at 40mm, and ViewThatFits picking the third rung is
            // the difference between "Cindy" and a truncated first rung.
            ViewThatFits {
                Label(Self.inlineLong(for: entry.variant), systemImage: Self.symbol)
                Label(Self.inlineMedium(for: entry.variant), systemImage: Self.symbol)
                Label("Cindy", systemImage: Self.symbol)
            }
            // Stated rather than left to SwiftUI's default propagation, like the
            // other three families. A `Label` is a symbol and a string, so this is
            // the branch where the collapse is least automatic, not most.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenLabel(for: entry.variant))

        default:
            // Unreachable on watchOS — every `system*` WidgetFamily case is
            // @available(watchOS, unavailable) and the four above are the whole
            // list — but the enum is not frozen, so a future family gets the mark
            // rather than an empty tile. It gets the label too: this is the branch
            // a new family lands in, and an unlabelled tile is worse than an
            // unstyled one.
            CindyMark(arcs: 5, ringFraction: 0.90, discFraction: 0.34, stroke: stroke)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spokenLabel(for: entry.variant))
        }
    }

    /// `figure.pullup`, `figure.pushup` and `figure.squat` do not exist in any SF
    /// Symbols release — checked against CoreGlyphs' own name_availability.plist,
    /// where this one is listed for 2022, meaning watchOS 9.0. It is also the same
    /// activity family `WorkoutSessionManager` already logs per movement, so the
    /// inline row and the Health entry agree.
    private static let symbol = "figure.strengthtraining.functional"

    /// The bezel word. "CINDY" unqualified means Rx, which is how the workout is
    /// named everywhere else in the product — the Start screen's title chip reads
    /// "Cindy · 20:00" whatever the variant, and the variant's own name sits beside
    /// it in the toolbar.
    static func faceLabel(for variant: CindyVariant) -> String {
        switch variant {
        case .rx: return "CINDY"
        case .scaled: return "SCALED"
        case .babyCindy: return "BABY"
        case .weightedVest: return "VEST"
        case .hardCindy: return "HARD"
        }
    }

    /// Rx spends the line on the movement scheme, which is what Cindy *is* for
    /// anyone who has not memorised the benchmark — and it is true for every
    /// variant by construction, since `movementSequence` is variant-independent.
    /// Every other variant spends it on the thing that distinguishes it, in the
    /// app's own title-chip wording, because for those the name carries more than
    /// a scheme the athlete can already see is the same.
    ///
    /// The widest line this produces is 21 characters (~121 pt of the 162 pt box);
    /// the Rx line is the tightest at 109.5 pt. Both caps come from
    /// `CindyVariant.timeCapText` rather than a literal, so the tile and its own
    /// spoken value cannot disagree the day a cap changes — the measured widths
    /// hold as long as the cap stays four glyphs.
    static func subLine(for variant: CindyVariant) -> String {
        variant == .rx
            ? "5 · 10 · 15   \(variant.timeCapText)"
            : "\(variant.displayName) · \(variant.timeCapText)"
    }

    static func inlineLong(for variant: CindyVariant) -> String {
        "Cindy \(variant.displayName) · \(variant.timeCapText)"
    }

    static func inlineMedium(for variant: CindyVariant) -> String {
        "Cindy \(variant.displayName)"
    }

    /// VoiceOver reads "20:00" as "twenty colon zero zero" and "5 · 10 · 15" as
    /// "five dot ten dot fifteen", so every family collapses to one element with an
    /// explicit spoken phrase rather than letting the visible strings be read
    /// literally. "AMRAP" is deliberately left as a word: VoiceOver says it the way
    /// athletes do, and spelling it out would be slower and stranger.
    static func spokenLabel(for variant: CindyVariant) -> String {
        "Cindy \(variant.displayName), \(Int(variant.timeCapSeconds) / 60) minute AMRAP"
    }

    static func spokenValue(for variant: CindyVariant) -> String {
        "\(variant.displayName). Five pull-ups, ten push-ups, fifteen air squats. "
        + "\(Int(variant.timeCapSeconds) / 60) minute AMRAP."
    }
}

// The four previews are the only layout check available without a paired watch,
// so all four families are covered. Rx in circular is the mark-only read; Baby
// Cindy in corner and rectangular is the labelled read, and it is also the
// variant whose cap differs, so a 12:00 that renders as 20:00 is visible here.

#Preview(as: .accessoryCircular) { StartCindyComplication() }
    timeline: { StartCindyEntry(date: .now, variant: .rx) }

#Preview(as: .accessoryCorner) { StartCindyComplication() }
    timeline: { StartCindyEntry(date: .now, variant: .babyCindy) }

#Preview(as: .accessoryRectangular) { StartCindyComplication() }
    timeline: { StartCindyEntry(date: .now, variant: .babyCindy) }

#Preview(as: .accessoryInline) { StartCindyComplication() }
    timeline: { StartCindyEntry(date: .now, variant: .weightedVest) }
