import Foundation

/// Whether the athlete is currently working through a movement or resting.
public enum WorkoutActivityState: Equatable, Sendable {
    case working
    case resting(since: Date)

    public var isResting: Bool {
        if case .resting = self { return true }
        return false
    }

    public func restDuration(at now: Date) -> TimeInterval? {
        guard case .resting(let since) = self else { return nil }
        return max(0, now.timeIntervalSince(since))
    }
}

/// Rest detection, done without touching a sensor.
///
/// Apple's two built-in candidates are both wrong for this. Workout auto-pause
/// (`HKWorkoutEventType.motionPaused`) is documented only for running workouts.
/// `CMMotionActivityManager`'s stationary state is a battery-optimized
/// daily-activity classifier whose transition latency Apple has never published
/// for the stationary case, for watchOS, or anywhere in the SDK headers — so
/// there is literally nothing to tune a set-gap threshold against.
///
/// Cindy needs neither, because every repetition here is already a discrete,
/// timestamped event rather than a noisy inference. Rest reduces to arithmetic
/// on ``RoundRepTracker/lastRepAt``: no sensor, no variance threshold, no false
/// positives from sensor noise. This is also how the shipped ML-based competitor
/// operationalizes it — Train Fitness/Motra's docs say rest starts "when a set is
/// detected as finished", i.e. time-since-last-confirmed-event, not a separately
/// trained resting-motion class.
///
/// The one gap it cannot close: an athlete genuinely still repping but not
/// logging will be called resting. That is a fair trade for having no false
/// positives from the sensor side, and automatic rep detection narrows it
/// further by removing most of the reason to stop logging.
public enum RestDetection {
    /// How long without a repetition before the athlete counts as resting.
    ///
    /// Chosen from the shape of the problem rather than from research, and the
    /// research notes say so explicitly: the real value has to come from tuning
    /// against fatigued attempts. It trades early rest indication against
    /// flagging a brief mid-set pause — shaking out forearms between pull-ups —
    /// as a real break. 12 s sits at the middle of the 8–15 s range the notes
    /// suggest.
    public static let defaultThreshold: TimeInterval = 12

    /// - Parameters:
    ///   - lastRepAt: when the most recent repetition was logged, if any.
    ///   - sessionStartedAt: fallback reference before the first repetition, so an
    ///     athlete who starts the clock and then stands still is correctly called
    ///     resting rather than indefinitely "working".
    ///   - now: the instant being evaluated.
    ///   - threshold: seconds of silence that constitute rest.
    public static func state(
        lastRepAt: Date?,
        sessionStartedAt: Date,
        now: Date,
        threshold: TimeInterval = defaultThreshold
    ) -> WorkoutActivityState {
        let reference = lastRepAt ?? sessionStartedAt
        let silence = now.timeIntervalSince(reference)
        guard silence >= threshold else { return .working }
        return .resting(since: reference)
    }
}
