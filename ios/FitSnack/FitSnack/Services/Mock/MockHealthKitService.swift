import Foundation

final class MockHealthKitService: HealthKitServiceProtocol {
    var isAuthorized: Bool = false

    func requestAuthorization() async throws {
        isAuthorized = true
    }

    func writeWorkout(duration: TimeInterval, calories: Double, startDate: Date) async throws {
        // No-op in mock
    }

    func readLatestWeight() async throws -> Double? { nil }
    func readLatestHeartRate() async throws -> Double? { nil }
    func readAverageRestingHeartRate(days: Int) async throws -> Double? { nil }
}
