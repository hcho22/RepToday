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
    /// Assembles a complete session. `sessionPolicy` is the per-user program the engine runs
    /// on (US-D04 seam): `SessionPolicy.default` reproduces pre-policy behavior exactly, and
    /// the policy's levers are threaded into the pipeline's Steps 2/5/6 by
    /// `SessionAssembly.assemble` (US-E03).
    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout

    /// Resolves a deterministic substitute for one prescribed slot (US-C08), or `.noAlternative`
    /// when no safe, equivalent, in-budget movement exists - never an unsafe or off-pattern pick.
    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome
}

/// Reads, re-programs, and detects triggers for the per-user Session Policy - the single seam
/// between the AI Programmer (Epic F) and the engine (Epic E).
///
/// The Programmer *writes* a policy and the engine *reads* one; they never otherwise touch, so
/// swapping the mock for the real deterministic Programmer is a one-line change in
/// `ServiceContainer`. The policy is always valid: before the Programmer has ever run,
/// `currentPolicy(for:)` returns `SessionPolicy.default`, so the engine generates sessions
/// offline from day one.
protocol SessionPolicyServiceProtocol {
    /// The policy currently in force for `user` - always valid, `SessionPolicy.default` until
    /// the Programmer has written one (US-D03).
    func currentPolicy(for user: User) async throws -> SessionPolicy

    /// Seeds and persists the starting policy for a freshly onboarded user (US-I01/US-G01):
    /// the neutral `SessionPolicy.default` with a cold-start contract layered on - Starting
    /// Difficulty capped from `user.profile.fitnessLevel` and First-Week Contrast forced on.
    /// Onboarding calls this once, before the first session is generated, so the engine's Step 0
    /// cold-start overrides (US-E04) apply from session one and the contract survives to the next
    /// open. Returns the seeded policy so the caller can generate the first session against it
    /// without a second read.
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy

    /// Writes and returns a fresh policy in response to `trigger`, reading `recentLogs` for
    /// context (US-F03). The version increments and the change is felt on the next open, never
    /// mid-session.
    func reprogram(
        user: User,
        recentLogs: [WorkoutLog],
        trigger: ReprogramTrigger
    ) async throws -> SessionPolicy

    /// The re-program triggers due as of `asOf`, in precedence order (US-F01). Pure and
    /// deterministic for a given `(user, recentLogs, asOf)` - the clock is passed in, never
    /// read inside the logic.
    func dueTriggers(
        user: User,
        recentLogs: [WorkoutLog],
        asOf: Date
    ) async throws -> [ReprogramTrigger]
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
