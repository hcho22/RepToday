import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for the Ready Screen's **Different workout** button, driven on the
/// production `ReadyView` in a real key window: VoiceOver reads it as a labeled button with a hint,
/// activating it the VoiceOver way rebuilds the listed session while Start stays present and enabled, and
/// at the largest accessibility text size it stays inside the screen width. The PNGs land under
/// `artifacts/reports/different-workout/` when regenerated with `REPTODAY_WRITE_EVIDENCE=1`. The engine
/// and view-model rules are pinned in `DifferentWorkoutTests` and `ReadyDifferentWorkoutTests`.
@MainActor
final class DifferentWorkoutEvidenceTests: XCTestCase {

    private let story = EvidenceOutput.Story.differentWorkout

    /// The labels of the listed movements: every row reads "<name>, <target>".
    private func exerciseRows(in root: UIView) -> [String] {
        AccessibilityTree.labels(in: root).filter { $0.contains(" set") || $0.contains(" second") }
    }

    /// The mock container with a signed-up user to build today's session for, waiting until the
    /// hosted screen has listed it.
    private func services() -> ServiceContainer {
        let services = ServiceContainer.mock()
        let saved = expectation(description: "a user to build today's session for")
        Task {
            try await services.userService.save(MockPersistence.sampleUser)
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

    private func capture(_ root: UIView, width: CGFloat, height: CGFloat = 1400, name: String) throws {
        let height = min(root.bounds.height, height)
        let image = HostedSurface.capture(root, size: CGSize(width: width, height: height))
        let path = try EvidenceOutput.write(image, named: name, for: story)
        print("DIFFERENT WORKOUT EVIDENCE: \(name) -> \(path)")
    }

    func testVoiceOverPressRebuildsTheSessionWhileStartStaysEnabled() throws {
        let size = CGSize(width: 393, height: 2400)
        let (host, window) = HostedSurface.host(ReadyView(services: services()), size: size)
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("Different workout", in: root)

        let button = try XCTUnwrap(
            AccessibilityTree.element(labeled: "Different workout", in: root),
            "tree reads \(AccessibilityTree.labels(in: root))"
        )
        XCTAssertTrue(button.accessibilityTraits.contains(.button), "VoiceOver announces it as a button")
        XCTAssertEqual(button.accessibilityHint, "Builds another 15 minute workout with other moves.")
        let before = exerciseRows(in: root)
        XCTAssertFalse(before.isEmpty, "the session is listed")
        try capture(root, width: size.width, name: "ready-before-press.png")

        XCTAssertTrue(button.accessibilityActivate())
        HostedSurface.pump(for: 1.0)

        let after = exerciseRows(in: root)
        XCTAssertFalse(after.isEmpty)
        XCTAssertNotEqual(after, before, "the press lists other moves")
        let start = try XCTUnwrap(AccessibilityTree.element(labeled: "Start", in: root), "Start is still on screen")
        XCTAssertTrue(start.accessibilityTraits.contains(.button))
        XCTAssertFalse(start.accessibilityTraits.contains(.notEnabled), "Start stays enabled")
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Different workout", in: root), "the control stays for another press")
        try capture(root, width: size.width, name: "ready-after-press.png")
    }

    func testTheLabelWrapsInsideTheScreenAtTheLargestTextSize() throws {
        let size = CGSize(width: 375, height: 3200)
        let (host, window) = HostedSurface.host(
            ReadyView(services: services()).environment(\.dynamicTypeSize, .accessibility5), size: size
        )
        defer { withExtendedLifetime(window) {} }
        let root = host.view!
        waitFor("Different workout", in: root)

        let button = try XCTUnwrap(AccessibilityTree.element(labeled: "Different workout", in: root))
        let frame = button.accessibilityFrame
        XCTAssertGreaterThanOrEqual(frame.minX, window.frame.minX, "does not run off the leading edge")
        XCTAssertLessThanOrEqual(frame.maxX, window.frame.maxX, "does not run off the trailing edge")
        XCTAssertGreaterThanOrEqual(frame.height, Theme.Spacing.minTouchTarget, "keeps the 44 pt touch target")
        let bottom = root.convert(frame, from: nil).maxY
        try capture(root, width: size.width, height: bottom + Theme.Spacing.lg, name: "ready-accessibility5.png")
    }
}
