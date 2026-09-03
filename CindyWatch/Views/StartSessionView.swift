import SwiftUI
import CindyKit

/// Variant picker, auto-count switch, and Start. **No scrolling.**
///
/// Starting a session is one action: tapping Start triggers the HealthKit
/// permission prompt (first launch only) and, once granted, creates the
/// `HKWorkoutSession` and begins the `AmrapTimerEngine` in the same flow.
///
/// The auto-count toggle lives here rather than mid-workout on purpose. Published
/// counting accuracy for these three movements runs 80–88% of sets within ±1 rep,
/// with the air squat worst, so some athletes will want it off — and the moment to
/// make that call is before the clock starts, not while hanging off a bar. There is
/// no permission to pre-request: Core Motion exposes no authorization request API
/// for accelerometer data at all, so the app simply starts the stream and degrades.
struct StartSessionView: View {
    @Binding var selectedVariant: CindyVariant
    @Binding var isAutoCountEnabled: Bool
    let isRequestingAuthorization: Bool
    let authorizationErrorMessage: String?
    let onStart: () -> Void
    let onShowHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Variant", selection: $selectedVariant) {
                ForEach(CindyVariant.allCases) { variant in
                    Text(variant.displayName).tag(variant)
                }
            }
            .pickerStyle(.navigationLink)
            .frame(height: 38)

            Text(sequenceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)

            Toggle(isOn: $isAutoCountEnabled) {
                Label("Auto-count", systemImage: "waveform")
                    .font(.caption)
                    .lineLimit(1)
            }
            .toggleStyle(.switch)
            .padding(.top, 4)

            if let authorizationErrorMessage {
                Text(authorizationErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button(action: onStart) {
                Group {
                    if isRequestingAuthorization {
                        ProgressView()
                    } else {
                        Text("Start")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .clipShape(Capsule())
            .frame(height: WatchLayout.actionHeight)
            .disabled(isRequestingAuthorization)
        }
        .padding(.horizontal, WatchLayout.horizontalMargin)
        .padding(.bottom, 2)
        .navigationTitle { titleChip }
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Color.green.opacity(0.15).gradient, for: .navigation)
        .toolbar {
            // History is a destination, not an action, so it belongs in the bar
            // rather than spending a row that the Start button can have instead.
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShowHistory) {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("History")
            }
        }
    }

    private var titleChip: some View {
        Text("Cindy · \(timeCapText)")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var timeCapText: String {
        "\(Int(selectedVariant.timeCapSeconds) / 60):00"
    }

    private var sequenceText: String {
        selectedVariant.movementSequence
            .map { "\($0.reps) \($0.movement.displayName)" }
            .joined(separator: " · ")
    }
}

#Preview("Start") {
    @Previewable @State var variant: CindyVariant = .rx
    @Previewable @State var autoCount = true

    NavigationStack {
        StartSessionView(
            selectedVariant: $variant,
            isAutoCountEnabled: $autoCount,
            isRequestingAuthorization: false,
            authorizationErrorMessage: nil,
            onStart: {},
            onShowHistory: {}
        )
    }
}

/// The tallest this screen ever gets: a two-line authorization error on top of
/// everything else.
#Preview("Authorization failed") {
    @Previewable @State var variant: CindyVariant = .weightedVest
    @Previewable @State var autoCount = true

    NavigationStack {
        StartSessionView(
            selectedVariant: $variant,
            isAutoCountEnabled: $autoCount,
            isRequestingAuthorization: false,
            authorizationErrorMessage: "Couldn't start: the operation couldn't be completed.",
            onStart: {},
            onShowHistory: {}
        )
    }
}
