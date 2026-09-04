import SwiftUI

/// How much of the web motif a screen is allowed to draw.
///
/// The reference design puts a full web across every screen. That works on a still
/// image and fails during a workout: the strokes cross the countdown at the exact
/// moment the countdown is the only thing on screen that matters, and the
/// always-on display dims the whole frame so contrast is already scarce.
///
/// So the motif is a property of the *screen*, not of the app. Screens the athlete
/// reads standing still get the full web. The live workout gets an anchor ring and
/// nothing else, and in always-on it gets nothing at all.
public enum WebIntensity: Sendable {
    /// Radiating tension lines plus two dashed arcs. Start, Summary, History.
    case full

    /// One dashed ring, no radials. The live workout screen.
    case anchor

    /// Nothing drawn. Always-on, and anywhere contrast has to be spent on content.
    case none
}

/// The web itself: straight tension lines converging on a centre, crossed by dashed
/// arcs.
///
/// The geometry is deliberately shared with the app icon, which draws the same
/// dashed stroke in the same red. The icon uses the arcs and this uses both, so the
/// two read as one system without being the same drawing.
public struct WebMotif: View {
    private let intensity: WebIntensity

    public init(intensity: WebIntensity) {
        self.intensity = intensity
    }

    public var body: some View {
        switch intensity {
        case .none:
            Color.clear
        case .anchor:
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                dashedRing(diameter: side * 0.86)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(false)
        case .full:
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    radials(in: proxy.size)
                    dashedRing(diameter: side * 0.86)
                    dashedRing(diameter: side * 1.24)
                    centreScrim
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Eight lines through the centre, drawn past the edges so the web reads as a
    /// fragment of something larger rather than a decal sitting on the screen.
    private func radials(in size: CGSize) -> some View {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = max(size.width, size.height)

        return Path { path in
            for step in 0..<8 {
                let angle = Double(step) * .pi / 4
                let dx = cos(angle) * reach
                let dy = sin(angle) * reach
                path.move(to: CGPoint(x: centre.x - dx, y: centre.y - dy))
                path.addLine(to: CGPoint(x: centre.x + dx, y: centre.y + dy))
            }
        }
        .stroke(SenseColor.motif, lineWidth: 0.6)
    }

    /// Fades the web out of the middle of the screen.
    ///
    /// Eight radials converging on one point put their densest area exactly where
    /// a centred layout puts its most important text. On the Start screen that
    /// convergence is hidden behind the blue button; on Summary and History there
    /// is nothing to hide it, and the lines cross the score and the stat row.
    ///
    /// So the web keeps its full geometry and loses its contrast where content
    /// sits: opaque ground at the centre, clear by the edges. The result reads as
    /// a web seen behind the screen rather than drawn on top of it, which is what
    /// the design reference actually looks like.
    private var centreScrim: some View {
        RadialGradient(
            colors: [
                SenseColor.ground,
                SenseColor.ground.opacity(0.92),
                SenseColor.ground.opacity(0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 96
        )
    }

    private func dashedRing(diameter: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                SenseColor.motif,
                style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 3.5])
            )
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public extension View {
    /// Puts the ground and the web behind a screen.
    ///
    /// Pass `isLuminanceReduced` from the environment on the watch. Always-on
    /// forces ``WebIntensity/none`` regardless of what the screen asked for,
    /// because the dimmed frame has no contrast to spare on decoration.
    func senseBackground(_ intensity: WebIntensity, isLuminanceReduced: Bool = false) -> some View {
        background {
            ZStack {
                SenseColor.ground
                WebMotif(intensity: isLuminanceReduced ? .none : intensity)
            }
            .ignoresSafeArea()
        }
    }
}

#Preview("Full") {
    VStack {
        Text("20:00").font(SenseFont.clock(size: 34)).foregroundStyle(SenseColor.ink)
        Text("Start").font(SenseFont.display(size: 20)).foregroundStyle(SenseColor.ink)
    }
    .frame(width: 162, height: 197)
    .senseBackground(.full)
}

#Preview("Anchor") {
    Text("11:11")
        .font(SenseFont.clock(size: 34))
        .foregroundStyle(SenseColor.ink)
        .frame(width: 162, height: 197)
        .senseBackground(.anchor)
}
