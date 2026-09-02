import SwiftUI
import CindyKit

/// The in-workout screen: a big countdown backed by `AmrapTimerEngine.activeInterval`,
/// the current movement + reps-into-round from `RoundRepTracker`, live heart rate
/// from the workout builder, and the rep-logging controls.
struct ActiveWorkoutView: View {
    let timerEngine: AmrapTimerEngine
    let tracker: RoundRepTracker
    let sessionManager: WorkoutSessionManager
    var onFinish: () -> Void

    /// Mirrors the moment `timerEngine.pause(at:)` was called so `Text(timerInterval:pauseTime:...)`
    /// freezes its display in step with the engine — `AmrapTimerEngine` doesn't expose
    /// its internal pause timestamp, so this view tracks its own copy of the same `Date`.
    @State private var pausedAt: Date?
    @State private var showEndConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                timerSection
                movementSection
                RoundRepControlsView(tracker: tracker)
                controlButtons
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(tracker.variant.displayName)
        .navigationBarBackButtonHidden(true)
        .task { await watchForTimeCap() }
        .task { await publishLiveContextPeriodically() }
        .confirmationDialog(
            "End this workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive, action: finish)
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        if let interval = timerEngine.activeInterval {
            Text(timerInterval: interval, pauseTime: pausedAt, countsDown: true, showsHours: false)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)

            ProgressView(timerInterval: interval, countsDown: true)
                .progressViewStyle(.linear)
                .tint(.green)
        }

        if let heartRate = sessionManager.currentHeartRate {
            Label("\(Int(heartRate.rounded())) bpm", systemImage: "heart.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var movementSection: some View {
        VStack(spacing: 2) {
            Text(tracker.currentMovement.displayName)
                .font(.headline)
            Text("\(tracker.repsInCurrentMovement) / \(currentStepReps)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Score \(tracker.scoreString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button(action: togglePause) {
                Image(systemName: timerEngine.phase == .paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showEndConfirmation = true
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private var currentStepReps: Int {
        let sequence = tracker.variant.movementSequence
        guard sequence.indices.contains(tracker.currentStepIndex) else { return 0 }
        return sequence[tracker.currentStepIndex].reps
    }

    private func togglePause() {
        switch timerEngine.phase {
        case .running:
            let now = Date()
            timerEngine.pause(at: now)
            pausedAt = now
            sessionManager.pause()
        case .paused:
            timerEngine.resume()
            pausedAt = nil
            sessionManager.resume()
        default:
            break
        }
    }

    private func finish() {
        guard timerEngine.phase == .running || timerEngine.phase == .paused else { return }
        timerEngine.finish()
        HapticSignal.sessionFinished.play()
        onFinish()
    }

    /// Polls `remaining` while the clock is running so the 0:00 buzzer fires
    /// (haptic + auto-transition to Summary) without the athlete having to tap
    /// anything. `Text(timerInterval:)` updates its own on-screen display for free;
    /// this loop only exists to notice the moment the cap is reached.
    private func watchForTimeCap() async {
        while !Task.isCancelled {
            switch timerEngine.phase {
            case .running:
                if timerEngine.remaining <= 0 {
                    finish()
                    return
                }
            case .finished:
                return
            default:
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Publishes this attempt's elapsed time + score to `WatchConnectivityBridge`'s
    /// "latest state only" application-context channel roughly once a second so the
    /// iPhone's Timer tab (Watch mode) has something to mirror — nothing else in this
    /// app ever calls `publishLiveContext`, so without this loop that iOS-side mirror
    /// would never receive live data. `updateApplicationContext` is cheap and
    /// coalesces to the latest call, so a 1s cadence is more than sufficient for a
    /// "roughly live" mirror.
    private func publishLiveContextPeriodically() async {
        while !Task.isCancelled {
            switch timerEngine.phase {
            case .running, .paused:
                try? WatchConnectivityBridge.shared.publishLiveContext(
                    elapsedSeconds: timerEngine.elapsed,
                    completedRounds: tracker.completedRounds,
                    partialReps: tracker.partialReps
                )
            case .idle, .finished:
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
