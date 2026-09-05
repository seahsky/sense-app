import SwiftUI
import SwiftData
import SenseKit

/// Root navigation shell. Routes Start -> Active -> Summary in a single linear
/// flow, owning the `AmrapTimerEngine` / `RoundRepTracker` / `WorkoutSessionManager`
/// / `MotionRepSensor` for whichever attempt is currently in progress, plus a
/// History entry point.
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

    /// Persisted for the same reason `isAutoCountEnabled` is: an athlete who only
    /// ever does Baby Cindy should not have to re-pick it on every launch.
    ///
    /// It carries a second job since the complication landed. A tap on a watch face
    /// writes its variant back here — inside `startWorkout`, so it can only ever
    /// name the variant that actually began — and so the tile and the Start screen
    /// converge on one value rather than each holding its own idea of what "Cindy"
    /// means. That write-back is what makes a configurable complication safe:
    /// without it the face is a second source of truth, and the athlete has no way
    /// to see which one they are about to get.
    @AppStorage("selectedVariant") private var selectedVariant: CindyVariant = .rx

    @State private var isRequestingAuthorization = false
    @State private var authorizationErrorMessage: String?

    /// Persisted so the choice survives a relaunch — an athlete who turned
    /// auto-count off after a bad session should not have to turn it off again
    /// every time.
    @AppStorage("isAutoCountEnabled") private var isAutoCountEnabled = true

    // Complication hand-off state.

    /// The variant a `sense://start` URL asked for, held until
    /// `consumePendingStart()` can act on it.
    ///
    /// A box rather than a direct call, because `.onOpenURL` and `.task` race on a
    /// cold launch and nothing in the SDK fixes their order. Neither can the order
    /// be observed: `simctl openurl` is unsupported on the watchOS simulator and
    /// refuses even system schemes, so a launch-from-face is only reproducible on a
    /// wrist. Both paths write here and both call the one consumer, so whichever
    /// runs second finds the box already empty and does nothing.
    @State private var pendingStart: CindyVariant?

    /// Which affordance began the attempt in progress.
    ///
    /// Read only by the two ``UnattendedStart`` rules, which exist to tear down an
    /// attempt nobody meant to start. They are scoped to `.complication` on
    /// purpose: an attempt begun on the Start button had the athlete's eyes on it,
    /// so it is never taken away behind their back, however empty it is.
    @State private var startTrigger: StartTrigger = .startButton

    /// The armed abandon check for a complication-started attempt, held so every
    /// route out of an attempt can cancel it.
    @State private var unattendedCheck: Task<Void, Never>?

    /// True from the moment `finishWorkout()` is entered until the attempt has left
    /// the Active screen.
    ///
    /// `finishWorkout()` has two independent callers — the End button and the
    /// abandon check — and between them sits `sessionManager.finish`, which is an
    /// asynchronous HealthKit chain with a ten-second timeout. Without this flag a
    /// press of End inside that window re-enters the whole teardown: a second
    /// `finish` overwrites the first's completion and issues a second
    /// `stopActivity` on a session that is already stopping.
    @State private var isFinishing = false

    // In-progress workout state, live for the duration of one attempt.
    @State private var timerEngine: AmrapTimerEngine?
    @State private var tracker: RoundRepTracker?
    @State private var sessionManager = WorkoutSessionManager()
    @State private var repSensor = MotionRepSensor()
    @State private var sessionStartedAt = Date()

    // Snapshot handed from Active to Summary once the attempt ends.
    @State private var summaryVariant: CindyVariant = .rx
    @State private var summaryDurationSeconds: TimeInterval = 0
    @State private var summaryCompletedRounds: Int = 0
    @State private var summaryPartialReps: Int = 0
    @State private var summaryAverageHeartRate: Double?
    @State private var summaryActiveEnergyBurned: Double?
    @State private var summaryDetectedRepFraction: Double?

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            // The DEBUG preview hook runs before this closure's own consume, and
            // that ordering is the one that matters: it moves `route` off `.start`,
            // which is the very condition `consumePendingStart()` guards on, so a
            // screenshot run drops a deep link rather than fighting it. One guard
            // covers the collision; no extra flag, no ordering token.
            //
            // It is NOT ordered against the `Task` that `.onOpenURL` spawns below,
            // and nothing in SwiftUI orders those two. Nothing rests on it: the
            // preview hook is DEBUG-only and opt-in by launch argument, and the one
            // machine that can pass that argument is a simulator, where a URL can
            // never arrive — `simctl openurl` is unsupported on the watchOS
            // simulator.
            applyUIPreviewRouteIfRequested()
            await consumePendingStart()
        }
        .onOpenURL { url in
            guard case .startSession(let variant)? = SenseDeepLink(url: url) else { return }
            pendingStart = variant
            // The `Task` is load-bearing rather than incidental: the HealthKit
            // pre-check inside the consumer is async and this closure is not.
            Task { await consumePendingStart() }
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
                isAutoCountEnabled: $isAutoCountEnabled,
                isRequestingAuthorization: isRequestingAuthorization,
                authorizationErrorMessage: authorizationErrorMessage,
                onStart: { startWorkout(variant: selectedVariant) },
                onShowHistory: { showHistory = true }
            )

        case .active:
            if let timerEngine, let tracker {
                ActiveWorkoutView(
                    timerEngine: timerEngine,
                    tracker: tracker,
                    sessionManager: sessionManager,
                    repSensor: repSensor,
                    sessionStartedAt: sessionStartedAt,
                    isAutoCountEnabled: isAutoCountEnabled,
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
                detectedRepFraction: summaryDetectedRepFraction,
                onSave: saveSession,
                onDiscard: resetToStart
            )
        }
    }

    /// The single place a complication tap becomes a workout.
    ///
    /// Both `.onOpenURL` and `.task` call it, so the hand-off never depends on a
    /// cold-launch ordering that cannot be verified anywhere but on a wrist.
    private func consumePendingStart() async {
        guard let variant = pendingStart else { return }

        // Cleared before the first `await`, so a doubled delivery — two taps, or
        // one tap redelivered along the launch path — finds an empty box. That is
        // half the protection: `startWorkout` re-checks the same guards below,
        // because a second delivery can land *inside* the authorization await, by
        // which point this box has long been empty.
        pendingStart = nil

        // Dropped, never queued. A queued start would open an AMRAP minutes after
        // the athlete asked for it, and a second `HKWorkoutSession` would orphan
        // the first. `timerEngine == nil` is a third condition rather than a
        // restatement of the first: `route` and `timerEngine` are set at different
        // points inside `startWorkout`, so `route` alone leaves a window open.
        guard route == .start, !isRequestingAuthorization, timerEngine == nil else { return }

        // The one thing worse than not starting is starting behind a permission
        // sheet the athlete cannot see past — the clock would already be running by
        // the time they dismissed it. Land them on the Start screen with the tapped
        // variant already selected instead; the toolbar chip naming the variant is
        // the receipt (the title chip reads "Cindy · <cap>" whatever the variant, so
        // it only moves for Baby Cindy, whose cap differs), and one press of Start
        // brings the prompt and then the session. Happens once per install.
        let needsPrompt = await HealthKitAuthManager.needsAuthorizationPrompt()
        guard !needsPrompt else {
            selectedVariant = variant
            return
        }

        // The write-back for the path that does start lives inside `startWorkout`,
        // after its own guard. Writing it here instead would let two deliveries
        // interleave across the authorization await and leave the chip naming one
        // variant while the attempt runs another — the exact drift the persisted
        // variant exists to prevent.
        startWorkout(variant: variant, trigger: .complication)
    }

    /// Requests HealthKit authorization, starts the `HKWorkoutSession`, and spins
    /// up a fresh `AmrapTimerEngine` + `RoundRepTracker` for this attempt.
    ///
    /// Motion sensing starts only *after* the workout session does, and that
    /// ordering is a requirement rather than a tidiness preference:
    /// `CMBatchedSensorManager` produces no data at all without an active
    /// `HKWorkoutSession`.
    ///
    /// The variant arrives as a parameter rather than being read from
    /// `selectedVariant` so that the Start button and a complication tap share one
    /// code path instead of growing two. `trigger` is recorded for the same reason
    /// the parameter exists: what happens at the *end* of this attempt depends on
    /// how it began.
    private func startWorkout(variant: CindyVariant, trigger: StartTrigger = .startButton) {
        // The second half of the re-entrancy protection, and both halves are
        // needed: a second URL delivery can arrive while the first is still inside
        // the authorization await, long after the pending box was cleared. The
        // Start button cannot reach this guard — it is disabled for the whole of
        // `isRequestingAuthorization`, and `route` is `.start` and `timerEngine`
        // nil whenever it is on screen — so the button path pays nothing for it.
        guard route == .start, !isRequestingAuthorization, timerEngine == nil else { return }

        // Written here rather than at the point a URL was parsed, so the persisted
        // chip can only ever name the variant that actually started. A no-op on the
        // Start-button path, where it is where the variant came from.
        selectedVariant = variant

        startTrigger = trigger
        isRequestingAuthorization = true
        authorizationErrorMessage = nil

        Task {
            do {
                try await HealthKitAuthManager.requestAuthorization()
                try sessionManager.start()

                let engine = AmrapTimerEngine(capSeconds: variant.timeCapSeconds)
                let repTracker = RoundRepTracker(variant: variant)
                engine.start()

                await MainActor.run {
                    timerEngine = engine
                    tracker = repTracker
                    sessionStartedAt = Date()
                    isRequestingAuthorization = false
                    route = .active

                    if isAutoCountEnabled {
                        repSensor.onRepsDetected = { [weak repTracker] count in
                            guard let repTracker else { return }
                            RepLogging.logDetected(count, into: repTracker)
                        }
                        repSensor.start(movement: repTracker.currentMovement)
                    }

                    if trigger == .complication {
                        // A tap on a watch face skips the Start screen, so a cold
                        // launch from the face is seconds of black screen with
                        // nothing to say the tap registered. The haptic is the only
                        // confirmation available before the first frame draws.
                        HapticSignal.sessionStarted.play()
                        scheduleUnattendedCheck()
                    }
                }
            } catch {
                await MainActor.run {
                    isRequestingAuthorization = false
                    authorizationErrorMessage = "Couldn't start: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Arms the abandon check for a complication-started attempt.
    ///
    /// This is the case every wrist-mounted trigger has and the Start button does
    /// not: a tap the athlete never noticed — a sleeve, a doorframe, a hand into a
    /// bag — which otherwise runs a silent full 20:00 and surfaces as a Summary
    /// screen hours later. A mis-tap rule that only fires when the athlete presses
    /// End cannot reach it, because nobody is going to press End.
    ///
    /// Armed only for `.complication`, since ``UnattendedStart/shouldAbandonUnattended(trigger:elapsed:hasAssertedARep:)``
    /// answers false for every other trigger and a task that can only ever no-op is
    /// a task not worth arming. The rule is still asked, rather than assumed, when
    /// the timer fires.
    ///
    /// The task must be cancelled by every route out of an attempt — which is why
    /// both `finishWorkout()` and `resetToStart()` do it. One left armed wakes up
    /// into a session that has already gone.
    private func scheduleUnattendedCheck() {
        unattendedCheck = Task {
            try? await Task.sleep(for: .seconds(UnattendedStart.abandonAfter))

            await MainActor.run {
                // Re-read inside the hop, not before it. `finishWorkout()` cancels
                // this task, and the athlete can press End in the gap between the
                // check and the main actor picking this closure up — at which point
                // the attempt is already being torn down and asking again would
                // tear it down twice.
                guard !Task.isCancelled,
                      let engine = timerEngine, let tracker,
                      UnattendedStart.shouldAbandonUnattended(
                          trigger: startTrigger,
                          elapsed: engine.elapsed,
                          hasAssertedARep: tracker.hasAssertedARep
                      )
                else { return }

                // The same close `ActiveWorkoutView.finish()` makes before calling
                // out. Its own re-entry guard is `phase == .running || .paused`, and
                // that guard is the only thing standing between a live End button
                // and a second teardown — so an abandon that skipped this would
                // leave the Active screen on a running clock for the whole of the
                // discard chain with the door still open.
                engine.finish()
                finishWorkout()
            }
        }
    }

    /// Called once the AMRAP clock hits 0:00, the athlete manually ends the
    /// attempt, or the abandon check decides nobody is there. Snapshots the
    /// tracker/timer state, then runs the HealthKit stop/finalize chain to pull the
    /// final average heart rate and active energy before handing off to the Summary
    /// screen — or, for a complication start the athlete never touched, throwing the
    /// attempt away instead.
    private func finishWorkout() {
        // Idempotent, because two callers can reach it: the End button and the
        // abandon check. The teardown below is asynchronous and can take the whole
        // of `WorkoutSessionManager.finishTimeout`, and a second entry inside that
        // window would overwrite the first's completion and stop an already-stopped
        // session.
        guard !isFinishing, let timerEngine, let tracker else { return }
        isFinishing = true

        // Cancelled here and not only in `resetToStart()`, because the ordinary
        // path stops at the Summary screen with the attempt's state still standing:
        // a check left armed would fire into it partway through the athlete reading
        // their score.
        unattendedCheck?.cancel()
        unattendedCheck = nil

        let variant = tracker.variant
        let duration = timerEngine.elapsed
        let rounds = tracker.completedRounds
        let reps = tracker.partialReps
        let detectedFraction = isAutoCountEnabled ? tracker.detectedRepFraction : nil

        // A complication start the athlete never touched is a mis-tap, not a session.
        // Carrying it to Summary would ask the athlete to confirm the teardown of
        // something they never began; discarding it hands the Start screen straight
        // back, and the Start screen reappearing is the whole feedback.
        let discarding = UnattendedStart.shouldDiscardOnEnd(
            trigger: startTrigger,
            hasAssertedARep: tracker.hasAssertedARep
        )

        repSensor.stop()
        repSensor.onRepsDetected = nil

        sessionManager.finish(discardingWorkout: discarding) { averageHeartRate, activeEnergyBurned in
            guard !discarding else {
                resetToStart()
                return
            }

            summaryVariant = variant
            summaryDurationSeconds = duration
            summaryCompletedRounds = rounds
            summaryPartialReps = reps
            summaryAverageHeartRate = averageHeartRate
            summaryActiveEnergyBurned = activeEnergyBurned
            summaryDetectedRepFraction = detectedFraction
            route = .summary
            isFinishing = false
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

    /// Jumps straight to a screen with synthetic state, so the live-workout and
    /// summary layouts can be screenshotted on a simulator.
    ///
    /// Those two screens are otherwise unreachable without HealthKit
    /// authorization and a real `HKWorkoutSession`, neither of which a simulator
    /// grants unattended — which meant the densest screen in the app, and the only
    /// one with a no-scroll guarantee to defend, could never be checked
    /// automatically at the 40mm floor it is designed against.
    ///
    /// DEBUG-only and opt-in by launch argument, so it cannot reach a release
    /// build or affect a normal run:
    ///
    ///     xcrun simctl launch <udid> <bundle-id> -SenseUIPreview active
    private func applyUIPreviewRouteIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-SenseUIPreview"),
              arguments.index(after: flagIndex) < arguments.endIndex else { return }

        // Pinned rather than read from `selectedVariant`. That property is now
        // `@AppStorage`, so it carries whatever the last run of this simulator left
        // in UserDefaults — and a screenshot check whose clock reads 20:00 or 12:00
        // depending on the container's history is not a layout check. Rx is the
        // widest state: 20:00 in the clock and the full three-movement pip row.
        let previewVariant = CindyVariant.rx

        let engine = AmrapTimerEngine(capSeconds: previewVariant.timeCapSeconds)
        let repTracker = RoundRepTracker(variant: previewVariant)
        engine.start()

        // Mid-round, mid-movement, with a mix of provenance: the state that
        // exercises every branch of the pip row at once.
        RepLogging.logAsserted(5, source: .manual, into: repTracker)
        RepLogging.logAsserted(10, source: .manual, into: repTracker)
        RepLogging.logAsserted(4, source: .manual, into: repTracker)
        RepLogging.logDetected(5, into: repTracker)

        switch arguments[arguments.index(after: flagIndex)] {
        case "active":
            timerEngine = engine
            tracker = repTracker
            sessionStartedAt = Date()
            route = .active
        case "summary":
            summaryVariant = previewVariant
            summaryDurationSeconds = 1200
            summaryCompletedRounds = 17
            summaryPartialReps = 8
            summaryAverageHeartRate = 164
            summaryActiveEnergyBurned = 287
            summaryDetectedRepFraction = 0.61
            route = .summary
        default:
            break
        }
        #endif
    }

    private func resetToStart() {
        unattendedCheck?.cancel()
        unattendedCheck = nil
        // Back to the default, so the next attempt is judged by how it actually
        // began. A `.complication` left standing here would let the two
        // ``UnattendedStart`` rules reach an attempt the athlete pressed Start for,
        // which is exactly what those rules are scoped to avoid.
        startTrigger = .startButton
        isFinishing = false
        repSensor.stop()
        repSensor.onRepsDetected = nil
        timerEngine = nil
        tracker = nil
        route = .start
    }
}
