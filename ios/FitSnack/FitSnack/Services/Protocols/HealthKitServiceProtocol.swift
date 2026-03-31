import Foundation

protocol HealthKitServiceProtocol {
    func requestAuthorization() async throws
    func writeWorkout(duration: TimeInterval, calories: Double, startDate: Date) async throws
    var isAuthorized: Bool { get }
}
