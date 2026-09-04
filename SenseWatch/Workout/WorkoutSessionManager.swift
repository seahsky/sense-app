import Foundation
import HealthKit
import Observation
import SenseKit

/// Owns the `HKWorkoutSession`/`HKLiveWorkoutBuilder` lifecycle for a single Cindy
/// attempt, using the architecture spec's exact configuration and stop/finalize
/// sequence:
///
///   `session.startActivity(with:)` + `builder.beginCollection(withStart:)` to start;
///   `session.stopActivity(with:)` -> `.stopped` delegate callback ->
///   `builder.endCollection(withEnd:completion:)` -> `builder.finishWorkout(completion:)`
///   -> `session.end()` -> `.ended` delegate callback to stop and finalize.
///
/// Heart rate has no HealthKit-side "average" query in this pipeline: every sample
/// observed via `HKLiveWorkoutBuilderDelegate.workoutBuilder(_:didCollectDataOf:)`
/// is appended to `heartRateSamples`, and the mean of that array — computed
/// app-side — is what `finish(completion:)` hands back as the average heart rate.
/// Active energy is read once at the end as `HKStatistics.sumQuantity()`.
@Observable
final class WorkoutSessionManager: NSObject {
    enum WorkoutError: Error {
        case healthDataUnavailable
    }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var finishCompletion: ((Double?, Double?) -> Void)?

    private(set) var isActive = false

    /// Set when the workout started but HealthKit refused to begin collecting.
    /// The AMRAP itself still works — this only means no heart rate, no energy,
    /// and no per-movement activities.
    private(set) var startupError: String?
    private(set) var currentHeartRate: Double?
    private(set) var activeEnergyBurned: Double?
    private(set) var heartRateSamples: [Double] = []

    /// Starts the workout session/builder pair per the spec's HealthKit
    /// configuration block: `.crossTraining` activity type (best fit for Cindy's
    /// mixed bodyweight circuit), `.indoor` location type.
    func start(
        activityType: HKWorkoutActivityType = .crossTraining,
        locationType: HKWorkoutSessionLocationType = .indoor
    ) throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutError.healthDataUnavailable
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder
        heartRateSamples = []
        currentHeartRate = nil
        activeEnergyBurned = nil
        startupError = nil

