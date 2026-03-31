import Foundation

protocol NotificationServiceProtocol {
    func requestPermission() async throws -> Bool
    func scheduleDailyReminder(at hour: Int, minute: Int) async throws
    func scheduleStreakAtRiskNotification() async throws
    func cancelAll()
}
