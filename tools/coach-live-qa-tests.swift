import Foundation

// Every request is intercepted in process; these tests never construct a native Keychain reader.
private enum TestFailure: Error { case assertion(String) }
private func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    if !condition() { throw TestFailure.assertion(label) }
}
private let doubleGate = Data(String(repeating: "0", count: 64).utf8)

private final class QAReaderDouble: CoachCredentialReader {
    var reads: [CoachCredential] = []
    var bytes = doubleGate
    var denied = false
    func read(_ item: CoachCredential) throws -> Data {
        reads.append(item)
        if denied { throw TestFailure.assertion("arbitrary-private-error") }
        return bytes
    }
}

private final class QACoordinatorDouble: CoachLiveQACoordinator {
    var calls = 0
    var output = CoachQA.successLines.joined(separator: "\n")
    func run(clientGate: Data) async throws -> String {
        calls += 1
        try require(clientGate == doubleGate, "credential-transfer")
        return output
    }
}

private final class QAClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
}

private final class QATransportDouble: CoachProxyTransport, @unchecked Sendable {
    struct Call { let body: Data; let headers: [String: String]; let timeout: Double }
    var calls: [Call] = []
    var failAt: Int?
    var failure = CoachQAFailure.request
    var modelReplies = ["Your discipline-phase bodyweight squat frontier and recent patterns support squat practice.", "Your assisted pistol squat frontier supports discussing pistol form."]
    var modelStatus = 200
    var responseOverride: Data?
    var onCall: ((Int) -> Void)?
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        try require(url == CoachQA.endpoint, "approved-target")
        let index = calls.count
        calls.append(.init(body: jsonBody, headers: headers, timeout: timeoutSeconds))
        onCall?(index)
        if index == failAt { throw failure }
        let errors = ["unauthorized", "unauthorized", "payload_too_large", "invalid_json"]
        let statuses = [401, 401, 413, 400]
        if index < 4 {
            return (responseOverride ?? Data("{\"error\":\"\(errors[index])\"}".utf8), statuses[index])
        }
        let data = try responseOverride ?? JSONSerialization.data(withJSONObject: ["reply": modelReplies[index - 4]])
        return (data, modelStatus)
    }

    var paidCallCount: Int { max(0, calls.count - 4) }
}

private final class LocalQAURLProtocol: URLProtocol, @unchecked Sendable {
    struct Plan { var status = 200; var data = Data("{}".utf8); var declaredLength: Int?; var complete = true }
    static var plan = Plan()
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true } // No fallback to a real network.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let plan = Self.plan
        let headers = plan.declaredLength.map { ["Content-Length": String($0)] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: plan.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: plan.data)
        if plan.complete { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}

private func localConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LocalQAURLProtocol.self]
    return configuration
}

