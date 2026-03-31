import SwiftUI
import SwiftData

@Observable
final class ServiceContainer {
    let auth: AuthServiceProtocol
    let workout: WorkoutServiceProtocol
    let exercise: ExerciseServiceProtocol
    let user: UserServiceProtocol
    let healthKit: HealthKitServiceProtocol
    let notification: NotificationServiceProtocol
    let subscription: SubscriptionServiceProtocol

    init(
        auth: AuthServiceProtocol,
        workout: WorkoutServiceProtocol,
        exercise: ExerciseServiceProtocol,
        user: UserServiceProtocol,
        healthKit: HealthKitServiceProtocol,
        notification: NotificationServiceProtocol,
        subscription: SubscriptionServiceProtocol
    ) {
        self.auth = auth
        self.workout = workout
        self.exercise = exercise
        self.user = user
        self.healthKit = healthKit
        self.notification = notification
        self.subscription = subscription
    }

    static func mock(modelContext: ModelContext) -> ServiceContainer {
        let exerciseService = MockExerciseService()
        let userService = MockUserService(modelContext: modelContext)
        let workoutService = MockWorkoutService(
            modelContext: modelContext,
            exerciseService: exerciseService
        )

        return ServiceContainer(
            auth: MockAuthService(),
            workout: workoutService,
            exercise: exerciseService,
            user: userService,
            healthKit: MockHealthKitService(),
            notification: MockNotificationService(),
            subscription: MockSubscriptionService()
        )
    }
}

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: ServiceContainer? = nil
}

extension EnvironmentValues {
    var services: ServiceContainer? {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
