import Foundation
import Observation

/// Tracks progress through a variant's fixed movement sequence and derives the
/// official rounds+reps score from it.
///
/// Internally this keeps a single source of truth — the total rep count logged
/// so far — and derives `completedRounds`/`currentStepIndex`/`repsInCurrentMovement`
/// from it on every change. That makes `logRep()`/`undoLastRep()` trivially correct
/// (undo can never desync from a hand-rolled inverse of the forward state machine)
/// at the cost of an O(movementSequence.count) walk per call, which is negligible
/// against a 3-step sequence tapped a few hundred times over a 20-minute AMRAP.
@Observable
public final class RoundRepTracker {
    public let variant: CindyVariant

    public private(set) var completedRounds: Int = 0
    public private(set) var currentStepIndex: Int = 0
    public private(set) var repsInCurrentMovement: Int = 0

    private var totalRepsLogged: Int = 0

    public init(variant: CindyVariant) {
        self.variant = variant
    }

    public func logRep() {
        totalRepsLogged += 1
        recompute()
    }

    public func undoLastRep() {
        guard totalRepsLogged > 0 else { return }
        totalRepsLogged -= 1
        recompute()
    }

    public func reset() {
        totalRepsLogged = 0
        recompute()
    }

    public var currentMovement: Movement {
        let sequence = variant.movementSequence
        guard sequence.indices.contains(currentStepIndex) else { return .airSquat }
        return sequence[currentStepIndex].movement
    }

    public var partialReps: Int {
        totalRepsLogged - completedRounds * variant.repsPerRound
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

        completedRounds = totalRepsLogged / perRound
        var remainder = totalRepsLogged % perRound

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
