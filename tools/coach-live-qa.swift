import Foundation

// Compiled with the actual app client/context and the existing native Keychain reader.
// No provider/WAF credential, persistence, raw response output or configurable destination.
enum CoachQAStage: String {
    case credential, missingAuthorization = "missing-authorization", wrongAuthorization = "wrong-authorization"
    case oversized, malformed, offline, localLimit = "local-limit", whySquats = "why-squats", pistolForm = "pistol-form", output
}

enum CoachQAFailure: String, Error { case credential, request, timeout, redirect, size, contract, contextSignals = "context-signals", output }

struct CoachQAStop: Error {
    let stage: CoachQAStage
    let failure: CoachQAFailure
    var safeLine: String { "blocked: coach live QA stage \(stage.rawValue) failure \(failure.rawValue); no values or response content printed" }
}

enum CoachQA {
    static let endpoint = URL(string: "https://coach.reptoday.app/coach")!
    static let maximumResponseBytes = 16 * 1024
    static let networkBudgetSeconds: Double = 100
    static let successLines = [
        "qa: missing-authorization pass", "qa: wrong-authorization pass",
        "qa: oversized pass", "qa: malformed pass", "qa: offline pass", "qa: local-limit pass",
        "qa: why-squats non-empty lexical-context-signals-present",
        "qa: pistol-form non-empty lexical-context-signals-present",
        "qa: semantic-context-form-and-no-workout-fabrication unverified",
        "validated: CoachProxyClient live model path returned; shipped client authentication pending"
    ]

    static func validatedOutput(_ text: String) throws -> String {
        guard text == successLines.joined(separator: "\n") else { throw CoachQAStop(stage: .output, failure: .output) }
        return text
    }

    static let whyContext = CoachSyntheticFixtures.whyContext
    static let pistolContext = CoachSyntheticFixtures.pistolContext
    static let whyPrompt = CoachSyntheticFixtures.whyPrompt
    static let pistolPrompt = CoachSyntheticFixtures.pistolPrompt

    // Lexical smoke signals only: these cannot prove personalization, form safety or non-fabrication.
    static func hasContextSignals(_ reply: String, stage: CoachQAStage) -> Bool {
        let text = reply.lowercased()
        switch stage {
        case .whySquats:
            return text.contains("squat") && ["bodyweight", "discipline", "63", "20", "recent patterns"].contains(where: text.contains)
        case .pistolForm: return text.contains("pistol") && text.contains("assisted")
        default: return false
        }
    }
}

private final class CoachQANoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the bearer to a redirect target, including the same host.
    }
}

struct BoundedCoachQATransport: CoachProxyTransport {
    // Tests can install a local URLProtocol double; the live entry point uses only .ephemeral.
    let configuration: @Sendable () -> URLSessionConfiguration
    init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) { self.configuration = configuration }

    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        guard url == CoachQA.endpoint, timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 30,
              Set(headers.keys).isSubset(of: ["Authorization"]) else { throw CoachQAFailure.contract }
        let config = configuration()
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds // Entire transfer, including a streamed body.
        let session = URLSession(configuration: config, delegate: CoachQANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"; request.httpBody = jsonBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (stream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw CoachQAFailure.contract }
            guard !(300..<400).contains(http.statusCode), http.url == url else { throw CoachQAFailure.redirect }
            guard http.expectedContentLength <= Int64(CoachQA.maximumResponseBytes) else { throw CoachQAFailure.size }
            var data = Data()
            for try await byte in stream {
                guard data.count < CoachQA.maximumResponseBytes else { throw CoachQAFailure.size }
                data.append(byte)
            }
            return (data, http.statusCode)
        } catch let failure as CoachQAFailure { throw failure }
        catch let error as URLError { throw error.code == .timedOut ? CoachQAFailure.timeout : CoachQAFailure.request }
        catch { throw CoachQAFailure.request }
    }
}

private struct CoachQAOfflineTransport: CoachProxyTransport {
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        throw URLError(.notConnectedToInternet) // Local real-client error-path check, never a network request.
    }
}

protocol CoachLiveQACoordinator {
    func run(clientGate: Data) async throws -> String
}

struct NativeCoachLiveQACoordinator: CoachLiveQACoordinator {
    let transport: any CoachProxyTransport
    let now: @Sendable () -> Double
    init(transport: any CoachProxyTransport = BoundedCoachQATransport(), now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport; self.now = now
    }

