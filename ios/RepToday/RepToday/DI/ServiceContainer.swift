import CoreData
import SwiftUI

/// App-wide service registry.
///
/// Views read this from `@Environment(\.services)`, and view models receive the service
/// values they need from views. Replacing an implementation is localized here: change the
/// matching argument in `mock()` (or the production `live(...)` factory) from `Mock...`
/// to the real service.
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
    /// The anonymous product-telemetry sink (US-T02; live transport at US-T04). Additive and never
    /// gates the core loop, but it carries no initializer default: every construction site wires it
    /// explicitly, like every other service here, so a container built without a sink is a build
    /// error rather than silent data loss.
    let analyticsService: any AnalyticsServiceProtocol

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
        authService: any AuthServiceProtocol,
        analyticsService: any AnalyticsServiceProtocol
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
        self.analyticsService = analyticsService
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
            authService: MockAuthService(),
            // The in-memory telemetry sink (US-T02): records events for test assertions, no I/O.
            analyticsService: MockAnalyticsService()
        )
    }

    /// Production wiring (US-N02): the same real services as `mock()`, but backed by the
    /// CloudKit-enabled CoreData stack rather than in-memory stores, so the user, their
    /// history, and the in-force policy persist across relaunch and sync across devices, while
    /// the transient active session stays on-device (the `Local` store configuration).
    ///
    /// The one shared `context` (the app's `viewContext`) backs every CoreData store, and a
    /// single `CoreDataSessionPolicyStore` / user / log / consistency service is shared between
    /// the Programmer, the Ready Screen, and the completion recorder, so a written session is
    /// the same history everyone reads back - exactly as `mock()` shares its in-memory stores.
    ///
    /// Subscription is the real StoreKit 2 service (US-N04), HealthKit is the real write-only
    /// integration (US-N03), and auth is the real Keychain-backed Sign in with Apple (US-N01).
    ///
    /// - Parameters:
    ///   - installId: The anonymous per-install identifier (US-T05), which the telemetry
    ///     transport puts on every event. It is passed in rather than resolved here because
    ///     `AppState.init` is the *only* thing that mints it and decides which of the three launch
    ///     states an install is in; a second resolution path could disagree with the first about
    ///     whether an install is new. `RepTodayApp.init()` therefore builds `AppState` first and
    ///     hands its id down. Callers other than the app (tests) pass a fixed id.
    ///   - analyticsService: The telemetry sink, `nil` (the default, and what the app passes by
    ///     omitting it) meaning "resolve production's own". The seam exists so that a test building
    ///     this container for reasons unrelated to telemetry - it is the only way to get the
    ///     CoreData-backed services composed - can substitute an inert sink and be structurally
    ///     unable to reach the network, rather than relying on no emission call site existing yet.
    ///     Once US-T07 through US-T12 add those call sites, "no test performs a real network call"
    ///     (FR-13) is held here by the code instead of by discipline - but only for tests running
    ///     *in this process*. `RepTodayUITests` launches the real app out of process, which builds
    ///     its own container from the defaults below, so nothing passed here reaches it; that half
    ///     now rests on `LiveAnalyticsService`'s `isEnabled` gate, which US-T06 pointed at
    ///     `AppState.analyticsEnabled` - a persisted flag the `-AppState.analyticsEnabled NO` launch
    ///     argument overrides. Read that as one of two mechanisms rather than as universally applied:
    ///     `OnboardingImperialUITests` passes it on every launch, while `TelemetryOptOutUITests`
    ///     passes it only where being opted out *is* the assertion and holds its opted-in legs off
    ///     the wire by **interception** instead - the probe harness swaps the transport's
    ///     `URLSession` for an in-process counting `URLProtocol`, so those launches need the gate
    ///     genuinely open and are safe anyway. That suite's invariant is therefore not "consent is
    ///     always off" but "consent off **or** the probe armed", and it holds by construction *for
    ///     launches that go through the helper*: the sole `TestApp` wrapper
    ///     (`RepTodayUITests/TestApp.swift`) owns the only `XCUIApplication`, and its one launch entry
    ///     point takes a `TelemetryPosture` by value - an enum with no case meaning neither - so a
    ///     launch that names no posture is not expressible through the suite's API. Because
    ///     `XCUIApplication` is a framework type any file can still construct, that guarantee is
    ///     "cannot ship a bypass" rather than "cannot type one": `UITestLaunchGuardTests`
    ///     (`RepTodayTests/UITestLaunchGuardTests.swift`, in the unit bundle) scans every
    ///     `RepTodayUITests` source and fails the routinely-run `-scheme RepToday test` gate if
    ///     `XCUIApplication(` is constructed anywhere but `TestApp.swift`.
    ///   - analyticsGate: The opt-out gate (US-T06), read fresh per emission. Passed down for the
    ///     same reason `installId` is: `AppState` owns the flag, so the app hands over a gate bound
    ///     to the store its own `AppState` writes rather than letting this side re-derive which
    ///     store to read. The default reads `.standard`, which is where production's `AppState`
    ///     lives, so a test that only wants the CoreData services keeps its existing call.
    static func live(
        context: NSManagedObjectContext,
        installId: String,
        analyticsGate: @escaping @Sendable () -> Bool = AppState.analyticsGate(),
        analyticsService: (any AnalyticsServiceProtocol)? = nil
    ) -> ServiceContainer {
        // The bundled exercise library is integrity-gated at load; a failure here is a build-time
        // defect, so `try!` surfaces it loudly rather than shipping an empty catalog.
        let exerciseService = try! MockExerciseService()
        let userService = CoreDataUserService(context: context)
        let workoutLogService = CoreDataWorkoutLogService(context: context)
        // One policy store shared by the Programmer (re-programs) and the completion recorder
        // (the cold-start handoff's reconciled policy, US-G04).
        let policyStore = CoreDataSessionPolicyStore(context: context)
        let consistencyService = ConsistencyScoreService()
        // The real write-only HealthKit integration (US-N03): mirrors each completed session into
        // Health, resolving MET values from the exercise catalog for the energy estimate. Shared so the
        // completion recorder writes through the same instance exposed on the container.
        let healthKitService = HealthKitService(exerciseService: exerciseService)
        // The telemetry transport keeps its own session in every ordinary build. The one exception is
        // an XCUITest run launched with the US-T06 probe argument, where it is swapped for an
        // in-process counting interceptor so an out-of-process test can observe the opt-out gate
        // without a single byte leaving the app (`TelemetryUITestHarness`). `nil` means "keep your
        // own", so nothing about the production path changes.
        let analyticsSession: URLSession?
        #if DEBUG
        analyticsSession = TelemetryUITestHarness.interceptingSession()
        #else
        analyticsSession = nil
        #endif
        // Resolve the telemetry sink once, so the completion recorder's `week_active` emission (US-T11)
        // and the container's own sink are the same instance and share the consent gate. An explicit
        // `analyticsService` overrides the build-configured resolution; otherwise it is the live
        // transport when an endpoint is configured (Debug) and the inert no-op when it is not (Release
        // today), so a Release build's completion path stays silent exactly like every other site.
        let resolvedAnalyticsService: any AnalyticsServiceProtocol = analyticsService
            ?? LiveAnalyticsService.configured(
                installId: installId,
                session: analyticsSession,
                isEnabled: analyticsGate
            )
            ?? NoOpAnalyticsService()
        return ServiceContainer(
            exerciseService: exerciseService,
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService),
            sessionPolicyService: DeterministicSessionPolicyService(
                store: policyStore,
                exerciseService: exerciseService,
                userService: userService
            ),
            consistencyService: consistencyService,
            phaseService: PhaseEvaluatorService(exerciseService: exerciseService),
            userService: userService,
            workoutLogService: workoutLogService,
            // The CoreData active-session store: an abandoned session now survives a full
            // relaunch (it lives in the device-local `Local` store, never synced).
            activeSessionStore: CoreDataActiveSessionStore(context: context),
            sessionCompletionService: SessionCompletionService(
                workoutLogService: workoutLogService,
                userService: userService,
                consistencyService: consistencyService,
                policyStore: policyStore,
                healthKitService: healthKitService,
                // The `week_active` emission site (US-T11): the same resolved sink the container exposes,
                // so consent and destination match every other emission. The emit-once store defaults to
                // `.standard` and the event timestamp is stamped from `log.completedAt`; the cadence
                // buckets in `AppState.cohortCalendar` (the initializer's default), not `Calendar.current`.
                analytics: resolvedAnalyticsService
            ),
            healthKitService: healthKitService,
            // Real StoreKit 2 subscriptions and paywall (US-N04): entitlement drives the US-M02 depth
            // gate; the free tier is unlimited core workouts forever, so nothing here gates the loop.
            subscriptionService: StoreKitSubscriptionService.live(),
            // Real Keychain-backed Sign in with Apple (US-N01).
            authService: AppleAuthService.live(),
            // The same telemetry sink resolved above (`resolvedAnalyticsService`), so the container and
            // the completion recorder's `week_active` emission (US-T11) share one instance and one
            // consent gate. It is the live Convex-backed transport (US-T04) when an endpoint is
            // configured (Debug), the inert no-op when it is not (Release today, with an empty
            // `REPTODAY_ANALYTICS_ENDPOINT`), or an explicit override a test passed. Emission sites
            // US-T07 through US-T11 have landed (app entry, onboarding, Ready Screen, session lifecycle,
            // weekly rollup); US-T12 (the paywall funnel) remains.
            analyticsService: resolvedAnalyticsService
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
