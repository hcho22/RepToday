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

    private func makeService(
        installId: String = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) -> LiveAnalyticsService {
        LiveAnalyticsService(
            endpoint: endpoint,
            installId: installId,
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

    // MARK: - The opt-out gate (US-T06 connects it; this is the seam)

    /// With the gate closed there is no request at all - not a dropped response, no network call.
    /// "Zero emission when off" is a US-T06 criterion and this is the seam it will point at.
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

    /// The gate is read per emission, not captured at construction, so US-T06's toggle takes effect
    /// without an app restart.
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

    /// A bundle without the key configures nothing - which is the whole "inert, not fatal" claim,
    /// exercised against a real `Bundle` rather than a stand-in. The unit-test bundle carries no
    /// `RepTodayAnalyticsEndpoint`.
    func testConfiguredReturnsNilForABundleWithNoEndpoint() {
        let testBundle = Bundle(for: LiveAnalyticsServiceTests.self)
        XCTAssertNil(testBundle.object(forInfoDictionaryKey: LiveAnalyticsService.endpointInfoPlistKey))
        XCTAssertNil(LiveAnalyticsService.configured(bundle: testBundle, installId: "install-42"))
    }

    /// The app bundle *does* carry one, and the service built from it posts to that deployment's
    /// `/logEvent`. The expected host is read back out of the same `Info.plist` rather than
    /// hard-coded, so moving the deployment does not turn this into a failing test.
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

        let url = try XCTUnwrap(StubURLProtocol.captured.first?.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, expectedHost)
        XCTAssertEqual(url.path, "/logEvent")
    }
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
        // `URLSession` moves `httpBody` into `httpBodyStream` before a `URLProtocol` sees the
        // request, so reading `httpBody` here would silently yield `nil` and make every body
        // assertion vacuous.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        Self.captured.append(CapturedRequest(request, body: body))
        Self.onRequest?(request)

        if Self.holdSeconds > 0 {
            Thread.sleep(forTimeInterval: Self.holdSeconds)
        }

        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let responseBody = Self.responseBody {
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
