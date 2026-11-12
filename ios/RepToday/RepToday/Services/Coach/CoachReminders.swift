import Foundation
import UserNotifications

/// A repeating training reminder (M4, US-CA08, decision 30): on-device notifications only - no server
/// push - set up from a Coach proposal or in Settings, and listed, edited and deleted in Settings.
struct CoachReminder: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Local time of day.
    var hour: Int
    var minute: Int
    /// `Calendar` weekdays it repeats on (1 = Sunday ... 7 = Saturday), ascending.
    var weekdays: [Int]
    var isEnabled: Bool = true
    var createdAt: Date

    init(id: UUID = UUID(), hour: Int, minute: Int, weekdays: [Int], isEnabled: Bool = true, createdAt: Date) {
        self.id = id
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

/// The reminder copy, one source for the notification, Settings and the Coach's cards. Identity-framed:
/// a reminder is an invitation, never a warning - no streaks, no guilt, nothing about days missed.
enum CoachReminderCopy {
    static let notificationTitle = "Rep Today"

    /// The notification's text, varied by weekday so it never reads like a nag.
    static func notificationBody(weekday: Int) -> String {
        let bodies = [
            "Your session is ready when you are. You're someone who moves.",
            "A few minutes is all it takes. Let's move.",
            "Time for you. Your session is ready.",
        ]
        return bodies[(max(weekday, 1) - 1) % bodies.count]
    }

    static let settingsTitle = "Reminders"
    static let settingsFooter = "Reminders are notifications on this iPhone at the times you choose. You can also ask the Coach to set one."
    static let addReminder = "Add reminder"
    static let empty = "No reminders yet."
    static let permissionDenied = "Notifications are off for Rep Today. Turn them on in the iPhone Settings app to get reminders."

    /// "7:30 AM"
    static func time(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Weekdays", "Every day", "Weekends", or "Mon, Wed, Fri".
    static func days(_ weekdays: [Int], calendar: Calendar = .current) -> String {
        let set = Set(weekdays)
        if set == Set(1...7) { return "Every day" }
        if set == Set(2...6) { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        let symbols = calendar.shortWeekdaySymbols
        return weekdays.sorted(by: weekdayOrder).compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
    }

    /// The spoken form of `days`: full weekday names.
    static func spokenDays(_ weekdays: [Int], calendar: Calendar = .current) -> String {
        let set = Set(weekdays)
        if set == Set(1...7) { return "every day" }
        if set == Set(2...6) { return "on weekdays" }
        if set == [1, 7] { return "on weekends" }
        let symbols = calendar.weekdaySymbols
        let names = weekdays.sorted(by: weekdayOrder).compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
        guard names.count > 1 else { return "on \(names.first ?? "")" }
        return "on " + names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// "7:30 AM, Weekdays"
    static func summary(_ reminder: CoachReminder) -> String {
        "\(time(hour: reminder.hour, minute: reminder.minute)), \(days(reminder.weekdays))"
    }

    /// Monday first, Sunday last, the way a week reads.
    private static func weekdayOrder(_ a: Int, _ b: Int) -> Bool {
        ((a + 5) % 7) < ((b + 5) % 7)
    }
}

/// Whether the app may post notifications.
enum NotificationPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// One repeating notification to schedule.
struct ScheduledReminderNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let weekday: Int
    let hour: Int
    let minute: Int
}

/// The system's notification center, behind a seam so tests never post a real notification.
protocol ReminderNotificationScheduling: Sendable {
    func permission() async -> NotificationPermission
    /// Asks the user, the first time a reminder is set. Returns whether notifications are allowed.
    func requestPermission() async -> Bool
    func add(_ notifications: [ScheduledReminderNotification]) async throws
    func removePending(identifiers: [String]) async
}

/// The live scheduler over `UNUserNotificationCenter`.
struct SystemReminderNotificationScheduler: ReminderNotificationScheduling {
    func permission() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ notifications: [ScheduledReminderNotification]) async throws {
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            var components = DateComponents()
            components.weekday = notification.weekday
            components.hour = notification.hour
            components.minute = notification.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
            )
        }
    }

    func removePending(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// A scheduler that records instead of posting, for tests and previews.
actor RecordingReminderNotificationScheduler: ReminderNotificationScheduling {
    private(set) var current: NotificationPermission
    private let grantsOnRequest: Bool
    private(set) var pending: [String: ScheduledReminderNotification] = [:]
    private(set) var permissionRequests = 0

    init(permission: NotificationPermission = .notDetermined, grantsOnRequest: Bool = true) {
        current = permission
        self.grantsOnRequest = grantsOnRequest
    }

    func permission() async -> NotificationPermission { current }

    func requestPermission() async -> Bool {
        permissionRequests += 1
        current = grantsOnRequest ? .allowed : .denied
        return grantsOnRequest
    }

    func add(_ notifications: [ScheduledReminderNotification]) async throws {
        for notification in notifications {
            pending[notification.identifier] = notification
        }
    }

    func removePending(identifiers: [String]) async {
        for identifier in identifiers {
            pending[identifier] = nil
        }
    }
}

enum CoachReminderError: Error, Equatable {
    /// The user has not allowed notifications, so nothing was scheduled.
    case permissionDenied
}

/// Keeps the reminders and their notifications in step (US-CA08): every reminder saved here has exactly
/// one pending notification per weekday while it is enabled, and none once it is disabled or deleted.
actor CoachReminderService {
    private let defaults: UserDefaults
    private let scheduler: any ReminderNotificationScheduling
    static let key = "Coach.reminders"

    init(defaults: UserDefaults = .standard, scheduler: any ReminderNotificationScheduling = SystemReminderNotificationScheduler()) {
        self.defaults = defaults
        self.scheduler = scheduler
    }

    /// Every reminder, earliest in the day first.
    func reminders() -> [CoachReminder] {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([CoachReminder].self, from: data) else { return [] }
        return stored.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// Saves a new or edited reminder and schedules its notifications. Asks for notification permission
    /// the first time, and saves nothing when it is refused.
    func save(_ reminder: CoachReminder) async throws {
        if reminder.isEnabled {
            try await ensurePermission()
        }
        var all = reminders().filter { $0.id != reminder.id }
        await scheduler.removePending(identifiers: Self.identifiers(for: reminder.id))
        all.append(reminder)
        write(all)
        if reminder.isEnabled {
            try await scheduler.add(Self.notifications(for: reminder))
        }
    }

    func delete(id: UUID) async {
        await scheduler.removePending(identifiers: Self.identifiers(for: id))
        write(reminders().filter { $0.id != id })
    }

    /// Removes every reminder and its notifications (account deletion).
    func removeAll() async {
        let ids = reminders().flatMap { Self.identifiers(for: $0.id) }
        await scheduler.removePending(identifiers: ids)
        defaults.removeObject(forKey: Self.key)
    }

    private func ensurePermission() async throws {
        switch await scheduler.permission() {
        case .allowed:
            return
        case .denied:
            throw CoachReminderError.permissionDenied
        case .notDetermined:
            guard await scheduler.requestPermission() else { throw CoachReminderError.permissionDenied }
        }
    }

    private func write(_ reminders: [CoachReminder]) {
        if reminders.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(reminders) {
            defaults.set(data, forKey: Self.key)
        }
    }

    static func identifiers(for id: UUID) -> [String] {
        (1...7).map { "coach.reminder.\(id.uuidString).\($0)" }
    }

    static func notifications(for reminder: CoachReminder) -> [ScheduledReminderNotification] {
        reminder.weekdays.map { weekday in
            ScheduledReminderNotification(
                identifier: "coach.reminder.\(reminder.id.uuidString).\(weekday)",
                title: CoachReminderCopy.notificationTitle,
                body: CoachReminderCopy.notificationBody(weekday: weekday),
                weekday: weekday,
                hour: reminder.hour,
                minute: reminder.minute
            )
        }
    }
}
