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
            HKQuantityType(.bodyMass),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
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

    // MARK: - HealthKit Read

    func readLatestWeight() async throws -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKQuantityType(.bodyMass)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    func readLatestHeartRate() async throws -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKQuantityType(.heartRate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let bpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            store.execute(query)
        }
    }

    func readAverageRestingHeartRate(days: Int) async throws -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKQuantityType(.restingHeartRate)
        let now = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let avg = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: avg)
            }
            store.execute(query)
        }
    }
}
