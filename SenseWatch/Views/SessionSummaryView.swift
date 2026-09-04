import SwiftUI
import SenseKit
import SenseUI

/// Post-workout screen: final score, the session's stats, and Save or Discard.
/// **No scrolling** — the whole thing fits at the 40mm floor.
///
/// The stat strip carries a fourth number the old summary had no way to show: how
/// much of the score the watch guessed. For a feature whose real-world accuracy is
/// unproven, one honest figure per session is how an athlete decides across
/// sessions whether to keep trusting it — and it costs one line, from data
/// `RoundRepTracker` already holds.
struct SessionSummaryView: View {
    let variant: CindyVariant
    let durationSeconds: TimeInterval
    let completedRounds: Int
    let partialReps: Int
    let averageHeartRate: Double?
    let activeEnergyBurned: Double?
    /// Share of reps that came from motion detection, 0...1. Nil when auto-count
    /// was off, so the row disappears rather than reading a misleading "0%".
    let detectedRepFraction: Double?
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Text("\(completedRounds)+\(partialReps)")
                .font(SenseFont.clock(size: WatchLayout.isCompact ? 38 : 44))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("rounds + reps")
                .font(.caption2)
                .foregroundStyle(SenseColor.inkSecondary)

            // One row of four compact stats instead of four labelled rows. At
            // 162 pt wide a "Duration        20:00" row spends most of its width
            // on the word.
            HStack(alignment: .top, spacing: 0) {
                statCell(value: formattedDuration, label: "TIME")
                if let averageHeartRate {
                    statCell(value: "\(Int(averageHeartRate.rounded()))", label: "BPM")
                }
                if let activeEnergyBurned {
                    statCell(value: "\(Int(activeEnergyBurned.rounded()))", label: "KCAL")
                }
                if let detectedRepFraction {
                    statCell(value: "\(Int((detectedRepFraction * 100).rounded()))%", label: "AUTO")
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                // Confirmed, and set well apart from Save. This tap destroys a
                // finished 20-minute attempt that exists nowhere else yet —
                // nothing is written to the store until `onSave`.
                Button {
                    showDiscardConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(SenseColor.alert)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .background { Circle().strokeBorder(SenseColor.alert, lineWidth: 1.5) }
                // Square, so the capsule renders as a circle rather than the
                // vertical pill a 44 x 56 capsule gives next to a horizontal Save.
                .frame(width: WatchLayout.actionHeight)
                .accessibilityLabel("Discard")

                Button(action: onSave) {
                    Text("Save")
                        .font(SenseFont.display(size: 16))
                        .foregroundStyle(SenseColor.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .background(SenseColor.accent, in: Capsule())
            }
            .frame(height: WatchLayout.actionHeight)
        }
        .padding(.horizontal, WatchLayout.horizontalMargin)
        .padding(.bottom, 2)
        .navigationTitle { titleChip }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .foregroundStyle(SenseColor.ink)
        .senseBackground(.full)
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var titleChip: some View {
        Text(variant.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SenseColor.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SenseColor.accentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(SenseColor.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDuration: String {
        let totalSeconds = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#Preview("With auto-count") {
    SessionSummaryView(
        variant: .rx,
        durationSeconds: 1200,
        completedRounds: 17,
        partialReps: 8,
        averageHeartRate: 164,
        activeEnergyBurned: 287,
        detectedRepFraction: 0.61,
        onSave: {},
        onDiscard: {}
    )
}
