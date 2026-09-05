import SwiftUI

/// The palette, and the only place a raw colour literal is allowed to exist.
///
/// Every value below was measured against the ground rather than chosen by eye.
/// The ratios in the comments are WCAG 2.1 contrast against ``ground``, computed
/// from the sRGB relative-luminance formula. They matter more here than in a
/// typical app: the watch is read at arm's length, often in a badly lit gym, often
/// while the wearer is out of breath.
///
/// The design reference used a saturated `#2B3FD9` for text. That measures
/// **2.68:1**, which fails even the 3:1 large-text threshold, so it survives here
/// only as a *fill* (``accent``, behind cream) and never as ink. ``accentInk`` is
/// the lifted blue that small text uses instead.
///
/// **Every ratio below stops applying the moment a view leaves the app's own
/// screens.** A watch complication has no ``ground``: it draws over whatever face
/// the athlete chose, through a translucent `AccessoryWidgetBackground` plate.
/// Recomputed there against black, against a lighter plate, and over a light photo
/// face, ``motif`` falls from 3.00:1 to 2.48:1, 1.90:1 and **1.30:1**, and
/// ``accent`` to 1.16:1. ``ink`` holds at 14.4 / 11.0 / 4.44 and ``accentInk`` at
/// 5.04 / 3.86 / 1.56, which is why the complication's mark draws its web in
/// ``ink`` and spends its one hue on the disc in ``accentInk``.
///
/// Colour may not survive the trip at all. Most watch faces render complications
/// in `.accented`, where the system treats the views as template images and paints
/// them from the alpha channel, discarding the hue entirely. So a complication
/// design that carries meaning in colour fails by construction, and the red is the
/// first thing the next person will reach for.
public enum SenseColor {
    // MARK: Grounds

    /// Near-black with a slight warm cast, so cream text sits on it without the
    /// blue-grey chill a neutral black gives.
    public static let ground = Color(hex: 0x0D0708)

    /// Raised surfaces: list rows, cards, the settings form.
    public static let surface = Color(hex: 0x17100F)

    // MARK: Ink

    /// 17.42:1. All primary text and the countdown clock.
    public static let ink = Color(hex: 0xF5EFE0)

    /// 9.14:1. Labels and supporting text.
    public static let inkSecondary = Color(hex: 0xB9AE9D)

    /// 6.39:1. The dimmest text allowed anywhere. Still clears AA for body text.
    public static let inkTertiary = Color(hex: 0x9C9081)

    // MARK: Accent

    /// Primary action fill. Cream on this measures 5.15:1, so the Start label is
    /// comfortably readable. Never use it for text on ``ground``.
    public static let accent = Color(hex: 0x3A55E0)

    /// 6.10:1. Blue *text*: rep counts, the score, anything numeric and small.
    public static let accentInk = Color(hex: 0x6E86F7)

    // MARK: Motif and status

    /// 3.00:1. The web geometry only. Decorative strokes carry no text, so the
    /// large-text threshold is the right bar and this deliberately sits at it:
    /// the webbing should read as structure behind the content, not compete with
    /// it.
    public static let motif = Color(hex: 0xB3202A)

    /// 6.30:1. Paused state, destructive actions, and error text.
    public static let alert = Color(hex: 0xF0616A)

    // MARK: Rep provenance

    /// A rep the athlete asserted. Filled, cream. See ``detectedRep`` for why the
    /// pair differs in shape as well as colour.
    public static let assertedRep = Color(hex: 0xF5EFE0)

    /// A rep the motion counter guessed. Drawn as a hollow outline in this red,
    /// never as a filled pip.
    ///
    /// Colour alone is not enough to carry this distinction. The pips are 7pt tall
    /// on a 40mm watch, the always-on display dims everything, and roughly one man
    /// in twelve cannot separate these two hues reliably. Fill versus outline
    /// survives all three.
    public static let detectedRep = Color(hex: 0xD93B45)
}

extension Color {
    /// Builds a colour from a `0xRRGGBB` literal.
    ///
    /// Deliberately not public: outside this file, colours come from
    /// ``SenseColor`` by name, so there is exactly one place to change a value
    /// and exactly one place where the contrast ratios are recorded.
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
