import SwiftUI
import SenseKit
import SenseUI

/// The in-workout screen. **One screen, no scrolling, no pages.**
///
/// The old version was a `ScrollView`, which meant an athlete mid-AMRAP could
/// scroll the countdown off the top of the screen with a stray palm and then have
/// to fix it one-handed while hanging off a bar. Apple's watchOS HIG asks for
/// "quick, glanceable, single-screen interactions", and this is the honest
/// version of that: everything fits at the 40mm floor of 162 × 197 pt, so nothing
/// can ever move.
///
/// Two structural decisions buy the room:
///
/// 1. **Controls that are not "+1 rep" live in the navigation bar.** Pause and
///    undo sit in `.topBarLeading` / `.topBarTrailing`, and the score sits in the
///    watchOS-exclusive `navigationTitle { }` view builder. That bar band exists
///    whether or not it is used, so those three cost zero content height. What
///    used to be a two-button control row and a "Score 12+7" line is now free.
/// 2. **No `.verticalPage` TabView.** Paging is Apple's answer to "more content
///    than fits", but it costs the Digital Crown — which this app needs for rep
///    logging — and its index dots cannot be hidden, since `indexDisplayMode` is
///    a `PageTabViewStyle` member and does not exist on `VerticalPageTabViewStyle`.
///    Making the content actually fit is cheaper than paying both.
///
/// Height budget at 162 × 197 pt, against ~163 pt of usable height:
/// clock 34 · progress 6 · movement 24 · pips 11 · status 13 · action 56 · pad 2
/// = 146 pt, leaving ~17 pt of real slack for Dynamic Type to eat.
struct ActiveWorkoutView: View {
    let timerEngine: AmrapTimerEngine
    let tracker: RoundRepTracker
    let sessionManager: WorkoutSessionManager
    let repSensor: MotionRepSensor
    let sessionStartedAt: Date
    let isAutoCountEnabled: Bool
    var onFinish: () -> Void

    /// Mirrors the moment `timerEngine.pause(at:)` was called so `Text(timerInterval:pauseTime:...)`
    /// freezes its display in step with the engine — `AmrapTimerEngine` doesn't expose
    /// its internal pause timestamp, so this view tracks its own copy of the same `Date`.
    @State private var pausedAt: Date?
    @State private var showEndConfirmation = false
    @State private var showBulkUndoConfirmation = false
    @State private var activityState: WorkoutActivityState = .working

    /// Advanced once a second by `trackActivityState`, and the only thing that
    /// drives the cap bar — see `remainingFraction`.
    @State private var now: Date = .now

    /// The instant rest is measured from when no rep has been logged yet.
    ///
    /// Advanced on resume so a pause — which the athlete took precisely to stop
    /// the clock — is not then billed back to them as several minutes of rest the
    /// moment they start again.
    @State private var restReference: Date = .now

    /// Crown position as an integer step count. See `handleCrown(_:)` for why this
    /// is tracked separately from the bound `Double`.
    @State private var crownValue: Double = 0
    @State private var crownBaseline: Int = 0
    @State private var lastTapAt: Date = .distantPast
    @FocusState private var isCrownFocused: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// A crown gesture is one flick. Anything larger is a glitch, not an athlete
    /// doing forty pull-ups in one rotation.
    private static let maxRepsPerCrownGesture = 12

    /// Four taps a second is far above any human cadence and still forgiving of a
    /// shaking thumb double-hitting a 56 pt target.
    private static let minimumTapInterval: TimeInterval = 0.25