@main
private struct CoachLiveQATests {
    @MainActor static func main() async {
        do {
            let reader = QAReaderDouble(), coordinator = QACoordinatorDouble()
            let accepted = try await validateCoachLive(reader: reader, coordinator: coordinator)
            try require(accepted == coordinator.output && reader.reads == [.clientGate] && coordinator.calls == 1, "only-client-gate")
            for denied in [true, false] {
                let bad = QAReaderDouble(), unused = QACoordinatorDouble()
                bad.denied = denied; bad.bytes = Data("invalid".utf8)
                do { _ = try await validateCoachLive(reader: bad, coordinator: unused); throw TestFailure.assertion("credential-accepted") }
                catch let error as CoachQAStop { try require(error.stage == .credential && unused.calls == 0 && bad.reads == [.clientGate], "credential-fail-closed") }
            }
            for raw in [coordinator.output + "\n", "arbitrary-private-output", coordinator.output + "\n" + String(data: doubleGate, encoding: .utf8)!, "qa: missing-authorization pass"] {
                let rejected = QACoordinatorDouble(); rejected.output = raw
                do { _ = try await validateCoachLive(reader: QAReaderDouble(), coordinator: rejected); throw TestFailure.assertion("raw-output-accepted") }
                catch let error as CoachQAStop { try require(error.stage == .output && !error.safeLine.contains(raw), "raw-output-suppressed") }
            }
            let transport = QATransportDouble()
            let output = try await NativeCoachLiveQACoordinator(transport: transport).run(clientGate: doubleGate)
            try require(output == CoachQA.successLines.joined(separator: "\n") && transport.calls.count == 6, "six-bounded-calls")
            try require(transport.paidCallCount == 2, "two-successes-consume-exactly-two-paid-calls")
            try require(transport.calls[0].headers.isEmpty && transport.calls[1].headers["Authorization"] != transport.calls[2].headers["Authorization"], "authorization-order")
            try require(transport.calls[2].body.count == 32 * 1024 + 1 && transport.calls[3].body == Data("{".utf8), "invalid-only-boundaries")
            try require(transport.calls.prefix(4).allSatisfy { $0.timeout <= 10 } && transport.calls.suffix(2).allSatisfy { $0.timeout <= 30 }, "request-deadlines")
            for index in [4, 5] {
                let json = try JSONSerialization.jsonObject(with: transport.calls[index].body) as? [String: Any]
                try require(Set(json?.keys.map { $0 } ?? []) == ["message", "context", "safetyIdentifier"], "actual-client-wire")
                let context = json?["context"] as? [String: Any]
                try require(context?["phase"] as? String == (index == 4 ? "discipline" : "strength"), "distinct-contexts")
                try require(CoachSafetyIdentifier(rawValue: json?["safetyIdentifier"] as? String ?? "") != nil, "synthetic-pseudonym")
            }
            for index in 0..<6 {
                let failing = QATransportDouble(); failing.failAt = index
                do { _ = try await NativeCoachLiveQACoordinator(transport: failing).run(clientGate: doubleGate); throw TestFailure.assertion("request-failure-accepted") }
                catch let error as CoachQAStop { try require(failing.calls.count == index + 1 && !error.safeLine.contains("cannotConnect"), "no-retry-no-next-call") }
            }
            for body in [Data("not-json-private-content".utf8), Data("{\"error\":\"unexpected\"}".utf8), Data(repeating: 120, count: CoachQA.maximumResponseBytes + 1)] {
                let failing = QATransportDouble(); failing.responseOverride = body
                do { _ = try await NativeCoachLiveQACoordinator(transport: failing).run(clientGate: doubleGate); throw TestFailure.assertion("bad-contract-accepted") }
                catch let error as CoachQAStop { try require(error.stage == .missingAuthorization && failing.calls.count == 1, "boundary-stop-before-model") }
            }
            for reply in ["", "Generic encouragement without context"] {
                let failing = QATransportDouble(); failing.modelReplies[0] = reply
                do { _ = try await NativeCoachLiveQACoordinator(transport: failing).run(clientGate: doubleGate); throw TestFailure.assertion("bad-model-reply-accepted") }
                catch let error as CoachQAStop { try require(error.stage == .whySquats && failing.paidCallCount == 1, "one-paid-call-on-model-failure") }
            }
            let badStatus = QATransportDouble(); badStatus.modelStatus = 502
            do { _ = try await NativeCoachLiveQACoordinator(transport: badStatus).run(clientGate: doubleGate); throw TestFailure.assertion("model-status-accepted") }
            catch let error as CoachQAStop { try require(error.stage == .whySquats && badStatus.paidCallCount == 1, "model-error-stop") }
            for failure in [CoachQAFailure.request, .timeout] {
                let first = QATransportDouble(); first.failAt = 4; first.failure = failure
                do { _ = try await NativeCoachLiveQACoordinator(transport: first).run(clientGate: doubleGate); throw TestFailure.assertion("first-paid-failure-accepted") }
                catch let error as CoachQAStop {
                    try require(error.stage == .whySquats && error.failure == failure && first.paidCallCount == 1,
                                "first-paid-failure-stops-after-one")
                }
                let second = QATransportDouble(); second.failAt = 5; second.failure = failure
                do { _ = try await NativeCoachLiveQACoordinator(transport: second).run(clientGate: doubleGate); throw TestFailure.assertion("second-paid-failure-accepted") }
                catch let error as CoachQAStop {
                    try require(error.stage == .pistolForm && error.failure == failure && second.paidCallCount == 2,
                                "second-paid-failure-stops-after-two")
                }
            }
            var retryBudget = CoachQAPaidCallBudget(), retryPaidCalls = 0
            for _ in 0..<4 {
                do {
                    try await retryBudget.perform {
                        retryPaidCalls += 1
                        throw CoachQAFailure.timeout
                    }
                } catch CoachQAFailure.timeout, CoachQAFailure.paidCallBudget {}
            }
            try require(retryPaidCalls == 1 && retryBudget.consumedCalls == 1,
                        "ambiguous-timeout-retry-path-stays-at-one")
            var capBudget = CoachQAPaidCallBudget(), capPaidCalls = 0
            for _ in 0..<3 {
                do { try await capBudget.perform { capPaidCalls += 1 } }
                catch CoachQAFailure.paidCallBudget {}
            }
            try require(capPaidCalls == 2 && capBudget.consumedCalls == 2, "third-paid-call-is-impossible")
            let clock = QAClock(), slow = QATransportDouble()
            slow.onCall = { _ in clock.advance(101) }
            do { _ = try await NativeCoachLiveQACoordinator(transport: slow, now: { clock.read() }).run(clientGate: doubleGate); throw TestFailure.assertion("over-budget-accepted") }
            catch let error as CoachQAStop { try require(error.stage == .missingAuthorization && slow.calls.count == 1, "total-budget") }
            // Deliberately fabricated workout still matches lexical signals: output must retain the limitation.
            try require(CoachQA.hasContextSignals("Discipline bodyweight squat: I changed your workout to 99 sets", stage: .whySquats), "lexical-limit-counterexample")
            try require(output.contains("semantic-context-form-and-no-workout-fabrication unverified"), "semantic-limit-disclosed")
            let bounded = BoundedCoachQATransport(configuration: { localConfiguration() })
            LocalQAURLProtocol.requests = 0
            LocalQAURLProtocol.plan = .init(status: 200, data: Data(repeating: 120, count: CoachQA.maximumResponseBytes))
            let exact = try await bounded.post(to: CoachQA.endpoint, jsonBody: Data("{".utf8), headers: [:], timeoutSeconds: 1)
            try require(exact.data.count == CoachQA.maximumResponseBytes, "response-exact-limit")
            for plan in [LocalQAURLProtocol.Plan(status: 302), .init(data: Data(repeating: 120, count: CoachQA.maximumResponseBytes + 1)), .init(declaredLength: CoachQA.maximumResponseBytes + 1)] {
                LocalQAURLProtocol.plan = plan
                do { _ = try await bounded.post(to: CoachQA.endpoint, jsonBody: Data(), headers: [:], timeoutSeconds: 1); throw TestFailure.assertion("transport-boundary-accepted") }
                catch let failure as CoachQAFailure { try require(failure == (plan.status == 302 ? .redirect : .size), "transport-boundary-rejected") }
            }
            let before = LocalQAURLProtocol.requests
            for url in [URL(string: "https://example.invalid/coach")!, URL(string: "https://coach.reptoday.app/other")!] {
                do { _ = try await bounded.post(to: url, jsonBody: Data(), headers: [:], timeoutSeconds: 1); throw TestFailure.assertion("destination-accepted") }
                catch CoachQAFailure.contract {}
            }
            try require(LocalQAURLProtocol.requests == before, "no-destination-fallback")
            LocalQAURLProtocol.plan = .init(data: Data("{".utf8), complete: false)
            let start = ProcessInfo.processInfo.systemUptime
            do { _ = try await bounded.post(to: CoachQA.endpoint, jsonBody: Data(), headers: [:], timeoutSeconds: 0.05); throw TestFailure.assertion("stream-timeout-accepted") }
            catch CoachQAFailure.timeout {}
            try require(ProcessInfo.processInfo.systemUptime - start < 2, "whole-stream-deadline")
            print("passed: native Coach QA doubles, actual client wire/error paths, output rejection and local transport bounds; zero Keychain or live calls")
        } catch let TestFailure.assertion(label) { print("failed: Coach QA offline assertion \(label)"); exit(1) }
        catch { print("failed: Coach QA offline check; no diagnostic values printed"); exit(1) }
    }
}
