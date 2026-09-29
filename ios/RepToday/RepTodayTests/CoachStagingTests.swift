#if COACH_STAGING
import XCTest
import CryptoKit
@testable import RepToday

// Staging lane doubles only: no Apple service, Keychain, network or production URL is used.
private let stagingEndpoint = URL(string: "https://reptoday-coach-staging.fixture-account.workers.dev/coach")!
private let stagingKey = Data(repeating: 7, count: 32).base64EncodedString()
private let stagingChallenge = "eA." + String(repeating: "A", count: 43) // Shape fixture; never a valid server HMAC.

private final class StagingKeyStore: CoachAuthenticationKeyStoring, @unchecked Sendable {
    private let lock = NSLock(); private var key: String?
    init(_ key: String? = stagingKey) { self.key = key }
    func load() -> String? { lock.lock(); defer { lock.unlock() }; return key }
    func save(_ key: String?) { lock.lock(); defer { lock.unlock() }; self.key = key }
}
private actor StagingAttester: CoachAppAttesting {
    nonisolated let isSupported = true
    private(set) var hashes = [Data]()
    func generateKey() async throws -> String { stagingKey }
    static let attestationObject = Data((0..<2000).map { UInt8($0 % 251) })
    func attest(key: String, hash: Data) async throws -> Data { Self.attestationObject }
    func assertion(key: String, hash: Data) async throws -> Data { hashes.append(hash); return Data([2]) }
}
private struct StagingPurchase: CoachPurchaseProofProviding {
    func appStorePremiumProof() async throws -> String { "fixture.purchase.proof" }
}
private final class StagingLines: @unchecked Sendable {
    private let lock = NSLock(); private var values = [String]()
    func append(_ line: String) { lock.lock(); values.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return values }
}

