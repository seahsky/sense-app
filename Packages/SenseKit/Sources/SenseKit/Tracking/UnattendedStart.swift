import Foundation

/// A complication is a permanent one-tap trigger sitting on a wrist, so it will
/// sometimes fire when the athlete brushes a doorframe or reaches into a bag.
/// These two rules are the escape hatch, and they exist as pure functions so the
/// thing that decides what reaches HealthKit is unit-tested rather than buried in
/// `ContentView`.
///
/// Both are scoped to ``StartTrigger/complication``. An attempt begun on the Start
/// button had the athlete's eyes on it, so it is never torn down behind their
/// back, however empty it is.
///
/// Both ask ``RoundRepTracker/hasAssertedARep`` rather than
/// ``RoundRepTracker/totalRepsLogged``, and the difference is the whole reason that
/// flag exists. A count answers "what is the score"; these rules are asking "was
/// anybody here", and only one of those two survives an undo. An athlete who logs
/// three reps, rolls the Digital Crown back to correct a miscount and then presses
/// End is back at a count of zero while having demonstrably noticed their watch —
/// and tearing that attempt down without a Summary is precisely the teardown these
/// rules exist to avoid.
public enum UnattendedStart {
    /// How long a complication-started attempt may run with nothing asserted before
    /// the app ends it by itself.
    ///
    /// Two minutes, not thirty seconds. `RoundRepTracker.detectedRepAllowance`
    /// refuses to open a movement block until the athlete asserts a rep, so an
    /// untouched attempt means nothing has been tapped at all — and a real Cindy
    /// round is roughly 60-70 seconds, so two silent minutes is not a session
    /// anybody is doing. The window is generous on purpose: killing a real attempt
    /// is worse than a stray sample in Health.
    public static let abandonAfter: TimeInterval = 120

    /// Whether an attempt nobody has touched should end itself now.
    ///
    /// Every mis-tap rule that only fires when the athlete presses End misses the
    /// case that matters most — the tap they never noticed, which otherwise runs a
    /// full silent 20:00 and lands on the Summary screen hours later.
    ///
    /// - Parameters:
    ///   - trigger: which affordance began the attempt.
    ///   - elapsed: seconds since the clock started, from `AmrapTimerEngine.elapsed`.
    ///   - hasAssertedARep: `RoundRepTracker.hasAssertedARep`.
    public static func shouldAbandonUnattended(
        trigger: StartTrigger,
        elapsed: TimeInterval,
        hasAssertedARep: Bool
    ) -> Bool {
        trigger == .complication && !hasAssertedARep && elapsed >= abandonAfter
    }

    /// Whether an attempt the athlete has just ended should be discarded instead of
    /// carried to the Summary screen.
    ///
    /// A complication-started attempt the athlete never touched scores `0+0`.
    /// Routing that to Summary asks them to confirm a teardown of something they
    /// did not start; discarding it returns them to the Start screen, which is the
    /// feedback.
    ///
    /// - Parameters:
    ///   - trigger: which affordance began the attempt.
    ///   - hasAssertedARep: `RoundRepTracker.hasAssertedARep`.
    public static func shouldDiscardOnEnd(trigger: StartTrigger, hasAssertedARep: Bool) -> Bool {
        trigger == .complication && !hasAssertedARep
    }
}
