import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// The "just crossed into `.strength`" detector behind the US-SP06 graduation reveal.
///
/// Two layers of coverage: the crossing *decision* against a controllable phase service (earned
/// Strength -> reveal; still Discipline -> no reveal; a missing user -> no reveal), and one true
/// end-to-end pass that drives the **real** deterministic `PhaseEvaluatorService` over the **real**
/// catalog with logs that actually clear the earn threshold - the PRD Validation Test's "a user whose
/// logs just crossed the earn threshold" setup. The once-only / survives-relaunch half of the
/// validation lives in `AppStateTests` (the persisted one-shot flag).
@MainActor
final class StrengthGraduationViewModelTests: XCTestCase {

    // MARK: - Crossing decision (controllable phase service)

    func testEarnedStrengthTriggersTheReveal() async {
        let userService = CountingUserService(user: MockPersistence.sampleUser)
        let viewModel = StrengthGraduationViewModel(
            userService: userService,
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .strength)
        )

        await viewModel.evaluate()

        XCTAssertTrue(viewModel.earnedStrength, "a user the evaluator resolves to .strength should trigger the reveal")
        let persistedPhase = await userService.user?.phase
        let phaseAdvanceCount = await userService.phaseAdvanceCount
        let saveCount = await userService.saveCount
        XCTAssertEqual(persistedPhase, .strength, "the app-open lifecycle persists the transition")
        XCTAssertEqual(phaseAdvanceCount, 1)
        XCTAssertEqual(saveCount, 0, "app-open reconciliation uses the phase-only persistence path")
    }

    func testStillDisciplineDoesNotTriggerTheReveal() async {
        let userService = CountingUserService(user: MockPersistence.sampleUser)
        let viewModel = StrengthGraduationViewModel(
            userService: userService,
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .discipline)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "a user still earning Strength must not trigger the reveal")
        let phaseAdvanceCount = await userService.phaseAdvanceCount
        XCTAssertEqual(phaseAdvanceCount, 0, "an unchanged phase must not produce a user write")
    }

    func testPersistedStrengthIsNeverReevaluatedDowngradedOrRewritten() async {
        var user = MockPersistence.sampleUser
        user.phase = .strength
        let userService = CountingUserService(user: user)
        let phaseService = StubPhaseService(earned: .discipline)
        let viewModel = StrengthGraduationViewModel(
            userService: userService,
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: phaseService
        )

        await viewModel.evaluate()

        XCTAssertTrue(viewModel.earnedStrength, "persisted Strength remains the effective earned phase")
        let persistedPhase = await userService.user?.phase
        let phaseAdvanceCount = await userService.phaseAdvanceCount
        let phaseCallCount = await phaseService.phaseCallCount
        XCTAssertEqual(persistedPhase, .strength)
        XCTAssertEqual(phaseAdvanceCount, 0, "a current phase must not be rewritten")
        XCTAssertEqual(phaseCallCount, 0, "a current phase needs no reevaluation")
    }

    func testNoUserDoesNotTriggerTheReveal() async {
        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: nil),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: StubPhaseService(earned: .strength)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "with no profile there is nothing to congratulate; the reveal must stay closed")
    }

    func testRootWaitsForReconciliationBeforeGeneratingPhaseDependentTabs() async {
        let suiteName = "StrengthGraduationViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(userDefaults: defaults)
        appState.isOnboarded = true
        let userService = GatedPhaseUserService(user: MockPersistence.sampleUser)
        let phaseService = StubPhaseService(earned: .strength)
        let base = ServiceContainer.mock()
        let services = ServiceContainer(
            exerciseService: base.exerciseService,
            workoutEngine: base.workoutEngine,
            sessionPolicyService: base.sessionPolicyService,
            consistencyService: base.consistencyService,
            phaseService: phaseService,
            userService: userService,
            workoutLogService: base.workoutLogService,
            activeSessionStore: base.activeSessionStore,
            sessionCompletionService: base.sessionCompletionService,
            healthKitService: base.healthKitService,
            subscriptionService: base.subscriptionService,
            premiumSessionAuthority: base.premiumSessionAuthority,
            authService: base.authService,
            analyticsService: base.analyticsService,
            accountDeletionService: base.accountDeletionService
        )

        let (host, window) = HostedSurface.host(
            RootView()
                .environment(\.services, services)
                .environment(appState),
            size: CGSize(width: 393, height: 852),
            settleFor: HostedSurface.settleInterval
        )
        defer {
            window.isHidden = true
            _ = host
        }

        await userService.waitUntilPhaseAdvanceStarts()
        let labelsBeforeRelease = AccessibilityTree.labels(in: host.view)
        XCTAssertTrue(labelsBeforeRelease.contains("Preparing today’s session"))
        XCTAssertFalse(labelsBeforeRelease.contains("Today"))

        await userService.releasePhaseAdvance()
        try? await Task.sleep(nanoseconds: 100_000_000)
        HostedSurface.pump(for: 0.2)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        HostedSurface.pump(for: 0.1)

        let labelsAfterRelease = AccessibilityTree.labels(in: host.view)
        let persistedPhase = await userService.user?.phase
        XCTAssertTrue(labelsAfterRelease.contains("Today"), "tabs never appeared: \(labelsAfterRelease)")
        XCTAssertFalse(
            labelsAfterRelease.contains("Preparing today’s session"),
            "preparation remained after reconciliation: \(labelsAfterRelease)"
        )
        XCTAssertEqual(persistedPhase, .strength)
    }

    func testPastCelebrationDoesNotPromoteAUserWhoNoLongerQualifies() async {
        let suiteName = "StrengthGraduationViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(userDefaults: defaults)
        appState.isOnboarded = true
        appState.markStrengthGraduationCelebrated()
        let userService = CountingUserService(user: MockPersistence.sampleUser)
        let phaseService = StubPhaseService(earned: .discipline)
        let viewModel = StrengthGraduationViewModel(
            userService: userService,
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: phaseService
        )

        await viewModel.evaluate()

        let persistedPhase = await userService.user?.phase
        let phaseAdvanceCount = await userService.phaseAdvanceCount
        let phaseCallCount = await phaseService.phaseCallCount
        XCTAssertTrue(appState.hasCelebratedStrengthGraduation)
        XCTAssertFalse(viewModel.earnedStrength)
        XCTAssertEqual(persistedPhase, .discipline)
        XCTAssertEqual(phaseAdvanceCount, 0)
        XCTAssertEqual(phaseCallCount, 1)
    }

    /// Product-level evidence for the production reconciliation path: a persisted Discipline user
    /// with qualifying durable history opens the real app shell, waits behind the preparation state,
    /// is ratcheted to Strength through the real evaluator, and sees the graduation reveal. The same
    /// reloaded aggregate then reaches the difficulty-five catalog skill that US-SP01 gates on phase.
    func testRealAppOpenPersistsStrengthPresentsGraduationAndUnlocksHarderWork() async throws {
        let suiteName = "StrengthGraduationViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(userDefaults: defaults)
        appState.isOnboarded = true

        let persistence = MockPersistence.controller()
        let userService = CoreDataUserService(context: persistence.viewContext)
        let workoutLogService = CoreDataWorkoutLogService(context: persistence.viewContext)
        let disciplineUser = MockPersistence.sampleUser
        try await userService.save(disciplineUser)

        let exerciseService = try MockExerciseService()
        let library = try await exerciseService.exercises()
        let logs = Self.sustainedHistory(weeks: 10) + Self.competenceLogs(library: library)
        for log in logs {
            try await workoutLogService.save(log)
        }

        let phaseService = PhaseEvaluatorService(
            exerciseService: exerciseService,
            now: { Self.asOf },
            calendar: Self.calendar
        )
        let base = ServiceContainer.mock()
        let services = ServiceContainer(
            exerciseService: exerciseService,
            workoutEngine: base.workoutEngine,
            sessionPolicyService: base.sessionPolicyService,
            consistencyService: base.consistencyService,
            phaseService: phaseService,
            userService: userService,
            workoutLogService: workoutLogService,
            activeSessionStore: base.activeSessionStore,
            sessionCompletionService: base.sessionCompletionService,
            healthKitService: base.healthKitService,
            subscriptionService: base.subscriptionService,
            premiumSessionAuthority: base.premiumSessionAuthority,
            authService: base.authService,
            analyticsService: base.analyticsService,
            accountDeletionService: base.accountDeletionService
        )

        let (host, window) = HostedSurface.host(
            RootView()
                .environment(\.services, services)
                .environment(appState),
            size: CGSize(width: 393, height: 852),
            settleFor: HostedSurface.settleInterval
        )
        defer {
            window.isHidden = true
            _ = host
        }

        var spoken: [String] = []
        var persisted = disciplineUser
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            HostedSurface.pump(for: 0.05)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let reloaded = try await userService.currentUser()
            persisted = try XCTUnwrap(reloaded)
            spoken = AccessibilityTree.spokenStrings(in: host.view)
            if persisted.phase == .strength,
               spoken.contains(where: { $0.localizedCaseInsensitiveContains("You've earned the Strength Phase") }) {
                break
            }
        }

        XCTAssertEqual(persisted.phase, .strength, "app-open reconciliation must persist the earned phase")
        XCTAssertTrue(
            spoken.contains(where: { $0.localizedCaseInsensitiveContains("You've earned the Strength Phase") }),
            "the user must see the graduation after reconciliation; spoke: \(spoken)"
        )
        XCTAssertTrue(appState.hasCelebratedStrengthGraduation, "the reveal must be one-shot before presentation")

        let eligibleIds = ExercisePoolFilter
            .eligiblePool(from: library, user: persisted, recentLogs: logs)
            .map(\.id)
        XCTAssertTrue(
            eligibleIds.contains("push_one_arm"),
            "the persisted Strength phase must engage US-SP01's real difficulty-five skill"
        )

        HostedSurface.pump(for: 0.2)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = HostedSurface.capture(host.view, size: CGSize(width: 393, height: 852))
        let imagePath = try EvidenceOutput.write(
            image,
            named: "01-real-app-open-strength-graduation.png",
            for: "persist-earned-phase-transition"
        )
        let transcript = """
        # Earned-phase production lifecycle

        - Entry surface: `RootView` for an onboarded account
        - Persistence: in-memory `CoreDataUserService` and `CoreDataWorkoutLogService`
        - Evaluator: real `PhaseEvaluatorService` over the bundled exercise catalog
        - Durable qualifying history: \(logs.count) workout logs
        - Phase before app open: \(disciplineUser.phase.rawValue)
        - Phase reloaded after reconciliation: \(persisted.phase.rawValue)
        - One-shot graduation marked before presentation: \(appState.hasCelebratedStrengthGraduation)
        - Downstream real catalog skill `push_one_arm` eligible: \(eligibleIds.contains("push_one_arm"))
        - User-visible VoiceOver surface: \(spoken.joined(separator: " | "))
        - Screenshot: \(imagePath)
        """
        _ = try EvidenceOutput.write(
            transcript + "\n",
            named: "02-lifecycle-and-unlock-transcript.md",
            for: "persist-earned-phase-transition"
        )
    }

    // MARK: - End to end over the real evaluator + real catalog (the PRD Validation setup)

    /// Logs that have just crossed the real earn threshold - sustained consistency over the full window
    /// plus every foundation's entry tier cleared - make the real `PhaseEvaluatorService` report
    /// `.strength`, and the view model fires. This proves the wiring reaches the same gate the engine
    /// uses, not just a stub.
    func testRealLogsCrossingTheEarnThresholdTriggerTheReveal() async throws {
        let exerciseService = try MockExerciseService()
        let library = try await exerciseService.exercises()
        let logs = Self.sustainedHistory(weeks: 10) + Self.competenceLogs(library: library)
        let userService = CountingUserService(user: MockPersistence.sampleUser)

        let viewModel = StrengthGraduationViewModel(
            userService: userService,
            workoutLogService: MockWorkoutLogService(logs: logs),
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService, now: { Self.asOf }, calendar: Self.calendar)
        )

        await viewModel.evaluate()

        XCTAssertTrue(viewModel.earnedStrength, "real earn-threshold logs should resolve to .strength and fire the reveal")
        let persistedPhase = await userService.user?.phase
        XCTAssertEqual(persistedPhase, .strength, "the real evaluator's result is persisted")
    }

    /// The negative end-to-end control: a fresh user with no history stays Discipline through the real
    /// evaluator, so the reveal never fires - guarding against a wiring that always reports Strength.
    func testRealFreshHistoryDoesNotTriggerTheReveal() async throws {
        let exerciseService = try MockExerciseService()

        let viewModel = StrengthGraduationViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: []),
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService, now: { Self.asOf }, calendar: Self.calendar)
        )

        await viewModel.evaluate()

        XCTAssertFalse(viewModel.earnedStrength, "a user with no history has earned nothing yet")
    }

    // MARK: - Real earn-threshold fixture

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private static let asOf = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!

    private static func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    /// `weeklyGoal` on-goal show-up sessions per week across `weeks` weeks - a fully sustained history
    /// whose Consistency Score clears the bar over the full ~8-week window.
    private static func sustainedHistory(weeks: Int, weeklyGoal: Int = 3) -> [WorkoutLog] {
        (0..<weeks).flatMap { w in
            (0..<weeklyGoal).map { d in
                WorkoutLog(
                    id: UUID(), workoutId: UUID(),
                    completedAt: date(weeksAgo: w, dayOffset: d),
                    requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
                    shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
                    exercises: []
                )
            }
        }
    }

    /// One clearing log per foundational pattern, each derived from the **real** catalog: it finds the
    /// pattern's entry tier (the lowest `progressionOrder` in one of its chains) and logs a generous,
    /// non-skipped performance that clears whatever `advancementCriteria` that entry carries - so the
    /// fixture stays correct as the catalog evolves rather than hard-coding exercise ids.
    private static func competenceLogs(library: [Exercise]) -> [WorkoutLog] {
        PhaseEvaluator.foundationalPatterns.compactMap { pattern in
            let members = library.filter { $0.movementPattern == pattern }
            let byChain = Dictionary(grouping: members, by: \.progressionChainId)
            guard let entry = byChain.values
                .compactMap({ $0.min(by: { $0.progressionOrder < $1.progressionOrder }) })
                .min(by: { $0.progressionOrder < $1.progressionOrder })
            else { return nil }

            // Five generous sets each carrying both a big rep count and a big hold, so it clears any
            // "{sets}x{target}" criteria whether the entry is rep-based or a hold.
            let sets = (0..<5).map { _ in CompletedSet(reps: 1000, durationSeconds: 1000) }
            return WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: date(weeksAgo: 0, dayOffset: 0),
                requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
                shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
                exercises: [
                    LoggedExercise(
                        id: UUID(), exerciseId: entry.id, pillar: entry.pillar,
                        movementPattern: pattern, completedSets: sets, skipped: false
                    )
                ]
            )
        }
    }
}

