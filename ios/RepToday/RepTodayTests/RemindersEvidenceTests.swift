import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Evidence for the Reminders screen in Settings (M4, US-CA08): the production `RemindersView` over a real
/// `CoachReminderService` holding two reminders, read through the accessibility tree and captured in
/// light and dark, at the largest accessibility text size and on a 375x667 screen. PNGs go to
/// `EvidenceOutput`'s folder for "US-CA08". Scheduling, editing and deleting are proved in
/// `CoachRemindersTests`; the Coach walk (`CoachEndToEndUITests`) lists and deletes one through the UI.
@MainActor
final class RemindersEvidenceTests: XCTestCase {

    private var windows: [UIWindow] = []
    private var defaults: UserDefaults!
    private var suite = ""
    private let story = "US-CA08"

    override func setUp() {
        super.setUp()
        suite = "RemindersEvidenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        windows.forEach(HostedSurface.dismantle)
        windows = []
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func service() async throws -> CoachReminderService {
        let service = CoachReminderService(defaults: defaults, scheduler: RecordingReminderNotificationScheduler())
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        try await service.save(CoachReminder(hour: 7, minute: 30, weekdays: Array(2...6), createdAt: created))
        try await service.save(CoachReminder(hour: 18, minute: 15, weekdays: [1, 7], isEnabled: false, createdAt: created))
        return service
    }

    private func host(_ service: CoachReminderService, size: CGSize, style: UIUserInterfaceStyle, textSize: DynamicTypeSize) async throws -> UIView {
        let viewModel = RemindersViewModel(service: service)
        await viewModel.load()
        let (host, window) = HostedSurface.host(
            NavigationStack { RemindersView(viewModel: viewModel) }
                .environment(\.dynamicTypeSize, textSize),
            size: size,
            style: style
        )
        windows.append(window)
        return host.view
    }

    func testEachReminderIsListedWithItsOwnSwitchInEveryLook() async throws {
        let service = try await service()
        let looks: [(String, CGSize, UIUserInterfaceStyle, DynamicTypeSize)] = [
            ("01-reminders-light", CGSize(width: 393, height: 852), .light, .large),
            ("02-reminders-dark", CGSize(width: 393, height: 852), .dark, .large),
            ("03-reminders-largest-text", CGSize(width: 393, height: 1800), .light, .accessibility5),
            ("04-reminders-375x667", CGSize(width: 375, height: 667), .light, .large),
        ]
        for (name, size, style, textSize) in looks {
            let root = try await host(service, size: size, style: style, textSize: textSize)
            let labels = AccessibilityTree.labels(in: root)
            let time = CoachReminderCopy.time(hour: 7, minute: 30)
            XCTAssertTrue(labels.contains { $0.hasPrefix("Reminder at \(time), ") }, "\(name): the row names its time and days; \(labels)")
            XCTAssertTrue(labels.contains("Reminder at \(time)"), "\(name): the switch names the reminder it turns on or off; \(labels)")
            XCTAssertTrue(labels.contains("Reminder at \(CoachReminderCopy.time(hour: 18, minute: 15))"), "\(name): \(labels)")
            XCTAssertFalse(labels.contains("Reminder on"), "\(name): no switch reads as a bare \"Reminder on\"")
            XCTAssertTrue(labels.contains(CoachReminderCopy.addReminder), "\(name): \(labels)")
            let path = try EvidenceOutput.write(HostedSurface.capture(root, size: size), named: "\(name).png", for: story)
            print("US-CA08 EVIDENCE: \(name) -> \(path)")
        }
    }
}
