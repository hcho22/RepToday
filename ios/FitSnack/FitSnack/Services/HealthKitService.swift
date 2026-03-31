import HealthKit

final class HealthKitService: HealthKitServiceProtocol {
    private let store = HKHealthStore()

    var isAuthorized: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
        ]

        try await store.requestAuthorization(toShare: typesToWrite, read: typesToRead)
    }

    func writeWorkout(duration: TimeInterval, calories: Double, startDate: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let endDate = startDate.addingTimeInterval(duration)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: startDate)

        let energySample = HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            start: startDate,
            end: endDate
        )
        try await builder.addSamples([energySample])
        try await builder.endCollection(at: endDate)
        try await builder.finishWorkout()
    }
}
