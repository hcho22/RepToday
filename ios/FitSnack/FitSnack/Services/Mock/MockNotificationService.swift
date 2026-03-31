import Foundation

final class MockNotificationService: NotificationServiceProtocol {
    func requestPermission() async throws -> Bool { true }
    func scheduleDailyReminder(at hour: Int, minute: Int) async throws {}
    func scheduleStreakAtRiskNotification() async throws {}
    func cancelAll() {}
}
