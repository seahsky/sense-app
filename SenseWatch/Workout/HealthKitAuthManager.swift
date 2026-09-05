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

    /// What the app asks permission to write. One type: the workout itself.
    private static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

    /// What the app asks permission to read.
    ///
    /// Hoisted out of ``requestAuthorization()`` so the request and
    /// ``needsAuthorizationPrompt()`` cannot ask about different type sets. A
    /// status query is only meaningful for the exact pair of sets that will be
    /// requested — query a narrower set and it answers `.unnecessary` for a
    /// permission the app has not actually got, which on the complication path
    /// would start a clock straight into the sheet the check exists to avoid.
    ///
    /// Computed rather than stored, and throwing rather than lenient: both
    /// quantity types come from failable `HKQuantityType.quantityType(forIdentifier:)`
    /// lookups, and a set silently missing one of them is exactly the silently
    /// wrong question above. The failure is the same one this file has always
    /// raised for a HealthKit that cannot answer at all.
    private static var readTypes: Set<HKObjectType> {
        get throws {
            guard
                let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
                let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            else {
                throw AuthError.healthDataUnavailable
            }

            return [
                HKObjectType.workoutType(),
                heartRateType,
                activeEnergyType
            ]
        }
    }

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AuthError.healthDataUnavailable
        }

        let readTypes = try Self.readTypes
        let healthStore = HKHealthStore()
        try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: readTypes)
    }

    /// Whether asking for authorization right now would put a modal in front of
    /// the athlete.
    ///
    /// `statusForAuthorizationRequest(toShare:read:)` (watchOS 5.0+) answers
    /// `.shouldRequest`, `.unnecessary` or `.unknown` without showing anything, so
    /// the complication path can decide *before* it starts a clock the athlete
    /// cannot see behind a sheet. Pressing Start has never needed this — the
    /// athlete is looking at the screen when the prompt appears — but a tap on a
    /// watch face skips that screen entirely.
    ///
    /// Returns false when Health is unavailable or the query throws, which reads
    /// as "go ahead and try". That is deliberate rather than optimistic: a broken
    /// HealthKit already fails loudly one step later at `sessionManager.start()`,
    /// and the existing catch in `ContentView.startWorkout` puts the reason on the
    /// Start screen. Answering true here would instead swallow a real fault into a
    /// tap that appears to do nothing.
    static func needsAuthorizationPrompt() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        do {
            let readTypes = try Self.readTypes
            let status = try await HKHealthStore()
                .statusForAuthorizationRequest(toShare: Self.shareTypes, read: readTypes)
            return status == .shouldRequest
        } catch {
            return false
        }
    }
}
