import Foundation
import HealthKit

/// Thin wrapper around `HKHealthStore.requestAuthorization(toShare:read:)` for the
/// two things SENSE needs on the watch: permission to save each attempt as an
/// `HKWorkout` (share), and permission to read heart rate / active energy so the
/// live workout builder can report stats during and after the session.
///
/// No `NSLocationWhenInUseUsageDescription` or Core Location permission is needed
/// anywhere in this app — `HKWorkoutSessionLocationType.indoor` (used when
/// configuring the workout session) is purely a HealthKit workout-classification
/// enum case, not a request for the device's actual location.
enum HealthKitAuthManager {
    enum AuthError: Error {
        case healthDataUnavailable
    }

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AuthError.healthDataUnavailable
        }

        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            throw AuthError.healthDataUnavailable
        }

        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            heartRateType,
            activeEnergyType
        ]

        let healthStore = HKHealthStore()
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }
}
