import Foundation

public extension Movement {
    /// Plausible fastest and slowest time for one repetition of this movement.
    ///
    /// **These are starting points, not measurements.** RecoFit sets its
    /// equivalent constants from knowledge of the movement ("it is nearly
    /// impossible for a situp to take less than 0.75s or more than 4s") and the
    /// research notes are explicit that real values only mean something when
    /// tuned against fatigued attempts, not fresh-form test data. Treat every
    /// number here as a hypothesis to be replaced by measurement.
    ///
    /// The brackets are wide on purpose. Cindy is a 20-minute AMRAP: round 1
    /// pull-ups are fast and crisp, round 15 pull-ups are slow, kipping, and
    /// ragged. A tight bracket fitted to fresh reps stops counting exactly when
    /// the athlete most needs it to keep counting.
    ///
    /// The `activityFloor` values are set an order of magnitude above resting
    /// accelerometer noise (~0.005 G RMS) and an order of magnitude below the
    /// excursion any real repetition produces, so there is room to be wrong in
    /// either direction. The push-up floor is the lowest of the three because a
    /// push-up genuinely moves the wrist least — the signal there is the gravity
    /// vector tilting, not the wrist travelling.
    var repCountingProfile: RepCountingProfile {
        switch self {
        case .pullUp:
            // The cleanest signal of the three — a large, controlled vertical arm
            // excursion against gravity. The wide upper bound covers a fatigued
            // athlete hanging between reps.
            return RepCountingProfile(minPeriod: 0.8, maxPeriod: 4.0, activityFloor: 0.030)

        case .pushUp:
            // The weakest signal physically: a push-up barely translates a
            // wrist-worn sensor, so what the accelerometer sees is mostly the
            // gravity vector tilting. That is exactly why the pipeline projects
            // onto the first principal component instead of using vector
            // magnitude, which would be near-flat here.
            return RepCountingProfile(minPeriod: 0.6, maxPeriod: 3.0, activityFloor: 0.020)

        case .airSquat:
            // Empirically the worst counter of all ten movements Soro et al.
            // tested (MAE 1.82, 79.5% within +/-1), despite an unremarkable
            // signal — because each rep produces two acceleration bursts, one
            // down and one up, and RecoFit's Figure 2b shows the resulting
            // "double peak". `minPeriod` is what collapses that pair into one
            // count, so it is load-bearing here in a way it is not elsewhere.
            return RepCountingProfile(minPeriod: 0.7, maxPeriod: 3.0, activityFloor: 0.025)
        }
    }
}
