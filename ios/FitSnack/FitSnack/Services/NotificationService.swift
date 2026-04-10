import Foundation
import UserNotifications

final class NotificationService: NotificationServiceProtocol {
    private let center = UNUserNotificationCenter.current()

    /// Minimum number of workout data points before personalized timing kicks in.
    private static let minimumDataPoints = 5

    /// Default reminder hour when insufficient data (8 AM).
    private static let defaultReminderHour = 8

    /// Minutes before the computed workout hour to send the reminder.
    private static let reminderOffsetMinutes = 30

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleDailyReminder(at hour: Int, minute: Int) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["dailyReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Time for FitSnack!"
        content.body = "Even 5 minutes makes a difference. Ready for a quick workout?"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyReminder", content: content, trigger: trigger)

        try await center.add(request)
    }

    func schedulePersonalizedReminder(basedOnHistory workoutTimes: [Date]) async throws {
        // Filter to last 14 days
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentTimes = workoutTimes.filter { $0 >= fourteenDaysAgo }

        // If fewer than 5 data points, fall back to default fixed-time schedule
        guard recentTimes.count >= Self.minimumDataPoints else {
            try await scheduleDailyReminder(at: Self.defaultReminderHour, minute: 0)
            return
        }

        // Find the most common hour (mode)
        let hours = recentTimes.map { Calendar.current.component(.hour, from: $0) }
        let modeHour = Self.mode(of: hours)

        // Schedule 30 minutes before the mode hour
        let totalMinutes = modeHour * 60 - Self.reminderOffsetMinutes
        let adjustedMinutes = totalMinutes < 0 ? totalMinutes + 24 * 60 : totalMinutes
        let reminderHour = adjustedMinutes / 60
        let reminderMinute = adjustedMinutes % 60

        try await scheduleDailyReminder(at: reminderHour, minute: reminderMinute)
    }

    func scheduleStreakAtRiskNotification() async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["streakAtRisk"])

        let content = UNMutableNotificationContent()
        content.title = "Your streak is at risk!"
        content.body = "Complete a workout today to keep your streak alive."
        content.sound = .default

        // Schedule for 6 PM today
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "streakAtRisk", content: content, trigger: trigger)

        try await center.add(request)
    }

    func scheduleStreakSaverCheck() async throws {
        // Streak saver check is handled by the mock service for now
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    /// Returns the mode (most frequent value) of an array of integers.
    /// In case of a tie, returns the earliest hour.
    static func mode(of values: [Int]) -> Int {
        var counts: [Int: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maxCount }.keys.min() ?? 8
    }
}
