import SwiftUI
import CindyKit

/// Variant picker + HealthKit authorization + "Start" button. Starting a session
/// is one action on the watch: tapping Start triggers the HealthKit permission
/// prompt (first launch only) and, once granted, creates the `HKWorkoutSession`
/// and begins the `AmrapTimerEngine` in the same flow.
struct StartSessionView: View {
    @Binding var selectedVariant: CindyVariant
    let isRequestingAuthorization: Bool
    let authorizationErrorMessage: String?
    let onStart: () -> Void
    let onShowHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Cindy")
                    .font(.title3.bold())

                Picker("Variant", selection: $selectedVariant) {
                    ForEach(CindyVariant.allCases) { variant in
                        Text(variant.displayName).tag(variant)
                    }
                }
                .pickerStyle(.navigationLink)

                VStack(spacing: 2) {
                    Text(timeCapText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sequenceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let authorizationErrorMessage {
                    Text(authorizationErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: onStart) {
                    Group {
                        if isRequestingAuthorization {
                            ProgressView()
                        } else {
                            Text("Start")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isRequestingAuthorization)

                Button("History", action: onShowHistory)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Cindy")
    }

    private var timeCapText: String {
        let minutes = Int(selectedVariant.timeCapSeconds) / 60
        return "\(minutes):00 AMRAP"
    }

    private var sequenceText: String {
        selectedVariant.movementSequence
            .map { "\($0.reps) \($0.movement.displayName)" }
            .joined(separator: " · ")
    }
}
