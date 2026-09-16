import Foundation
import CryptoKit
import DeviceCheck
import StoreKit

enum CoachAuthenticationError: Error, Equatable { case unavailable, invalidKey, timeout }

protocol CoachAppAttesting: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attest(key: String, hash: Data) async throws -> Data
    func assertion(key: String, hash: Data) async throws -> Data
}
protocol CoachPurchaseProofProviding: Sendable {
    func productionPremiumProof() async throws -> String
}
protocol CoachAuthenticationKeyStoring: Sendable {
    func load() -> String?
    func save(_ key: String?)
}

/// Only a non-secret App Attest key identifier is stored locally. Apple owns its private key.
/// A reinstall/new account gets a fresh key; the server independently expires old metadata.
final class DefaultsCoachAuthenticationKeyStore: CoachAuthenticationKeyStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let name = "coachProductionAppAttestKeyV1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> String? { lock.lock(); defer { lock.unlock() }; return defaults.string(forKey: name) }
    func save(_ key: String?) { lock.lock(); defer { lock.unlock() }; defaults.set(key, forKey: name) }
}

struct DeviceCoachAppAttester: CoachAppAttesting {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }
    static func authenticationError(_ error: Error?) -> CoachAuthenticationError {
        guard let error = error as NSError?, error.domain == DCErrorDomain,
              error.code == DCError.invalidKey.rawValue else { return .unavailable }
        return .invalidKey
    }
    func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateKey { value, error in
                if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: Self.authenticationError(error)) }
            }
        }
    }
    func attest(key: String, hash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.attestKey(key, clientDataHash: hash) { value, error in
                if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: Self.authenticationError(error)) }
            }
        }
    }
    func assertion(key: String, hash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateAssertion(key, clientDataHash: hash) { value, error in
                if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: Self.authenticationError(error)) }
            }
        }
    }
}

struct StoreKitCoachPurchaseProof: CoachPurchaseProofProviding {
    func productionPremiumProof() async throws -> String {
        // No local premium boolean, AppState trial date, sign-in identity or restore exclusivity.
        // Sandbox/TestFlight/Xcode transactions cannot authorize the production model endpoint.
        let products = Set(SubscriptionPlan.ProductID.all)
        for await verification in Transaction.currentEntitlements {
            try Task.checkCancellation()
            guard case .verified(let transaction) = verification,
                  products.contains(transaction.productID), transaction.productType == .autoRenewable,
                  transaction.environment == .production, transaction.revocationDate == nil,
                  !transaction.isUpgraded, let expiry = transaction.expirationDate, expiry > Date()
            else { continue }
            let proof = verification.jwsRepresentation
            guard !proof.isEmpty, proof.utf8.count <= 12_000 else { continue }
            return proof
        }
        throw CoachAuthenticationError.unavailable
    }
}

