import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// US-TD05: Today on a Rest Day - the Rest Day card with its Recovery flow and "Train anyway" - rendered
/// from the production `ReadyView` in light and dark, and at the largest text size on a small phone.
@MainActor
final class RestDayEvidenceTests: XCTestCase {

    private let story = EvidenceOutput.Story.restDay

    /// A container whose user finished Push, Pull and Legs in the last three days, so today owes rest.
    private func services() -> ServiceContainer {
        let services = ServiceContainer.mock()
        var user = MockPersistence.sampleUser
        user.profile.injuries = []
        let cycle = [
            TrainingDayFixtures.trainingLog(.push, completedAt: Date().addingTimeInterval(-3 * 86_400)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: Date().addingTimeInterval(-2 * 86_400)),
            TrainingDayFixtures.trainingLog(.legs, completedAt: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(12 * 3_600)),
        ]
        let saved = expectation(description: "a user who has finished a Cycle")
        Task {
            try await services.userService.save(user)
            for log in cycle { try await services.workoutLogService.save(log) }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        return services
    }

    private func waitFor(_ label: String, in root: UIView, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while AccessibilityTree.element(labeled: label, in: root) == nil, Date() < deadline {
            HostedSurface.pump(for: 0.1)
        }
        HostedSurface.pump(for: 0.3)
    }

    private func assertRestDay(in root: UIView, window: UIWindow) throws {
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Rest Day", in: root), "\(AccessibilityTree.labels(in: root))")
        for label in ["Recovery", "Train anyway"] {
            let button = try XCTUnwrap(AccessibilityTree.element(labeled: label, in: root), "\(label) missing")
            XCTAssertTrue(button.accessibilityTraits.contains(.button), label)
            let frame = button.accessibilityFrame
            XCTAssertGreaterThanOrEqual(frame.minX, window.frame.minX, "\(label) runs off the leading edge")
            XCTAssertLessThanOrEqual(frame.maxX, window.frame.maxX, "\(label) runs off the trailing edge")
            XCTAssertGreaterThanOrEqual(frame.height, Theme.Spacing.minTouchTarget, "\(label) keeps its touch target")
        }
        XCTAssertNil(AccessibilityTree.element(labeled: "Start", in: root), "a Rest Day offers no session to start")
        let spoken = AccessibilityTree.spokenStrings(in: root).joined(separator: " ")
        XCTAssertTrue(spoken.contains("You trained Push, Pull and Legs."), spoken)
        XCTAssertFalse(spoken.lowercased().contains("streak"), "no streak framing")
    }

    func testRestDayCardInLightAndDark() throws {
        for (style, name) in [(UIUserInterfaceStyle.light, "rest-day-light.png"), (.dark, "rest-day-dark.png")] {
            let size = CGSize(width: 393, height: 852)
            let (host, window) = HostedSurface.host(ReadyView(services: services()), size: size, style: style)
            defer { withExtendedLifetime(window) {} }
            let root = host.view!
            waitFor("Train anyway", in: root)
            try assertRestDay(in: root, window: window)
            let path = try EvidenceOutput.write(HostedSurface.capture(root, size: size), named: name, for: story)
            print("REST DAY EVIDENCE: \(name) -> \(path)")
        }
    }

    func testRestDayCardFitsASmallPhoneAtTheLargestTextSize() throws {
        let size = CGSize(width: 375, height: 2400)
        let (host, window) = HostedSurface.host(
            ReadyView(services: services()).environment(\.dynamicTypeSize, .accessibility5), size: size, style: .light
        )
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("Train anyway", in: root)
        try assertRestDay(in: root, window: window)
        let path = try EvidenceOutput.write(HostedSurface.capture(root, size: size), named: "rest-day-accessibility5.png", for: story)
        print("REST DAY EVIDENCE: rest-day-accessibility5.png -> \(path)")
    }
}
