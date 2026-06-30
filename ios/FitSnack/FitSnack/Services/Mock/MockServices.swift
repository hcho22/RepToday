import Foundation

/// Mock service implementations wired for the US-A05 app shell.
///
/// These are intentionally small and deterministic. Later stories replace individual
/// mocks with real services by changing the corresponding line in `ServiceContainer`.
///
/// The exercise service is the exception: the real bundled-library loader already lives in
/// `MockExerciseService` (US-B02, `Services/Mock/MockExerciseService.swift`).

// MARK: - Workout engine

final class MockWorkoutEngine: WorkoutEngineProtocol {
    /// The validated catalog is the engine's exercise source; pulling it from the exercise service
    /// keeps a single, integrity-checked source of truth rather than re-loading the library here.
    private let exerciseService: any ExerciseServiceProtocol

    init(exerciseService: any ExerciseServiceProtocol) {
        self.exerciseService = exerciseService
    }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> Workout {
        // The full deterministic pipeline (US-C01…US-C07) runs through `SessionAssembly`, which
        // chains Steps 1-6 and assembles a timing-fit, fully-formed `Workout`. Routing the mock
        // through the canonical assembler keeps it in lockstep with the real engine.
        let library = try await exerciseService.exercises()
        return SessionAssembly.assemble(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            asOf: Date()
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> PrescribedExercise {
        prescription
    }
}

// MARK: - Consistency

final class MockConsistencyService: ConsistencyServiceProtocol {
    func consistency(for logs: [WorkoutLog], weeklyGoal: Int) async throws -> Consistency {
        let completedMinutes = logs.reduce(0) { $0 + $1.durationMinutes }
        return Consistency(
            weeklyGoal: weeklyGoal,
            score: logs.isEmpty ? 0 : 100,
            workoutsThisWeek: logs.count,
            longestChain: logs.isEmpty ? 0 : 1,
            totalWorkoutsCompleted: logs.count,
            totalMinutesExercised: completedMinutes
        )
    }

    func updatedConsistency(after log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws -> Consistency {
        try await consistency(for: recentLogs + [log], weeklyGoal: user.consistency.weeklyGoal)
    }
}

// MARK: - Phase

final class MockPhaseService: PhaseServiceProtocol {
    func phase(for user: User, recentLogs: [WorkoutLog]) async throws -> Phase {
        .discipline
    }
}

// MARK: - User

actor MockUserService: UserServiceProtocol {
    private var user: User?

    init(user: User? = nil) {
        self.user = user
    }

    func currentUser() async throws -> User? {
        user
    }

    func save(_ user: User) async throws {
        self.user = user
    }

    func deleteCurrentUser() async throws {
        user = nil
    }
}

// MARK: - Workout logs

actor MockWorkoutLogService: WorkoutLogServiceProtocol {
    private var logs: [WorkoutLog]

    init(logs: [WorkoutLog] = []) {
        self.logs = logs
    }

    func workoutLogs(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutLog] {
        logs
            .filter { log in
                let startsInRange = startDate.map { log.completedAt >= $0 } ?? true
                let endsInRange = endDate.map { log.completedAt < $0 } ?? true
                return startsInRange && endsInRange
            }
            .sorted { $0.completedAt < $1.completedAt }
    }

    func save(_ log: WorkoutLog) async throws {
        logs.removeAll { $0.id == log.id }
        logs.append(log)
    }

    func deleteLog(id: UUID) async throws {
        logs.removeAll { $0.id == id }
    }
}

// MARK: - HealthKit

final class MockHealthKitService: HealthKitServiceProtocol {
    func authorizationStatus() async throws -> HealthKitAuthorizationStatus {
        .notDetermined
    }

    func requestAuthorization() async throws -> HealthKitAuthorizationStatus {
        .notDetermined
    }

    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws {
        // No-op until US-J03 wires HealthKit.
    }
}

// MARK: - Subscription

final class MockSubscriptionService: SubscriptionServiceProtocol {
    private let subscription: Subscription

    init(
        subscription: Subscription = Subscription(
            tier: .free,
            provider: .apple,
            expiresAt: nil,
            trialEndsAt: nil
        )
    ) {
        self.subscription = subscription
    }

    func currentSubscription() async throws -> Subscription {
        subscription
    }

    func refreshEntitlements() async throws -> Subscription {
        subscription
    }

    func purchasePremium() async throws -> Subscription {
        subscription
    }

    func restorePurchases() async throws -> Subscription {
        subscription
    }
}

// MARK: - Auth

actor MockAuthService: AuthServiceProtocol {
    private var userIdentifier: String?

    init(userIdentifier: String? = nil) {
        self.userIdentifier = userIdentifier
    }

    func currentUserIdentifier() async throws -> String? {
        userIdentifier
    }

    func signInWithApple() async throws -> String {
        let id = userIdentifier ?? "mock-apple-user"
        userIdentifier = id
        return id
    }

    func signOut() async throws {
        userIdentifier = nil
    }
}
