import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AN01, the premium strength-journey analytics: a premium user sees,
/// on the Progress tab's deep layer, analytics anchored on their climb over time - the dated
/// tier-advancement timeline ("Wall Push-Up -> Standard Push-Up, over 6 weeks") read from real history,
/// plus the current phase-earning progress (US-SP04's signals) - while a free user sees only the free
/// layers and the upsell in its place.
///
/// This drives the *production* `ProgressTabView` in a real key window over the PRD Validation Test's
/// shape - a premium user whose push chain climbed a tier across multiple weeks - and asserts the
/// load-bearing values on the live accessibility tree (the advancement line with its duration, the
/// per-tier dates, the earned-progress readout), then confirms a free user's tree carries none of it.
/// Because the view reads through the real `ProgressAnalytics`/`PhaseEvaluatorService` over the real
/// catalog, the journey on screen is the engine's own - the deterministic logic is pinned in
/// `ProgressAnalyticsTests`; this shows a reviewer the actual pixels.
@MainActor
final class StrengthJourneyEvidenceTests: XCTestCase {

    private var window: UIWindow?

    private let story = "US-AN01"

    /// A fixed Gregorian/UTC Sunday-start calendar, matching the other Progress/Phase suites so week
    /// bucketing (and the milestone dates/durations) is deterministic.
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

    /// A session whose single logged exercise is a completed set of `exerciseId` - enough to make it a
    /// reached tier of its chain (any non-skipped exercise with a recorded set).
    private func workLog(exerciseId: String, pattern: MovementPattern, reps: Int, weeksAgo: Int, dayOffset: Int = 0) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                               movementPattern: pattern, completedSets: [CompletedSet(reps: reps, durationSeconds: nil)],
                               skipped: false)
            ]
        )
    }

    /// The PRD Validation Test history: the push chain climbed a tier across weeks - Wall Push-Up six
    /// weeks ago, Knee Push-Up three weeks ago, Standard Push-Up this week - so the journey shows a
    /// dated, multi-week advancement. Squat gets a single token tier so a second foundation renders.
    private func validationLogs() -> [WorkoutLog] {
        [
            workLog(exerciseId: "push_wall", pattern: .push, reps: 15, weeksAgo: 6),
            workLog(exerciseId: "push_knee", pattern: .push, reps: 12, weeksAgo: 3),
            workLog(exerciseId: "push_standard", pattern: .push, reps: 10, weeksAgo: 0),
            workLog(exerciseId: "squat_bodyweight", pattern: .squat, reps: 15, weeksAgo: 0, dayOffset: 1),
        ]
    }

    private func disciplineUser() -> User {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        return user
    }

    private func makeViewModel(logs: [WorkoutLog], premium: Bool) -> ProgressViewModel {
        let subscription = premium
            ? Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
            : .free
        return ProgressViewModel(
            userService: MockUserService(user: disciplineUser()),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
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

    private func captureFullSurface(named fileName: String) throws {
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        let layoutHeight = window?.bounds.height ?? 4600
        var captureHeight = layoutHeight
        if let scroll = firstScrollView(in: root) {
            let bottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: root).y
                + scroll.adjustedContentInset.bottom
            if bottom > 0 { captureHeight = min(layoutHeight, ceil(bottom)) }
        }
        let image = HostedSurface.capture(root, size: CGSize(width: root.bounds.width, height: captureHeight))
        let path = try EvidenceOutput.write(image, named: fileName, for: story)
        print("US-AN01 EVIDENCE: \(fileName) -> \(path)")
    }

    /// A premium user's deep layer shows the dated strength journey - the advancement line with its
    /// six-week duration, the per-tier reached dates, and the phase-earning readout - and captures it.
    func testPremiumStrengthJourneyShowsDatedAdvancement() async throws {
        let viewModel = makeViewModel(logs: validationLogs(), premium: true)
        await viewModel.load()

        // Sanity: the view model derived the multi-week push climb through the deep layer.
        XCTAssertTrue(viewModel.isPremium)
        let push = viewModel.analytics?.deep.strengthJourney.chains.first { $0.pattern == .push }
        XCTAssertEqual(push?.startMilestone?.displayName, "Wall Push-Up")
        XCTAssertEqual(push?.currentMilestone?.displayName, "Standard Push-Up")
        XCTAssertEqual(push?.weeksClimbed, 6)

        let layoutSize = CGSize(width: 393, height: 4600)
        let (host, hostedWindow) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: layoutSize)
        window = hostedWindow

        // The section header and its identity-framed intent.
        XCTAssertTrue(labelsContain("Your strength journey"),
                      "the deep layer should carry the strength-journey section; tree reads \(labels())")
        // The dated advancement: from -> to over the measured span.
        XCTAssertTrue(labelsContain("Advanced from Wall Push-Up to Standard Push-Up"),
                      "the push journey should read the dated advancement; tree reads \(labels())")
        XCTAssertTrue(labelsContain("over 6 weeks"),
                      "the advancement should state the six-week duration; tree reads \(labels())")
        // The per-tier timeline carries the reached-on dates and marks the current frontier.
        XCTAssertTrue(labelsContain("Wall Push-Up, reached"),
                      "the timeline should date the entry tier; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Standard Push-Up, reached") && labelsContain("you're here"),
                      "the frontier tier should be dated and marked current; tree reads \(labels())")
        // Phase-earning progress reused from US-SP04's signals.
        XCTAssertTrue(labelsContain("Earning the Strength Phase"),
                      "the journey should surface phase-earning progress; tree reads \(labels())")

        try captureFullSurface(named: "01-strength-journey-premium.png")
        _ = host
    }

    /// A free user with the same history sees the free layers only: no strength-journey section, and
    /// the deep layer replaced by the upsell. Proves the render-boundary gate (no deep depth leaks).
    func testFreeUserSeesNoStrengthJourney() async throws {
        let viewModel = makeViewModel(logs: validationLogs(), premium: false)
        await viewModel.load()
        XCTAssertFalse(viewModel.isPremium)

        let layoutSize = CGSize(width: 393, height: 4600)
        let (host, hostedWindow) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: layoutSize)
        window = hostedWindow

        // The deep-only strength journey is absent for a free user.
        XCTAssertFalse(labelsContain("Your strength journey"),
                       "a free user must not see the premium strength journey; tree reads \(labels())")
        XCTAssertFalse(labelsContain("Advanced from Wall Push-Up"),
                       "a free user must not see the dated advancement; tree reads \(labels())")
        // The upsell stands in its place, and the free chain-position layer still renders.
        XCTAssertTrue(labelsContain("Go deeper with Premium"),
                      "a free user should see the upsell in place of the deep layer; tree reads \(labels())")

        try captureFullSurface(named: "02-strength-journey-free-gated.png")
        _ = host
    }
}
