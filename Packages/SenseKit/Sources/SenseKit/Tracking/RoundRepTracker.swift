import Foundation
import Observation

/// Tracks progress through a variant's fixed movement sequence and derives the
/// official rounds+reps score from it.
///
/// Internally this keeps a single source of truth — the ordered list of logged
/// repetitions — and derives `completedRounds`/`currentStepIndex`/`repsInCurrentMovement`
/// from its count on every change. That makes `logRep()`/`undoLastRep()` trivially correct
/// (undo can never desync from a hand-rolled inverse of the forward state machine)
/// at the cost of an O(movementSequence.count) walk per call, which is negligible
/// against a 3-step sequence tapped a few hundred times over a 20-minute AMRAP.
///
/// The list replaced a bare `Int` when automatic rep detection landed. Two things
/// need more than a count: rest detection needs the timestamp of the most recent
/// rep, and correction needs to know which reps the app inferred rather than the
/// athlete asserting. Both are properties of individual repetitions, so they live
/// on individual repetitions.
@Observable
public final class RoundRepTracker {
    public let variant: CindyVariant

    public private(set) var completedRounds: Int = 0
    public private(set) var currentStepIndex: Int = 0
    public private(set) var repsInCurrentMovement: Int = 0

    /// Every repetition logged this attempt, oldest first.
    public private(set) var events: [RepEvent] = []

    public init(variant: CindyVariant) {
        self.variant = variant
    }

    /// Logs one repetition.
    ///
    /// The single shared mutator: the "+1 REP" button, the Digital Crown, and the
    /// motion detector all land here, so the score can never depend on which
    /// input produced it.
    public func logRep(at date: Date = .now, source: RepSource = .manual) {
        events.append(RepEvent(date: date, source: source))
        recompute()
    }

    /// Logs `count` repetitions at the same instant.
    ///
    /// Exists so a burst from one input cannot be mistaken for a burst of
    /// separate athlete actions, and so a single detector tick that resolves more
    /// than one repetition is recorded as such.
    public func logReps(_ count: Int, at date: Date = .now, source: RepSource = .manual) {
        guard count > 0 else { return }
        events.append(contentsOf: (0..<count).map { _ in RepEvent(date: date, source: source) })
        recompute()
    }

    public func undoLastRep() {
        guard !events.isEmpty else { return }
        events.removeLast()
        recompute()
    }

    /// Removes the most recent repetitions the app inferred, leaving anything the
    /// athlete asserted alone.
    ///
    /// This is the correction the accuracy data demands: when the counter runs
    /// away mid-set, the athlete needs to strike its guesses without also
    /// destroying the reps they logged by hand. Only a trailing run is removed —
    /// reaching back past a manual rep would silently rewrite history the athlete
    /// already confirmed.
    @discardableResult
    public func undoTrailingDetectedReps() -> Int {
        var removed = 0
        while let last = events.last, last.source == .detected {
            events.removeLast()
            removed += 1
        }
        if removed > 0 { recompute() }
        return removed
    }

    public func reset() {
        events.removeAll()
        recompute()
    }

    // MARK: - Automatic detection

    /// How many detected repetitions may be committed right now.
    ///
    /// Always one short of closing the movement. This single expression is the
    /// whole of "never a silent auto-advance": the detector can do the bulk of a
    /// set — four of five pull-ups, nine of ten push-ups, fourteen of fifteen air
    /// squats — but the rep that moves the sequence on always comes from the
    /// athlete.
    ///
    /// The reason to gate exactly here, rather than to propose reps and have the
    /// athlete confirm them, is what the published accuracy data actually says.
    /// A counter that is right 54-65% of the time on exact count means the
    /// athlete cannot audit *how many* without counting in their head — which is
    /// the entire labour the feature exists to remove. But they always know
    /// whether they have *finished*. So the app asks the question they can
    /// answer, once per movement, using the same tap they already know: keep
    /// tapping until it moves on.
    ///
    /// It also costs nothing structurally. Nothing is parked outside `events`,
    /// no second source of truth appears, and `recompute()` is untouched — so the
    /// score stays derivable from the event list alone.
    public var detectedRepAllowance: Int {
        // The detector may not OPEN a movement block either, and the reason is
        // measured. A block opens on the athlete's boundary tap, while they are
        // still dropping off the bar or walking to the floor, and at that instant
        // the allowance is at its widest — 4, 9 and 14. Every phantom-rep source
        // the audit found discharges into exactly that window: the engine's
        // watermark reset, the sensor batch that straddles the tap, and the
        // band-pass priming transient. Requiring one asserted rep to open the
        // block closes all three at once, for all three movements, with no
        // threshold to tune and no signal processing involved.
        //
        // It is also the only defence that reaches the air squat. Two of Cindy's
        // three movements anchor the wrist to something fixed, so their posture is
        // recognisable; the squat's hand is free and reads the same as walking.
        // See docs/research/posture-aware-rep-detection.md.
        //
        // The cost is one extra tap per movement, which is the interaction the
        // athlete already knows: keep tapping until it moves on. That is a
        // visible, bounded price. The alternative defences all fail silently.
        guard hasAssertedRepInCurrentMovement else { return 0 }
        return max(0, repsRemainingInCurrentMovement - 1)
    }

    /// True once the athlete has asserted at least one repetition of the movement
    /// now in progress.
    ///
    /// Derived from `events` on every read rather than cached. A cached flag would
    /// be a second source of truth that `undoLastRep`, the bulk undo and `reset`
    /// would each have to keep in step, which is the class of bug this type's
    /// derived-state design exists to prevent.
    public var hasAssertedRepInCurrentMovement: Bool {
        currentMovementEvents.contains { $0.source.isUserConfirmed }
    }

