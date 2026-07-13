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
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        // The full deterministic pipeline (US-C01…US-C07) runs through `SessionAssembly`, which
        // chains Steps 1-6 and assembles a timing-fit, fully-formed `Workout`. Routing the mock
        // through the canonical assembler keeps it in lockstep with the real engine.
        //
        // `sessionPolicy` is threaded through the assembler (US-E03): its `pillarWeighting`,
        // `varietyWindow`, and `progressionRate` levers reach Steps 2/5/6. With `SessionPolicy.default`
        // (every lever neutral) that is a no-op, so output is identical to pre-policy behavior.
        let library = try await exerciseService.exercises()
        return SessionAssembly.assemble(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: Date()
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        // The deterministic swap (US-C08) runs through `ExerciseSwap`, drawing substitutes from the
        // same validated library the assembler uses so the swap stays in lockstep with the engine.
        let library = try await exerciseService.exercises()
        return ExerciseSwap.swap(
            prescription,
            in: workout,
            user: user,
            library: library,
            recentLogs: recentLogs
        )
    }
}

// MARK: - Session policy

/// The MVP-shell session-policy service: always hands back the neutral `SessionPolicy.default`
/// and never reports a due trigger, so the engine runs exactly as it did before policies
/// existed. The real, persistence-backed deterministic Programmer (trigger detection in US-F01,
/// re-weighting in US-F03) replaces this by swapping one line in `ServiceContainer`.
final class MockSessionPolicyService: SessionPolicyServiceProtocol {
    func currentPolicy(for user: User) async throws -> SessionPolicy {
        .default
    }

    func seedInitialPolicy(for user: User) async throws -> SessionPolicy {
        // The stateless mock persists nothing; it just hands back the seeded policy so callers and
        // tests see the cold-start contract onboarding would install (US-I01/US-G01).
        .seeded(forFitnessLevel: user.profile.fitnessLevel)
    }

    func reprogram(
        user: User,
        recentLogs: [WorkoutLog],
        trigger: ReprogramTrigger
    ) async throws -> SessionPolicy {
        // The mock never re-programs; it returns the neutral default so behavior is unchanged.
        // Real deterministic re-weighting (version bump, `updatedBy == .deterministic`) is US-F03.
        .default
    }

    func dueTriggers(
        user: User,
        recentLogs: [WorkoutLog],
        asOf: Date
    ) async throws -> [ReprogramTrigger] {
        // No triggers ever fire in the mock - real detection lands in US-F01.
        []
    }
}

// MARK: - Consistency
//
// The real Consistency Score is `ConsistencyScoreService` (US-H01, `Services/Consistency/`); the
// mock was retired once the forgiving evaluator replaced it.

// MARK: - Phase
//
// The real `PhaseEvaluator` is `PhaseEvaluatorService` (US-H02, `Services/Consistency/`); the mock
// was retired once the deterministic evaluator replaced it.

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
        // No-op: the mock container never touches Health. The real write-only integration is
        // `HealthKitService` (US-N03), wired in `ServiceContainer.live(context:)`.
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

    func completeSignIn(identifier: String) async throws {
        userIdentifier = identifier
    }

    func signOut() async throws {
        userIdentifier = nil
    }
}