/// Serializes the complete challenge/assertion exchange. Reentrant sends fail promptly instead of
/// overwriting another turn's one-time server challenge. The UI already admits one send at a time.
/// Every await, including non-cancellable Apple callbacks, fits inside the client's total deadline.
actor RuntimeAuthenticatedCoachTransport: CoachProxyTransport {
    static let origin = URL(string: "https://coach.reptoday.app/coach")!
    static let protocolVersion = "reptoday-coach-auth-v1"
    private let attester: any CoachAppAttesting
    private let purchase: any CoachPurchaseProofProviding
    private let keys: any CoachAuthenticationKeyStoring
    private let http: any CoachProxyTransport
    private var busy = false
    private var generation: UInt64 = 0

    init(attester: any CoachAppAttesting = DeviceCoachAppAttester(),
         purchase: any CoachPurchaseProofProviding = StoreKitCoachPurchaseProof(),
         keys: any CoachAuthenticationKeyStoring = DefaultsCoachAuthenticationKeyStore(),
         http: any CoachProxyTransport = BoundedCoachHTTPTransport()) {
        self.attester = attester; self.purchase = purchase; self.keys = keys; self.http = http
    }

    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        guard url == Self.origin, headers.isEmpty, jsonBody.count <= 32_768, timeoutSeconds.isFinite,
              timeoutSeconds > 0, timeoutSeconds <= 30, !busy, attester.isSupported else {
            throw CoachAuthenticationError.unavailable
        }
        busy = true; defer { busy = false }
        let expectedGeneration = generation
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        return try await boundedCoachOperation(seconds: timeoutSeconds) {
            try await self.send(body: jsonBody, generation: expectedGeneration, deadline: deadline)
        }
    }

    private func remaining(_ deadline: Double, _ expected: UInt64) throws -> Double {
        try Task.checkCancellation()
        let left = deadline - ProcessInfo.processInfo.systemUptime
        guard left > 0, generation == expected else { throw CoachAuthenticationError.timeout }
        return left
    }
    private static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    private static func hex(_ data: Data) -> String { digest(data).map { String(format: "%02x", $0) }.joined() }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(value)
    }
    private func handshake(_ input: [String: String], generation expected: UInt64, deadline: Double) async throws -> (Data, Int) {
        let left = try remaining(deadline, expected)
        let result = try await http.post(to: Self.origin, jsonBody: Self.encode(input), headers: [:], timeoutSeconds: min(left, 10))
        _ = try remaining(deadline, expected)
        guard result.data.count <= 1024 else { throw CoachAuthenticationError.unavailable }
        return (result.data, result.statusCode)
    }
    private func challenge(key: String, kind: String, generation expected: UInt64, deadline: Double) async throws -> String {
        let (data, status) = try await handshake(["operation": "challenge", "kind": kind, "keyId": key], generation: expected, deadline: deadline)
        if status == 401, (try? JSONDecoder().decode(AuthError.self, from: data).error) == "key_unavailable" {
            throw KeyUnavailable()
        }
        guard status == 200, let challenge = try? JSONDecoder().decode(Challenge.self, from: data).challenge,
              !challenge.isEmpty, challenge.utf8.count <= 512,
              challenge.range(of: "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        else { throw CoachAuthenticationError.unavailable }
        return challenge
    }
    private func enroll(generation expected: UInt64, deadline: Double) async throws -> String {
        let key = try await attester.generateKey()
        _ = try remaining(deadline, expected)
        guard Self.validKey(key) else { throw CoachAuthenticationError.unavailable }
        let token = try await challenge(key: key, kind: "enroll", generation: expected, deadline: deadline)
        let attestation = try await attester.attest(key: key, hash: Self.digest(Data(token.utf8)))
        _ = try remaining(deadline, expected)
        guard !attestation.isEmpty, attestation.count <= 8192 else { throw CoachAuthenticationError.unavailable }
        let (data, status) = try await handshake(["operation": "enroll", "keyId": key, "challenge": token,
                                                "attestation": attestation.base64EncodedString()], generation: expected, deadline: deadline)
        guard status == 200, (try? JSONDecoder().decode(Enrollment.self, from: data).enrolled) == true else { throw CoachAuthenticationError.unavailable }
        _ = try remaining(deadline, expected)
        keys.save(key) // Only persist an enrolled key; a failed/ambiguous enrollment uses a fresh key next time.
        return key
    }
    private static func validKey(_ value: String) -> Bool {
        guard let data = Data(base64Encoded: value) else { return false }
        return data.count == 32 && data.base64EncodedString() == value
    }
    private func send(body: Data, generation expected: UInt64, deadline: Double) async throws -> (data: Data, statusCode: Int) {
        let transaction = try await purchase.productionPremiumProof()
        _ = try remaining(deadline, expected)
        guard !transaction.isEmpty, transaction.utf8.count <= 12_000 else { throw CoachAuthenticationError.unavailable }
        var key = keys.load()
        var enrolledFreshly = false
        if key.map(Self.validKey) != true {
            key = try await enroll(generation: expected, deadline: deadline)
            enrolledFreshly = true
        }
        guard var enrolled = key else { throw CoachAuthenticationError.unavailable }
        var token: String
        do { token = try await challenge(key: enrolled, kind: "assert", generation: expected, deadline: deadline) }
        catch is KeyUnavailable {
            _ = try remaining(deadline, expected); keys.save(nil)
            enrolled = try await enroll(generation: expected, deadline: deadline)
            enrolledFreshly = true
            token = try await challenge(key: enrolled, kind: "assert", generation: expected, deadline: deadline)
        }
        let headers: [String: String]
        do {
            headers = try await proof(operation: "reply", key: enrolled, challenge: token, body: body,
                                      transaction: transaction, generation: expected, deadline: deadline)
        } catch CoachAuthenticationError.invalidKey {
            _ = try remaining(deadline, expected)
            keys.save(nil)
            guard !enrolledFreshly else { throw CoachAuthenticationError.unavailable }
            enrolled = try await enroll(generation: expected, deadline: deadline)
            token = try await challenge(key: enrolled, kind: "assert", generation: expected, deadline: deadline)
            do {
                headers = try await proof(operation: "reply", key: enrolled, challenge: token, body: body,
                                          transaction: transaction, generation: expected, deadline: deadline)
            } catch CoachAuthenticationError.invalidKey {
                _ = try remaining(deadline, expected)
                keys.save(nil)
                throw CoachAuthenticationError.unavailable
            }
        }
        let left = try remaining(deadline, expected)
        let result = try await http.post(to: Self.origin, jsonBody: body, headers: headers, timeoutSeconds: left)
        _ = try remaining(deadline, expected)
        return result // No retry of the final paid request, including ambiguous network failures.
    }
    private func proof(operation: String, key: String, challenge: String, body: Data, transaction: String,
                       generation expected: UInt64, deadline: Double) async throws -> [String: String] {
        let payload = try Self.encode([Self.protocolVersion, "POST", Self.origin.absoluteString, operation,
                                       key, challenge, Self.hex(body), Self.hex(Data(transaction.utf8))])
        let assertion = try await attester.assertion(key: key, hash: Self.digest(payload))
        _ = try remaining(deadline, expected)
        guard !assertion.isEmpty, assertion.count <= 1024 else { throw CoachAuthenticationError.unavailable }
        let encoded = try Self.encode(["operation": operation, "keyId": key, "challenge": challenge,
                                       "assertion": assertion.base64EncodedString(), "transactionJws": transaction])
        guard encoded.count <= 20_000, let value = String(data: encoded, encoding: .utf8) else { throw CoachAuthenticationError.unavailable }
        return ["X-RepToday-Coach-Auth": value]
    }

    /// Immediate local unlink/cancellation boundary; network cleanup is best effort, at most 5s.
    /// If offline/busy/unsupported, security metadata expires within 30 days of its last activity.
    func resetAccount() {
        let previous = keys.load(); keys.save(nil); generation &+= 1
        guard !busy, attester.isSupported, let key = previous, Self.validKey(key) else { return }
        let expected = generation
        Task {
            await self.eraseBounded(key: key, generation: expected)
        }
    }
    private func eraseBounded(key: String, generation expected: UInt64) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        _ = try? await boundedCoachOperation(seconds: 5) {
            try await self.erase(key: key, generation: expected, deadline: deadline)
        }
    }
    private func erase(key: String, generation expected: UInt64, deadline: Double) async throws {
        let token = try await challenge(key: key, kind: "assert", generation: expected, deadline: deadline)
        let body = Data("{}".utf8)
        let headers = try await proof(operation: "delete", key: key, challenge: token, body: body, transaction: "", generation: expected, deadline: deadline)
        _ = try await http.post(to: Self.origin, jsonBody: body, headers: headers, timeoutSeconds: remaining(deadline, expected))
    }
    private struct Challenge: Decodable { let challenge: String }
    private struct Enrollment: Decodable { let enrolled: Bool }
    private struct AuthError: Decodable { let error: String }
    private struct KeyUnavailable: Error {}
}

