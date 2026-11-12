import XCTest
@testable import RepToday

final class ServiceContainerTests: XCTestCase {
    /// Every property on the container is resolved and exercised here, so a service added to
    /// `ServiceContainer` and left unwired fails rather than passing unnoticed. The property count
    /// is asserted first so *adding* a service without extending this list is itself the failure.
    func testMockContainerResolvesEveryService() async throws {
        let services = ServiceContainer.mock()
        let user = MockPersistence.sampleUser

        XCTAssertEqual(
            Mirror(reflecting: services).children.count,
            27,
            "a service was added to ServiceContainer - resolve it below and update this count"
        )

        _ = try await services.exerciseService.exercises()
        let policy = try await services.sessionPolicyService.currentPolicy(for: user)
        _ = try await services.workoutEngine.generateWorkout(
            requestedMinutes: 10,
            user: user,
            recentLogs: [],
            sessionPolicy: policy,
            variation: .none
        )
        _ = try await services.consistencyService.consistency(for: [], weeklyGoal: 3)
        _ = try await services.phaseService.phase(for: user, recentLogs: [])
        _ = try await services.userService.currentUser()
        _ = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
        _ = try await services.outsideActivityService.activities(from: nil, to: nil)
        _ = try await services.activeSessionStore.load(for: user.id)
        _ = services.sessionCompletionService
        _ = try await services.healthKitService.authorizationStatus()
        _ = try await services.subscriptionService.currentSubscription()
        XCTAssertEqual(services.premiumSessionAuthority.subscription, .free)
        _ = try await services.authService.currentUserIdentifier()
        services.analyticsService.record(AnalyticsEvent(name: .appInstall, timestampMs: 0))
        // Resolved but not exercised: running it would tear down the container's stores and mutate an
        // AppState. Its teardown is covered by `AccountDeletionServiceTests`.
        _ = services.accountDeletionService
        // The Coach agent (M4): a scripted Coach and a free account in the mock container - no network,
        // no model - plus its on-device state, empty.
        let history = try await XCTUnwrap(services.coachService).history()
        XCTAssertEqual(history, [])
        let status = try await XCTUnwrap(services.premiumEntitlements).status()
        XCTAssertFalse(status.premium)
        let workouts = try await services.customWorkoutService.workouts()
        XCTAssertEqual(workouts, [])
        XCTAssertTrue(services.todayChoices.choices(on: "2026-11-11").isEmpty)
        // The account (M3): the mock container signs in on the device only and never syncs.
        XCTAssertFalse(services.accountAuthService.isConfigured)
        let token = try await services.accountAuthService.sessionToken()
        XCTAssertNil(token, "no session token, so nothing can be uploaded")
        let pending = try await services.syncStore.pendingCount()
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(services.syncCursorStore.cursor(), 0)
        XCTAssertNil(services.syncRemote, "no account backend in the mock container")
        XCTAssertNil(services.syncEngine)
        let importOutcome = await services.legacyICloudImport.waitForImport(timeout: .zero)
        XCTAssertEqual(importOutcome, .nothingToImport)
    }

    /// US-D04 validation test: the container resolves the session-policy service, its
    /// `currentPolicy` returns the always-valid default, and a fresh user has no due triggers.
    func testMockContainerResolvesSessionPolicyService() async throws {
        let services = ServiceContainer.mock()
        let user = MockPersistence.sampleUser

        let policy = try await services.sessionPolicyService.currentPolicy(for: user)
        XCTAssertEqual(policy, .default)

        let triggers = try await services.sessionPolicyService.dueTriggers(
            user: user,
            recentLogs: [],
            asOf: Date()
        )
        XCTAssertTrue(triggers.isEmpty)
    }
}
