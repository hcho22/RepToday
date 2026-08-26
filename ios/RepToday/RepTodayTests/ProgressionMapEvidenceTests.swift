import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-SP05, the progression map (the ladder): a user sees the per-pattern
/// ladder they are climbing, with the current frontier marked, the harder discipline tiers shown ahead,
/// and the Strength-Phase summit shown *locked* with an "earn the Strength Phase to unlock" affordance -
/// previewable but never selectable, and with **no start/select control on any rung** (thesis: the map
/// is never a menu).
///
/// This drives the *production* `ProgressTabView` in a real key window over the PRD Validation Test's
/// exact shape - a Discipline user at the full push-up (`push_standard`) tier - and asserts the
/// load-bearing marks on the live accessibility tree (current at Standard Push-Up; Archer ahead;
/// One-Arm Push-Up locked with the earn affordance), confirms the rungs are readouts and not buttons,
/// then captures the screen to a PNG. Because the view reads through the real `ProgressAnalytics` over
/// the real catalog, the ladder on screen is the engine's own - the deterministic logic is pinned in
/// `ProgressAnalyticsTests`; this shows a reviewer the actual pixels.
@MainActor
final class ProgressionMapEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "US-SP05"

    /// A fixed Gregorian/UTC Sunday-start calendar, matching the other Progress/Phase suites so week
    /// bucketing is deterministic.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    /// A session whose single logged exercise is a completed set of `exerciseId` - enough to make it the
    /// worked frontier of its chain (the map counts any non-skipped exercise with a recorded set).
    private func workLog(exerciseId: String, pattern: MovementPattern, reps: Int, weeksAgo: Int, dayOffset: Int = 0) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                               movementPattern: pattern, completedSets: [CompletedSet(reps: reps, durationSeconds: nil)],
                               skipped: false)
            ]
        )
    }

    /// The PRD Validation Test history: a Discipline user whose push frontier sits at the full push-up
    /// (`push_standard`). Squat and core get a token entry too, so the whole map renders populated.
    private func validationLogs() -> [WorkoutLog] {
        [
            workLog(exerciseId: "push_standard", pattern: .push, reps: 15, weeksAgo: 0),
            workLog(exerciseId: "squat_bodyweight", pattern: .squat, reps: 15, weeksAgo: 0, dayOffset: 1),
            workLog(exerciseId: "hinge_glute_bridge", pattern: .hinge, reps: 15, weeksAgo: 1),
            workLog(exerciseId: "core_hollow_hold", pattern: .core, reps: 20, weeksAgo: 1, dayOffset: 1),
        ]
    }

    private func disciplineUser() -> User {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        return user
    }

    private func makeViewModel(logs: [WorkoutLog]) -> ProgressViewModel {
        ProgressViewModel(
            userService: MockUserService(user: disciplineUser()),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: .free),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// Hosts the production Progress tab over the validation history, asserts the push ladder's marks
    /// on the live tree, confirms no rung is an activatable control, and captures the screen.
    func testProgressionMapMarksCurrentAheadAndLockedSummit() async throws {
        let viewModel = makeViewModel(logs: validationLogs())
        await viewModel.load()

        // Sanity: the view model derived the push frontier at the full push-up, and the summit is a
        // locked strength skill for this Discipline user.
        XCTAssertEqual(viewModel.phase, .discipline)
        let pushLadder = viewModel.analytics?.progressionMap.ladders.first { $0.pattern == .push }
        XCTAssertEqual(pushLadder?.currentRung?.exerciseId, "push_standard")
        XCTAssertEqual(pushLadder?.rungs.first { $0.exerciseId == "push_one_arm" }?.isLocked, true)

        let layoutSize = CGSize(width: 393, height: 4200)
        let (host, hostedWindow) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: layoutSize)
        window = hostedWindow

        // Current position marked at the full push-up.
        XCTAssertTrue(labelsContain("Standard Push-Up, You're here"),
                      "the push ladder should mark Standard Push-Up as the current rung; tree reads \(labels())")
        // Harder discipline tiers shown ahead (not locked).
        XCTAssertTrue(labelsContain("Archer Push-Up, Coming up"),
                      "Archer Push-Up should be shown ahead; tree reads \(labels())")
        // The phase-gated summit shown locked with the earn affordance - previewable, not hidden.
        XCTAssertTrue(labelsContain("One-Arm Push-Up, Earn the Strength Phase to unlock"),
                      "the One-Arm Push-Up summit should read locked with the earn affordance; tree reads \(labels())")

        // No start/select control on any rung: the rung elements are readouts, never buttons.
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        for label in ["Standard Push-Up, You're here.", "One-Arm Push-Up, Earn the Strength Phase to unlock."] {
            let element = AccessibilityTree.element(labeled: label, in: root)
            XCTAssertNotNil(element, "expected a rung element labeled '\(label)'")
            XCTAssertFalse((element as? NSObject)?.accessibilityTraits.contains(.button) ?? false,
                           "rung '\(label)' must not be an activatable control - the map is never a menu")
        }

        // Capture the whole scrolling surface, cropped to the content it laid out to.
        var captureHeight = layoutSize.height
        if let scroll = firstScrollView(in: root) {
            let bottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: root).y
                + scroll.adjustedContentInset.bottom
            if bottom > 0 { captureHeight = min(layoutSize.height, ceil(bottom)) }
        }
        let image = HostedSurface.capture(root, size: CGSize(width: layoutSize.width, height: captureHeight))
        let path = try EvidenceOutput.write(image, named: "01-progression-map-ladder.png", for: story)
        print("US-SP05 EVIDENCE: 01-progression-map-ladder.png -> \(path)")
        _ = host
    }
}