        let startDate = Date()
        session.startActivity(with: startDate)
        builder.beginCollection(withStart: startDate) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.isActive = true
                } else {
                    // Swallowing this used to leave the app in a half-started
                    // state: a workout that looks like it is running, with
                    // `isActive` false, so every per-movement activity silently
                    // no-ops for the whole session and nothing says why.
                    self.startupError = error?.localizedDescription
                        ?? "HealthKit didn't start collecting workout data."
                }
            }
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    // MARK: - Per-movement activities

    /// Records the movement the athlete is now on as an `HKWorkoutActivity` inside
    /// the workout.
    ///
    /// HealthKit has no API that can *detect* a pull-up, but it has had first-class
    /// APIs for *recording* sub-activities since watchOS 9, and SENSE already knows
    /// its movement boundaries deterministically from `RoundRepTracker` — no
    /// sensors, no inference, no new failure mode. Apple documents this exact
    /// shape: "you can divide interval training into active and rest periods…
    /// you may want to add custom metadata to indicate whether the activity is an
    /// active or resting interval."
    ///
    /// The result is per-movement timing plus per-movement heart-rate and energy
    /// statistics in the saved workout, which this app previously threw away.
    ///
    /// `HKWorkoutActivityType` has 84 cases and none of them is a pull-up, a
    /// push-up, or an air squat, so movement identity lives in metadata — whose
    /// values must be `NSString`, `NSNumber`, or `NSDate`.
    /// The movement whose activity is currently open, or `nil` if none is.
    ///
    /// Exposed so the caller can reconcile rather than fire-and-forget. `isActive`
    /// only becomes true once `beginCollection` reports back asynchronously, so an
    /// activity opened the instant the view appears can silently no-op; a caller
    /// that compares this against the movement it wants will simply open one on
    /// its next tick instead of losing the first segment of the workout.
    private(set) var currentActivityMovement: Movement?

    func beginMovementActivity(_ movement: Movement, round: Int, date: Date = Date()) {
        guard let session, isActive else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        session.beginNewActivity(
            configuration: configuration,
            date: date,
            metadata: [
                Self.movementMetadataKey: movement.rawValue,
                Self.movementNameMetadataKey: movement.displayName,
                Self.roundMetadataKey: NSNumber(value: round)
            ]
        )
        currentActivityMovement = movement
    }

    func endCurrentMovementActivity(date: Date = Date()) {
        // `currentActivity` returns the workout's own primary activity when no
        // sub-activity is open, and ending that would end the workout — so check
        // for the sub-activity's configuration rather than assuming one is open.
        guard let session, session.currentActivity.workoutConfiguration.activityType == .functionalStrengthTraining else { return }
        session.endCurrentActivity(on: date)
        currentActivityMovement = nil
    }

    static let movementMetadataKey = "com.senseapp.movement"
    static let movementNameMetadataKey = "com.senseapp.movementName"
    static let roundMetadataKey = "com.senseapp.round"

    /// Runs the spec's exact stop/finalize chain and, once the session has fully
    /// ended, hands back `(averageHeartRate, activeEnergyBurned)`. If no session
    /// was ever started, calls back immediately with `(nil, nil)`.
    func finish(completion: @escaping (Double?, Double?) -> Void) {
        guard let session else {
            completion(nil, nil)
            return
        }
        finishCompletion = completion
        // Close any open per-movement activity first: an activity left open when
        // the session stops has no end date, and HealthKit would either drop it
        // or clamp it to the workout end, losing the final movement's timing.
        let now = Date()
        endCurrentMovementActivity(date: now)
        session.stopActivity(with: now)

        // The completion is what advances the UI to the Summary screen, and the
        // only things that call it are the `.ended` delegate transition and
        // `didFailWithError`. If HealthKit delivers neither — and it is a
        // multi-step asynchronous chain across an XPC boundary — the athlete is
        // stranded on the Active screen with a finished workout and no way
        // forward. Better a summary missing its heart-rate average than a lost
        // session.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishTimeout) { [weak self] in
            guard let self, self.finishCompletion != nil else { return }
            self.completeFinish()
        }
    }

    /// Generous: the normal chain is stopActivity → endCollection → finishWorkout
    /// → end, and finishWorkout writes to the HealthKit store.
    private static let finishTimeout: TimeInterval = 10

    private func completeFinish() {
        // Idempotent: the timeout above and the `.ended` delegate callback can
        // both arrive, and the second one must do nothing.
        guard let completion = finishCompletion else { return }
        finishCompletion = nil
        isActive = false
        currentActivityMovement = nil
        let averageHeartRate = heartRateSamples.isEmpty
            ? nil
            : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        completion(averageHeartRate, activeEnergyBurned)
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        switch toState {
        case .stopped:
            builder?.endCollection(withEnd: date) { [weak self] _, _ in
                guard let self else { return }
                self.builder?.finishWorkout { [weak self] _, _ in
                    self?.session?.end()
                }
            }
        case .ended:
            DispatchQueue.main.async { [weak self] in
                self?.completeFinish()
            }
        default:
            break
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.completeFinish()
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard
                let quantityType = type as? HKQuantityType,
                let statistics = workoutBuilder.statistics(for: quantityType)
            else { continue }

            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                guard let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) else { continue }
                DispatchQueue.main.async { [weak self] in
                    self?.currentHeartRate = value
                    self?.heartRateSamples.append(value)
                }

            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                guard let sum = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) else { continue }
                DispatchQueue.main.async { [weak self] in
                    self?.activeEnergyBurned = sum
                }

            default:
                break
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