    func run(clientGate: Data) async throws -> String {
        guard CoachCredential.clientGate.accepts(clientGate), let gate = String(data: clientGate, encoding: .utf8) else {
            throw CoachQAStop(stage: .credential, failure: .credential)
        }
        let deadline = now() + CoachQA.networkBudgetSeconds
        let authorization = ["Authorization": "Bearer \(gate)"]
        let invalid = Data("{".utf8)
        let wrongGate = String(repeating: gate.first == "0" ? "1" : "0", count: 64)
        let probes: [(CoachQAStage, Data, [String: String], Int, String)] = [
            (.missingAuthorization, invalid, [:], 401, "unauthorized"),
            (.wrongAuthorization, invalid, ["Authorization": "Bearer \(wrongGate)"], 401, "unauthorized"),
            (.oversized, Data(repeating: 32, count: 32 * 1024 + 1), authorization, 413, "payload_too_large"),
            (.malformed, invalid, authorization, 400, "invalid_json")
        ]
        for (stage, body, headers, status, expectedError) in probes {
            try await checked(stage) {
                let remaining = deadline - now()
                guard remaining > 0 else { throw CoachQAFailure.timeout }
                let result = try await transport.post(to: CoachQA.endpoint, jsonBody: body, headers: headers, timeoutSeconds: min(10, remaining))
                guard now() < deadline, result.data.count <= CoachQA.maximumResponseBytes,
                      result.statusCode == status,
                      let json = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
                      json["error"] as? String == expectedError else { throw CoachQAFailure.contract }
            }
        }
        let safetyIdentifier = CoachSafetyIdentifier.random() // Ephemeral synthetic QA pseudonym, no install/account identity.
        let offline = CoachProxyClient(endpoint: CoachQA.endpoint, sharedSecret: gate, safetyIdentifier: safetyIdentifier, transport: CoachQAOfflineTransport())
        try await checked(.offline) {
            do { _ = try await offline.reply(to: CoachQA.whyPrompt, context: CoachQA.whyContext) }
            catch let error as URLError where error.code == .notConnectedToInternet { return }
            throw CoachQAFailure.contract
        }
        try await checked(.localLimit) {
            do { _ = try await offline.reply(to: String(repeating: "x", count: 2001), context: CoachQA.whyContext) }
            catch CoachProxyClient.CoachError.messageTooLong(limit: 2000) { return }
            throw CoachQAFailure.contract
        }
        // No retries. Only these two calls carry valid model payloads. Stop before call two on any failure.
        for (stage, prompt, context) in [(CoachQAStage.whySquats, CoachQA.whyPrompt, CoachQA.whyContext), (.pistolForm, CoachQA.pistolPrompt, CoachQA.pistolContext)] {
            try await checked(stage) {
                let remaining = deadline - now()
                guard remaining > 0 else { throw CoachQAFailure.timeout }
                let client = CoachProxyClient(endpoint: CoachQA.endpoint, timeoutSeconds: min(30, remaining), sharedSecret: gate,
                                              safetyIdentifier: safetyIdentifier, transport: transport)
                let reply = try await client.reply(to: prompt, context: context)
                guard now() < deadline else { throw CoachQAFailure.timeout }
                guard CoachQA.hasContextSignals(reply, stage: stage) else { throw CoachQAFailure.contextSignals }
            }
        }
        return try CoachQA.validatedOutput(CoachQA.successLines.joined(separator: "\n"))
    }

    private func checked(_ stage: CoachQAStage, operation: () async throws -> Void) async throws {
        do { try await operation() }
        catch let failure as CoachQAFailure { throw CoachQAStop(stage: stage, failure: failure) }
        catch { throw CoachQAStop(stage: stage, failure: .contract) } // Never retain an arbitrary error string.
    }
}

@MainActor
func validateCoachLive(reader: CoachCredentialReader, coordinator: CoachLiveQACoordinator) async throws -> String {
    var bytes: Data
    do { bytes = try reader.read(.clientGate) }
    catch { throw CoachQAStop(stage: .credential, failure: .credential) }
    defer { bytes.resetBytes(in: 0..<bytes.count) }
    guard CoachCredential.clientGate.accepts(bytes) else { throw CoachQAStop(stage: .credential, failure: .credential) }
    return try CoachQA.validatedOutput(try await coordinator.run(clientGate: bytes))
}

#if !COACH_LIVE_QA_TESTS
@main
struct CoachLiveQAMain {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 1 else { print("blocked: coach live QA accepts no arguments"); exit(64) }
        do {
            let output = try await validateCoachLive(reader: AppKitCoachCredentialReader(reader: NativeCoachCredentialReader()), coordinator: NativeCoachLiveQACoordinator())
            print(output)
        } catch let stopped as CoachQAStop { print(stopped.safeLine); exit(78) }
        catch { print(CoachQAStop(stage: .output, failure: .output).safeLine); exit(78) }
    }
}
#endif
