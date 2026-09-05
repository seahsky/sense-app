import SwiftUI
import SenseKit
import SenseUI

/// Variant chip, auto-count switch, and Start. **No scrolling.**
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
///
/// **Why the variant moved into the top bar.** It used to be a 38 pt
/// `.navigationLink` picker in the body. The navigation bar band exists whether or
/// not it is used, so putting the variant there costs no content height and buys
/// all 38 pt for the Start target — which is what lets this screen carry the
/// design's circular button instead of a capsule.
struct StartSessionView: View {
    @Binding var selectedVariant: CindyVariant
    @Binding var isAutoCountEnabled: Bool
    let isRequestingAuthorization: Bool
    let authorizationErrorMessage: String?
    let onStart: () -> Void
    let onShowHistory: () -> Void

    @State private var showVariantPicker = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            startButton

            Spacer(minLength: 0)

            sequenceLine
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let authorizationErrorMessage {
                Text(authorizationErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(SenseColor.alert)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
            }

            autoCountRow
                .padding(.top, 5)
        }
        .padding(.horizontal, WatchLayout.horizontalMargin)
        .padding(.bottom, 2)
        .foregroundStyle(SenseColor.ink)
        .senseBackground(.full)
        .navigationTitle { titleChip }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // History is a destination, not an action, so it belongs in the bar
            // rather than spending a row the Start target can have instead.
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onShowHistory) {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("History")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showVariantPicker = true
                } label: {
                    Text(selectedVariant.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityLabel("Variant, \(selectedVariant.displayName)")
            }
        }
        .sheet(isPresented: $showVariantPicker) {
            VariantPickerSheet(selectedVariant: $selectedVariant)
        }
    }

    /// Auto-count, built as an explicit row rather than a `Toggle` with a label.
    ///
    /// `labelsHidden()` plus a plain `Text` is what lets this row set its own size.
    /// watchOS's `caption2` is around 13 pt, which is correct for a control label
    /// but reads heavy next to the movement sequence above it — that line carries
    /// `minimumScaleFactor` and is usually shrunk well below its nominal size to
    /// fit 162 pt. An explicit 11 pt keeps the two lines in proportion.
    private var autoCountRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(SenseColor.inkSecondary)

            Text("Auto-count")
                .font(.system(size: 11))
                .foregroundStyle(SenseColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Toggle("Auto-count", isOn: $isAutoCountEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SenseColor.motif)
                .scaleEffect(0.8, anchor: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// The one control the athlete hits blind. Round rather than a capsule, per the
    /// design, and sized to the glass so the thumb gets everything the screen can
    /// give.
    private var startButton: some View {
        Button(action: onStart) {
            Group {
                if isRequestingAuthorization {
                    ProgressView()
                } else {
                    Text("Start")
                        .font(SenseFont.display(size: WatchLayout.startLabelSize))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(SenseColor.ink)
        }
        .buttonStyle(.plain)
        .frame(width: WatchLayout.startDiameter, height: WatchLayout.startDiameter)
        .background(SenseColor.accent, in: Circle())
        .disabled(isRequestingAuthorization)
    }

    private var titleChip: some View {
        Text("Cindy · \(selectedVariant.timeCapText)")
            .font(SenseFont.clock(size: 15))
            .foregroundStyle(SenseColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Rep counts in blue, movement names in the dimmer ink, matching the design.
    /// Built by concatenating `Text` rather than with an `AttributedString`, so each
    /// run keeps its own `foregroundStyle` and the whole line still scales as one
    /// unit under `minimumScaleFactor`.
    private var sequenceLine: Text {
        selectedVariant.movementSequence.enumerated().reduce(Text("")) { line, entry in
            let (index, item) = entry
            let separator = index == 0 ? Text("") : Text(" · ").foregroundStyle(SenseColor.inkTertiary)
            return line
                + separator
                + Text("\(item.reps)").foregroundStyle(SenseColor.accentInk)
                + Text(" \(item.movement.displayName)").foregroundStyle(SenseColor.inkSecondary)
        }
    }
}

/// Variant selection, moved out of the body and into a sheet so the Start screen
/// can spend its height on the Start target.
private struct VariantPickerSheet: View {
    @Binding var selectedVariant: CindyVariant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(CindyVariant.allCases) { variant in
                Button {
                    selectedVariant = variant
                    dismiss()
                } label: {
                    HStack {
                        Text(variant.displayName)
                            .foregroundStyle(SenseColor.ink)
                        Spacer()
                        if variant == selectedVariant {
                            Image(systemName: "checkmark")
                                .foregroundStyle(SenseColor.accentInk)
                        }
                    }
                }
            }
        }
        .navigationTitle("Variant")
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