    var body: some View {
        VStack(spacing: 0) {
            clockRow
            capProgress
            movementRow
            pipRow
            statusRow

            Spacer(minLength: 0)

            actionSlot
        }
        .padding(.horizontal, WatchLayout.horizontalMargin)
        .padding(.bottom, 2)
        .navigationTitle { titleChip }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .foregroundStyle(SenseColor.ink)
        // Anchor ring only, never the full web: this is the screen the athlete
        // reads mid-effort, and `senseBackground` drops even the ring in
        // always-on, where the dimmed frame has no contrast to spare.
        .senseBackground(.anchor, isLuminanceReduced: isLuminanceReduced)
        .focusable(true)
        .focused($isCrownFocused)
        // Re-asserted on every state change rather than only `.onAppear`: focus is
        // lost when the confirmation dialog or a system sheet takes over, and a
        // crown that silently stops logging reps mid-WOD is worse than one that
        // never worked.
        .onAppear { isCrownFocused = true }
        .onChange(of: showEndConfirmation) { _, isShowing in
            if !isShowing { isCrownFocused = true }
        }
        .onChange(of: showBulkUndoConfirmation) { _, isShowing in
            if !isShowing { isCrownFocused = true }
        }
        .digitalCrownRotation(
            $crownValue,
            from: -100_000,
            through: 100_000,
            by: 1,
            sensitivity: .low,
            // `isContinuous: false` is load-bearing. With wrapping enabled and a
            // value starting at the lower bound, one backward detent rolls over to
            // the far end of the range and the delta handler logs the entire range
            // as reps — 100,000 of them, each with a haptic, on the main thread.
            // Hard stops make that unreachable, and the symmetric range means
            // neither bound is anywhere near the value after a 20-minute AMRAP.
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .digitalCrownAccessory(.hidden)
        .onChange(of: crownValue) { _, newValue in handleCrown(newValue) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: togglePause) {
                    Image(systemName: timerEngine.phase == .paused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(timerEngine.phase == .paused ? "Resume" : "Pause")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(tracker.totalRepsLogged == 0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                        guard tracker.trailingDetectedRepCount > 0 else { return }
                        showBulkUndoConfirmation = true
                    }
                )
                .accessibilityLabel("Undo last rep")
                .accessibilityHint(
                    tracker.trailingDetectedRepCount > 0
                        ? "Long press to remove all \(tracker.trailingDetectedRepCount) auto-counted reps"
                        : ""
                )
            }
        }
        .onAppear { restReference = sessionStartedAt }
        .task { await watchForTimeCap() }
        .task { await trackActivityState() }
        .task { await publishLiveContextPeriodically() }
        .onChange(of: repSensor.status) { _, status in
            if case .failed = status { HapticSignal.detectionLost.play() }
        }
        // Retarget the detector in the same main-actor turn the tracker advances,
        // not on the next poll. The engine only confirms a peak once it is
        // `minPeriod` old, so with a 1 Hz poll the last rep of the outgoing
        // movement could still be emitted *after* the athlete's boundary tap and
        // be credited to the incoming movement.
        .onChange(of: tracker.currentStepIndex) { _, _ in
            repSensor.setMovement(tracker.currentMovement)
        }
        .confirmationDialog(
            "End this workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive, action: finish)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove \(tracker.trailingDetectedRepCount) auto-counted reps?",
            isPresented: $showBulkUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: undoTrailingDetected)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Rows

    /// The score, in the title slot rather than in a content row of its own.
    /// `navigationTitle { }` taking a view builder is watchOS-exclusive and is the
    /// standard way to buy back a line on a dense screen.
    private var titleChip: some View {
        HStack(spacing: 3) {
            if isAutoCountEnabled {
                Image(systemName: autoGlyph)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(autoTint)
            }
            Text(tracker.scoreString)
                .font(SenseFont.clock(size: 14))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Clock and heart rate share one row. Heart rate used to be a whole line of
    /// its own that appeared and disappeared as samples arrived, reflowing
    /// everything beneath it; here it has a permanent home in width the 30–34 pt
    /// countdown was never going to use.
    @ViewBuilder
    private var clockRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if let interval = timerEngine.activeInterval {
                Text(timerInterval: interval, pauseTime: pausedAt, countsDown: true, showsHours: false)
                    .font(SenseFont.clock(size: WatchLayout.clockFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(stateTint)
            }

            Spacer(minLength: 2)

            Text(heartRateText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(SenseColor.alert)
                .lineLimit(1, reservesSpace: true)
        }
    }

    /// The cap bar, driven from an explicit fraction in every state.
    ///
    /// Not `ProgressView(timerInterval:countsDown:)`, despite that being the
    /// obvious choice: it carries a default date label that the linear style
    /// renders *under* the bar, spending ~15 pt this layout has not budgeted —
    /// and it has no `pauseTime` parameter, so it would also keep advancing while
    /// paused. Driving `value:total:` in both states fixes both problems at once
    /// and keeps the bar the same height whether running or paused. A 1 Hz
    /// refresh is imperceptible on a 20-minute bar, where one second is 0.08% of
    /// the width.
    @ViewBuilder
    private var capProgress: some View {
        ProgressView(value: remainingFraction, total: 1)
            .progressViewStyle(.linear)
            .tint(stateTint)
            .padding(.top, 2)
    }

    /// Driven from `now`, which the 1 Hz loop advances, rather than from
    /// `timerEngine.remaining`.
    ///
    /// `remaining` reads the system clock inside a computed property, so SwiftUI
    /// has nothing to observe and the bar would simply never move — it would
    /// re-render only when some *other* piece of state happened to change. The
    /// explicit tick is what makes it a progress bar rather than a static line.
    private var remainingFraction: Double {
        guard let interval = timerEngine.activeInterval else { return 0 }
        let duration = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard duration > 0 else { return 0 }
        let reference = pausedAt ?? now
        let remaining = min(duration, max(0, interval.upperBound.timeIntervalSince(reference)))
        return remaining / duration
    }

    private var movementRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(tracker.currentMovement.displayName.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(SenseColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 2)

            Text("\(tracker.repsInCurrentMovement)/\(currentStepReps)")
                .font(SenseFont.clock(size: WatchLayout.movementFontSize))
                .lineLimit(1)
        }
        .padding(.top, 3)
    }

    private var pipRow: some View {
        RepPipRow(
            total: currentStepReps,
            completed: tracker.repsInCurrentMovement,
            detected: min(tracker.trailingDetectedRepCount, tracker.repsInCurrentMovement),
            awaitingBoundaryRep: isAutoCountEnabled && tracker.isAwaitingBoundaryRep
        )
        .padding(.top, 3)
    }

    /// One line, always present, never reflowing. `reservesSpace` matters more
    /// than it looks: without it, every transition between "RESTING 0:14" and
    /// nothing at all would shift the button below it by 13 pt mid-set.
    private var statusRow: some View {
        HStack(spacing: 3) {
            if case .resting(let since) = activityState, timerEngine.phase == .running {
                Text("REST")
                Text(
                    timerInterval: since...since.addingTimeInterval(3600),
                    pauseTime: nil,
                    countsDown: false,
                    showsHours: false
                )
                .monospacedDigit()
            } else {
                Text(statusText)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(statusTint)
        .lineLimit(1, reservesSpace: true)
        .minimumScaleFactor(0.7)
        .padding(.top, 2)
    }

    /// The action slot. One button while the clock runs; Resume and End while
    /// paused.
    ///
    /// Putting End here rather than in the toolbar is what makes it reachable at
    /// all. An earlier revision of this screen moved pause into `.topBarLeading`
    /// and gave `.topBarTrailing` to undo, which left the end-workout
    /// confirmation dialog with no way to present it — an athlete who blew up at
    /// 6:00 had no exit but force-quitting, which discards the attempt entirely,
    /// because nothing is persisted until the Summary screen. Pausing made it
    /// permanent, since the time-cap poller only advances while running.
    ///
    /// Both states occupy the same height, so nothing reflows when the athlete
    /// pauses.
    @ViewBuilder
    private var actionSlot: some View {
        if timerEngine.phase == .paused {
            HStack(spacing: 6) {
                Button(action: togglePause) {
                    Label("Resume", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(SenseColor.ink)
                }
                .buttonStyle(.plain)
                .background(SenseColor.accent, in: Capsule())
                .accessibilityLabel("Resume")

                Button {
                    showEndConfirmation = true
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(SenseColor.alert)
                }
                .buttonStyle(.plain)
                .background {
                    Capsule().strokeBorder(SenseColor.alert, lineWidth: 1.5)
                }
                .accessibilityLabel("End workout")
            }
            .frame(height: WatchLayout.actionHeight)
        } else {
            Button(action: tapRep) {
                Text("+1 REP")
                    .font(SenseFont.display(size: WatchLayout.isCompact ? 16 : 18))
                    .foregroundStyle(buttonLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(buttonFill, in: Capsule())
            .frame(height: WatchLayout.actionHeight)
        }
    }

    // MARK: - Derived presentation

    private var currentStepReps: Int {
        let sequence = tracker.variant.movementSequence
        guard sequence.indices.contains(tracker.currentStepIndex) else { return 0 }
        return sequence[tracker.currentStepIndex].reps
    }

    private var heartRateText: String {
        guard let heartRate = sessionManager.currentHeartRate else { return "" }
        return "\(Int(heartRate.rounded()))♥"
    }

    /// Colour is never the only carrier of state here — every case below also
    /// changes a word or a number. An athlete with a dimmed always-on display, or
    /// who is colour-blind, gets the same information.
    private var stateTint: Color {
        if timerEngine.phase == .paused { return SenseColor.alert }
        if activityState.isResting { return SenseColor.inkSecondary }
        return SenseColor.ink
    }

    /// Working state fills the action with the accent. The boundary rep inverts it
    /// to cream instead of reaching for another hue: the athlete has to notice this
    /// change while breathing hard and possibly in always-on, and a fill that flips
    /// from blue to near-white is a far bigger signal than any hue swap, while
    /// still reading for someone who cannot separate the two colours at all.
    private var buttonFill: Color {
        tracker.isAwaitingBoundaryRep && isAutoCountEnabled ? SenseColor.ink : SenseColor.accent
    }

    private var buttonLabel: Color {
        tracker.isAwaitingBoundaryRep && isAutoCountEnabled ? SenseColor.ground : SenseColor.ink
    }

    private var statusTint: Color {
        if timerEngine.phase == .paused { return SenseColor.alert }
        if tracker.isAwaitingBoundaryRep && isAutoCountEnabled { return SenseColor.accentInk }
        if activityState.isResting { return SenseColor.inkSecondary }
        return SenseColor.inkTertiary
    }

    private var statusText: String {
        if timerEngine.phase == .paused { return "PAUSED" }
        if !isAutoCountEnabled { return "MANUAL" }
        if tracker.isAwaitingBoundaryRep { return "TAP TO FINISH SET" }
        switch repSensor.status {
        case .failed: return "AUTO OFF · TAP EACH REP"
        case .idle: return "AUTO STARTING"
        case .running: return "AUTO ON"
        }
    }

    private var autoGlyph: String {
        switch repSensor.status {
        case .running: return "waveform"
        case .idle: return "waveform.badge.exclamationmark"
        case .failed: return "waveform.slash"
        }
    }

    private var autoTint: Color {
        repSensor.status.isRunning ? SenseColor.accentInk : SenseColor.inkTertiary
    }

    // MARK: - Actions

    private func tapRep() {
        // Debounce rather than trust the button: a 56 pt target hit by a shaking,
        // sweaty thumb double-fires, and a double-fire here is a wrong score.
        let now = Date()
        guard now.timeIntervalSince(lastTapAt) >= Self.minimumTapInterval else { return }
        lastTapAt = now
        RepLogging.logAsserted(source: .manual, into: tracker)
    }

    /// Undo removes exactly one rep. Always.
    ///
    /// An earlier revision made this branch on invisible state — striking the
    /// whole trailing run of detected reps when one existed, and a single rep
    /// otherwise. Same icon, same tap, sometimes removing one rep and sometimes
    /// fourteen. Predictability matters more here than efficiency: this is the
    /// control an athlete reaches for when something is already wrong.
    ///
    /// The bulk strike still exists, behind a long press and a dialog that names
    /// the count (see `showBulkUndoConfirmation`).
    private func undo() {
        guard tracker.totalRepsLogged > 0 else { return }
        tracker.undoLastRep()
        HapticSignal.repUndone.play()
    }

    private func undoTrailingDetected() {
        let removed = tracker.undoTrailingDetectedReps()
        if removed > 0 { HapticSignal.repUndone.play() }
    }

    /// The crown's bound value is a `Double` that SwiftUI moves in `by:` steps,
    /// and `onChange` can coalesce several steps into one call. Tracking an
    /// integer baseline makes each callback report exactly the steps since the
    /// last one, and clamping bounds the damage if the platform ever hands over a
    /// wild value.
    private func handleCrown(_ newValue: Double) {
        let position = Int(newValue.rounded())
        let rawDelta = position - crownBaseline
        guard rawDelta != 0 else { return }
        crownBaseline = position

        let delta = max(-Self.maxRepsPerCrownGesture, min(Self.maxRepsPerCrownGesture, rawDelta))
        if delta > 0 {
            RepLogging.logAsserted(delta, source: .crown, into: tracker)
        } else {
            for _ in 0..<(-delta) { tracker.undoLastRep() }
            HapticSignal.repLogged.play()
        }
    }

    private func togglePause() {
        switch timerEngine.phase {
        case .running:
            let now = Date()
            timerEngine.pause(at: now)
            pausedAt = now
            sessionManager.pause()
            // Stop sensing while paused, so walking to the water fountain cannot
            // log reps.
            repSensor.pause()
        case .paused:
            timerEngine.resume()
            pausedAt = nil
            restReference = Date()
            activityState = .working
            sessionManager.resume()
            if isAutoCountEnabled { repSensor.resume(movement: tracker.currentMovement) }
        default:
            break
        }
    }

    private func finish() {
        guard timerEngine.phase == .running || timerEngine.phase == .paused else { return }
        timerEngine.finish()
        repSensor.stop()
        HapticSignal.sessionFinished.play()
        onFinish()
    }

    // MARK: - Background loops

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
            case .paused, .idle:
                // Nothing to watch for while the clock is stopped, and background
                // CPU is the documented reason watchOS suspends a workout app —
                // so back off rather than spinning at 4 Hz for the length of a
                // rest break.
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Re-evaluates rest once a second, and keeps the sensor pointed at whichever
    /// movement is now current.
    ///
    /// Assigns only on an actual change, so a 20-minute workout costs a handful of
    /// view updates rather than 1,200 of them. The rest *clock* is not driven from
    /// here at all — `Text(timerInterval:countsDown: false)` renders that for free
    /// from the system.
    private func trackActivityState() async {
        while !Task.isCancelled {
            if timerEngine.phase == .running {
                now = .now

                // Whichever is later: the last rep, or the moment the clock
                // last started running. A rep logged before a five-minute pause
                // must not read as five minutes of rest the instant play resumes.
                let reference = max(tracker.lastRepAt ?? .distantPast, restReference)
                let next = RestDetection.state(
                    lastRepAt: reference,
                    sessionStartedAt: restReference,
                    now: .now
                )
                if next != activityState { activityState = next }
            }

            // Reconcile the HealthKit activity rather than fire-and-forget, so the
            // first segment is not lost to the workout session's asynchronous
            // start. Comparing against what HealthKit actually has open means a
            // missed open simply happens on the next tick.
            if timerEngine.phase == .running,
               sessionManager.currentActivityMovement != tracker.currentMovement {
                let boundary = Date()
                sessionManager.endCurrentMovementActivity(date: boundary)
                sessionManager.beginMovementActivity(
                    tracker.currentMovement,
                    round: tracker.completedRounds + 1,
                    date: boundary
                )
            }

            try? await Task.sleep(for: .seconds(1))
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

// MARK: - Previews
//
// The fastest way to work on this screen, and the only one that does not need a
// workout session: previews construct the engine and tracker directly, so the
// layout can be checked at every watch size without HealthKit or Core Motion.
//
// Always check the 40mm size first (Apple Watch SE 3 in the canvas device list).
// At 162 x 197 pt it is the smallest screen any watchOS 10+ device has, and this
// screen has no ScrollView any more — so content that does not fit is clipped
// silently rather than becoming reachable.

private func previewTracker(reps: Int, detected: Int) -> RoundRepTracker {
    let tracker = RoundRepTracker(variant: .rx)
    tracker.logReps(max(0, reps - detected), source: .manual)
    tracker.logDetectedReps(detected)
    return tracker
}

private func previewEngine() -> AmrapTimerEngine {
    let engine = AmrapTimerEngine(capSeconds: 1200)
    engine.start(at: Date().addingTimeInterval(-315))
    return engine
}

#Preview("Mid round, mixed provenance") {
    NavigationStack {
        ActiveWorkoutView(
            timerEngine: previewEngine(),
            tracker: previewTracker(reps: 47, detected: 6),
            sessionManager: WorkoutSessionManager(),
            repSensor: MotionRepSensor(),
            sessionStartedAt: Date().addingTimeInterval(-315),
            isAutoCountEnabled: true,
            onFinish: {}
        )
    }
}

/// The densest case: fifteen air-squat pips, the widest movement name, and a
/// three-digit score. If anything clips, it clips here first.
#Preview("Air squats, worst case") {
    NavigationStack {
        ActiveWorkoutView(
            timerEngine: previewEngine(),
            tracker: previewTracker(reps: 314, detected: 11),
            sessionManager: WorkoutSessionManager(),
            repSensor: MotionRepSensor(),
            sessionStartedAt: Date().addingTimeInterval(-900),
            isAutoCountEnabled: true,
            onFinish: {}
        )
    }
}

/// One rep short of the boundary — the state that has to teach "keep tapping
/// until it moves on" without any words.
#Preview("Awaiting the boundary tap") {
    NavigationStack {
        ActiveWorkoutView(
            timerEngine: previewEngine(),
            tracker: previewTracker(reps: 4, detected: 4),
            sessionManager: WorkoutSessionManager(),
            repSensor: MotionRepSensor(),
            sessionStartedAt: Date().addingTimeInterval(-20),
            isAutoCountEnabled: true,
            onFinish: {}
        )
    }
}

#Preview("Auto-count off") {
    NavigationStack {
        ActiveWorkoutView(
            timerEngine: previewEngine(),
            tracker: previewTracker(reps: 22, detected: 0),
            sessionManager: WorkoutSessionManager(),
            repSensor: MotionRepSensor(),
            sessionStartedAt: Date().addingTimeInterval(-315),
            isAutoCountEnabled: false,
            onFinish: {}
        )
    }
}
