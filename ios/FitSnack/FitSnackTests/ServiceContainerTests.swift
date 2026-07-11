import XCTest
@testable import FitSnack

final class ServiceContainerTests: XCTestCase {
    func testMockContainerResolvesEveryService() async throws {
        let services = ServiceContainer.mock()
        let user = MockPersistence.sampleUser

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
        _ = try await services.healthKitService.authorizationStatus()
        _ = try await services.subscriptionService.currentSubscription()
        _ = try await services.authService.currentUserIdentifier()
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