/// A `PhaseServiceProtocol` that reports a fixed earned phase, so the crossing decision can be tested
/// without standing up the real evaluator and its earn-threshold fixture.
private actor StubPhaseService: PhaseServiceProtocol {
    let earned: Phase
    private(set) var phaseCallCount = 0

    init(earned: Phase) {
        self.earned = earned
    }

    func phase(for user: User, recentLogs: [WorkoutLog]) async throws -> Phase {
        phaseCallCount += 1
        return earned
    }

    func progress(for user: User, recentLogs: [WorkoutLog]) async throws -> PhaseProgress {
        PhaseProgress(
            activeWeeks: 0, requiredWeeks: PhaseEvaluator.sustainedWeeks,
            currentScore: 0, scoreThreshold: PhaseEvaluator.consistencyThreshold, foundations: []
        )
    }
}

private actor CountingUserService: UserServiceProtocol {
    private(set) var user: User?
    private(set) var saveCount = 0
    private(set) var phaseAdvanceCount = 0

    init(user: User?) {
        self.user = user
    }

    func currentUser() async throws -> User? { user }

    func save(_ user: User) async throws {
        saveCount += 1
        let persistedPhase = self.user?.phase
        self.user = persistedPhase.map { user.advancingPhase(to: $0) } ?? user
    }

    func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? {
        phaseAdvanceCount += 1
        guard let user, user.id == userId else { return nil }
        let advanced = user.advancingPhase(to: earnedPhase)
        self.user = advanced
        return advanced
    }

    func deleteCurrentUser() async throws {
        user = nil
    }
}

private actor GatedPhaseUserService: UserServiceProtocol {
    private(set) var user: User?
    private var phaseAdvanceStarted = false
    private var phaseAdvanceReleased = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(user: User?) {
        self.user = user
    }

    func currentUser() async throws -> User? { user }

    func save(_ user: User) async throws {
        let persistedPhase = self.user?.phase
        self.user = persistedPhase.map { user.advancingPhase(to: $0) } ?? user
    }

    func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? {
        phaseAdvanceStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        if !phaseAdvanceReleased {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        guard let user, user.id == userId else { return nil }
        let advanced = user.advancingPhase(to: earnedPhase)
        self.user = advanced
        return advanced
    }

    func deleteCurrentUser() async throws { user = nil }

    func waitUntilPhaseAdvanceStarts() async {
        if phaseAdvanceStarted { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func releasePhaseAdvance() {
        phaseAdvanceReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
