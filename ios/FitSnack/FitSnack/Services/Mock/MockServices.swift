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
    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> Workout {
        // Pipeline Step 1 (US-C01): derive the shape from the requested minutes, then
        // Step 2 (US-C02): balance pillars by staleness. Both flow through the canonical
        // engine selectors so the mock and the real engine stay in lockstep.
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)
        let pillarPlan = PillarPlan.select(
            template: template,
            recentLogs: recentLogs,
            profile: user.profile,
            asOf: Date()
        )
        let focusPillar: Pillar?
        switch pillarPlan {
        case .single(let pillar): focusPillar = pillar
        case .blend: focusPillar = nil
        }

        return Workout(
            id: UUID(),
            createdAt: Date(),
            shape: template.shape,
            focusPillar: focusPillar,
            requestedMinutes: requestedMinutes,
            blocks: []
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
