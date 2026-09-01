import XCTest
@testable import RepToday

/// US-T04 validation: the live Convex-backed transport.
///
/// **No test here touches the network** (FR-13). Every request is intercepted in process by
/// `StubURLProtocol`, which is registered on a private ephemeral `URLSession` handed to the service
/// - so the URL, the method, the headers, and the exact request body are read off the request the
/// service actually built, without a socket ever opening.
///
/// One gotcha worth naming, because it silently makes a body assertion vacuous: `URLSession` moves
/// `httpBody` into `httpBodyStream` before a `URLProtocol` sees the request, so
/// `request.httpBody` is always `nil` in `startLoading()`. The stub reads the stream instead.
final class LiveAnalyticsServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-08-03T00:00:00Z, pinned rather than read from the clock.
    private static let installMs = 1_785_715_200_000

    private let endpoint = URL(string: "https://example-deployment.convex.site/logEvent")!

    /// A default shared secret for tests that do not care about its value, and the value the header
    /// assertion checks against.
    private static let testSecret = "wire-secret-abc123"

    private func makeService(
        installId: String = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
        secret: String = LiveAnalyticsServiceTests.testSecret,
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) -> LiveAnalyticsService {
        LiveAnalyticsService(
            endpoint: endpoint,
            installId: installId,
            secret: secret,
            session: StubURLProtocol.makeSession(),
            isEnabled: isEnabled
        )
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - The request the sink's `POST /logEvent` contract describes

    /// The whole wire contract in one assertion: the configured URL, `POST`, a JSON content type,
    /// and a body of exactly `{name, installId, clientTs, props}` with the property bag flattened
    /// to plain scalars.
    func testRecordPostsTheWireContractToTheConfiguredEndpoint() async throws {
        let sent = expectation(description: "request intercepted")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        let service = makeService(installId: "install-42")
        await service.record(
            AnalyticsEvent(
                name: .sessionCompleted,
                timestampMs: Self.installMs,
                properties: [
                    "requested_minutes": .int(20),
                    "completed_minutes": .double(19.5),
                    "was_return": .bool(false),
                    "perceived_difficulty": .string("justRight")
                ]
            )
        )
        await fulfillment(of: [sent], timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.captured.first)
        XCTAssertEqual(request.url?.absoluteString, endpoint.absoluteString)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.capturedBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // The four top-level keys the sink requires, and nothing else. `props` is always written,
        // even when empty, rather than relying on the action's absent-bag default.
        XCTAssertEqual(Set(json.keys), ["name", "installId", "clientTs", "props"])
        XCTAssertEqual(json["name"] as? String, "session_completed")
        XCTAssertEqual(json["installId"] as? String, "install-42")
        XCTAssertEqual(json["clientTs"] as? Int, Self.installMs)

        // Flattened scalars: the bag holds numbers, strings, and booleans - not `AnalyticsValue`'s
        // tagged in-process form.
        let props = try XCTUnwrap(json["props"] as? [String: Any])
        XCTAssertEqual(props.count, 4)
        XCTAssertEqual(props["requested_minutes"] as? Int, 20)
        XCTAssertEqual(props["completed_minutes"] as? Double, 19.5)
        XCTAssertEqual(props["was_return"] as? Bool, false)
        XCTAssertEqual(props["perceived_difficulty"] as? String, "justRight")
    }

    /// US-T14: every POST carries the shared secret on its header, sourced from the build. The value
    /// is read off the request the service actually built, intercepted in process - nothing leaves
    /// the process (FR-13).
    func testRecordAttachesTheSharedSecretHeader() async throws {
        let sent = expectation(description: "request intercepted")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        let service = makeService(secret: "s3cr3t-value-xyz")
        await service.record(AnalyticsEvent(name: .appInstall, timestampMs: Self.installMs))
        await fulfillment(of: [sent], timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.captured.first)
        // The header name is the exact one `convex/http.ts` reads (`ANALYTICS_SECRET_HEADER`).
        XCTAssertEqual(LiveAnalyticsService.secretHeaderField, "X-RepToday-Analytics-Secret")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: LiveAnalyticsService.secretHeaderField),
            "s3cr3t-value-xyz",
            "the shared secret was not attached to the POST"
        )
    }

    /// An event with no properties still sends a bag, as an empty JSON object.
    func testEventWithNoPropertiesSendsAnEmptyBag() async throws {
        let sent = expectation(description: "request intercepted")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        await makeService().record(AnalyticsEvent(name: .weekActive, timestampMs: Self.installMs))
        await fulfillment(of: [sent], timeout: 5)

        let body = try XCTUnwrap(StubURLProtocol.captured.first?.capturedBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let props = try XCTUnwrap(json["props"] as? [String: Any])
        XCTAssertTrue(props.isEmpty)
    }

    /// `clientTs` must cross the wire as a **bare JSON number**, which already *is* the float64 a
    /// `v.number()` column stores. This is the pinned numeric convention (US-T03) and the
    /// `int64`/`float64` trap the US-T01 spike documented, and it is the assertion most likely to
    /// regress silently - a re-tagging encoder would still produce valid JSON. So it is checked
    /// against the raw bytes rather than a parsed value, which would hide the difference.
    func testClientTimestampCrossesTheWireAsABareJSONNumber() async throws {
        let sent = expectation(description: "request intercepted")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        await makeService().record(
            AnalyticsEvent(
                name: .readyScreenShown,
                timestampMs: Self.installMs,
                properties: ["generation_ms": .int(38)]
            )
        )
        await fulfillment(of: [sent], timeout: 5)

        let body = try XCTUnwrap(StubURLProtocol.captured.first?.capturedBody)
        let raw = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"clientTs\":1785715200000"), "clientTs was not a bare number: \(raw)")
        XCTAssertFalse(raw.contains("\"clientTs\":\""), "clientTs must not be sent as a string")
        XCTAssertFalse(raw.contains("$integer"), "nothing may re-tag the timestamp for a Convex SDK")
        // The property bag is flat: `{"generation_ms":38}`, not `{"type":"int","value":38}`.
        XCTAssertTrue(raw.contains("\"generation_ms\":38"), "props were not flattened: \(raw)")
        XCTAssertFalse(raw.contains("\"type\""), "the tagged in-process encoding leaked onto the wire")
    }

    /// The wire body is deliberately a *second* encoding, not the model's own. This pins the
    /// difference so a later "simplification" that sends `JSONEncoder().encode(event)` fails here
    /// rather than at the sink: the model's form is tagged and names its keys differently, and it
    /// carries no install identifier at all.
    func testTheModelsOwnCodableFormIsNotTheWireForm() throws {
        let event = AnalyticsEvent(
            name: .readyScreenShown,
            timestampMs: Self.installMs,
            properties: ["generation_ms": .int(38)]
        )

        let modelJSON = try XCTUnwrap(String(data: try JSONEncoder().encode(event), encoding: .utf8))
        XCTAssertTrue(modelJSON.contains("\"type\""), "US-T02's tagged in-process encoding must stay")
        XCTAssertTrue(modelJSON.contains("timestampMs"))
        XCTAssertFalse(modelJSON.contains("installId"))

        let wireJSON = try XCTUnwrap(
            String(data: try AnalyticsWireBody.encode(event, installId: "install-42"), encoding: .utf8)
        )
        XCTAssertFalse(wireJSON.contains("\"type\""))
        XCTAssertFalse(wireJSON.contains("timestampMs"))
        XCTAssertTrue(wireJSON.contains("\"installId\":\"install-42\""))
    }

    /// Every one of the 13 pre-registered names reaches the wire as its snake_case raw value, and
    /// no web-side event ever does.
    func testEveryPreRegisteredEventNameReachesTheWireAsItsRawValue() throws {
        for name in AnalyticsEventName.allCases {
            let body = try AnalyticsWireBody.encode(
                AnalyticsEvent(name: name, timestampMs: Self.installMs),
                installId: "install-42"
            )
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["name"] as? String, name.rawValue)
        }
    }

    // MARK: - Fire-and-forget

    /// `record(_:)` must return without awaiting the send. The stub holds the request open for well
    /// over a second; the call has to come back in a small fraction of that.
    func testRecordReturnsWithoutAwaitingTheSend() async throws {
        let held = expectation(description: "request reached the stub and was held")
        StubURLProtocol.holdSeconds = 1.5
        StubURLProtocol.onRequest = { _ in held.fulfill() }

        let started = Date()
        await makeService().record(AnalyticsEvent(name: .sessionStarted, timestampMs: Self.installMs))
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 0.5, "record(_:) awaited the network; it must be fire-and-forget")
        await fulfillment(of: [held], timeout: 10)
    }

    /// Every failure is swallowed: a transport error surfaces nothing to the caller and does not
    /// poison the service - the next event still goes out.
    func testTransportFailureIsSwallowedAndTheServiceKeepsSending() async throws {
        let firstSent = expectation(description: "first request intercepted")
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        StubURLProtocol.onRequest = { _ in firstSent.fulfill() }

        let service = makeService()
        await service.record(AnalyticsEvent(name: .sessionStarted, timestampMs: Self.installMs))
        await fulfillment(of: [firstSent], timeout: 5)

        let secondSent = expectation(description: "second request intercepted")
        StubURLProtocol.failure = nil
        StubURLProtocol.onRequest = { _ in secondSent.fulfill() }
        await service.record(AnalyticsEvent(name: .sessionCompleted, timestampMs: Self.installMs))
        await fulfillment(of: [secondSent], timeout: 5)

        XCTAssertEqual(StubURLProtocol.captured.count, 2)
    }

    /// A non-2xx answer is swallowed just as completely as a transport error - the sink's
    /// `4xx`/`5xx` split exists for a human watching the PMF test, not for this client.
    func testRejectionResponseIsSwallowed() async throws {
        let sent = expectation(description: "request intercepted")
        StubURLProtocol.statusCode = 400
        StubURLProtocol.responseBody = Data(#"{"error":"props has 40 keys, over the 32-key limit"}"#.utf8)
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        await makeService().record(AnalyticsEvent(name: .subscribe, timestampMs: Self.installMs))
        await fulfillment(of: [sent], timeout: 5)

        XCTAssertEqual(StubURLProtocol.captured.count, 1)
    }

    // MARK: - The opt-out gate, as a seam

    /// With the gate closed there is no request at all - not a dropped response, no network call.
    /// "Zero emission when off" is US-T06's criterion; these two drive the seam with a hand-written
    /// closure, and the pair further down drives it with the persisted flag US-T06 actually wired.
    func testDisabledGateEmitsNothing() async throws {
        StubURLProtocol.onRequest = { _ in
            XCTFail("a request was sent while telemetry was disabled")
        }

        let service = makeService(isEnabled: { false })
        await service.record(AnalyticsEvent(name: .appInstall, timestampMs: Self.installMs))

        // The send would have been dispatched by now if it were going to be; nothing was.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(StubURLProtocol.captured.isEmpty)
    }

    /// The gate is read per emission, not captured at construction, which is what makes US-T06's
    /// toggle take effect without an app restart.
    func testGateIsReReadOnEveryEmission() async throws {
        let enabled = UncheckedBox(false)
        let sent = expectation(description: "request intercepted once re-enabled")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }

        let service = makeService(isEnabled: { enabled.value })
        await service.record(AnalyticsEvent(name: .appInstall, timestampMs: Self.installMs))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(StubURLProtocol.captured.isEmpty, "the closed gate let an event through")

        enabled.value = true
        await service.record(AnalyticsEvent(name: .onboardingStarted, timestampMs: Self.installMs))
        await fulfillment(of: [sent], timeout: 5)
        XCTAssertEqual(StubURLProtocol.captured.count, 1)
    }

    /// Account deletion rotates the identifier without rebuilding the app-wide container. The
    /// transport therefore has to read its provider for each event, just as it reads consent for
    /// each event; freezing the initializer's value would link post-deletion onboarding to the old
    /// install identity even though `AppState` had persisted the replacement.
    func testInstallIdentifierIsReReadOnEveryEmission() async throws {
        let installId = UncheckedBox("before-deletion")
        let firstSent = expectation(description: "pre-deletion request intercepted")
        let secondSent = expectation(description: "post-deletion request intercepted")
        var requestCount = 0
        StubURLProtocol.onRequest = { _ in
            requestCount += 1
            (requestCount == 1 ? firstSent : secondSent).fulfill()
        }
        let service = LiveAnalyticsService(
            endpoint: endpoint,
            installId: { installId.value },
            secret: Self.testSecret,
            session: StubURLProtocol.makeSession()
        )

        await service.record(AnalyticsEvent(name: .sessionCompleted, timestampMs: Self.installMs))
        await fulfillment(of: [firstSent], timeout: 5)
        installId.value = "after-deletion"
        await service.record(AnalyticsEvent(name: .onboardingStarted, timestampMs: Self.installMs))
        await fulfillment(of: [secondSent], timeout: 5)

        let ids = try StubURLProtocol.captured.map { request in
            let body = try XCTUnwrap(request.capturedBody)
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["installId"] as? String)
        }
        XCTAssertEqual(ids, ["before-deletion", "after-deletion"])
    }

    // MARK: - The gate, backed by US-T06's persisted flag

    /// The gate the app actually holds is `AppState.isAnalyticsEnabled(in:)` over `UserDefaults`, so
    /// this drives the real transport through the real reader rather than through a hand-written
    /// `{ false }`: a fresh install emits, writing the flag stops emission on the very next event,
    /// and writing it back resumes - all without rebuilding the service, which is what "honoured
    /// immediately, without an app restart" means.
    func testThePersistedOptOutFlagStopsAndResumesEmissionWithoutRebuildingTheService() async throws {
        let suiteName = "RepToday.LiveAnalyticsServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = LiveAnalyticsService(
            endpoint: endpoint,
            installId: "install-42",
            secret: Self.testSecret,
            session: StubURLProtocol.makeSession(),
            // Reconstructed inside the closure from a `Sendable` name, so nothing non-`Sendable` is
            // captured; it is the same suite either way.
            isEnabled: { AppState.isAnalyticsEnabled(in: UserDefaults(suiteName: suiteName) ?? .standard) }
        )

        let optedIn = expectation(description: "the default opted-in state emits")
        StubURLProtocol.onRequest = { _ in optedIn.fulfill() }
        await service.record(AnalyticsEvent(name: .appInstall, timestampMs: Self.installMs))
        await fulfillment(of: [optedIn], timeout: 5)
        XCTAssertEqual(StubURLProtocol.captured.count, 1, "a fresh install must be opted in")

        defaults.set(false, forKey: AppState.analyticsEnabledKey)
        StubURLProtocol.onRequest = { _ in XCTFail("an event was sent after the user opted out") }
        await service.record(AnalyticsEvent(name: .sessionStarted, timestampMs: Self.installMs))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(StubURLProtocol.captured.count, 1, "opting out did not take effect until a restart")

        let resumed = expectation(description: "opting back in resumes emission")
        defaults.set(true, forKey: AppState.analyticsEnabledKey)
        StubURLProtocol.onRequest = { _ in resumed.fulfill() }
        await service.record(AnalyticsEvent(name: .sessionCompleted, timestampMs: Self.installMs))
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertEqual(StubURLProtocol.captured.count, 2)
    }

    /// The production container wires that flag, rather than the initializer's enabled-by-default
    /// stub. Asserted by reading the built service's own gate, so nothing is emitted to find out -
    /// and so a future edit that drops `isEnabled:` from the `configured(...)` call fails here.
    ///
    /// Debug-only because a raw Release test build has no privately-injected token and therefore
    /// wires `NoOpAnalyticsService`, which has no gate to read (`AnalyticsServiceTests` asserts that half).
    #if DEBUG
    func testTheProductionContainersGateIsThePersistedOptOutFlag() throws {
        let standard = UserDefaults.standard
        restoreAfterTest(AppState.analyticsEnabledKey, in: standard)

        let controller = MockPersistence.controller()
        let container = ServiceContainer.live(
            context: controller.viewContext,
            installId: "container-install",
            coachSafetyIdentifierProvider: { CoachSafetyIdentifier(rawValue: "coach-00000000-0000-4000-8000-000000000001") }
        )
        let service = try XCTUnwrap(
            container.analyticsService as? LiveAnalyticsService,
            "the Debug container must wire the live transport"
        )

        standard.removeObject(forKey: AppState.analyticsEnabledKey)
        XCTAssertTrue(service.isEmissionEnabled, "a fresh install must be opted in")

        standard.set(false, forKey: AppState.analyticsEnabledKey)
        XCTAssertFalse(
            service.isEmissionEnabled,
            "the container's gate is not backed by the persisted opt-out flag"
        )

        standard.set(true, forKey: AppState.analyticsEnabledKey)
        XCTAssertTrue(service.isEmissionEnabled)
    }

    /// And the container uses the gate it is *handed* rather than resolving one of its own, which is
    /// what lets the app pass a gate bound to the same store its `AppState` writes. Driven from a
    /// non-default suite so a container that quietly fell back to `.standard` would fail here.
    func testTheContainerUsesTheGateItIsHanded() throws {
        let suiteName = "RepToday.LiveAnalyticsServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(userDefaults: defaults)
        let controller = MockPersistence.controller()
        let container = ServiceContainer.live(
            context: controller.viewContext,
            installId: "container-install",
            coachSafetyIdentifierProvider: appState.coachSafetyIdentifierProvider,
            analyticsGate: appState.analyticsGate
        )
        let service = try XCTUnwrap(
            container.analyticsService as? LiveAnalyticsService,
            "the Debug container must wire the live transport"
        )

        XCTAssertTrue(service.isEmissionEnabled, "a fresh install must be opted in")

        appState.analyticsEnabled = false
        XCTAssertFalse(
            service.isEmissionEnabled,
            "the container did not use the gate it was handed; an opted-out user would still emit"
        )

        appState.analyticsEnabled = true
        XCTAssertTrue(service.isEmissionEnabled)
    }
    #endif

    // MARK: - Configuration: missing or malformed is inert, never fatal

    /// A build with no usable endpoint must simply not emit. Each of these returns `nil`, and the
    /// container answers `nil` with the inert sink rather than trapping.
    func testUnusableEndpointConfigurationResolvesToNil() {
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: nil))
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: ""))
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "   "))
        // `URL(string:)` happily accepts these as relative URLs, so the scheme/host checks are
        // what actually rule them out.
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "not a url"))
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "courteous-dogfish-560.convex.site"))
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "/logEvent"))
        // Telemetry over plaintext is a configuration mistake, not a deployment choice.
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "http://example.convex.site"))
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: "https://"))
        // Not a string at all - a plist value can be anything.
        XCTAssertNil(LiveAnalyticsService.endpoint(fromOrigin: 42))
    }

    /// A usable origin resolves to the deployment's route, with the path owned by the code rather
    /// than by configuration.
    func testUsableOriginResolvesToTheLogEventRoute() throws {
        let resolved = try XCTUnwrap(
            LiveAnalyticsService.endpoint(fromOrigin: "  https://example-deployment.convex.site  ")
        )
        XCTAssertEqual(resolved.absoluteString, "https://example-deployment.convex.site/logEvent")
    }

    // MARK: - The shared secret follows the same inert-when-empty rule as the endpoint (US-T14)

    /// A missing, empty, whitespace-only, or non-string secret is the same "unconfigured" state as a
    /// missing endpoint: it resolves to `nil`, so the build stays inert rather than firing requests
    /// the sink will only ever `401`.
    func testUnusableSecretConfigurationResolvesToNil() {
        XCTAssertNil(LiveAnalyticsService.secret(fromValue: nil))
        XCTAssertNil(LiveAnalyticsService.secret(fromValue: ""))
        XCTAssertNil(LiveAnalyticsService.secret(fromValue: "   "))
        XCTAssertNil(LiveAnalyticsService.secret(fromValue: 42))
    }

    /// A usable secret resolves to its trimmed value.
    func testUsableSecretResolvesTrimmed() throws {
        let resolved = try XCTUnwrap(LiveAnalyticsService.secret(fromValue: "  abc123  "))
        XCTAssertEqual(resolved, "abc123")
    }

    /// The secret is split per build configuration (`REPTODAY_ANALYTICS_SECRET` in
    /// `ios/RepToday/project.yml`, expanded into `Info.plist`) exactly as the endpoint is, and the
    /// split is read out of the **running app bundle** rather than asserted in prose: Debug carries
    /// the dev deployment's secret, while raw Release test builds carry no privately-injected token.
    ///
    /// Only the Debug half runs, for the same `ENABLE_TESTABILITY`-is-Debug-only reason
    /// `testTheAppBundlesEndpointFollowsTheBuildConfiguration` documents; the Release half is
    /// verified against the built Release artifact (recorded alongside the endpoint's).
    func testTheAppBundlesSecretFollowsTheBuildConfiguration() throws {
        let configured = Bundle.main.object(forInfoDictionaryKey: LiveAnalyticsService.secretInfoPlistKey)

        #if DEBUG
        let secret = try XCTUnwrap(configured as? String, "the Debug build carries no analytics secret")
        XCTAssertFalse(secret.isEmpty, "the Debug build's analytics secret expanded to nothing")
        XCTAssertNotNil(
            LiveAnalyticsService.secret(fromValue: secret),
            "the Debug build's analytics secret does not resolve"
        )
        // With both an endpoint and a secret present, the Debug build resolves a live service.
        XCTAssertNotNil(LiveAnalyticsService.configured(bundle: .main, installId: "install-42"))
        #else
        // Nothing configured, so nothing to authenticate with - inert exactly like the endpoint.
        XCTAssertNil(LiveAnalyticsService.secret(fromValue: configured))
        XCTAssertNil(LiveAnalyticsService.configured(bundle: .main, installId: "install-42"))
        #endif
    }

    /// A bundle without the key configures nothing - which is the whole "inert, not fatal" claim,
    /// exercised against a real `Bundle` rather than a stand-in. The unit-test bundle carries no
    /// `RepTodayAnalyticsEndpoint`.
    func testConfiguredReturnsNilForABundleWithNoEndpoint() {
        let testBundle = Bundle(for: LiveAnalyticsServiceTests.self)
        XCTAssertNil(testBundle.object(forInfoDictionaryKey: LiveAnalyticsService.endpointInfoPlistKey))
        XCTAssertNil(LiveAnalyticsService.configured(bundle: testBundle, installId: "install-42"))
    }

    /// The endpoint is split per build configuration (`REPTODAY_ANALYTICS_ENDPOINT` in
    /// `ios/RepToday/project.yml`, expanded into `Info.plist`), and the split is read out of the
    /// **running app bundle** rather than asserted in prose: Debug carries the dev deployment,
    /// Release carries the production endpoint; without the private archive token it remains inert.
    ///
    /// **Only the Debug half actually runs, and that limit is stated rather than glossed.** This
    /// project sets `ENABLE_TESTABILITY` on the Debug configuration only, so `@testable import
    /// RepToday` cannot resolve under `-configuration Release` and no Release test run exists to
    /// execute the `#else` branch - a pre-existing property of the project, not of this test, and
    /// not worth de-optimising the shipping binary to change. The Release half is verified instead
    /// by reading `RepTodayAnalyticsEndpoint` out of the **built Release app bundle** (recorded in
    /// the production-validation artifact): the origin is production, but the raw build's empty
    /// token keeps the combined configuration inert.
    /// The branch is kept because it is the assertion that becomes runnable the moment a Release
    /// test run is - it is not a claim that one happens today.
    func testTheAppBundlesEndpointFollowsTheBuildConfiguration() throws {
        let configured = Bundle.main.object(forInfoDictionaryKey: LiveAnalyticsService.endpointInfoPlistKey)

        #if DEBUG
        let origin = try XCTUnwrap(configured as? String, "the Debug build carries no analytics endpoint")
        XCTAssertFalse(origin.isEmpty, "the Debug build's analytics endpoint expanded to nothing")
        let endpoint = try XCTUnwrap(
            LiveAnalyticsService.endpoint(fromOrigin: origin),
            "the Debug build's analytics endpoint is not a usable HTTPS origin: \(origin)"
        )
        XCTAssertEqual(endpoint.scheme, "https")
        XCTAssertEqual(endpoint.path, "/logEvent")
        XCTAssertNotNil(LiveAnalyticsService.configured(bundle: .main, installId: "install-42"))
        #else
        // The endpoint is production, but the raw test build has no privately-injected token, so the
        // combined configuration is inert rather than firing unauthenticated requests.
        XCTAssertNotNil(LiveAnalyticsService.endpoint(fromOrigin: configured))
        XCTAssertNil(LiveAnalyticsService.configured(bundle: .main, installId: "install-42"))
        #endif
    }

    /// A configured bundle builds a service that posts to that deployment's `/logEvent`. The
    /// expected host is read back out of the same `Info.plist` rather than hard-coded, so moving the
    /// deployment does not turn this into a failing test. It is a Debug-only assertion because a
    /// A raw Release build has no injected token to build a service from - that half is asserted above.
    #if DEBUG
    func testConfiguredReadsTheAppBundlesEndpointAndPostsToItsRoute() async throws {
        let configured = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: LiveAnalyticsService.endpointInfoPlistKey) as? String
        )
        let expectedHost = try XCTUnwrap(URL(string: configured)?.host)

        let sent = expectation(description: "request intercepted")
        StubURLProtocol.onRequest = { _ in sent.fulfill() }
        let service = try XCTUnwrap(
            LiveAnalyticsService.configured(
                bundle: .main,
                installId: "install-42",
                session: StubURLProtocol.makeSession()
            )
        )

        await service.record(AnalyticsEvent(name: .appInstall, timestampMs: Self.installMs))
        await fulfillment(of: [sent], timeout: 5)

        let request = try XCTUnwrap(StubURLProtocol.captured.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, expectedHost)
        XCTAssertEqual(url.path, "/logEvent")

        // The configured service carries the app bundle's secret on the header the sink reads,
        // rather than an empty or hard-coded one (US-T14). The expected value is read back out of the
        // same `Info.plist` so rotating the dev secret does not turn this into a failing test.
        let expectedSecret = try XCTUnwrap(
            LiveAnalyticsService.secret(
                fromValue: Bundle.main.object(forInfoDictionaryKey: LiveAnalyticsService.secretInfoPlistKey)
            )
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: LiveAnalyticsService.secretHeaderField),
            expectedSecret
        )
    }
    #endif
}

