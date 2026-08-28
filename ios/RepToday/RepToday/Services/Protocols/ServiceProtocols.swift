import Foundation

/// The authorization state Rep Today needs from HealthKit.
///
/// Rep Today writes (shares) workouts only, so this mirrors the *sharing* authorization the real
/// `HealthKitService` (US-N03) reports; `MockHealthKitService` returns `.notDetermined`.
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
    ///
    /// `sessionPolicy` is the same program the session was generated against, so the substitute is
    /// sized by the same Step 6 levers as the rest of the lineup - `progressionRate`, the cold-start
    /// Start Seed (US-O02, at the assembler's own strength/primal scope), `varietyWindow`, and the
    /// Return / Re-entry Ramp ease (US-E06, read off the session's own `wasReturn` stamp rather than
    /// re-derived against a fresh clock) - instead of silently reverting to the neutral defaults.
    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
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
    /// Difficulty capped from `user.profile.fitnessLevel` and the cold-start strength lead forced on (US-004).
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

    /// The component earn signals behind that decision (US-SP04): weeks-sustained and per-foundation
    /// cleared flags, from the *same* `PhaseEvaluator` logic `phase(for:recentLogs:)` gates on, so a
    /// progress surface shows exactly what the gate decides. `hasEarnedStrength` on the result equals
    /// `phase(for:recentLogs:) == .strength`.
    func progress(for user: User, recentLogs: [WorkoutLog]) async throws -> PhaseProgress
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
    /// Bulk-deletes every workout log for account deletion (US-AD02/US-AD03), then saves so the
    /// CloudKit mirror propagates the tombstones. Rep Today has exactly one local user and
    /// `CDWorkoutLog` carries no owner column, so this clears the whole history without needing a
    /// decodable user id - matching its sibling teardown deletes (`SessionPolicyStore.deleteAll()`,
    /// `ActiveSessionStore.clearAll()`). A no-op (never an error) when there are no logs.
    func deleteAllLogs() async throws
}

/// Coordinates HealthKit authorization and workout writes.
protocol HealthKitServiceProtocol {
    func authorizationStatus() async throws -> HealthKitAuthorizationStatus
    func requestAuthorization() async throws -> HealthKitAuthorizationStatus
    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws
}

/// Reads and refreshes premium entitlement state, and drives the paywall (US-N04).
///
/// The entitlement methods (`currentSubscription`/`refreshEntitlements`) resolve the local premium
/// state that gates the US-M02 depth layer; the free tier is unlimited core workouts forever, so
/// nothing here ever gates the core loop. The paywall methods load purchasable plans and buy a
/// selected one; `purchasePremium()` is the plan-agnostic convenience (the primary monthly plan).
protocol SubscriptionServiceProtocol {
    func currentSubscription() async throws -> Subscription
    func refreshEntitlements() async throws -> Subscription
    /// The purchasable premium plans for the paywall, priced and ordered (monthly first).
    func premiumPlans() async throws -> [SubscriptionPlan]
    /// Purchase a specific plan chosen on the paywall; returns the outcome so the paywall can tell a
    /// resolved purchase apart from one still awaiting approval (Ask to Buy).
    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome
    func purchasePremium() async throws -> Subscription
    func restorePurchases() async throws -> Subscription
    /// Begin observing StoreKit's out-of-band transaction updates (auto-renewals, refunds,
    /// cross-device purchases, deferred Ask-to-Buy approvals), finishing each so it never lingers
    /// in the queue; the entitlement-gated surfaces pick up the change on their next read. Called
    /// once at launch, retained for the app's lifetime. Never gates the core loop; the mock and
    /// any StoreKit-free implementation default to an immediately-completing no-op.
    @discardableResult
    func startObservingTransactions() -> Task<Void, Never>
}

extension SubscriptionServiceProtocol {
    /// Default no-op listener: only the real StoreKit service (US-N04) overrides this, so mocks,
    /// previews, and test stubs stay StoreKit-free and deterministic.
    @discardableResult
    func startObservingTransactions() -> Task<Void, Never> { Task {} }
}

/// Records anonymous product-telemetry events (US-T02).
///
/// The single emission method is the funnel-instrumentation seam: every later story emits the 13
/// pre-registered events (the event-metric schema) through this one interface, and
/// tests assert on `MockAnalyticsService`'s in-memory record with no network. `record(_:)` is
/// `async` but **not** `throws` - unlike the rest of this file's `async throws` house style - because
/// emission is strictly fire-and-forget: a call site reads `await analytics.record(event)` with no
/// `try`, and a failed, slow, or offline send is swallowed by `LiveAnalyticsService` (US-T04),
/// never surfaced to a caller and never allowed to gate the core loop. The first production caller
/// landed in US-T07 - `RepTodayApp.init()` emits the three app-entry events through
/// `AppEntryTelemetry` - and the other 10 of the 13 emission sites landed across US-T08 through
/// US-T12, so all 13 events now have their emission sites;
/// US-T06's `#if DEBUG`, launch-argument-gated `TelemetryUITestHarness` also calls this, with its
/// events intercepted in process.
///
/// **A call site never checks consent.** The user's opt-out (US-T06, `AppState.analyticsEnabled`)
/// is enforced inside `LiveAnalyticsService.record(_:)`, which re-reads it per emission, so an
/// emission site calls this unconditionally and an opted-out install simply produces no request.
/// Re-reading the flag at a call site would be a second gate that could disagree with the first.
/// `MockAnalyticsService` deliberately has no gate at all: it records everything, because a test
/// asserting on emission wants the event, not the consent decision.
///
/// That rule says where the one gate lives; it does not make the gate structural. Consent is
/// enforced inside `LiveAnalyticsService.record(_:)`, so the privacy invariant is a property of
/// **that implementation** rather than of this protocol: a second emitting sink would have to
/// re-implement it from memory, and neither the type system nor any existing test would catch its
/// absence. The rule above still stands either way - a call site must not check consent itself, and
/// none of this is a hint to start. The trigger is written as a condition to check rather than a
/// caveat, so a reader can answer it by looking instead of by judgement: **count the emitting
/// conformers of this protocol.** Today there is exactly one. `NoOpAnalyticsService` discards,
/// `MockAnalyticsService` records in memory, and the Debug-only probe harness intercepts in process,
/// so none of them can reach the network. If that count is ever greater than one while the gate
/// still lives inside a concrete sink - a batching queue, a retry wrapper, a secondary transport -
/// the decorator is already overdue: the gate moves to a `ConsentGatedAnalyticsService` applied once
/// in `ServiceContainer.live`, so it holds for any sink rather than for one. A trigger that depends
/// on somebody noticing a defect is the weaker kind, which is why this one is a count. The item is
/// filed in firstmate's work queue as well, so the sequencing does not rest on this paragraph.
protocol AnalyticsServiceProtocol {
    func record(_ event: AnalyticsEvent) async
}

/// Handles Sign in with Apple identity.
protocol AuthServiceProtocol {
    func currentUserIdentifier() async throws -> String?
    func signInWithApple() async throws -> String
    /// Persists an externally-obtained Sign in with Apple identifier (e.g. from the official
    /// `SignInWithAppleButton`'s completion), so the identity keys the user record just as
    /// `signInWithApple()`'s programmatic path would.
    func completeSignIn(identifier: String) async throws
    func signOut() async throws
}
