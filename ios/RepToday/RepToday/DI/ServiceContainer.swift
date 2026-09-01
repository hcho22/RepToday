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
    /// Erases the user's on-device account (US-AD03): the App Store 5.1.1(v) deletion path behind the
    /// Settings "Delete Account" control. Composes the same user/log/policy/active-session/auth seams
    /// this container already wires, so a delete clears exactly what the rest of the app reads.
    let accountDeletionService: any AccountDeletionServiceProtocol
    /// The premium AI coach transport (US-AC02), `nil` when no coach proxy is configured for this
    /// build - which is every build today, because the `proxy/` Worker is deploy-ready but not yet
    /// deployed. The coach chat surface reads this and, when it is `nil`, shows a clear "coach
    /// unavailable" state; it never gates or blocks the core loop. `live(...)` resolves it once from
    /// the build-configured `Info.plist` origin (`CoachProxyClient.configured(...)`), exactly like the
    /// telemetry sink; `mock()` leaves it `nil`. Unlike the other services this is genuinely optional -
    /// the coach is a best-effort upgrade, never a dependency - so it carries an initializer default.
    let coachClient: CoachProxyClient?
    /// The sovereign on-device write path for a coach-sourced `SessionPolicy` nudge (US-AC07). It writes
    /// through the **same** `SessionPolicyStore` as the deterministic Programmer (`sessionPolicyService`),
    /// so the two writers share one in-force policy and the coach's bounded, preference-only overlay can
    /// never clobber a deterministic safety move (ADR-0005). Reachable only from the premium, disclosure-
    /// gated coach surface; it never gates or blocks the core loop. `mock()`/`live()` wire it from the
    /// shared store; a container built without one simply cannot tune from the coach (the chat still talks),
    /// so it carries an initializer default like `coachClient`.
    let coachPolicyService: (any CoachPolicyServiceProtocol)?

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
        analyticsService: any AnalyticsServiceProtocol,
        accountDeletionService: any AccountDeletionServiceProtocol,
        coachClient: CoachProxyClient? = nil,
        coachPolicyService: (any CoachPolicyServiceProtocol)? = nil
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
        self.accountDeletionService = accountDeletionService
        self.coachClient = coachClient
        self.coachPolicyService = coachPolicyService
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
        // In-memory active-session store and mock auth, held as locals so the account-deletion
        // service (US-AD03) tears down the very instances this container exposes, rather than a
        // second copy a delete would leave the app still reading from.
        let activeSessionStore = InMemoryActiveSessionStore()
        let authService = MockAuthService()
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
            activeSessionStore: activeSessionStore,
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
            authService: authService,
            // The in-memory telemetry sink (US-T02): records events for test assertions, no I/O.
            analyticsService: MockAnalyticsService(),
            // The account-deletion orchestrator (US-AD03), composed over the same in-memory user, log,
            // policy, active-session, and auth seams this container exposes, so a delete from Settings
            // clears exactly what previews and tests read back.
            accountDeletionService: AccountDeletionService(
                userService: userService,
                workoutLogService: workoutLogService,
                sessionPolicyStore: policyStore,
                activeSessionStore: activeSessionStore,
                authService: authService
            ),
            // The coach's bounded policy-write path (US-AC07), over the same shared in-memory policy store
            // as the deterministic Programmer above, so both writers share one in-force policy.
            coachPolicyService: CoachSessionPolicyService(store: policyStore)
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
    ///   - installId: The launch-time anonymous per-install identifier (US-T05), used as the fixed
    ///     fallback by tests and callers that do not pass `analyticsInstallId`. It is passed in
    ///     rather than resolved here because
    ///     `AppState.init` is the *only* thing that mints it and decides which of the three launch
    ///     states an install is in; a second resolution path could disagree with the first about
    ///     whether an install is new. `RepTodayApp.init()` therefore builds `AppState` first and
    ///     hands its id down. Callers other than the app (tests) pass a fixed id.
    ///   - analyticsInstallId: The production per-emission reader from `AppState`. Account deletion
    ///     rotates the persisted value while this container stays alive, so the transport must read
    ///     it again for the next event instead of freezing `installId` at launch.
    ///   - analyticsService: The telemetry sink, `nil` (the default, and what the app passes by
    ///     omitting it) meaning "resolve production's own". The seam exists so that a test building
    ///     this container for reasons unrelated to telemetry - it is the only way to get the
    ///     CoreData-backed services composed - can substitute an inert sink and be structurally
    ///     unable to reach the network, rather than relying on no emission call site existing yet.
    ///     Now that US-T07 through US-T12 have added those call sites, "no test performs a real
    ///     network call" (FR-13) is held here by the code instead of by discipline - but only for tests running
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
        analyticsInstallId: (@Sendable () -> String)? = nil,
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
        // The CoreData active-session store (US-K04) and the real Keychain-backed Sign in with Apple
        // (US-N01), held as locals so the account-deletion service (US-AD03) clears the very
        // active-session record and Keychain identifier this container exposes - the `CDActiveSession`
        // row in the device-local store and the Keychain item that outlives a reinstall.
        let activeSessionStore = CoreDataActiveSessionStore(context: context)
        let authService = AppleAuthService.live()
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
        // transport when the endpoint and shared token are configured (Debug and a privately-injected
        // Release archive), or the inert no-op when either value is missing.
        let resolvedAnalyticsService: any AnalyticsServiceProtocol = analyticsService
            ?? LiveAnalyticsService.configured(
                installId: analyticsInstallId ?? { installId },
                session: analyticsSession,
                isEnabled: analyticsGate
            )
            ?? NoOpAnalyticsService()
        // The premium coach transport (US-AC02), resolved once from the build-configured `POST /coach`
        // origin exactly like the telemetry sink. `nil` today (no proxy deployed and no origin set), so
        // the coach surface renders its "unavailable" state; it never gates the core loop.
        let resolvedCoachClient = CoachProxyClient.configured()
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
            activeSessionStore: activeSessionStore,
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
            authService: authService,
            // The same telemetry sink resolved above (`resolvedAnalyticsService`), so the container and
            // the completion recorder's `week_active` emission (US-T11) share one instance and one
            // consent gate. It is the live Convex-backed transport (US-T04) when an endpoint is
            // fully configured (Debug and a privately-injected Release archive), the inert no-op when
            // either value is missing, or an explicit override a test passed. All emission
            // sites US-T07 through US-T12 have landed (app entry, onboarding, Ready Screen, session
            // lifecycle, weekly rollup, and the paywall funnel), so all 13 events now emit.
            analyticsService: resolvedAnalyticsService,
            // The account-deletion orchestrator (US-AD03), over the same CoreData user/log/policy and
            // device-local active-session stores plus the Keychain-backed auth this container wires -
            // so a delete tombstones the CloudKit-mirrored records, drops the local active session,
            // and clears the reinstall-surviving Keychain identifier in one pass.
            accountDeletionService: AccountDeletionService(
                userService: userService,
                workoutLogService: workoutLogService,
                sessionPolicyStore: policyStore,
                activeSessionStore: activeSessionStore,
                authService: authService
            ),
            // The build-configured premium coach transport (US-AC02); nil until a proxy origin is set.
            coachClient: resolvedCoachClient,
            // The coach's bounded policy-write path (US-AC07), over the same shared `CoreDataSessionPolicyStore`
            // as the deterministic Programmer, so a coach nudge and a deterministic re-program write one
            // in-force policy and the engine reads whichever landed last on the next open.
            coachPolicyService: CoachSessionPolicyService(store: policyStore)
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
