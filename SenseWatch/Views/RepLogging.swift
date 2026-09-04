import Foundation
import SenseKit

/// The single place a repetition becomes a repetition on the Watch.
///
/// Before automatic detection, the confirmation haptic lived inside the rep
/// button's own private `logRep()`, which meant every new input path had to
/// remember to reproduce it. That is exactly the shape of bug that ships: a
/// detected rep would silently move the athlete from pull-ups to push-ups with no
/// haptic at all, which is the "silent auto-advance" the plan rules out — not
/// because anyone decided to allow it, but because the confirmation was somewhere
/// else.
///
/// So every input — button, crown, detector — routes through here, and the
/// haptic policy is written once.
@MainActor
enum RepLogging {
    /// Logs reps the athlete asserted. Never gated: a tap or a crown detent is
    /// ground truth and is always allowed to close a movement or a round.
    static func logAsserted(_ count: Int = 1, source: RepSource, into tracker: RoundRepTracker) {
        guard count > 0 else { return }
        let before = Snapshot(tracker)
        tracker.logReps(count, source: source)
        announce(tracker, since: before, source: source)
    }

    /// Offers reps the detector found. Returns how many were accepted.
    ///
    /// The tracker clamps this to stop one short of the movement boundary, so
    /// this call can never advance the sequence — see
    /// ``RoundRepTracker/detectedRepAllowance``.
    @discardableResult
    static func logDetected(_ count: Int, into tracker: RoundRepTracker) -> Int {
        let before = Snapshot(tracker)
        let accepted = tracker.logDetectedReps(count)
        guard accepted > 0 else { return 0 }
        announce(tracker, since: before, source: .detected)
        return accepted
    }

    private struct Snapshot {
        let rounds: Int
        let stepIndex: Int

        init(_ tracker: RoundRepTracker) {
            rounds = tracker.completedRounds
            stepIndex = tracker.currentStepIndex
        }
    }

    /// One haptic per gesture, not per rep — a crown flick that logs three reps
    /// is one action and should feel like one.
    ///
    /// Priority runs from the most consequential event down: a round closing
    /// outranks a movement changing, which outranks an individual rep. The
    /// movement-change signal fires whatever caused it, because a movement
    /// changing under an athlete who did not expect it is precisely the moment
    /// they most need to feel something.
    private static func announce(_ tracker: RoundRepTracker, since before: Snapshot, source: RepSource) {
        if tracker.completedRounds > before.rounds {
            HapticSignal.roundCompleted.play()
        } else if tracker.currentStepIndex != before.stepIndex {
            HapticSignal.movementChanged.play()
        } else if source == .detected {
            HapticSignal.repDetected.play()
        } else {
            HapticSignal.repLogged.play()
        }
    }
}
