import Foundation

/// The authorization state FitSnack needs from HealthKit.
///
/// The real HealthKit implementation lands in US-J03. Until then, mock services return
/// `.notDetermined` so the rest of the app can depend on a stable protocol surface.
enum HealthKitAuthorizationStatus: Equatable {
    case notDetermined
    case sharingDenied
    case sharingAuthorized
}

/// Loads and queries the bundled exercise catalog.
///
/// The implementation loads `Exercises.json` once, integrity-checks it (US-B02), and caches
/// the result; a malformed library fails loudly at load rather than producing subtly wrong
/// sessions later. The query helpers are the surface the engine (Epic C) builds sessions from.
protocol ExerciseServiceProtocol {
    func exercises() async throws -> [Exercise]
    func exercise(id: String) async throws -> Exercise?
    func exercises(for pillar: Pillar) async throws -> [Exercise]
    func exercises(for movementPattern: MovementPattern) async throws -> [Exercise]
    func exercises(for phase: Phase) async throws -> [Exercise]
    /// Movements whose `difficulty` falls inside `range` (used to apply a fitness-level cap).
    func exercises(inDifficultyRange range: ClosedRange<Int>) async throws -> [Exercise]
    /// The next movement up the progression chain from the exercise with `id`, or `nil` when
    /// `id` is unknown or already sits at the top of its chain.
    func nextInChain(after id: String) async throws -> Exercise?
}

/// Generates complete workouts and deterministic in-session swaps.
protocol WorkoutEngineProtocol {
    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> Workout

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> PrescribedExercise
}

/// Calculates the forgiving consistency score from completed workouts.
protocol ConsistencyServiceProtocol {
    func consistency(for logs: [WorkoutLog], weeklyGoal: Int) async throws -> Consistency
    func updatedConsistency(after log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws -> Consistency
}

/// Evaluates which journey phase a user has earned.
protocol PhaseServiceProtocol {
    func phase(for user: User, recentLogs: [WorkoutLog]) async throws -> Phase
}

/// Reads and writes the current user aggregate.
protocol UserServiceProtocol {
    func currentUser() async throws -> User?
    func save(_ user: User) async throws
    func deleteCurrentUser() async throws
}

/// Reads and writes completed workout logs.
protocol WorkoutLogServiceProtocol {
    func workoutLogs(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutLog]
    func save(_ log: WorkoutLog) async throws
    func deleteLog(id: UUID) async throws
}

/// Coordinates HealthKit authorization and workout writes.
protocol HealthKitServiceProtocol {
    func authorizationStatus() async throws -> HealthKitAuthorizationStatus
    func requestAuthorization() async throws -> HealthKitAuthorizationStatus
    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws
}

/// Reads and refreshes premium entitlement state.
protocol SubscriptionServiceProtocol {
    func currentSubscription() async throws -> Subscription
    func refreshEntitlements() async throws -> Subscription
    func purchasePremium() async throws -> Subscription
    func restorePurchases() async throws -> Subscription
}

/// Handles Sign in with Apple identity.
protocol AuthServiceProtocol {
    func currentUserIdentifier() async throws -> String?
    func signInWithApple() async throws -> String
    func signOut() async throws
}