    /// True when the movement is one repetition from advancing, and that
    /// repetition has to come from the athlete.
    public var isAwaitingBoundaryRep: Bool {
        repsRemainingInCurrentMovement == 1
    }

    /// Commits up to `count` detected repetitions, stopping short of the movement
    /// boundary, and reports how many were actually taken.
    ///
    /// Detected reps beyond the allowance are dropped rather than queued. Queuing
    /// would mean the athlete's boundary tap released a burst of the detector's
    /// older guesses, which is the silent auto-advance in a different costume.
    @discardableResult
    public func logDetectedReps(_ count: Int, at date: Date = .now) -> Int {
        let allowed = min(count, detectedRepAllowance)
        guard allowed > 0 else { return 0 }
        logReps(allowed, at: date, source: .detected)
        return allowed
    }

    /// The share of this attempt's repetitions the app inferred, 0...1.
    ///
    /// Surfaced on the summary. For a feature whose real-world accuracy is
    /// unproven, one honest number per session is how an athlete decides across
    /// sessions whether to keep trusting it.
    public var detectedRepFraction: Double {
        guard !events.isEmpty else { return 0 }
        return Double(events.filter { $0.source == .detected }.count) / Double(events.count)
    }

    /// When the most recent repetition was logged, or `nil` if none has been.
    /// The whole of rest detection rests on this one value.
    public var lastRepAt: Date? { events.last?.date }

    public var totalRepsLogged: Int { events.count }

    public var currentMovement: Movement {
        let sequence = variant.movementSequence
        guard sequence.indices.contains(currentStepIndex) else { return .airSquat }
        return sequence[currentStepIndex].movement
    }

    /// Reps still owed on the current movement before the sequence advances.
    public var repsRemainingInCurrentMovement: Int {
        let sequence = variant.movementSequence
        guard sequence.indices.contains(currentStepIndex) else { return 0 }
        return max(0, sequence[currentStepIndex].reps - repsInCurrentMovement)
    }

    /// The repetitions logged so far in the movement now in progress, oldest first.
    ///
    /// The slice, not a copy, because every caller here only counts or maps it.
    public var currentMovementEvents: ArraySlice<RepEvent> {
        guard repsInCurrentMovement > 0 else { return [] }
        let start = events.count - repsInCurrentMovement
        guard start >= 0, start <= events.count else { return [] }
        return events[start...]
    }

    /// Where each repetition of the current movement came from, oldest first.
    ///
    /// The pip row renders from this rather than from a count, because a count
    /// cannot say *which* pip was the watch's opinion. Rendering "n asserted then
    /// m detected" from two integers silently relabels any detected rep that is
    /// not part of the trailing run as the athlete's own, which is the one thing
    /// ``RepPipRow`` exists to prevent.
    public var currentMovementRepSources: [RepSource] {
        currentMovementEvents.map(\.source)
    }

    /// How many repetitions of the current movement the app inferred.
    public var detectedRepCountInCurrentMovement: Int {
        currentMovementEvents.filter { $0.source == .detected }.count
    }

    /// Removes every repetition the app inferred in the movement now in progress,
    /// keeping everything the athlete asserted.
    ///
    /// This is the correction the accuracy data demands, and it is deliberately
    /// wider than ``undoTrailingDetectedReps()``. That one stops at the first
    /// asserted rep, so an athlete who taps once to correct a runaway counter
    /// breaks the trailing run and cements every phantom before it for the rest of
    /// the attempt. Scoping to the current movement instead means the undo can
    /// reach past an asserted rep, but never past the boundary the athlete
    /// themselves closed — so it can clean up the block in progress and can never
    /// rewrite a movement they already finished.
    @discardableResult
    public func undoDetectedRepsInCurrentMovement() -> Int {
        let current = currentMovementEvents
        guard !current.isEmpty else { return 0 }

        let kept = current.filter { $0.source.isUserConfirmed }
        let removed = current.count - kept.count
        guard removed > 0 else { return 0 }

        events.replaceSubrange(current.startIndex..<events.count, with: kept)
        recompute()
        return removed
    }

    /// How many of the trailing repetitions were inferred rather than asserted.
    /// Drives the "these ones were the app's idea" affordance in the UI.
    public var trailingDetectedRepCount: Int {
        var count = 0
        for event in events.reversed() {
            guard event.source == .detected else { break }
            count += 1
        }
        return count
    }

    public var partialReps: Int {
        events.count - completedRounds * variant.repsPerRound
    }

    public var scoreString: String {
        "\(completedRounds)+\(partialReps)"
    }

    private func recompute() {
        let sequence = variant.movementSequence
        let perRound = variant.repsPerRound

        guard !sequence.isEmpty, perRound > 0 else {
            completedRounds = 0
            currentStepIndex = 0
            repsInCurrentMovement = 0
            return
        }

        let total = events.count
        completedRounds = total / perRound
        var remainder = total % perRound

        var stepIndex = 0
        for (index, step) in sequence.enumerated() {
            if remainder < step.reps {
                stepIndex = index
                break
            }
            remainder -= step.reps
            stepIndex = index + 1
        }
        if stepIndex >= sequence.count {
            stepIndex = 0
        }

        currentStepIndex = stepIndex
        repsInCurrentMovement = remainder
    }
}
