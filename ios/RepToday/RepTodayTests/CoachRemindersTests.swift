import XCTest
@testable import RepToday

/// Coach reminders (M4, US-CA08, decision 30): on-device notifications only, permission asked at the
/// first schedule, listed, editable and deletable, and identity-framed - never guilt or streak framed.
final class CoachRemindersTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "CoachRemindersTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func reminder(_ weekdays: [Int] = [2, 4, 6], enabled: Bool = true) -> CoachReminder {
        CoachReminder(hour: 7, minute: 30, weekdays: weekdays, isEnabled: enabled, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testPermissionIsAskedOnlyAtTheFirstScheduleAndOneNotificationRepeatsPerDay() async throws {
        let scheduler = RecordingReminderNotificationScheduler()
        let service = CoachReminderService(defaults: defaults, scheduler: scheduler)
        let first = reminder()
        try await service.save(first)
        try await service.save(reminder([1]))
        let asked = await scheduler.permissionRequests
        XCTAssertEqual(asked, 1, "asked once, when the first reminder is set")
        let pending = await scheduler.pending
        XCTAssertEqual(pending.count, 4)
        XCTAssertEqual(Set(pending.values.filter { $0.identifier.contains(first.id.uuidString) }.map(\.weekday)), [2, 4, 6])
    }

    func testARefusedPermissionSavesNothing() async {
        let scheduler = RecordingReminderNotificationScheduler(grantsOnRequest: false)
        let service = CoachReminderService(defaults: defaults, scheduler: scheduler)
        do {
            try await service.save(reminder())
            XCTFail("a reminder without notifications would never fire")
        } catch {
            XCTAssertEqual(error as? CoachReminderError, .permissionDenied)
        }
        let saved = await service.reminders()
        XCTAssertTrue(saved.isEmpty)
    }

    func testEditingReschedulesDisablingCancelsAndDeletingRemovesEverything() async throws {
        let scheduler = RecordingReminderNotificationScheduler(permission: .allowed)
        let service = CoachReminderService(defaults: defaults, scheduler: scheduler)
        var edited = reminder()
        try await service.save(edited)

        edited.weekdays = [7]
        edited.hour = 18
        try await service.save(edited)
        var pending = await scheduler.pending
        XCTAssertEqual(pending.values.map(\.weekday), [7], "an edit replaces the old days")
        XCTAssertEqual(pending.values.first?.hour, 18)

        edited.isEnabled = false
        try await service.save(edited)
        pending = await scheduler.pending
        XCTAssertTrue(pending.isEmpty, "a switched-off reminder schedules nothing")
        let listed = await service.reminders()
        XCTAssertEqual(listed.count, 1, "it is still listed, switched off")

        await service.delete(id: edited.id)
        let afterDelete = await service.reminders()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testRemindersPersistAndAreListedEarliestFirst() async throws {
        let scheduler = RecordingReminderNotificationScheduler(permission: .allowed)
        let service = CoachReminderService(defaults: defaults, scheduler: scheduler)
        try await service.save(CoachReminder(hour: 19, minute: 0, weekdays: [2], createdAt: Date()))
        try await service.save(CoachReminder(hour: 6, minute: 45, weekdays: [3], createdAt: Date()))
        let reloaded = await CoachReminderService(defaults: defaults, scheduler: scheduler).reminders()
        XCTAssertEqual(reloaded.map(\.hour), [6, 19])
    }

    func testTheCopyIsIdentityFramedNeverGuiltOrStreakFramed() {
        let forbidden = ["streak", "miss", "missed", "don't", "lose", "losing", "guilt", "fail", "break", "behind", "lazy", "skip"]
        let copy = (1...7).map(CoachReminderCopy.notificationBody(weekday:))
            + [CoachReminderCopy.notificationTitle, CoachReminderCopy.settingsFooter, CoachReminderCopy.empty]
        for text in copy {
            let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init))
            XCTAssertTrue(words.isDisjoint(with: forbidden), "\"\(text)\" carries guilt or streak framing")
        }
    }

    func testDaysReadNaturally() {
        XCTAssertEqual(CoachReminderCopy.days(Array(1...7)), "Every day")
        XCTAssertEqual(CoachReminderCopy.days(Array(2...6)), "Weekdays")
        XCTAssertEqual(CoachReminderCopy.days([1, 7]), "Weekends")
        XCTAssertEqual(CoachReminderCopy.spokenDays([2, 4, 6]), "on Monday, Wednesday and Friday")
        XCTAssertEqual(CoachReminder(hour: 30, minute: -2, weekdays: [9, 2, 2, 0], createdAt: Date()).weekdays, [2])
    }
}
