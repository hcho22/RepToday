import SwiftUI

/// App-wide service registry.
///
/// Views read this from `@Environment(\.services)`, and view models receive the service
/// values they need from views. Replacing an implementation is localized here: change the
/// matching argument in `mock()` (or a future production factory) from `Mock...` to the
/// real service.
struct ServiceContainer {
    let exerciseService: any ExerciseServiceProtocol
    let workoutEngine: any WorkoutEngineProtocol
    let consistencyService: any ConsistencyServiceProtocol
    let phaseService: any PhaseServiceProtocol
    let userService: any UserServiceProtocol
    let workoutLogService: any WorkoutLogServiceProtocol
    let healthKitService: any HealthKitServiceProtocol
    let subscriptionService: any SubscriptionServiceProtocol
    let authService: any AuthServiceProtocol

    init(
        exerciseService: any ExerciseServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        consistencyService: any ConsistencyServiceProtocol,
        phaseService: any PhaseServiceProtocol,
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        subscriptionService: any SubscriptionServiceProtocol,
        authService: any AuthServiceProtocol
    ) {
        self.exerciseService = exerciseService
        self.workoutEngine = workoutEngine
        self.consistencyService = consistencyService
        self.phaseService = phaseService
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.healthKitService = healthKitService
        self.subscriptionService = subscriptionService
        self.authService = authService
    }

    static func mock() -> ServiceContainer {
        // The bundled exercise library is integrity-gated by `ExerciseLibraryTests` and
        // `ExerciseServiceTests`, so a load/validation failure here is a build-time defect,
        // not a runtime condition - `try!` makes that surface loudly instead of silently
        // shipping an empty catalog.
        ServiceContainer(
            exerciseService: try! MockExerciseService(),
            workoutEngine: MockWorkoutEngine(),
            consistencyService: MockConsistencyService(),
            phaseService: MockPhaseService(),
            userService: MockUserService(),
            workoutLogService: MockWorkoutLogService(),
            healthKitService: MockHealthKitService(),
            subscriptionService: MockSubscriptionService(),
            authService: MockAuthService()
        )
    }
}

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue = ServiceContainer.mock()
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
