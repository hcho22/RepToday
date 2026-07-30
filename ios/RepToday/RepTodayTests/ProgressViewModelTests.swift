import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Tests the Progress tab view model (US-M01).
///
/// The Progress tab reads the real `WorkoutLog` history and the real forgiving Consistency Score and
/// derives three surfaces: the headline score with its earned `longestChain`, the score trend over
/// time, and the set of completed days for the calendar. These tests verify each surface is populated
/// from real history, an empty history is a valid encouraging state (not an error), and no-user
/// degrades gracefully.
final class ProgressViewModelTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    private func week(weeksAgo: Int, count: Int) -> [WorkoutLog] {
        (0..<count).map { i in
            WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: date(weeksAgo: weeksAgo, dayOffset: i),
                requestedMinutes: 15, durationMinutes: 15,
                wasReturn: false, shape: .singleFocus, focusPillar: .strength,
                perceivedDifficulty: nil, exercises: []
            )
        }
    }

    private func makeViewModel(user: User?, logs: [WorkoutLog], premium: Bool = false) -> ProgressViewModel {
        let subscription = Subscription(
            tier: premium ? .premium : .free,
            provider: .apple,
            expiresAt: nil,
            trialEndsAt: nil
        )
        return ProgressViewModel(
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
    }

    private func onboardedUser() -> User { MockPersistence.sampleUser }

    // MARK: - Populated history

    /// Three weeks of logged sessions populate the score, the trend, and the calendar days.
    func testLoadPopulatesAllSurfacesFromHistory() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertTrue(vm.hasHistory)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.consistency)
        XCTAssertEqual(vm.consistency?.totalWorkoutsCompleted, 9)
        // Nine sessions on nine distinct days -> nine marked days.
        XCTAssertEqual(vm.completedDays.count, 9)
        // Three active weeks -> a three-point trajectory.
        XCTAssertEqual(vm.trend.count, 3)
    }

    /// `longestChain` is surfaced as earned pride: a sustained on-goal run shows a positive number.
    func testLongestChainSurfacedAsPositiveAchievement() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertEqual(vm.consistency?.longestChain, 3)
    }

    /// The completed days are start-of-day normalized, so a session marks exactly its calendar day.
    func testCompletedDaysAreStartOfDayNormalized() async {
        let logs = week(weeksAgo: 0, count: 1)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        let day = vm.completedDays.first
        XCTAssertNotNil(day)
        XCTAssertEqual(day, calendar.startOfDay(for: logs[0].completedAt))
    }

    /// The headline score matches the newest trend point, so the card and chart agree.
    func testHeadlineScoreMatchesNewestTrendPoint() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 2) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertEqual(vm.consistency!.score, vm.trend.last!.score, accuracy: 0.0001)
    }

    // MARK: - Empty history

    /// A fresh onboarded user with no logs is a valid, encouraging empty state - not an error.
    func testEmptyHistoryIsNotAnError() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [])

        await vm.load()

        XCTAssertFalse(vm.hasHistory)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.trend.isEmpty)
        XCTAssertTrue(vm.completedDays.isEmpty)
    }

    // MARK: - No user

    /// With no profile, the view model surfaces a message and touches no history.
    func testNoUserSurfacesMessage() async {
        let vm = makeViewModel(user: nil, logs: [])

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.hasHistory)
    }

    // MARK: - Refresh

    /// Loading twice refreshes rather than duplicating, so returning to the tab reflects new history.
    func testReloadRefreshes() async {
        let vm = makeViewModel(user: onboardedUser(), logs: week(weeksAgo: 0, count: 2))
        await vm.load()
        XCTAssertEqual(vm.completedDays.count, 2)

        await vm.load()
        XCTAssertEqual(vm.completedDays.count, 2)
    }

    // MARK: - US-M02: analytics + premium gating

    /// A log carrying a worked strength push so the analytics layer has real content to summarize.
    private func pushLog(weeksAgo: Int, dayOffset: Int = 0, reps: Int = 12) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 15, durationMinutes: 12, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: "push_knee", pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: reps, durationSeconds: nil)], skipped: false
                )
            ]
        )
    }

    /// `load` computes the legibility layer (US-M02) from real history: pillar balance, chain
    /// position for the trained pattern, and personal bests.
    func testLoadPopulatesAnalyticsFromHistory() async {
        let logs = [pushLog(weeksAgo: 0), pushLog(weeksAgo: 1, reps: 15)]
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        let analytics = vm.analytics
        XCTAssertNotNil(analytics)
        // All the training was push (strength), so strength owns the whole pillar balance.
        let strength = analytics?.pillarBalance.first { $0.pillar == .strength }
        XCTAssertEqual(strength?.fraction ?? 0, 1.0, accuracy: 0.0001)
        // The push foundation reports the worked movement; the untrained ones are "not started".
        let push = analytics?.chainPositions.first { $0.pattern == .push }
        XCTAssertEqual(push?.currentExercise?.id, "push_knee")
        let squat = analytics?.chainPositions.first { $0.pattern == .squat }
        XCTAssertEqual(squat?.hasStarted, false)
        // The best single set is the 15-rep set.
        XCTAssertEqual(analytics?.personalBests.bestReps?.value, 15)
    }

    /// A free user's entitlement leaves the deep layer gated (`isPremium == false`); the free
    /// analytics surfaces are still computed.
    func testFreeUserIsNotPremiumButStillGetsBasicAnalytics() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [pushLog(weeksAgo: 0)], premium: false)

        await vm.load()

        XCTAssertFalse(vm.isPremium)
        XCTAssertNotNil(vm.analytics)
    }

    /// A premium user's entitlement unlocks the deep layer (`isPremium == true`).
    func testPremiumUserUnlocksDeepLayer() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [pushLog(weeksAgo: 0)], premium: true)

        await vm.load()

        XCTAssertTrue(vm.isPremium)
        XCTAssertNotNil(vm.analytics?.deep)
    }
}

