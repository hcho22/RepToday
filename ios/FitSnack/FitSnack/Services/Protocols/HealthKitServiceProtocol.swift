import Foundation

protocol HealthKitServiceProtocol {
    func requestAuthorization() async throws
    func writeWorkout(duration: TimeInterval, calories: Double, startDate: Date) async throws
    var isAuthorized: Bool { get }

    // Phase 2: HealthKit Read
    func readLatestWeight() async throws -> Double? // kg
    func readLatestHeartRate() async throws -> Double? // bpm
    func readAverageRestingHeartRate(days: Int) async throws -> Double? // bpm
}
