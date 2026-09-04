import SwiftUI
import CoreText

/// Typography. Zilla Slab SemiBold for display, the system font for everything else.
///
/// **Why the face is split.** Measured on the shipped binaries, every heavy display
/// serif in this class loses its counters below about 13pt on a dark ground: the
/// `o`, `e`, `a` and `8` fill in and the word turns into a shape. The watch UI has
/// 9pt and 11pt labels. So the display face is reserved for the sizes it survives
/// (clock, score, titles, action labels) and the system font carries everything
/// that has to be read small. The design reference does the same thing: its title
/// and button are set in the slab, its movement list is not.
///
/// **Why the clock needs ``clock(size:)`` and not just ``display(size:)``.** Zilla
/// Slab's default digits are proportional, nine different widths across the ten
/// numerals. A centred countdown set in them physically shifts every second. The
/// shipped subset keeps the font's `tnum` feature, whose ten tabular digits are all
/// exactly 600 units wide, and `.monospacedDigit()` is what switches it on.
///
/// That modifier is silent when it fails. Apple documents it as leaving the font
/// unchanged if the face has no tabular figures, with no error and no warning, so a
/// future font swap to a face without `tnum` would reintroduce the jitter invisibly.
/// ``clock(size:)`` exists to make that one decision in one place.
public enum SenseFont {
    /// PostScript name, which is what `Font.custom` resolves against. It is not the
    /// file name, and the two are unrelated in general.
    private static let displayFace = "ZillaSlab-SemiBold"

    /// Registers the bundled font with Core Text.
    ///
    /// The `UIAppFonts` Info.plist key only searches the *app* bundle, and this
    /// font ships inside a Swift package's resource bundle, so the plist route
    /// cannot see it. Registering by URL is the supported alternative.
    ///
    /// Call once at launch, before any view is built. Repeat calls are harmless:
    /// the flag makes the work idempotent, and Core Text would in any case just
    /// report that the font is already registered.
    public static func register() {
        guard !isRegistered else { return }
        isRegistered = true

        guard let url = Bundle.module.url(forResource: "ZillaSlab-SemiBold", withExtension: "ttf") else {
            assertionFailure("SenseUI: display font missing from the package bundle")
            return
        }

        var error: Unmanaged<CFError>?
        // `.process` scopes the registration to this process, which is what an app
        // wants: nothing is installed for other apps or left behind on exit.
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            assertionFailure("SenseUI: could not register display font: \(String(describing: error?.takeUnretainedValue()))")
        }
    }

    private nonisolated(unsafe) static var isRegistered = false

    /// Display face at an explicit size. For titles and action labels.
    ///
    /// Sizes below ``minimumDisplaySize`` are refused in debug builds rather than
    /// silently shipped, because the failure they cause is subtle: the text stays
    /// legible enough in a simulator screenshot and turns to mush on a real watch
    /// held at arm's length.
    public static func display(size: CGFloat) -> Font {
        assert(size >= minimumDisplaySize, "SenseFont.display used at \(size)pt; below \(minimumDisplaySize)pt the counters close up. Use the system font.")
        return .custom(displayFace, size: size)
    }

    /// Display face with tabular figures. The only correct way to set a clock, a
    /// score, or any number that changes in place.
    public static func clock(size: CGFloat) -> Font {
        display(size: size).monospacedDigit()
    }

    /// Below this, the display face is not legible on a dark ground at watch
    /// viewing distance. Measured, not assumed.
    public static let minimumDisplaySize: CGFloat = 13

    /// Attribution required by the SIL Open Font License, clause 2, which asks that
    /// the copyright notice ship with any redistribution of the font. Surfaced in
    /// the iPhone app's Settings tab.
    public static let attribution = FontAttribution(
        name: "Zilla Slab",
        copyright: "Copyright 2017, The Mozilla Foundation",
        license: "SIL Open Font License, Version 1.1",
        note: "Subset to Latin, and shipped with the font's own tabular-figure feature retained."
    )

    /// Full licence text, as required by OFL clause 2.
    public static var licenseText: String {
        guard let url = Bundle.module.url(forResource: "OFL-ZillaSlab", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Licence text unavailable."
        }
        return text
    }
}

public struct FontAttribution: Sendable, Hashable {
    public let name: String
    public let copyright: String
    public let license: String
    public let note: String
}
