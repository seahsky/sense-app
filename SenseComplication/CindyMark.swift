import SwiftUI
// For `widgetAccentable()`, which is declared on View by WidgetKit
// (WidgetKit.swiftinterface:752) and not by SwiftUI.
import WidgetKit
import SenseUI

/// The SENSE mark at complication weights: one dashed ring around a solid disc.
///
/// **Why this is not `SenseMotif.WebMotif`.** Apple's complication guidance sets a
/// 2 pt floor on line width, and neither of the app's existing webs survives the
/// trip. The app icon's stroke is 2.5% of the icon width, which at a 42 pt circular
/// content box is 1.05 pt, and its four concentric rings at 2 pt inside a 21 pt
/// radius are a solid block of ink. `WebMotif` is thinner still — 0.9 pt rings and
/// 0.6 pt radials — and renders as sub-pixel dotted noise on a 2× watch display.
/// So the mark is re-weighted rather than scaled: one ring at 2 pt, and a disc at
/// 0.34 of the side rather than the icon's 0.17. That is `WebIntensity.anchor`
/// applied to a surface where contrast is scarce, which is the rule `SenseMotif`
/// already states — it just cannot be reached by reusing that view.
///
/// **Why the colours barely matter.** Most watch faces render complications
/// `.accented`, where the system treats the views as template images and paints
/// from the alpha channel, discarding colour entirely — and which of the two groups
/// receives the accent flips between faces (Infograph and X-Large are opposites).
/// So the split is semantic rather than tonal: identity (the disc) in the accent
/// group, structure (the ring) in the default group, and the drawing has to read as
/// a ring around a dot under either assignment. Note the one-way trap in Apple's
/// documentation: `widgetAccentable(false)` on a subview cannot undo an ancestor's
/// `true`, which is why the modifier sits on the disc shape itself and never on an
/// enclosing container.
///
/// **Why `SenseColor.ink` and not `SenseColor.motif`.** Every ratio recorded in
/// `SenseColor` is measured against `SenseColor.ground`, which a complication never
/// has. Recomputed over a translucent `AccessoryWidgetBackground` plate, `motif`
/// falls from 3.00:1 to as low as 1.30:1 on a light photo face and `accent` to
/// 1.16:1 — both invisible. `ink` holds at 4.44:1 in that same worst case and
/// `accentInk` at 1.56:1, so the web is drawn in `ink` and the one hue in the
/// design is spent on the disc, where losing it to accenting costs nothing.
struct CindyMark: View {
    /// How many arcs the ring is broken into. Fewer on smaller slots: each arc is
    /// a fixed fraction of the circumference, so at a constant count they shorten
    /// with the radius until they read as specks.
    let arcs: Int
    /// Ring diameter as a fraction of the shorter side.
    let ringFraction: CGFloat
    /// Disc diameter as a fraction of the shorter side.
    let discFraction: CGFloat
    /// Ring line width in points. 2 normally, 2.5 in always-on.
    let stroke: CGFloat

    var body: some View {
        // `Canvas` rather than a dashed `Circle().stroke(style:)` so the stroke
        // width stays a literal point value and the arc pitch is arithmetic. A
        // dash pattern is measured along the circumference, so the same
        // `dash: [a, b]` produces a different number of arcs at every radius —
        // which is exactly the drift that makes the icon's ratios unusable here.
        Canvas { context, size in
            let side = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * ringFraction / 2
            let pitch = 360.0 / Double(arcs)
            // 0.60 duty: ink for three fifths of each step, gap for two. Below
            // about half the ring stops reading as a ring at 42 pt.
            let sweep = pitch * 0.60

            // SwiftUI's 0° is 3 o'clock and its y grows downward, so 12 o'clock is
            // -90°. The ring is phased so the middle of a GAP lands there: an arc
            // edge at the top reads as a tick mark belonging to the watch face
            // rather than to this app.
            //
            // Derived rather than fixed, because the mark is drawn at two arc
            // counts. A constant -20° does not hold for both — at five arcs it puts
            // an arc start 2° off the top, which is 0.66 pt on the 37.8 pt ring and
            // is very nearly the worst phase available. This gives 68.4° at five
            // arcs and 18° at four, centring a gap on 12 o'clock in each.
            let phase = -90 - (pitch + sweep) / 2

            for index in 0..<arcs {
                let start = Angle(degrees: Double(index) * pitch + phase)
                var path = Path()
                path.addArc(
                    center: centre,
                    radius: radius,
                    startAngle: start,
                    endAngle: start + Angle(degrees: sweep),
                    clockwise: false
                )
                // `.butt` stated rather than left to the default: a round cap adds
                // half the line width to each end of every arc, which at 2.5 pt in
                // always-on closes the gaps the mark is made of.
                context.stroke(
                    path,
                    with: .color(SenseColor.ink),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .butt)
                )
            }
        }
        .overlay {
            // The disc lives outside the Canvas because `.widgetAccentable()` is a
            // view modifier and a Canvas is one opaque view: anything drawn inside
            // it lands in whichever group the Canvas itself is in, so ring and disc
            // could never be split.
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                Circle()
                    .fill(SenseColor.accentInk)
                    .frame(width: side * discFraction, height: side * discFraction)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .widgetAccentable()
            }
        }
    }
}
