import CoreData
import XCTest
@testable import RepToday

/// Guards the claim "Airplane mode on. The session still builds."
///
/// Each test drives the cold-open path the app takes - the production `ServiceContainer.live(...)`
/// wiring, `RootView`'s app-open phase reconciliation (`StrengthGraduationViewModel.evaluate()`), then
/// the Ready Screen's `ReadyViewModel.load()` built exactly as `ReadyView` builds it - with every network
/// seam answering the way it does in airplane mode, and asserts a complete session reaches the ready
/// state with no error.
///
/// The network seams, and how each is held offline here:
/// - **Telemetry** (`POST /logEvent`): the real `LiveAnalyticsService` over a `URLSession` whose only
///   protocol fails every request with `URLError(.notConnectedToInternet)` - or, in the not-awaited
///   test, never answers at all.
/// - **Variety Language** (`POST /variety-language`): the production Ready Screen wires no provider, so
///   the line is template-only by construction; one test also wires the real `ProxyVarietyLanguageProvider`
///   over an offline `URLSession` behind a resolver told the network is up, the worst case.
/// - **Coach** (`POST /coach`): not on this path - `ReadyViewModel` takes no coach seam at all.
/// - **Anything on `URLSession.shared`**: a tripwire protocol is registered globally for each test and
///   must see no request, so a future shared-session call on the cold-open path fails here.
///
/// CloudKit mirroring, StoreKit and HealthKit are not URL-loading seams; the in-memory store this suite
/// uses has no CloudKit, so the device-check row in `artifacts/reports/offline-session/validation.md`
/// carries the real-iPhone half of the claim.
@MainActor
final class OfflineSessionGenerationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OfflineFailingURLProtocol.log.reset()
        OfflineHangingURLProtocol.log.reset()
        SharedSessionTripwireURLProtocol.log.reset()
        URLProtocol.registerClass(SharedSessionTripwireURLProtocol.self)
    }

    override func tearDown() {
        // The offline sessions are deliberately not invalidated: the telemetry queue outlives the test
        // and may still start a retry, and starting a task on an invalidated session raises an
        // Objective-C exception that takes the whole test process down.
        URLProtocol.unregisterClass(SharedSessionTripwireURLProtocol.self)
        super.tearDown()
    }

    /// A fresh install offline: onboarding saves the user with no Sign in with Apple, then the first
    /// Ready Screen shows a complete session while every telemetry send fails.
    func testFreshInstallOfflineOnboardsAndBuildsACompleteSession() async throws {
        let telemetry = makeTelemetry(protocolClass: OfflineFailingURLProtocol.self)
        let services = makeLiveContainer(context: MockPersistence.controller().viewContext, telemetry: telemetry)

        try await onboard(through: services, minutes: 20)
        let viewModel = await coldOpenReadyScreen(services)

        try await assertReadyWithCompleteSession(viewModel, requestedMinutes: 20)
        XCTAssertEqual(viewModel.varietyNote?.source, .template, "offline, the Variety Language line is the template")

        // Non-vacuity: telemetry really tried the wire, every attempt failed offline, and the events
        // stay queued for a later connection instead of failing the screen.
        try await waitForRequests(on: OfflineFailingURLProtocol.log)
        XCTAssertTrue(OfflineFailingURLProtocol.log.urls.allSatisfy { $0.path.hasSuffix("/logEvent") })
        let pending = await telemetry.pendingDeliveryCount
        XCTAssertGreaterThan(pending, 0, "an offline send keeps its event for a later connection")
        XCTAssertEqual(SharedSessionTripwireURLProtocol.log.count, 0, "nothing on the cold-open path may use URLSession.shared")
    }

    /// A cold open of an existing install with history: a second container over the same store stands
    /// in for the relaunched process, and the session builds from the saved history offline.
    func testColdOpenOfAnExistingInstallOfflineBuildsACompleteSession() async throws {
        let context = MockPersistence.controller().viewContext
        let installed = makeLiveContainer(context: context, telemetry: makeTelemetry(protocolClass: OfflineFailingURLProtocol.self))
        try await onboard(through: installed, minutes: 15)
        try await seedHistory(through: installed, sessions: 3)

        let relaunched = makeLiveContainer(context: context, telemetry: makeTelemetry(protocolClass: OfflineFailingURLProtocol.self))
        let viewModel = await coldOpenReadyScreen(relaunched)

        try await assertReadyWithCompleteSession(viewModel, requestedMinutes: 15)
        XCTAssertEqual(viewModel.recentLogs.count, 3, "the session was built from the saved history")
        XCTAssertNotNil(viewModel.consistency, "the Consistency Score is computed on-device")
        XCTAssertEqual(SharedSessionTripwireURLProtocol.log.count, 0, "nothing on the cold-open path may use URLSession.shared")
    }

    /// The Ready Screen never waits on the network: with a telemetry request already in flight and
    /// never answered (a radio that will not connect), the app-open reconciliation and the Ready load
    /// both finish with a complete session while that request is still outstanding.
    func testReadyScreenDoesNotAwaitAnOutstandingNetworkRequest() async throws {
        let services = makeLiveContainer(
            context: MockPersistence.controller().viewContext,
            telemetry: makeTelemetry(protocolClass: OfflineHangingURLProtocol.self)
        )
        try await onboard(through: services, minutes: 10)
        try await waitForRequests(on: OfflineHangingURLProtocol.log)
        XCTAssertEqual(OfflineHangingURLProtocol.log.ended, 0, "the onboarding telemetry send is still in flight")

        let clock = ContinuousClock()
        let start = clock.now
        let viewModel = await coldOpenReadyScreen(services)
        let elapsed = start.duration(to: clock.now)

        try await assertReadyWithCompleteSession(viewModel, requestedMinutes: 10)
        XCTAssertEqual(OfflineHangingURLProtocol.log.ended, 0, "the session became ready without the network request ending")
        XCTAssertLessThan(elapsed, .seconds(2), "the cold open finished well inside the request timeout, so it waited on no request")
    }

    /// The Variety Language upgrade falls back offline even if a provider were wired: the real proxy
    /// provider over an offline `URLSession`, behind a resolver that believes the network is up, still
    /// yields the template line and a ready session for a cold-start user (the only user it calls for).
    func testVarietyLanguageProviderFallsBackToTheTemplateOffline() async throws {
        let services = makeLiveContainer(
            context: MockPersistence.controller().viewContext,
            telemetry: makeTelemetry(protocolClass: OfflineFailingURLProtocol.self)
        )
        try await onboard(through: services, minutes: 15)
        let onboarded = try await services.userService.currentUser()
        XCTAssertEqual(onboarded?.coldStart.active, true, "a fresh user is cold-start-active, so the provider is tried")

        let provider = ProxyVarietyLanguageProvider(
            endpoint: try XCTUnwrap(URL(string: "https://offline.example/variety-language")),
            transport: URLSessionVarietyLanguageProxyTransport(session: makeSession(protocolClass: OfflineFailingURLProtocol.self))
        )
        let viewModel = ReadyViewModel(
            userService: services.userService,
            sessionPolicyService: services.sessionPolicyService,
            workoutEngine: services.workoutEngine,
            workoutLogService: services.workoutLogService,
            consistencyService: services.consistencyService,
            varietyLanguageResolver: VarietyLanguageResolver(provider: provider, isOnline: { true }),
            activeSessionStore: services.activeSessionStore,
            analytics: services.analyticsService
        )
        await viewModel.load()

        try await assertReadyWithCompleteSession(viewModel, requestedMinutes: 15)
        XCTAssertEqual(viewModel.varietyNote?.source, .template)
        XCTAssertTrue(
            OfflineFailingURLProtocol.log.urls.contains { $0.path == "/variety-language" },
            "the provider really tried the wire and failed offline"
        )
    }

    /// The Ready Screen's own resolver is template-only: no provider, and it never believes it is online.
    func testProductionReadyScreenResolverIsTemplateOnly() {
        let resolver = VarietyLanguageResolver()
        XCTAssertNil(resolver.provider)
        XCTAssertFalse(resolver.isOnline())
    }

    // MARK: - Cold-open path

    /// `RootView.prepareAppOpen()` then `ReadyView`'s `.task`: the reconciliation the app awaits before
    /// building the tabs, then the Ready Screen's load over a view model built the way `ReadyView` does.
    private func coldOpenReadyScreen(_ services: ServiceContainer) async -> ReadyViewModel {
        await StrengthGraduationViewModel(services: services).evaluate()
        let viewModel = ReadyViewModel(
            userService: services.userService,
            sessionPolicyService: services.sessionPolicyService,
            workoutEngine: services.workoutEngine,
            workoutLogService: services.workoutLogService,
            consistencyService: services.consistencyService,
            activeSessionStore: services.activeSessionStore,
            analytics: services.analyticsService
        )
        await viewModel.load()
        return viewModel
    }

    /// The onboarding flow as `OnboardingView` wires it, skipping the optional Sign in with Apple.
    private func onboard(through services: ServiceContainer, minutes: Int) async throws {
        let onboarding = OnboardingViewModel(
            userService: services.userService,
            sessionPolicyService: services.sessionPolicyService,
            authService: services.authService,
            analytics: services.analyticsService
        )
        onboarding.onboardingStarted()
        onboarding.displayName = "Offline"
        onboarding.durationMinutes = minutes
        let finished = await onboarding.finish()
        XCTAssertTrue(finished, "onboarding finishes offline: \(onboarding.errorMessage ?? "")")
    }

    /// Saves completed sessions built by the container's own engine, a day apart, as earlier opens would have.
    private func seedHistory(through services: ServiceContainer, sessions count: Int) async throws {
        let current = try await services.userService.currentUser()
        let user = try XCTUnwrap(current)
        for daysAgo in (1...count).reversed() {
            let workout = try await services.workoutEngine.generateWorkout(
                requestedMinutes: user.duration.defaultMinutes,
                user: user,
                recentLogs: [],
                sessionPolicy: .default,
                variation: .none
            )
            let exercises = workout.blocks.flatMap(\.exercises).map { prescription in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: prescription.exercise.id,
                    pillar: prescription.exercise.pillar,
                    movementPattern: prescription.exercise.movementPattern,
                    completedSets: Array(
                        repeating: CompletedSet(reps: prescription.reps, durationSeconds: prescription.durationSeconds),
                        count: prescription.sets
                    ),
                    skipped: false
                )
            }
            try await services.workoutLogService.save(
                WorkoutLog(
                    id: UUID(),
                    workoutId: workout.id,
                    completedAt: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
                    requestedMinutes: workout.requestedMinutes,
                    durationMinutes: workout.requestedMinutes,
                    wasReturn: false,
                    shape: workout.shape,
                    focusPillar: workout.focusPillar,
                    perceivedDifficulty: .justRight,
                    exercises: exercises
                )
            )
        }
    }

    private func assertReadyWithCompleteSession(
        _ viewModel: ReadyViewModel,
        requestedMinutes: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertNil(viewModel.errorMessage, "no error state", file: file, line: line)
        XCTAssertFalse(viewModel.isLoading, "no spinner once the session is ready", file: file, line: line)
        let workout = try XCTUnwrap(viewModel.workout, "the Ready Screen has today's session", file: file, line: line)
        XCTAssertEqual(workout.requestedMinutes, requestedMinutes, file: file, line: line)
        XCTAssertFalse(workout.blocks.isEmpty, file: file, line: line)
        XCTAssertTrue(workout.blocks.allSatisfy { !$0.exercises.isEmpty }, "every block has movements", file: file, line: line)
        XCTAssertTrue(
            workout.blocks.contains { $0.category == .strength },
            "the session carries its Training Day circuit",
            file: file,
            line: line
        )
        // The session lands within the tolerance of the length chosen, or - when even the top of the
        // range and the longest rests cannot fill it - runs short with every fit lever spent (an honest
        // shortfall), never short with a lever left.
        let gap = SessionAssembly.plannedSeconds(of: workout) - requestedMinutes * 60
        guard abs(gap) > SessionAssembly.toleranceSeconds else { return }
        XCTAssertLessThan(gap, 0, "the session overruns the requested length", file: file, line: line)
        let user = try XCTUnwrap(viewModel.user, file: file, line: line)
        var plan = SessionAssembly.planSession(
            requestedMinutes: requestedMinutes,
            user: user,
            library: try await MockExerciseService().exercises(),
            recentLogs: viewModel.recentLogs,
            sessionPolicy: viewModel.policy,
            trainingDay: try XCTUnwrap(workout.trainingDay, file: file, line: line),
            asOf: Date()
        )
        SessionAssembly.fit(&plan, targetSeconds: requestedMinutes * 60)
        XCTAssertTrue(plan.isSaturated, "the session runs \(-gap)s short with fit levers left", file: file, line: line)
    }

    // MARK: - Offline wiring

    /// The production container with only its telemetry sink chosen here; the Coach client and every
    /// other service resolve exactly as the app resolves them.
    private func makeLiveContainer(context: NSManagedObjectContext, telemetry: LiveAnalyticsService) -> ServiceContainer {
        ServiceContainer.live(
            context: context,
            installId: "offline-install",
            coachSafetyIdentifierProvider: { CoachSafetyIdentifier(rawValue: "coach-00000000-0000-4000-8000-000000000001") },
            analyticsGate: { true },
            analyticsService: telemetry
        )
    }

    /// The real telemetry transport and queue, consent on, over an offline session with volatile storage.
    private func makeTelemetry(protocolClass: URLProtocol.Type) -> LiveAnalyticsService {
        LiveAnalyticsService(
            endpoint: LiveAnalyticsService.endpoint(fromOrigin: "https://offline.example")!,
            installId: "offline-install",
            secret: "offline-test-secret",
            session: makeSession(protocolClass: protocolClass),
            isEnabled: { true },
            outboxStorage: VolatileAnalyticsOutboxStorage(),
            backgroundExecution: .none
        )
    }

    /// A session whose only protocol is `protocolClass`. The short request timeout ends a hanging
    /// request on its own a few seconds after the test that opened it.
    private func makeSession(protocolClass: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }

    /// Waits for the asynchronous telemetry queue to reach the transport at least once.
    private func waitForRequests(on log: OfflineRequestLog, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while log.count == 0 {
            guard Date() < deadline else {
                XCTFail("no request reached the offline transport within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - Offline transports

/// What an offline `URLProtocol` saw, readable from the test while the loading system runs it.
final class OfflineRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URL] = []
    private var endedCount = 0

    var urls: [URL] { lock.withLock { seen } }
    var count: Int { lock.withLock { seen.count } }
    var ended: Int { lock.withLock { endedCount } }

    func record(_ url: URL?) { lock.withLock { seen.append(url ?? URL(fileURLWithPath: "/")) } }
    func recordEnd() { lock.withLock { endedCount += 1 } }
    func reset() { lock.withLock { seen = []; endedCount = 0 } }
}

/// Answers every request the way airplane mode does: `URLError(.notConnectedToInternet)`.
final class OfflineFailingURLProtocol: URLProtocol {
    static let log = OfflineRequestLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request.url)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {
        Self.log.recordEnd()
    }
}

/// Accepts every request and never answers it; only the session's request timeout ends it.
final class OfflineHangingURLProtocol: URLProtocol {
    static let log = OfflineRequestLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request.url)
    }

    override func stopLoading() {
        Self.log.recordEnd()
    }
}

/// Registered globally so any request on `URLSession.shared` is recorded and fails offline.
final class SharedSessionTripwireURLProtocol: URLProtocol {
    static let log = OfflineRequestLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request.url)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
