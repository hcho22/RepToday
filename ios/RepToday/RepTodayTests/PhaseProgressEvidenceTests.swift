import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-SP04, the free "visible climb" surface: a Discipline-Phase user
/// sees, on the Progress tab, exactly how close they are to earning the Strength Phase - the two real
/// earn signals computed from real logs by the *same* `PhaseEvaluator` logic that gates the phase.
///
/// This drives the *production* `ProgressTabView` in a real key window over the PRD Validation Test's
/// exact shape - five sustained weeks with push and squat cleared (hinge/core not) - and asserts the
/// load-bearing values on the live accessibility tree ("5 of 8 weeks", "2 of 4 cleared", the two
/// cleared foundations and the two still in progress), then captures the screen to a PNG. Because the
/// view reads through the real `PhaseEvaluatorService` over the real catalog, the numbers on screen
/// are the gate's own - the deterministic parity is pinned in `PhaseEvaluatorTests`; this shows a
/// reviewer the actual pixels.
@MainActor
final class PhaseProgressEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "US-SP04"

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

    /// A plain on-goal show-up (no exercises) - builds the sustained-consistency history.
    private func showUp(weeksAgo: Int, dayOffset: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil, exercises: []
        )
    }

    /// A log this week whose single logged exercise clears the entry tier `exerciseId` - three sets
    /// each meeting `value` (reps for a rep entry, seconds for a hold). Uses the *real* catalog's entry
    /// exercises so the gate's own competence test clears them.
    private func clearingLog(exerciseId: String, pattern: MovementPattern, isHold: Bool, value: Int) -> WorkoutLog {
        let sets = (0..<3).map { _ in
            CompletedSet(reps: isHold ? nil : value, durationSeconds: isHold ? value : nil)
        }
        return WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: 0, dayOffset: 1),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                               movementPattern: pattern, completedSets: sets, skipped: false)
            ]
        )
    }

    /// The PRD Validation Test history: five fully on-goal weeks (weekly goal 3) plus push and squat
    /// entry tiers cleared, hinge and core untouched.
    private func validationLogs() -> [WorkoutLog] {
        var logs = (0..<5).flatMap { w in (0..<3).map { showUp(weeksAgo: w, dayOffset: $0) } }
        logs.append(clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15))
        logs.append(clearingLog(exerciseId: "squat_wall_sit", pattern: .squat, isHold: true, value: 45))
        return logs
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

    /// Hosts the production Progress tab over the validation history, asserts the two earn signals are
    /// on the live tree with the exact PRD numbers, and captures the screen.
    func testPhaseProgressCardShowsFiveOfEightAndTwoOfFour() async throws {
        let viewModel = makeViewModel(logs: validationLogs())
        await viewModel.load()

        // Sanity: the view model read the same numbers the gate decides on, and the user is still
        // climbing (Discipline) so the card is shown at all.
        XCTAssertEqual(viewModel.phase, .discipline)
        XCTAssertEqual(viewModel.phaseProgress?.weeksSustained, 5)
        XCTAssertEqual(viewModel.phaseProgress?.clearedFoundationCount, 2)
        XCTAssertEqual(viewModel.phaseProgress?.hasEarnedStrength, false)

        let layoutSize = CGSize(width: 393, height: 3400)
        let (host, hostedWindow) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: layoutSize)
        window = hostedWindow

        // The consistency signal: five of the eight-week window.
        XCTAssertTrue(labelsContain("5 of 8 weeks"),
                      "the climb card should show '5 of 8 weeks'; tree reads \(labels())")
        // The competence signal: exactly two of four foundations cleared.
        XCTAssertTrue(labelsContain("2 of 4 cleared"),
                      "the climb card should show '2 of 4 cleared'; tree reads \(labels())")
        // Per-foundation state: push and squat cleared, hinge and core still in progress.
        XCTAssertTrue(labelsContain("Push, cleared"), "push should read cleared; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Squat, cleared"), "squat should read cleared; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Hinge, in progress"), "hinge should read in progress; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Core, in progress"), "core should read in progress; tree reads \(labels())")

        // Capture the whole scrolling surface, cropped to the content it laid out to.
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        var captureHeight = layoutSize.height
        if let scroll = firstScrollView(in: root) {
            let bottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: root).y
                + scroll.adjustedContentInset.bottom
            if bottom > 0 { captureHeight = min(layoutSize.height, ceil(bottom)) }
        }
        let image = HostedSurface.capture(root, size: CGSize(width: layoutSize.width, height: captureHeight))
        let path = try EvidenceOutput.write(image, named: "01-phase-progress-climb.png", for: story)
        print("US-SP04 EVIDENCE: 01-phase-progress-climb.png -> \(path)")
        _ = host
    }
}
