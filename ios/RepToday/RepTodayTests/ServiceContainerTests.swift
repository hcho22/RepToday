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
            16,
            "a service was added to ServiceContainer - resolve it below and update this count"
        )

        _ = try await services.exerciseService.exercises()
        let policy = try await services.sessionPolicyService.currentPolicy(for: user)
        _ = try await services.workoutEngine.generateWorkout(
            requestedMinutes: 10,
            user: user,
            recentLogs: [],
            sessionPolicy: policy
        )
        _ = try await services.consistencyService.consistency(for: [], weeklyGoal: 3)
        _ = try await services.phaseService.phase(for: user, recentLogs: [])
        _ = try await services.userService.currentUser()
        _ = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
        _ = try await services.activeSessionStore.load(for: user.id)
        _ = services.sessionCompletionService
        _ = try await services.healthKitService.authorizationStatus()
        _ = try await services.subscriptionService.currentSubscription()
        _ = try await services.authService.currentUserIdentifier()
        await services.analyticsService.record(AnalyticsEvent(name: .appInstall, timestampMs: 0))
        // Resolved but not exercised: running it would tear down the container's stores and mutate an
        // AppState. Its teardown is covered by `AccountDeletionServiceTests`.
        _ = services.accountDeletionService
        // The premium coach transport (US-AC02): `nil` in the mock container (no proxy configured),
        // which is the coach's "inert, never fatal" state - the chat surface shows "unavailable".
        XCTAssertNil(services.coachClient)
        // The coach's bounded policy-write path (US-AC07): wired over the same shared policy store as
        // the deterministic Programmer, so applying a no-op proposal reads the default in force and writes
        // nothing (returns nil) - resolved and exercised without mutating the container.
        let coachPolicy = try XCTUnwrap(services.coachPolicyService)
        let noOp = try await coachPolicy.applyProposal(CoachPolicyProposal(), for: user, asOf: Date())
        XCTAssertNil(noOp, "an empty proposal moves no lever, so nothing is written")
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
