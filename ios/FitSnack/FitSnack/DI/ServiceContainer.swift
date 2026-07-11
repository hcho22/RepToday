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
    let sessionPolicyService: any SessionPolicyServiceProtocol
    let consistencyService: any ConsistencyServiceProtocol
    let phaseService: any PhaseServiceProtocol
    let userService: any UserServiceProtocol
    let workoutLogService: any WorkoutLogServiceProtocol
    let activeSessionStore: any ActiveSessionStore
    /// Records a finished session (US-L01): writes the log and does the post-session bookkeeping.
    let sessionCompletionService: any SessionCompletionServiceProtocol
    let healthKitService: any HealthKitServiceProtocol
    let subscriptionService: any SubscriptionServiceProtocol
    let authService: any AuthServiceProtocol

    init(
        exerciseService: any ExerciseServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol,
        phaseService: any PhaseServiceProtocol,
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        activeSessionStore: any ActiveSessionStore,
        sessionCompletionService: any SessionCompletionServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        subscriptionService: any SubscriptionServiceProtocol,
        authService: any AuthServiceProtocol
    ) {
        self.exerciseService = exerciseService
        self.workoutEngine = workoutEngine
        self.sessionPolicyService = sessionPolicyService
        self.consistencyService = consistencyService
        self.phaseService = phaseService
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.activeSessionStore = activeSessionStore
        self.sessionCompletionService = sessionCompletionService
        self.healthKitService = healthKitService
        self.subscriptionService = subscriptionService
        self.authService = authService
    }

    static func mock() -> ServiceContainer {
        // The bundled exercise library is integrity-gated by `ExerciseLibraryTests` and
        // `ExerciseServiceTests`, so a load/validation failure here is a build-time defect,
        // not a runtime condition - `try!` makes that surface loudly instead of silently
        // shipping an empty catalog.
        let exerciseService = try! MockExerciseService()
        // A single user service is shared so the deterministic Programmer (US-F03) can persist its
        // learned Default Duration back onto the same user aggregate the rest of the app reads.
        let userService = MockUserService()
        // A single policy store is shared between the Programmer (which writes re-programs) and the
        // session-completion service (which writes the cold-start handoff's reconciled policy, US-G04),
        // so both read and write the same in-force policy.
        let policyStore = InMemorySessionPolicyStore()
        // The real forgiving, Return-protected Consistency Score (US-H01) in place of the mock; a pure
        // evaluator over the log history, shared by the Ready Screen and the completion recorder.
        let consistencyService = ConsistencyScoreService()
        // A single log service so a session written by the completion recorder (US-L01) is the same
        // history the Ready Screen and the Programmer read back.
        let workoutLogService = MockWorkoutLogService()
        return ServiceContainer(
            exerciseService: exerciseService,
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService),
            // The real on-device deterministic Programmer (US-F03), backed by the shared in-memory
            // policy store so the mock container stays deterministic and disk-free. It returns
            // `SessionPolicy.default` until it has written a policy, so pre-programming behavior
            // (and `ServiceContainerTests`) is unchanged.
            sessionPolicyService: DeterministicSessionPolicyService(
                store: policyStore,
                exerciseService: exerciseService,
                userService: userService
            ),
            consistencyService: consistencyService,
            // The real deterministic `PhaseEvaluator` (US-H02) in place of `MockPhaseService`; it
            // reads the validated library from the exercise service to gate competence and stays
            // deterministic given a fixed clock. All MVP users resolve to `.discipline` until they
            // earn Strength (sustained consistency + cleared foundational entry tiers).
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
            userService: userService,
            workoutLogService: workoutLogService,
            // In-memory active-session store (US-K04), consistent with the other in-memory stores in
            // the mock container: an abandoned session is resumable within a run and can be resumed or
            // discarded from the Ready Screen. `CoreDataActiveSessionStore` (tested in isolation) is
            // ready to be swapped in for true cross-relaunch survival when the production CoreData
            // container is wired (US-N02), alongside the CoreData user/log/policy stores.
            activeSessionStore: InMemoryActiveSessionStore(),
            // Records a finished session (US-L01): writes the log and does the post-session bookkeeping
            // (Consistency Score refresh, cold-start handoff) over the same user, log, and policy stores
            // the rest of the container reads, so the win is durable and reflected everywhere.
            sessionCompletionService: SessionCompletionService(
                workoutLogService: workoutLogService,
                userService: userService,
                consistencyService: consistencyService,
                policyStore: policyStore
            ),
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
