import SwiftUI
import SenseKit
import SenseUI

/// One pip per rep in the current movement, showing at a glance how many are done
/// and — for each of them — whether the athlete asserted it or the watch guessed
/// it.
///
/// This replaces a transient "auto +1" flash, and the reason is the accuracy data.
/// A counter that is exactly right on 55–65% of sets will be wrong often enough
/// that the athlete needs to see *which* reps are the watch's opinion, not just
/// be told once, a second and a half ago, that one happened. Provenance has to
/// persist for the life of the movement or it is not auditable at all.
///
/// Three channels carry the state, because one is never enough on a wrist at arm's
/// length while breathing hard: **fill** (solid for reps the athlete asserted,
/// hollow for the watch's guesses), **height** (full for done, half for pending),
/// and **hue** (cream, red, dim). Colour alone would fail a colour-blind athlete;
/// shape alone would fail at a glance; together they read.
struct RepPipRow: View {
    let total: Int
    /// Where each completed rep of this movement came from, oldest first.
    ///
    /// Provenance per rep, not two counts. Rendering "n asserted, then m
    /// detected" from a pair of integers puts every asserted pip first regardless
    /// of the real order, so a detected rep that is not part of the trailing run
    /// is drawn as the athlete's own — tap, detect three, tap gives five solid
    /// pips and launders three guesses into ground truth. That defeats the
    /// requirement in this file's own doc comment.
    let sources: [RepSource]
    /// The movement is one rep from advancing and that rep must come from a tap.
    let awaitingBoundaryRep: Bool

    private var completed: Int { sources.count }

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                pip(at: index)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchLayout.pipHeight, alignment: .center)
            }
        }
        // Deliberately NOT containerRelativeFrame(.horizontal, count:). That
        // divides the container it lands in — on watchOS the unpadded screen —
        // so 15 air-squat pips would overflow the padded row they actually own.
        // `maxWidth: .infinity` inside an HStack divides the row itself.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) reps, \(detectedCount) detected automatically")
    }

    @ViewBuilder
    private func pip(at index: Int) -> some View {
        let shape = Capsule(style: .continuous)
        if index < completed {
            if sources[index].isUserConfirmed {
                // Asserted by the athlete: solid, full height.
                shape.fill(SenseColor.assertedRep).frame(height: WatchLayout.pipHeight)
            } else {
                // The watch's opinion: hollow and shorter, so provenance survives
                // both a colour-blind athlete and a glance from arm's length.
                shape.strokeBorder(SenseColor.detectedRep, lineWidth: 1.5)
                    .frame(height: WatchLayout.pipHeight)
            }
        } else if awaitingBoundaryRep && index == completed {
            // The rep the detector is not allowed to take. Marking it is what
            // teaches "keep tapping until it moves on" without any words.
            shape.fill(SenseColor.assertedRep.opacity(isLuminanceReduced ? 0.6 : 0.45))
                .frame(height: WatchLayout.pipHeight)
        } else {
            shape.fill(SenseColor.inkTertiary.opacity(isLuminanceReduced ? 0.5 : 0.3))
                .frame(height: max(3, WatchLayout.pipHeight * 0.45))
        }
    }

    private var detectedCount: Int { sources.filter { !$0.isUserConfirmed }.count }
}

/// Builds a source list from a compact pattern: `m` asserted, `d` detected.
/// Previews only — the real row reads `RoundRepTracker.currentMovementRepSources`.
private func previewSources(_ pattern: String) -> [RepSource] {
    pattern.map { $0 == "d" ? .detected : .manual }
}

#Preview("Mid set, interleaved provenance") {
    RepPipRow(total: 15, sources: previewSources("mdddmddmd"), awaitingBoundaryRep: false)
        .padding()
}

#Preview("Awaiting the boundary tap") {
    RepPipRow(total: 5, sources: previewSources("mddd"), awaitingBoundaryRep: true)
        .padding()
}