struct CoachAuthenticationAccountCleanup: Sendable {
    private let keys: any CoachAuthenticationKeyStoring
    private let runtime: RuntimeAuthenticatedCoachTransport?

    init(keys: any CoachAuthenticationKeyStoring, runtime: RuntimeAuthenticatedCoachTransport?) {
        self.keys = keys
        self.runtime = runtime
    }

    func resetAccount() async {
        if let runtime {
            await runtime.resetAccount()
        } else {
            keys.save(nil)
        }
    }
}

/// A timeout must return even when an Apple callback ignores cancellation. Late work is cancelled
/// and generation/deadline-checked before any subsequent HTTP call or local key write.
private final class CoachOperationResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock(); self.continuation = continuation; let result = self.result; lock.unlock()
        if let result { continuation.resume(with: result) }
    }
    func track(_ tasks: [Task<Void, Never>]) {
        lock.lock(); self.tasks = tasks; let finished = result != nil; lock.unlock()
        if finished { tasks.forEach { $0.cancel() } }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result; let continuation = self.continuation; let tasks = self.tasks; lock.unlock()
        tasks.forEach { $0.cancel() }; continuation?.resume(with: result)
    }
}
func boundedCoachOperation<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    guard seconds.isFinite, seconds > 0, seconds <= 30 else { throw CoachAuthenticationError.unavailable }
    let result = CoachOperationResult<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            result.install(continuation)
            let worker = Task<Void, Never> {
                do { result.finish(.success(try await operation())) }
                catch { result.finish(.failure(CoachAuthenticationError.unavailable)) }
            }
            let timer = Task<Void, Never> {
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                catch { return }
                result.finish(.failure(CoachAuthenticationError.timeout))
            }
            result.track([worker, timer])
        }
    } onCancel: { result.finish(.failure(CoachAuthenticationError.unavailable)) }
}

private final class CoachNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct BoundedCoachHTTPTransport: CoachProxyTransport {
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        makeConfiguration = configuration
    }
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        guard url == RuntimeAuthenticatedCoachTransport.origin, jsonBody.count <= 32768, timeoutSeconds.isFinite,
              timeoutSeconds > 0, timeoutSeconds <= 30,
              headers.isEmpty || Set(headers.keys) == ["X-RepToday-Coach-Auth"] else { throw CoachAuthenticationError.unavailable }
        let configuration = makeConfiguration()
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeoutSeconds; configuration.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: configuration, delegate: CoachNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = jsonBody
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url,
              !(300...399).contains(response.statusCode), response.expectedContentLength <= 16384 else { throw CoachAuthenticationError.unavailable }
        var body = Data()
        for try await byte in bytes {
            guard body.count < 16384 else { throw CoachAuthenticationError.unavailable }; body.append(byte)
        }
        return (body, response.statusCode)
    }
}
