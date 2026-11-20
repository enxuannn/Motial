import Foundation
import HealthKit

/// Optional: saves each completed session to Apple Health as a workout (Functional Strength Training),
/// so rehab shows up in the person's Activity history alongside everything else. Nothing is read.
@MainActor
enum HealthSync {
    private static let store = HKHealthStore()

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAccess() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        } catch { return false }
    }

    static func save(_ s: SessionRecord) async {
        guard available, store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let end = s.date.addingTimeInterval(max(60, s.duration))
        do {
            try await builder.beginCollection(at: s.date)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Motial ankle rehab"])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Health is optional; a failed save never affects the session record in Steady.
        }
    }
}
