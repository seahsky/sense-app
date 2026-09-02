import SwiftUI
import SwiftData
import CindyKit

/// Root navigation shell. Routes Start -> Active -> Summary in a single linear
/// flow, owning the `AmrapTimerEngine` / `RoundRepTracker` / `WorkoutSessionManager`
/// for whichever attempt is currently in progress, plus a History entry point.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    private enum Route {
        case start
        case active
        case summary
    }

    @State private var route: Route = .start
    @State private var showHistory = false

    // Start screen state.
    @State private var selectedVariant: CindyVariant = .rx
    @State private var isRequestingAuthorization = false
    @State private var authorizationErrorMessage: String?

    // In-progress workout state, live for the duration of one attempt.
    @State private var timerEngine: AmrapTimerEngine?
    @State private var tracker: RoundRepTracker?
    @State private var sessionManager = WorkoutSessionManager()

    // Snapshot handed from Active to Summary once the attempt ends.
    @State private var summaryVariant: CindyVariant = .rx
    @State private var summaryDurationSeconds: TimeInterval = 0
    @State private var summaryCompletedRounds: Int = 0
    @State private var summaryPartialReps: Int = 0
    @State private var summaryAverageHeartRate: Double?
    @State private var summaryActiveEnergyBurned: Double?

    var body: some View {
        NavigationStack {
            content
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                WatchHistoryView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .start:
            StartSessionView(
                selectedVariant: $selectedVariant,
                isRequestingAuthorization: isRequestingAuthorization,
                authorizationErrorMessage: authorizationErrorMessage,
                onStart: startWorkout,
                onShowHistory: { showHistory = true }
            )

        case .active:
            if let timerEngine, let tracker {
                ActiveWorkoutView(
                    timerEngine: timerEngine,
                    tracker: tracker,
                    sessionManager: sessionManager,
                    onFinish: finishWorkout
                )
            } else {
                ProgressView()
            }

        case .summary:
            SessionSummaryView(
                variant: summaryVariant,
                durationSeconds: summaryDurationSeconds,
                completedRounds: summaryCompletedRounds,
                partialReps: summaryPartialReps,
                averageHeartRate: summaryAverageHeartRate,
                activeEnergyBurned: summaryActiveEnergyBurned,
                onSave: saveSession,
                onDiscard: resetToStart
            )
        }
    }

    /// Requests HealthKit authorization, starts the `HKWorkoutSession`, and spins
    /// up a fresh `AmrapTimerEngine` + `RoundRepTracker` for this attempt.
    private func startWorkout() {
        isRequestingAuthorization = true
        authorizationErrorMessage = nil

        Task {
            do {
                try await HealthKitAuthManager.requestAuthorization()
                try sessionManager.start()

                let engine = AmrapTimerEngine(capSeconds: selectedVariant.timeCapSeconds)
                let repTracker = RoundRepTracker(variant: selectedVariant)
                engine.start()

                await MainActor.run {
                    timerEngine = engine
                    tracker = repTracker
                    isRequestingAuthorization = false
                    route = .active
                }
            } catch {
                await MainActor.run {
                    isRequestingAuthorization = false
                    authorizationErrorMessage = "Couldn't start: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Called once the AMRAP clock hits 0:00 or the athlete manually ends the
    /// attempt. Snapshots the tracker/timer state, then runs the HealthKit
    /// stop/finalize chain to pull the final average heart rate and active energy
    /// before handing off to the Summary screen.
    private func finishWorkout() {
        guard let timerEngine, let tracker else { return }

        let variant = tracker.variant
        let duration = timerEngine.elapsed
        let rounds = tracker.completedRounds
        let reps = tracker.partialReps

        sessionManager.finish { averageHeartRate, activeEnergyBurned in
            summaryVariant = variant
            summaryDurationSeconds = duration
            summaryCompletedRounds = rounds
            summaryPartialReps = reps
            summaryAverageHeartRate = averageHeartRate
            summaryActiveEnergyBurned = activeEnergyBurned
            route = .summary
        }
    }

    /// Persists the attempt to the watch's own local store and relays it to the
    /// paired iPhone via `WatchConnectivityBridge.sendCompletedSession(_:)` — the
    /// one and only transport used for the finished-workout event.
    private func saveSession() {
        let session = CindySession(
            variant: summaryVariant,
            durationSeconds: summaryDurationSeconds,
            completedRounds: summaryCompletedRounds,
            partialReps: summaryPartialReps,
            averageHeartRate: summaryAverageHeartRate,
            activeEnergyBurned: summaryActiveEnergyBurned,
            source: .watch
        )
        modelContext.insert(session)
        try? modelContext.save()

        WatchConnectivityBridge.shared.sendCompletedSession(session)

        resetToStart()
    }

    private func resetToStart() {
        timerEngine = nil
        tracker = nil
        route = .start
    }
}