// MARK: - In-process interception

/// A mutable box for a value a `@Sendable` closure reads. The tests that use it drive the service
/// from one task at a time, so the unchecked conformance is not papering over a race.
private final class UncheckedBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Intercepts every request on the session it is registered for, records it, and answers from
/// memory. Nothing leaves the process (FR-13).
final class StubURLProtocol: URLProtocol {
    /// Requests seen, in order, each with its body already read out of the stream.
    private(set) static var captured: [CapturedRequest] = []
    /// Called as each request arrives, on the URL loading system's thread.
    static var onRequest: ((URLRequest) -> Void)?
    /// Answer this status instead of `204`.
    static var statusCode = 204
    /// Answer with this body (the sink's `204` carries none).
    static var responseBody: Data?
    /// Fail the request with this error instead of answering.
    static var failure: Error?
    /// Hold the request open this long before answering, to prove a caller is not waiting on it.
    static var holdSeconds: TimeInterval = 0

    struct CapturedRequest {
        let url: URL?
        let httpMethod: String?
        let capturedBody: Data?
        private let headers: [String: String]

        init(_ request: URLRequest, body: Data?) {
            self.url = request.url
            self.httpMethod = request.httpMethod
            self.capturedBody = body
            self.headers = request.allHTTPHeaderFields ?? [:]
        }

        func value(forHTTPHeaderField field: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        captured = []
        onRequest = nil
        statusCode = 204
        responseBody = nil
        failure = nil
        holdSeconds = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Snapshot the configuration *before* `onRequest` announces the request. A test that
        // reconfigures the stub after awaiting that announcement - the failure/success pair in
        // `testTransportFailureIsSwallowedAndTheServiceKeepsSending` does exactly that - would
        // otherwise race this thread and could answer the first request from the second request's
        // settings, quietly making the leg it names vacuous while still passing.
        let failure = Self.failure
        let statusCode = Self.statusCode
        let responseBody = Self.responseBody
        let holdSeconds = Self.holdSeconds

        // `URLSession` moves `httpBody` into `httpBodyStream` before a `URLProtocol` sees the
        // request, so reading `httpBody` here would silently yield `nil` and make every body
        // assertion vacuous.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        Self.captured.append(CapturedRequest(request, body: body))
        Self.onRequest?(request)

        if holdSeconds > 0 {
            Thread.sleep(forTimeInterval: holdSeconds)
        }

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let responseBody {
            client?.urlProtocol(self, didLoad: responseBody)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
