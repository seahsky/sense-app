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
            // NOT "a large vertical arm excursion", which is what this comment
            // used to claim. The hand grips a bar that does not move, so the body
            // travels and the wrist does not: about 7.7 cm of arc about the bar
            // against the 40-60 cm the athlete's centre of mass covers. What the
            // watch sees is the forearm pivoting about a fixed hand — a gravity
            // *direction* sweep of roughly 35-50 degrees, beating linear
            // translation by about 20 to 1.
            //
            // The pull-up and the push-up are therefore the same case, not
            // opposite cases, and they are antipodal on the one axis this pipeline
            // discards: a pull-up keeps the hand above the elbow, a push-up below.
            // See docs/research/posture-aware-rep-detection.md.
            //
            // The wide upper bound covers a fatigued athlete hanging between reps.
            return RepCountingProfile(minPeriod: 0.8, maxPeriod: 4.0, activityFloor: 0.030)

        case .pushUp:
            // The same anchored case as the pull-up, mirrored. The palm is planted
            // on a floor that does not move, so the wrist is a near-fixed pivot
            // and the forearm sweeps about it: roughly 2.9 cm of arc and a gravity
            // direction sweep of about 33 degrees, again beating translation by
            // about 20 to 1.
            //
            // Weakest is the wrong word for it — it is weak in *translation*,
            // which is the channel the band-pass and PCA are built to read, and
            // strong in gravity direction, which they are built to discard. That
            // is why vector magnitude sees almost nothing here while projecting
            // onto the first principal component sees the swing.
            return RepCountingProfile(minPeriod: 0.6, maxPeriod: 3.0, activityFloor: 0.020)

        case .airSquat:
            // Empirically the worst counter of all ten movements Soro et al.
            // tested (MAE 1.82, 79.5% within +/-1), despite an unremarkable
            // signal — because each rep produces two acceleration bursts, one
            // down and one up, and RecoFit's Figure 2b shows the resulting
            // "double peak". `minPeriod` is what collapses that pair into one
            // count, so it is load-bearing here in a way it is not elsewhere.
            //
            // It is also the odd one out mechanically, and that is why it has no
            // posture defence. The hand is free, so no posture is required and
            // none is forbidden: an arms-hanging squat reads the same as walking,
            // and no accelerometer statistic separates them. The squat's only
            // protection is `detectedRepAllowance` refusing to open the block
            // without an asserted rep.
            return RepCountingProfile(minPeriod: 0.7, maxPeriod: 3.0, activityFloor: 0.025)
        }
    }
}
