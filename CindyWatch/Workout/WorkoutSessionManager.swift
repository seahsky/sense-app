import Foundation
import HealthKit
import Observation

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

        var configuration = HKWorkoutConfiguration()
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

        let startDate = Date()
        session.startActivity(with: startDate)
        builder.beginCollection(withStart: startDate) { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async {
                self?.isActive = true
            }
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Runs the spec's exact stop/finalize chain and, once the session has fully
    /// ended, hands back `(averageHeartRate, activeEnergyBurned)`. If no session
    /// was ever started, calls back immediately with `(nil, nil)`.
    func finish(completion: @escaping (Double?, Double?) -> Void) {
        guard let session else {
            completion(nil, nil)
            return
        }
        finishCompletion = completion
        session.stopActivity(with: Date())
    }

    private func completeFinish() {
        isActive = false
        let averageHeartRate = heartRateSamples.isEmpty
            ? nil
            : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        finishCompletion?(averageHeartRate, activeEnergyBurned)
        finishCompletion = nil
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
