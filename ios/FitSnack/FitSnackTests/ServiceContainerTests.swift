import XCTest
@testable import FitSnack

final class ServiceContainerTests: XCTestCase {
    func testMockContainerResolvesEveryService() async throws {
        let services = ServiceContainer.mock()
        let user = MockPersistence.sampleUser

        _ = try await services.exerciseService.exercises()
        _ = try await services.workoutEngine.generateWorkout(
            requestedMinutes: 10,
            user: user,
            recentLogs: []
        )
        _ = try await services.consistencyService.consistency(for: [], weeklyGoal: 3)
        _ = try await services.phaseService.phase(for: user, recentLogs: [])
        _ = try await services.userService.currentUser()
        _ = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
        _ = try await services.healthKitService.authorizationStatus()
        _ = try await services.subscriptionService.currentSubscription()
        _ = try await services.authService.currentUserIdentifier()
    }
}
