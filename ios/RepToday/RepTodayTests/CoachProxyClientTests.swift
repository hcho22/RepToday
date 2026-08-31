import XCTest
@testable import RepToday

let testCoachSafetyIdentifier = CoachSafetyIdentifier(
    rawValue: "coach-00000000-0000-4000-8000-000000000001"
)!

/// Tests US-AC01: the stateless coach transport client. It POSTs the audited `CoachContextBundle`
/// plus the user's message to the key-holding proxy and returns the Coach model's reply, throwing on any
/// failure so the (later, US-AC02) chat surface can degrade without ever blocking the core loop.
/// These drive it over a stub transport so the request/response contract and every failure path are
/// exercised without a live network - and prove an oversized/empty message is rejected *locally*,
/// before any call is even attempted.
final class CoachProxyClientTests: XCTestCase {

    private let endpoint = URL(string: "https://proxy.example.com/coach")!

    // MARK: - Stub transport

    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        enum Outcome {
            case success(data: Data, status: Int)
            case failure(Error)
        }
        var outcome: Outcome
        private(set) var lastURL: URL?
        private(set) var lastBody: Data?
        private(set) var lastHeaders: [String: String] = [:]
        private(set) var lastTimeout: Double?
        private(set) var callCount = 0

        init(_ outcome: Outcome) { self.outcome = outcome }

        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            callCount += 1
            lastURL = url
            lastBody = jsonBody
            lastHeaders = headers
            lastTimeout = timeoutSeconds
            switch outcome {
            case let .success(data, status): return (data, status)
            case let .failure(error): throw error
            }
        }
    }

    private struct TransportBoom: Error {}

    private func okData(reply: String) -> Data {
        Data(#"{"reply":"\#(reply)"}"#.utf8)
    }

    private func bundle() -> CoachContextBundle {
        CoachContextBundle(
            phase: "discipline",
            requestedMinutes: 15,
            chainPositions: [
                CoachContextBundle.ChainSummary(
                    pattern: "push", currentExercise: "Standard Push-Up",
                    tier: 3, chainLength: 7, hasNextTier: true
                ),
            ],
            recentPatterns: ["push", "core"],
            consistency: CoachContextBundle.ConsistencySummary(currentScore: 72, direction: .rising),
            strengthJourney: [
                CoachContextBundle.JourneySummary(pattern: "push", trend: "climbing", weeksAtCurrentTier: 0, hasAdvanced: true),
            ]
        )
    }

    // MARK: - Happy path

    func testSafetyIdentifierAcceptsOnlyNamespacedUUIDv4Values() {
        XCTAssertEqual(
            CoachSafetyIdentifier(rawValue: testCoachSafetyIdentifier.rawValue),
            testCoachSafetyIdentifier
        )
        XCTAssertNil(CoachSafetyIdentifier(rawValue: "00000000-0000-4000-8000-000000000001"))
        XCTAssertNil(CoachSafetyIdentifier(rawValue: "person@example.com"))
        XCTAssertNil(CoachSafetyIdentifier(rawValue: "coach-00000000-0000-1000-8000-000000000001"))
    }

    func testReturnsTrimmedReplyOnSuccess() async throws {
        let transport = StubTransport(.success(data: okData(reply: "  Because squats were stalest  "), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        let reply = try await client.reply(to: "why squats today?", context: bundle())

        XCTAssertEqual(reply, "Because squats were stalest")
        XCTAssertEqual(transport.callCount, 1, "exactly one Coach model call per request")
        XCTAssertEqual(transport.lastURL, endpoint)
        XCTAssertEqual(transport.lastTimeout, CoachProxyClient.defaultTimeoutSeconds)
    }

    /// The request body carries the context bundle, the (trimmed) message, and the dedicated
    /// pseudonymous safety identifier - never the installation or account identity.
    func testRequestBodyCarriesContextMessageAndSafetyIdentifierOnly() async throws {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        _ = try await client.reply(to: "  how do I do a pistol squat?  ", context: bundle())

        let body = try XCTUnwrap(transport.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["context", "message", "safetyIdentifier"])
        XCTAssertEqual(json["message"] as? String, "how do I do a pistol squat?")
        XCTAssertEqual(json["safetyIdentifier"] as? String, "coach-00000000-0000-4000-8000-000000000001")
        let context = try XCTUnwrap(json["context"] as? [String: Any])
        XCTAssertEqual(context["phase"] as? String, "discipline")

        // No identity field anywhere in the outbound body.
        let wire = String(decoding: body, as: UTF8.self).lowercased()
        for forbidden in ["installid", "idfa", "appleid", "email", "keychain"] {
            XCTAssertFalse(wire.contains(forbidden))
        }
    }

    func testRequestReadsRotatedSafetyIdentifierFromProvider() async throws {
        let suiteName = "CoachProxyClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(userDefaults: defaults)
        let original = appState.coachSafetyIdentifier
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(
            endpoint: endpoint,
            safetyIdentifierProvider: appState.coachSafetyIdentifierProvider,
            transport: transport
        )

        _ = try await client.reply(to: "first", context: bundle())
        let firstBody = try XCTUnwrap(transport.lastBody)
        let firstJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        XCTAssertEqual(firstJSON["safetyIdentifier"] as? String, original.rawValue)

        appState.rotateCoachSafetyIdentifier()
        _ = try await client.reply(to: "second", context: bundle())
        let secondBody = try XCTUnwrap(transport.lastBody)
        let secondJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        XCTAssertEqual(secondJSON["safetyIdentifier"] as? String, appState.coachSafetyIdentifier.rawValue)
        XCTAssertNotEqual(secondJSON["safetyIdentifier"] as? String, original.rawValue)
    }

    func testSendsAuthorizationHeaderWhenSharedSecretConfigured() async throws {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(
            endpoint: endpoint,
            sharedSecret: "s3cret",
            safetyIdentifier: testCoachSafetyIdentifier,
            transport: transport
        )

        _ = try await client.reply(to: "hi", context: bundle())

        XCTAssertEqual(transport.lastHeaders["Authorization"], "Bearer s3cret")
    }

    func testOmitsAuthorizationHeaderWhenNoSharedSecret() async throws {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        _ = try await client.reply(to: "hi", context: bundle())

        XCTAssertNil(transport.lastHeaders["Authorization"])
    }

    func testHonorsInjectedTimeout() async throws {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(
            endpoint: endpoint,
            timeoutSeconds: 12,
            safetyIdentifier: testCoachSafetyIdentifier,
            transport: transport
        )

        _ = try await client.reply(to: "hi", context: bundle())

        XCTAssertEqual(transport.lastTimeout, 12)
    }

    // MARK: - Local rejection (never touches the network)

    func testRejectsEmptyMessageBeforeAnyCall() async {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "   ", context: bundle())) { error in
            XCTAssertEqual(error as? CoachProxyClient.CoachError, .emptyMessage)
        }
        XCTAssertEqual(transport.callCount, 0, "an empty message must never bill a model call")
    }

    func testRejectsOverLengthMessageBeforeAnyCall() async {
        let transport = StubTransport(.success(data: okData(reply: "ok"), status: 200))
        let client = CoachProxyClient(
            endpoint: endpoint,
            messageCharacterLimit: 10,
            safetyIdentifier: testCoachSafetyIdentifier,
            transport: transport
        )

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "way too long a message", context: bundle())) { error in
            XCTAssertEqual(error as? CoachProxyClient.CoachError, .messageTooLong(limit: 10))
        }
        XCTAssertEqual(transport.callCount, 0, "an oversized message must never bill a model call")
    }

    // MARK: - Failure paths (all throw so the caller degrades)

    func testThrowsOnNon2xxStatus() async {
        let transport = StubTransport(.success(data: Data(#"{"error":"upstream_error"}"#.utf8), status: 502))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "hi", context: bundle())) { error in
            XCTAssertEqual(error as? CoachProxyClient.CoachError, .badStatus(502))
        }
    }

    func testThrowsOnEmptyReply() async {
        let transport = StubTransport(.success(data: okData(reply: "   "), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "hi", context: bundle())) { error in
            XCTAssertEqual(error as? CoachProxyClient.CoachError, .emptyReply)
        }
    }

    func testMapsSafetyRefusalOutcomeToTypedError() async {
        let data = Data(#"{"outcome":"safety_refusal"}"#.utf8)
        let transport = StubTransport(.success(data: data, status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "unsafe request", context: bundle())) { error in
            XCTAssertEqual(error as? CoachProxyClient.CoachError, .safetyRefusal)
        }
    }

    func testThrowsOnUndecodableBody() async {
        let transport = StubTransport(.success(data: Data("not json".utf8), status: 200))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "hi", context: bundle()))
    }

    func testPropagatesTransportFailure() async {
        let transport = StubTransport(.failure(TransportBoom()))
        let client = CoachProxyClient(endpoint: endpoint, safetyIdentifier: testCoachSafetyIdentifier, transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.reply(to: "hi", context: bundle())) { error in
            XCTAssertTrue(error is TransportBoom)
        }
    }
}

// MARK: - Async throwing assertion helper

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ onError: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message.isEmpty ? "Expected an error to be thrown" : message, file: file, line: line)
    } catch {
        onError(error)
    }
}
