import Foundation

public enum TrendAnalytics {
    /// Best session by (completedRounds, partialReps) within the same variant only —
    /// scores across different variants (Rx vs Baby Cindy) are not comparable.
    public static func personalRecord(among sessions: [CindySession], variant: CindyVariant) -> CindySession? {
        sessions
            .filter { $0.variant == variant }
            .max()
    }

    /// Works whether or not `sessions` already contains `session` itself: comparing
    /// with `>=` against the max of the filtered set is correct either way (a
    /// session ties itself), so callers don't need to know if the array was
    /// snapshotted before or after inserting the session being checked.
    public static func isPersonalRecord(_ session: CindySession, among sessions: [CindySession]) -> Bool {
        guard let pr = personalRecord(among: sessions, variant: session.variant) else { return true }
        return session >= pr
    }

    public static func averagePaceSecondsPerRound(for session: CindySession) -> TimeInterval? {
        guard session.completedRounds > 0 else { return nil }
        return session.durationSeconds / Double(session.completedRounds)
    }

    /// Simple linear projection from current pace — "AMRAP math" from the research
    /// (project final rounds from elapsed time and rounds so far). Deliberately
    /// ignores partial reps within the current round: it projects whole rounds only,
    /// matching the spec's `completedRounds`-only signature.
    public static func projectedFinalRounds(
        elapsedSeconds: TimeInterval,
        capSeconds: TimeInterval,
        completedRounds: Int
    ) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        let roundsPerSecond = Double(completedRounds) / elapsedSeconds
        return roundsPerSecond * capSeconds
    }
}

extension CindySession: Comparable {
    // `@Model` classes don't get automatic `Equatable` synthesis (unlike structs),
    // and `Comparable` requires it — identity (by `id`, the `@Attribute(.unique)`
    // primary key) is the correct notion of equality for a model entity, distinct
    // from `<`'s score-based ordering below.
    public static func == (lhs: CindySession, rhs: CindySession) -> Bool {
        lhs.id == rhs.id
    }

    public static func < (lhs: CindySession, rhs: CindySession) -> Bool {
        (lhs.completedRounds, lhs.partialReps) < (rhs.completedRounds, rhs.partialReps)
    }
}
