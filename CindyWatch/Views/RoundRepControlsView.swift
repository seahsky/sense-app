import SwiftUI
import CindyKit

/// Primary rep-logging control: a full-width "+1 REP" capsule button backed by
/// `RoundRepTracker.logRep()`, plus Digital Crown rotation bound to a `Double`
/// proxy as a fast alternate input (with the system's own built-in per-detent
/// crown haptics). Every logged rep plays `HapticSignal.repLogged`, escalating to
/// `.roundCompleted` on the tap that closes out a round — so the athlete gets
/// confirmation without having to look at the screen mid-AMRAP.
struct RoundRepControlsView: View {
    let tracker: RoundRepTracker

    @State private var crownValue: Double = 0
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Button(action: logRep) {
                Text("+1 REP")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .clipShape(Capsule())

            Button("Undo Last Rep", action: undoRep)
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .focusable(true)
        .focused($isCrownFocused)
        .onAppear { isCrownFocused = true }
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: 100_000,
            by: 1,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { oldValue, newValue in
            let delta = Int(newValue.rounded()) - Int(oldValue.rounded())
            guard delta != 0 else { return }
            if delta > 0 {
                for _ in 0..<delta { logRep() }
            } else {
                for _ in 0..<(-delta) { undoRep() }
            }
        }
    }

    private func logRep() {
        let roundsBefore = tracker.completedRounds
        tracker.logRep()
        if tracker.completedRounds > roundsBefore {
            HapticSignal.roundCompleted.play()
        } else {
            HapticSignal.repLogged.play()
        }
    }

    private func undoRep() {
        tracker.undoLastRep()
    }
}