private final class StagingHTTPState: @unchecked Sendable {
    struct Answer { var status: Int; var body: String; var label: String?; var digest: String? = nil }
    struct Seen { let url: URL?; let headers: [String: String]; let body: Data }
    private let lock = NSLock(); private var answers = [Answer](); private var seen = [Seen]()
    func set(_ answers: [Answer]) { lock.lock(); self.answers = answers; seen = []; lock.unlock() }
    func next(_ request: URLRequest, body: Data) -> Answer? {
        lock.lock(); defer { lock.unlock() }
        seen.append(Seen(url: request.url, headers: request.allHTTPHeaderFields ?? [:], body: body))
        return answers.isEmpty ? nil : answers.removeFirst()
    }
    var requests: [Seen] { lock.lock(); defer { lock.unlock() }; return seen }
}
private final class StagingHTTPFixture: URLProtocol, @unchecked Sendable {
    static let state = StagingHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true } // Captures every URL: no network fallback.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
        }
        guard request.url == stagingEndpoint, let answer = Self.state.next(request, body: body) else {
            client?.urlProtocol(self, didFailWithError: CoachAuthenticationError.unavailable); return
        }
        var headers = ["Content-Type": "application/json"]
        if let label = answer.label { headers[CoachStagingLabels.header] = label }
        if let digest = answer.digest { headers[CoachStagingLabels.digestHeader] = digest }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CoachStagingTests: XCTestCase {
    private func context() -> CoachContextBundle {
        CoachContextBundle(phase: "discipline", requestedMinutes: 20, chainPositions: [], recentPatterns: ["push"],
                           consistency: .init(currentScore: 63, direction: .rising), strengthJourney: [])
    }
    private func stagingClient(attester: StagingAttester, lines: StagingLines,
                               keys: any CoachAuthenticationKeyStoring = StagingKeyStore()) -> CoachProxyClient {
        CoachStaging.client(endpoint: stagingEndpoint, safetyIdentifierProvider: { testCoachSafetyIdentifier },
                            diagnostics: CoachDiagnostics { lines.append($0) }, attester: attester, purchase: StagingPurchase(),
                            keys: keys, configuration: {
                                let configuration = URLSessionConfiguration.ephemeral
                                configuration.protocolClasses = [StagingHTTPFixture.self]; return configuration })
    }
    private let challengeAnswer = StagingHTTPState.Answer(status: 200, body: #"{"challenge":"\#(stagingChallenge)"}"#, label: nil)

    func testStagingEndpointAcceptsOnlyTheSeparateWorkersDevCoachURL() {
        XCTAssertEqual(CoachStaging.endpoint(stagingEndpoint), stagingEndpoint)
        for value in ["https://coach.reptoday.app/coach", "http://reptoday-coach-staging.fixture-account.workers.dev/coach",
                      "https://reptoday-coach-staging.fixture-account.workers.dev/other",
                      "https://reptoday-coach-staging.fixture-account.workers.dev/coach?x=1",
                      "https://reptoday-coach-staging.fixture-account.workers.dev:8443/coach",
                      "https://reptoday-variety-language-proxy.fixture-account.workers.dev/coach",
                      "https://reptoday-coach-staging.workers.dev/coach", "https://reptoday-coach-staging.evil.example/coach"] {
            XCTAssertNil(URL(string: value).flatMap(CoachStaging.endpoint), value)
        }
    }

    func testLabelsKeepOnlyTheServerVocabularyAndAreConsumedByOneLine() {
        let labels = CoachStagingLabels()
        labels.record("do_assertion/assertion_signature")
        XCTAssertEqual(labels.annotate("line"), "line label=do_assertion/assertion_signature")
        XCTAssertEqual(labels.annotate("next"), "next")
        for value in ["do_assertion/PRIVATE", "do_state", "do_state/pending_challenge/x", "worker_premium/token_mac", "", nil] {
            labels.record(value); XCTAssertEqual(labels.annotate("line"), "line", String(describing: value))
        }
        labels.record("worker_premium/status_match"); labels.record(nil)
        XCTAssertEqual(labels.annotate("line"), "line")
        XCTAssertEqual(CoachStagingLabels.valid("worker_envelope/envelope"), "worker_envelope/envelope")
    }

    func testClientVocabularyExactlyMatchesTheServerContract() throws {
        let encoded = try XCTUnwrap(ProcessInfo.processInfo.environment["COACH_STAGING_LABELS_CONTRACT"])
        let data = try XCTUnwrap(encoded.data(using: .utf8))
        XCTAssertEqual(CoachStagingLabels.all, Set(try JSONDecoder().decode([String].self, from: data)))
    }

    func testStagingSendsEveryRequestToStagingButSignsTheProductionProtocolOrigin() async throws {
        let attester = StagingAttester(), lines = StagingLines()
        StagingHTTPFixture.state.set([challengeAnswer,
            .init(status: 401, body: #"{"error":"unauthorized"}"#, label: "do_assertion/assertion_signature")])
        do { _ = try await stagingClient(attester: attester, lines: lines).reply(to: "hello", context: context()); XCTFail("must reject") }
        catch CoachProxyClient.CoachError.badStatus(let status) { XCTAssertEqual(status, 401) }
        let requests = StagingHTTPFixture.state.requests
        XCTAssertEqual(requests.map(\.url), [stagingEndpoint, stagingEndpoint])
        XCTAssertNil(requests[0].headers["X-RepToday-Coach-Auth"])
        XCTAssertNotNil(requests[1].headers["X-RepToday-Coach-Auth"])
        // The signed payload names the production origin, byte-identical to a production send.
        let hex = { (data: Data) in SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let payload = try encoder.encode(["reptoday-coach-auth-v1", "POST", "https://coach.reptoday.app/coach", "reply",
                                          stagingKey, stagingChallenge, hex(requests[1].body), hex(Data("fixture.purchase.proof".utf8))])
        let hashes = await attester.hashes
        XCTAssertEqual(hashes, [Data(SHA256.hash(data: payload))])
        XCTAssertEqual(lines.all.first, "[RepTodayCoach] transport=runtime endpoint=other stage=http category=http status=401 error=unauthorized label=do_assertion/assertion_signature")
        // An assertion rejection also logs what was signed (no attestation: this key was already enrolled).
        XCTAssertEqual(lines.all.dropFirst().map { $0.components(separatedBy: " ").prefix(3).joined(separator: " ") },
                       ["[RepTodayCoach] staging signed", "[RepTodayCoach] staging clientDataHash=\(hex(payload))", "[RepTodayCoach] staging assertion=Ag=="])
    }

    func testStagingChallengeRejectionCarriesItsLabelAndUnknownLabelsAreDropped() async throws {
        let lines = StagingLines()
        StagingHTTPFixture.state.set([.init(status: 401, body: #"{"error":"unauthorized"}"#, label: "do_token_entry/token_future")])
        do { _ = try await stagingClient(attester: StagingAttester(), lines: lines).reply(to: "hello", context: context()); XCTFail("must fail") }
        catch {}
        XCTAssertEqual(lines.all, ["[RepTodayCoach] transport=runtime endpoint=other stage=challenge category=http status=401 error=unauthorized label=do_token_entry/token_future"])
        let unknown = StagingLines()
        StagingHTTPFixture.state.set([.init(status: 401, body: #"{"error":"unauthorized"}"#, label: "PRIVATE/SENTINEL")])
        do { _ = try await stagingClient(attester: StagingAttester(), lines: unknown).reply(to: "hello", context: context()); XCTFail("must fail") }
        catch {}
        XCTAssertEqual(unknown.all, ["[RepTodayCoach] transport=runtime endpoint=other stage=challenge category=http status=401 error=unauthorized"])
    }

    func testStagingKeyStoreNeverTouchesTheProductionKey() throws {
        let suite = "CoachStagingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let production = DefaultsCoachAuthenticationKeyStore(defaults: defaults)
        let staging = DefaultsCoachAuthenticationKeyStore(defaults: defaults, name: CoachStaging.keyStoreName)
        production.save("production-key")
        XCTAssertNil(staging.load())
        staging.save("staging-key"); staging.save(nil)
        XCTAssertEqual(production.load(), "production-key")
    }

    func testLegacyStagingKeyDoesNotSuppressEnrollmentOrAttestationEvidence() async throws {
        let suite = "CoachStagingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        DefaultsCoachAuthenticationKeyStore(defaults: defaults, name: "coachStagingAppAttestKeyV1").save("legacy-staging-key")
        let current = DefaultsCoachAuthenticationKeyStore(defaults: defaults, name: CoachStaging.keyStoreName)
        let lines = StagingLines()
        StagingHTTPFixture.state.set([challengeAnswer, .init(status: 200, body: #"{"enrolled":true}"#, label: nil), challengeAnswer,
            .init(status: 401, body: rejected, label: "do_assertion/assertion_signature", digest: serverDigest)])

        do {
            _ = try await stagingClient(attester: StagingAttester(), lines: lines, keys: current).reply(to: "hello", context: context())
            XCTFail("must reject")
        } catch CoachProxyClient.CoachError.badStatus(let status) {
            XCTAssertEqual(status, 401)
        }

        let requests = StagingHTTPFixture.state.requests
        XCTAssertEqual(requests.count, 4)
        let enrollment = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: String])
        XCTAssertEqual(enrollment["operation"], "enroll")
        XCTAssertEqual(enrollment["keyId"], stagingKey)
        XCTAssertEqual(current.load(), stagingKey)
        XCTAssertTrue(lines.all.contains { $0.hasPrefix("[RepTodayCoach] staging attestation part=1/") })
    }

    func testProductionTransportStillRefusesAnyOtherDestination() async {
        let transport = BoundedCoachHTTPTransport(configuration: {
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StagingHTTPFixture.self]; return configuration })
        StagingHTTPFixture.state.set([challengeAnswer])
        do { _ = try await transport.post(to: stagingEndpoint, jsonBody: Data("{}".utf8), headers: [:], timeoutSeconds: 5); XCTFail("must refuse") }
        catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
        XCTAssertTrue(StagingHTTPFixture.state.requests.isEmpty)
    }

    private let serverDigest = "payload=0123456789abcdef body=0123456789abcdef transaction=0123456789abcdef challenge=eyJ2Ijoi"
    private let rejected = #"{"error":"unauthorized"}"#

    func testAssertionRejectionLogsWhatTheDeviceSignedBesideTheServerDigests() async throws {
        let attester = StagingAttester(), lines = StagingLines()
        StagingHTTPFixture.state.set([challengeAnswer, .init(status: 200, body: #"{"enrolled":true}"#, label: nil), challengeAnswer,
            .init(status: 401, body: rejected, label: "do_assertion/assertion_signature", digest: serverDigest)])
        do { _ = try await stagingClient(attester: attester, lines: lines, keys: StagingKeyStore(nil)).reply(to: "hello", context: context())
             XCTFail("must reject") }
        catch CoachProxyClient.CoachError.badStatus(let status) { XCTAssertEqual(status, 401) }
        let requests = StagingHTTPFixture.state.requests
        let hex = { (data: Data) in SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let body = requests[3].body, transaction = "fixture.purchase.proof"
        let payload = try encoder.encode(["reptoday-coach-auth-v1", "POST", "https://coach.reptoday.app/coach", "reply",
                                          stagingKey, stagingChallenge, hex(body), hex(Data(transaction.utf8))])
        let attestation = StagingAttester.attestationObject.base64EncodedString()
        let parts = stride(from: 0, to: attestation.count, by: 800).map { start -> String in
            let from = attestation.index(attestation.startIndex, offsetBy: start)
            return String(attestation[from..<attestation.index(from, offsetBy: min(800, attestation.count - start))]) }
        XCTAssertEqual(lines.all, [
            "[RepTodayCoach] transport=runtime endpoint=other stage=http category=http status=401 error=unauthorized label=do_assertion/assertion_signature server \(serverDigest)",
            "[RepTodayCoach] staging signed payload=\(hex(payload).prefix(16)) body=\(hex(body).prefix(16)) transaction=\(hex(Data(transaction.utf8)).prefix(16)) challenge=\(stagingChallenge.prefix(8))",
            "[RepTodayCoach] staging clientDataHash=\(hex(payload))",
            "[RepTodayCoach] staging assertion=\(Data([2]).base64EncodedString())",
        ] + parts.enumerated().map { "[RepTodayCoach] staging attestation part=\($0.offset + 1)/\(parts.count) \($0.element)" })
        XCTAssertEqual(parts.count, 4)
        let hashes = await attester.hashes
        XCTAssertEqual(hashes, [Data(SHA256.hash(data: payload))])
    }

    func testOnlyAssertionRejectionsAddSigningDetailAndMalformedDigestsAreDropped() async throws {
        for (label, digest, expectedSuffix) in [("worker_premium/status_match", serverDigest, " label=worker_premium/status_match"),
                                                ("do_assertion/assertion_signature", "payload=PRIVATE", " label=do_assertion/assertion_signature")] {
            let lines = StagingLines()
            StagingHTTPFixture.state.set([challengeAnswer, .init(status: 401, body: rejected, label: label, digest: digest)])
            do { _ = try await stagingClient(attester: StagingAttester(), lines: lines).reply(to: "hello", context: context()); XCTFail("must reject") }
            catch {}
            let first = try XCTUnwrap(lines.all.first)
            XCTAssertTrue(first.hasSuffix(expectedSuffix), first)
            XCTAssertFalse(first.contains("server"))
            if label.hasPrefix("worker_") { XCTAssertEqual(lines.all.count, 1) }
            XCTAssertFalse(lines.all.contains { $0.contains("attestation part=") })
        }
    }
}
#endif
