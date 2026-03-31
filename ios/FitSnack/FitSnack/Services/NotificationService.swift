import UserNotifications

final class NotificationService: NotificationServiceProtocol {
    private let center = UNUserNotificationCenter.current()

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

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
