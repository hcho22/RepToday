import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for ADR-0007 (staple movements): the one-time "your sessions now focus on
/// the classics" note on the Ready Screen of an install that predates the change, and a beginner's
/// progression map showing only the classics as reachable with the rest locked until the Strength Phase.
///
/// Both drive the *production* surfaces in a real key window and assert the load-bearing marks on the
/// live accessibility tree before capturing the pixels; the deterministic rules are pinned in
/// `StapleMovementsTests`.
@MainActor
final class StapleMovementsEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = EvidenceOutput.Story.stapleMovements

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    }

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func user(level: FitnessLevel) -> User {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        user.profile.fitnessLevel = level
        user.profile.injuries = []
        return user
    }

    private func workLog(_ id: String, pattern: MovementPattern, reps: Int, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!,
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: id, pillar: .strength, movementPattern: pattern,
                    completedSets: [CompletedSet(reps: reps, durationSeconds: nil)], skipped: false
                )
            ]
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

    private func readyServices(for user: User) throws -> ServiceContainer {
        let exerciseService = try MockExerciseService()
        let userService = MockUserService(user: user)
        let policyStore = InMemorySessionPolicyStore()
        let consistencyService = ConsistencyScoreService(now: { self.asOf }, calendar: calendar)
        let workoutLogService = MockWorkoutLogService(logs: [])
        let activeSessionStore = InMemoryActiveSessionStore()
        let authService = MockAuthService()
        return ServiceContainer(
            exerciseService: exerciseService,
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService, now: { self.asOf }),
            sessionPolicyService: DeterministicSessionPolicyService(
                store: policyStore, exerciseService: exerciseService, userService: userService
            ),
            consistencyService: consistencyService,
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
            userService: userService,
            workoutLogService: workoutLogService,
            activeSessionStore: activeSessionStore,
            sessionCompletionService: SessionCompletionService(
                workoutLogService: workoutLogService, userService: userService,
                consistencyService: consistencyService,
                phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
                policyStore: policyStore
            ),
            healthKitService: MockHealthKitService(),
            subscriptionService: MockSubscriptionService(),
            premiumSessionAuthority: PremiumSessionAuthority(),
            authService: authService,
            analyticsService: MockAnalyticsService(),
            accountDeletionService: AccountDeletionService(
                userService: userService,
                workoutLogService: workoutLogService,
                sessionPolicyStore: policyStore,
                activeSessionStore: activeSessionStore,
                authService: authService
            )
        )
    }

    /// An `AppState` for an install that predates the change (onboarded, never through onboarding on this
    /// build) or a brand-new one (finishes onboarding on this build).
    private func appState(existingInstall: Bool) -> (AppState, UserDefaults, String) {
        let suite = "StapleMovementsEvidenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if existingInstall { defaults.set(true, forKey: "AppState.isOnboarded") }
        let state = AppState(userDefaults: defaults)
        if !existingInstall { state.isOnboarded = true }
        return (state, defaults, suite)
    }

    private func capture(_ root: UIView, size: CGSize, name: String) throws {
        var captureHeight = size.height
        if let scroll = firstScrollView(in: root) {
            let bottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: root).y
                + scroll.adjustedContentInset.bottom
            if bottom > 0 { captureHeight = min(size.height, ceil(bottom)) }
        }
        let image = HostedSurface.capture(root, size: CGSize(width: size.width, height: captureHeight))
        let path = try EvidenceOutput.write(image, named: name, for: story)
        print("STAPLE MOVEMENTS EVIDENCE: \(name) -> \(path)")
    }

    // MARK: - The one-time note

    /// An install that predates the change, an intermediate in the Discipline Phase: the Ready Screen shows
    /// the captain's note once, and appearing marks it seen.
    func testReadyScreenShowsTheClassicsNoteOnceToAnExistingIntermediateInstall() throws {
        let (state, defaults, suite) = appState(existingInstall: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(state.shouldShowClassicsUpdateNote)

        let size = CGSize(width: 393, height: 1500)
        let (host, hosted) = HostedSurface.host(
            ReadyView(services: try readyServices(for: user(level: .intermediate))).environment(state), size: size
        )
        window = hosted
        XCTAssertTrue(labelsContain("Your sessions now focus on the classics. More movements unlock when you earn the Strength Phase."),
                      "the note reads the captain's copy verbatim; tree reads \(labels())")
        XCTAssertFalse(state.shouldShowClassicsUpdateNote, "appearing marks the one-shot flag, so it is shown once")

        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        try capture(root, size: size, name: "01-ready-screen-classics-note.png")
        _ = host

        // A second Ready Screen on the same install never shows it again.
        let (secondHost, secondWindow) = HostedSurface.host(
            ReadyView(services: try readyServices(for: user(level: .intermediate))).environment(state), size: size
        )
        window = secondWindow
        XCTAssertFalse(labelsContain("focus on the classics"), "the note never reappears once seen")
        _ = secondHost
    }

    /// Nobody else sees it: a brand-new install (flag marked on onboarding completion), an advanced user and
    /// a Strength-Phase user on a pre-existing install.
    func testReadyScreenShowsNoNoteToNewInstallsAdvancedOrStrengthPhaseUsers() throws {
        let size = CGSize(width: 393, height: 1500)

        let (fresh, freshDefaults, freshSuite) = appState(existingInstall: false)
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
        var (host, hosted) = HostedSurface.host(
            ReadyView(services: try readyServices(for: user(level: .beginner))).environment(fresh), size: size
        )
        window = hosted
        XCTAssertFalse(labelsContain("focus on the classics"), "a brand-new install never sees the note")
        _ = host

        let (existingAdvanced, advancedDefaults, advancedSuite) = appState(existingInstall: true)
        defer { advancedDefaults.removePersistentDomain(forName: advancedSuite) }
        (host, hosted) = HostedSurface.host(
            ReadyView(services: try readyServices(for: user(level: .advanced))).environment(existingAdvanced), size: size
        )
        window = hosted
        XCTAssertFalse(labelsContain("focus on the classics"), "an advanced user's sessions did not change")
        XCTAssertTrue(existingAdvanced.shouldShowClassicsUpdateNote, "eligibility alone consumes nothing")
        _ = host

        var strengthUser = user(level: .beginner)
        strengthUser.phase = .strength
        let (existingStrength, strengthDefaults, strengthSuite) = appState(existingInstall: true)
        defer { strengthDefaults.removePersistentDomain(forName: strengthSuite) }
        (host, hosted) = HostedSurface.host(
            ReadyView(services: try readyServices(for: strengthUser)).environment(existingStrength), size: size
        )
        window = hosted
        XCTAssertFalse(labelsContain("focus on the classics"), "a Strength-Phase user already has every movement")
        _ = host
    }

    // MARK: - A beginner's progression map

    func testBeginnerProgressionMapShowsOnlyTheClassicsReachable() async throws {
        let logs = [
            workLog("push_standard", pattern: .push, reps: 15, daysAgo: 1),
            workLog("squat_bodyweight", pattern: .squat, reps: 20, daysAgo: 2),
            workLog("hinge_glute_bridge", pattern: .hinge, reps: 20, daysAgo: 3),
            workLog("core_bird_dog", pattern: .core, reps: 10, daysAgo: 4),
            workLog("pull_wall_scapular_pull", pattern: .pull, reps: 12, daysAgo: 5),
        ]
        let viewModel = ProgressViewModel(
            userService: MockUserService(user: user(level: .beginner)),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: .free),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
        await viewModel.load()

        let squat = try XCTUnwrap(viewModel.analytics?.progressionMap.ladders.first { $0.pattern == .squat })
        XCTAssertEqual(squat.rungs.filter { !$0.isLocked }.map(\.exerciseId), ["squat_wall_sit", "squat_bodyweight"],
                       "a beginner's squat progression is Wall Sit then Bodyweight Squat")

        let size = CGSize(width: 393, height: 4400)
        let (host, hosted) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: size)
        window = hosted
        XCTAssertTrue(labelsContain("Standard Push-Up, You're here"), "tree reads \(labels())")
        XCTAssertTrue(labelsContain("Diamond Push-Up, Earn the Strength Phase to unlock"), "an intermediate staple is locked for a beginner")
        XCTAssertTrue(labelsContain("Archer Push-Up, Earn the Strength Phase to unlock"))
        XCTAssertTrue(labelsContain("Bodyweight Squat, You're here"))
        XCTAssertTrue(labelsContain("Sumo Squat, Earn the Strength Phase to unlock"))
        XCTAssertFalse(labelsContain("Gorilla"), "no withdrawn crawl is named")

        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        try capture(root, size: size, name: "02-beginner-progression-map.png")
        _ = host
    }
}
