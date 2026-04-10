import Foundation

protocol NotificationServiceProtocol {
    func requestPermission() async throws -> Bool
    func scheduleDailyReminder(at hour: Int, minute: Int) async throws
    func schedulePersonalizedReminder(basedOnHistory workoutTimes: [Date]) async throws
    func scheduleStreakAtRiskNotification() async throws
    func scheduleStreakSaverCheck() async throws
    func cancelAll()
}
