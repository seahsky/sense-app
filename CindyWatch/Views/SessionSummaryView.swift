import SwiftUI
import CindyKit

/// Post-workout screen: final score, duration, average heart rate, and active
/// energy, with Save (persists locally + relays to iPhone) or Discard.
struct SessionSummaryView: View {
    let variant: CindyVariant
    let durationSeconds: TimeInterval
    let completedRounds: Int
    let partialReps: Int
    let averageHeartRate: Double?
    let activeEnergyBurned: Double?
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(variant.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(completedRounds)+\(partialReps)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("rounds + reps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 4) {
                    statRow(label: "Duration", value: formattedDuration)
                    if let averageHeartRate {
                        statRow(label: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm")
                    }
                    if let activeEnergyBurned {
                        statRow(label: "Energy", value: "\(Int(activeEnergyBurned.rounded())) kcal")
                    }
                }

                Button(action: onSave) {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(role: .destructive, action: onDiscard) {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Summary")
        .navigationBarBackButtonHidden(true)
    }

    private var formattedDuration: String {
        let totalSeconds = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.footnote)
    }
}