// MARK: - US-M02 rendered-UI evidence

/// Renders the actual `ProgressTabView` surface to PNGs so the US-M02 cards can be reviewed as an end
/// user would see them: the free legibility layer (pillar balance, chain position, personal bests)
/// with the non-nagging premium upsell in place of the deep layer, the premium variant with the deep
/// analytics section unlocked, and the fresh-user empty state. The mock container ships empty history
/// (US-M01), so these states cannot be reached by tapping the running app - the snapshots stand in for
/// that live capture.
@MainActor
final class ProgressTabSnapshotTests: XCTestCase {

    private let evidenceDir = "/var/folders/9t/k_yy9fqs5vd27rf12jx_rzqh0000gn/T/no-mistakes-evidence/01KXDS2JQK10M3QC5REGASPVYY"

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A varied, realistic six-week history: all three pillars, the four foundational patterns, a
    /// rep best and a hold best, and a spread of perceived-difficulty ratings so every US-M02 card
    /// (including the premium difficulty mix) has real content to render.
    private func sampleLogs() -> [WorkoutLog] {
        struct Spec {
            let exerciseId: String, pillar: Pillar, pattern: MovementPattern
            let reps: Int?, seconds: Int?, difficulty: PerceivedDifficulty
        }
        let specs: [Spec] = [
            Spec(exerciseId: "push_knee", pillar: .strength, pattern: .push, reps: 14, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "squat_bodyweight", pillar: .strength, pattern: .squat, reps: 22, seconds: nil, difficulty: .tooEasy),
            Spec(exerciseId: "hinge_glute_bridge", pillar: .strength, pattern: .hinge, reps: 18, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "core_forearm_plank", pillar: .strength, pattern: .core, reps: nil, seconds: 55, difficulty: .tooHard),
            Spec(exerciseId: "mobility_cat_cow", pillar: .mobility, pattern: .mobility, reps: 12, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "primal_bear_crawl", pillar: .primal, pattern: .locomotion, reps: 10, seconds: nil, difficulty: .justRight),
        ]
        return (0..<18).map { offset in
            let spec = specs[offset % specs.count]
            let set = CompletedSet(reps: spec.reps, durationSeconds: spec.seconds)
            let logged = LoggedExercise(
                id: UUID(), exerciseId: spec.exerciseId, pillar: spec.pillar,
                movementPattern: spec.pattern,
                completedSets: [set, set], skipped: false
            )
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: date(daysAgo: offset * 2),
                requestedMinutes: 20, durationMinutes: 15 + offset % 6, wasReturn: false,
                shape: .blend, focusPillar: spec.pillar, perceivedDifficulty: spec.difficulty,
                exercises: [logged]
            )
        }
    }

    private func makeViewModel(logs: [WorkoutLog], premium: Bool) -> ProgressViewModel {
        let subscription = Subscription(
            tier: premium ? .premium : .free, provider: .apple, expiresAt: nil, trialEndsAt: nil
        )
        return ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: self.calendar),
            now: { self.asOf },
            calendar: self.calendar
        )
    }

    private func snapshot(viewModel: ProgressViewModel, tall: Bool, fileName: String) async throws {
        // Pre-load so the populated content path renders when the view is hosted.
        await viewModel.load()
        try render(viewModel: viewModel, tall: tall, fileName: fileName)
    }

    /// Hosting, layout and capture stay in a synchronous context: spinning the run loop is unavailable
    /// from an async context, and the capture itself has nothing left to await.
    private func render(viewModel: ProgressViewModel, tall: Bool, fileName: String) throws {
        let size = CGSize(width: 393, height: tall ? 2500 : 760)
        let host = UIHostingController(rootView: ProgressTabView(viewModel: viewModel))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        // A real key window makes the view actually lay out and draw its layers; sizing the window to
        // the full content height means the whole scroll content is laid out (not just a screenful).
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let SwiftUI + Swift Charts finish their asynchronous layout/draw passes before capturing.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        // `layer.render(in:)` composites the entire layer tree offscreen, so it captures content past
        // the physical screen bounds - unlike `drawHierarchy(afterScreenUpdates:)`, which is limited to
        // what is actually on screen.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            host.view.layer.render(in: ctx.cgContext)
        }
        let data = try XCTUnwrap(image.pngData())

        try? FileManager.default.createDirectory(atPath: evidenceDir, withIntermediateDirectories: true)
        let path = (evidenceDir as NSString).appendingPathComponent(fileName)
        try data.write(to: URL(fileURLWithPath: path))

        XCTAssertGreaterThan(data.count, 8000, "Rendered PNG unexpectedly small - the surface may not have drawn")
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
    }

    /// Free tier: the three free cards render for everyone and the quiet premium upsell stands in for
    /// the deep layer.
    func testRenderFreeProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: sampleLogs(), premium: false),
                           tall: true, fileName: "progress-m02-free.png")
    }

    /// Premium tier: the same free cards plus the unlocked deep analytics section (pattern balance,
    /// weekly volume chart, difficulty mix).
    func testRenderPremiumProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: sampleLogs(), premium: true),
                           tall: true, fileName: "progress-m02-premium.png")
    }

    /// Fresh user: the encouraging empty state (no cards, never gated, never loss-framed).
    func testRenderEmptyProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: [], premium: false),
                           tall: false, fileName: "progress-m02-empty.png")
    }
}
