import XCTest
@testable import RepToday

/// Tests US-N05: the thin stateless proxy client that fulfills the Variety Language LLM seam.
///
/// The proxy provider (`ProxyVarietyLanguageProvider`) POSTs only the engine's contrast - no user
/// logs, no PII - to the key-holding proxy and returns the LLM line, throwing on any failure so the
/// resolver falls back to the deterministic template. These tests drive it over a stub transport so
/// the request/response contract and every failure path are exercised without a live network, plus
/// an end-to-end check that the resolver composes it correctly.
final class ProxyVarietyLanguageProviderTests: XCTestCase {

    private let endpoint = URL(string: "https://proxy.example.com/variety-language")!

    // MARK: - Stub transport

    /// A transport that records the last request and returns a canned result or throws.
    private final class StubTransport: VarietyLanguageProxyTransport, @unchecked Sendable {
        enum Outcome {
            case success(data: Data, status: Int)
            case failure(Error)
        }
        var outcome: Outcome
        // Captured from the most recent call.
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

    private func okData(line: String) -> Data {
        Data(#"{"line":"\#(line)"}"#.utf8)
    }

    private func contrast(today: Pillar, yesterday: Pillar?) -> VarietyLanguage.SessionContrast {
        VarietyLanguage.SessionContrast(today: today, yesterday: yesterday)
    }

    private func user() -> User {
        var user = User(
            id: "u1",
            displayName: "Test",
            createdAt: Date(timeIntervalSince1970: 0),
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .beginner,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 8
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: true)
        return user
    }

    // MARK: - Happy path

    func testReturnsTrimmedLineOnSuccess() async throws {
        let transport = StubTransport(.success(data: okData(line: "  Today leans into mobility  "), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        let line = try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())

        XCTAssertEqual(line, "Today leans into mobility")
        XCTAssertEqual(transport.callCount, 1, "exactly one Claude call per request (US-N05)")
        XCTAssertEqual(transport.lastURL, endpoint)
        XCTAssertEqual(transport.lastTimeout, ProxyVarietyLanguageProvider.defaultTimeoutSeconds)
    }

    /// The request carries the contrast (machine pillars + human labels) and nothing else - no user
    /// PII or logs.
    func testRequestBodyCarriesContrastOnly() async throws {
        let transport = StubTransport(.success(data: okData(line: "ok"), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        _ = try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())

        let body = try XCTUnwrap(transport.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["today"] as? String, "mobility")
        XCTAssertEqual(json["yesterday"] as? String, "strength")
        XCTAssertEqual(json["todayLabel"] as? String, "mobility")
        XCTAssertEqual(json["yesterdayLabel"] as? String, "strength")
        // No user identity, profile, why, or history is ever forwarded.
        XCTAssertEqual(Set(json.keys), ["today", "yesterday", "todayLabel", "yesterdayLabel"])
    }

    /// With no genuine prior contrast, `yesterday` is omitted so the proxy can never invent one.
    func testRequestOmitsYesterdayWhenAbsent() async throws {
        let transport = StubTransport(.success(data: okData(line: "ok"), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        _ = try await provider.line(for: contrast(today: .strength, yesterday: nil), user: user())

        let body = try XCTUnwrap(transport.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["today"] as? String, "strength")
        XCTAssertNil(json["yesterday"])
        XCTAssertNil(json["yesterdayLabel"])
    }

    /// When a shared secret is configured, the request carries `Authorization: Bearer <secret>` so
    /// the Worker's abuse gate accepts it.
    func testSendsAuthorizationHeaderWhenSharedSecretConfigured() async throws {
        let transport = StubTransport(.success(data: okData(line: "ok"), status: 200))
        let provider = ProxyVarietyLanguageProvider(
            endpoint: endpoint,
            sharedSecret: "s3cret",
            transport: transport
        )

        _ = try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())

        XCTAssertEqual(transport.lastHeaders["Authorization"], "Bearer s3cret")
    }

    /// With no shared secret (the default), no `Authorization` header is sent (an open dev Worker).
    func testOmitsAuthorizationHeaderWhenNoSharedSecret() async throws {
        let transport = StubTransport(.success(data: okData(line: "ok"), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        _ = try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())

        XCTAssertNil(transport.lastHeaders["Authorization"])
    }

    func testHonorsInjectedTimeout() async throws {
        let transport = StubTransport(.success(data: okData(line: "ok"), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, timeoutSeconds: 1.5, transport: transport)

        _ = try await provider.line(for: contrast(today: .primal, yesterday: nil), user: user())

        XCTAssertEqual(transport.lastTimeout, 1.5)
    }

    // MARK: - Failure paths (all throw so the resolver falls back)

    func testThrowsOnNon2xxStatus() async {
        let transport = StubTransport(.success(data: Data(#"{"error":"upstream_error"}"#.utf8), status: 502))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())
        ) { error in
            XCTAssertEqual(error as? ProxyVarietyLanguageProvider.ProxyError, .badStatus(502))
        }
    }

    func testThrowsOnEmptyLine() async {
        let transport = StubTransport(.success(data: okData(line: "   "), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())
        ) { error in
            XCTAssertEqual(error as? ProxyVarietyLanguageProvider.ProxyError, .emptyLine)
        }
    }

    func testThrowsOnUndecodableBody() async {
        let transport = StubTransport(.success(data: Data("not json".utf8), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())
        )
    }

    func testPropagatesTransportFailure() async {
        let transport = StubTransport(.failure(TransportBoom()))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await provider.line(for: contrast(today: .mobility, yesterday: .strength), user: user())
        ) { error in
            XCTAssertTrue(error is TransportBoom)
        }
    }

    // MARK: - End-to-end through the resolver

    /// Online, cold-start-active, and this provider wired: the resolver uses the proxy's line and
    /// marks it `.llm`.
    func testResolverUsesProxyLineWhenOnline() async {
        let transport = StubTransport(.success(data: okData(line: "A fresh mobility day after yesterday's strength"), status: 200))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)
        let resolver = VarietyLanguageResolver(provider: provider, isOnline: { true })

        let workout = Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            shape: .singleFocus,
            focusPillar: .mobility,
            requestedMinutes: 8,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-Up", category: .warmup, exercises: []),
                WorkoutBlock(id: UUID(), title: "Training", category: .mobility, exercises: []),
            ]
        )
        let previous = WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: Date(timeIntervalSince1970: 0),
            requestedMinutes: 8,
            durationMinutes: 8,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
        let note = await resolver.note(for: workout, previousLog: previous, user: user())
        XCTAssertEqual(note?.source, .llm)
        XCTAssertEqual(note?.text, "A fresh mobility day after yesterday's strength")
    }

    /// A proxy failure through the resolver falls back to the deterministic template - never blocks.
    func testResolverFallsBackWhenProxyFails() async {
        let transport = StubTransport(.failure(TransportBoom()))
        let provider = ProxyVarietyLanguageProvider(endpoint: endpoint, transport: transport)
        let resolver = VarietyLanguageResolver(provider: provider, isOnline: { true })

        let workout = Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            shape: .singleFocus,
            focusPillar: .mobility,
            requestedMinutes: 8,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-Up", category: .warmup, exercises: []),
                WorkoutBlock(id: UUID(), title: "Training", category: .mobility, exercises: []),
            ]
        )
        let previous = WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: Date(timeIntervalSince1970: 0),
            requestedMinutes: 8,
            durationMinutes: 8,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
        let note = await resolver.note(for: workout, previousLog: previous, user: user())
        XCTAssertEqual(note?.source, .template)
        XCTAssertEqual(note?.text, "Today's a mobility day - yesterday was strength")
    }
}

// MARK: - Async throwing assertion helper

/// Awaits an async throwing expression and fails if it does not throw, otherwise runs `onError`.
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
