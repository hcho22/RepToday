import XCTest
import CryptoKit
import DeviceCheck
import StoreKit
@testable import RepToday

private final class FixtureCoachKeyStore: CoachAuthenticationKeyStoring, @unchecked Sendable {
    private let lock = NSLock(); private var key: String?
    init(_ key: String? = nil) { self.key = key }
    func load() -> String? { lock.lock(); defer { lock.unlock() }; return key }
    func save(_ key: String?) { lock.lock(); defer { lock.unlock() }; self.key = key }
}
private actor FixtureCoachAttester: CoachAppAttesting {
    nonisolated let isSupported: Bool
    let key = Data(repeating: 255, count: 32).base64EncodedString()
    private(set) var calls = [String](); private(set) var hashes = [Data]()
    var wait: CheckedContinuation<String, Never>?
    var assertionWait: CheckedContinuation<Void, Never>?
    var hangKey: Bool
    var hangInvalidAssertion: Bool
    var assertionFailures: [CoachAuthenticationError]
    init(supported: Bool = true, hangKey: Bool = false, hangInvalidAssertion: Bool = false,
         assertionFailures: [CoachAuthenticationError] = []) {
        isSupported = supported
        self.hangKey = hangKey
        self.hangInvalidAssertion = hangInvalidAssertion
        self.assertionFailures = assertionFailures
    }
    func generateKey() async throws -> String {
        calls.append("key")
        if hangKey { return await withCheckedContinuation { wait = $0 } }
        return key
    }
    func releaseKey() { wait?.resume(returning: key); wait = nil }
    func releaseAssertion() { assertionWait?.resume(); assertionWait = nil }
    func attest(key: String, hash: Data) async throws -> Data { calls.append("attest"); hashes.append(hash); return Data([1]) }
    func assertion(key: String, hash: Data) async throws -> Data {
        calls.append("assert"); hashes.append(hash)
        if hangInvalidAssertion {
            hangInvalidAssertion = false
            await withCheckedContinuation { assertionWait = $0 }
            throw CoachAuthenticationError.invalidKey
        }
        if !assertionFailures.isEmpty { throw assertionFailures.removeFirst() }
        return Data([2])
    }
}
private struct FixtureCoachPurchase: CoachPurchaseProofProviding {
    let proof: String?
    func appStorePremiumProof() async throws -> String {
        guard let proof else { throw CoachAuthenticationError.unavailable }; return proof
    }
}
private actor FixtureCoachHTTP: CoachProxyTransport {
    struct Call: Sendable { let body: Data; let headers: [String: String]; let timeout: Double }
    private(set) var calls = [Call]()
    var failureAt: Int?; var expireFirstKey: Bool; var finalStatus: Int
    var finalResponses: [(Data, Int)]?
    var injectedError: NSError?
    var injectedResponse: (Data, Int)?
    let challenge = "eA." + String(repeating: "A", count: 43) // Shape fixture; never a valid server HMAC.
    init(failureAt: Int? = nil, expireFirstKey: Bool = false, finalStatus: Int = 200, finalResponses: [(Data, Int)]? = nil, injectedError: NSError? = nil, injectedResponse: (Data, Int)? = nil) {
        self.failureAt = failureAt; self.expireFirstKey = expireFirstKey; self.finalStatus = finalStatus
        self.finalResponses = finalResponses
        self.injectedError = injectedError; self.injectedResponse = injectedResponse
    }
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        guard url == RuntimeAuthenticatedCoachTransport.origin else { throw CoachAuthenticationError.unavailable }
        calls.append(Call(body: jsonBody, headers: headers, timeout: timeoutSeconds))
        if failureAt == calls.count {
            if let injectedResponse { return injectedResponse }
            if let injectedError { throw injectedError }
            throw CoachAuthenticationError.unavailable
        }
        if !headers.isEmpty {
            if finalResponses != nil {
                guard !finalResponses!.isEmpty else { throw CoachAuthenticationError.unavailable }
                return finalResponses!.removeFirst()
            }
            return (Data(#"{"reply":"Fixture supplied-context reply"}"#.utf8), finalStatus)
        }
        let input = try JSONDecoder().decode([String: String].self, from: jsonBody)
        if input["operation"] == "challenge" {
            if expireFirstKey, input["kind"] == "assert" { expireFirstKey = false; return (Data(#"{"error":"key_unavailable"}"#.utf8),401) }
            return (try JSONEncoder().encode(["challenge":challenge]), 200)
        }
        return (Data(#"{"enrolled":true}"#.utf8), 200)
    }
}

private final class RuntimeHTTPFixtureState: @unchecked Sendable {
    struct Plan {var status=200;var data=Data("{}".utf8);var length:Int?;var finish=true}
    private let lock=NSLock();private var plan=Plan();private var count=0
    func set(_ plan:Plan) {lock.lock();self.plan=plan;count=0;lock.unlock()}
    func next()->Plan {lock.lock();defer{lock.unlock()};count+=1;return plan}
    var requests:Int {lock.lock();defer{lock.unlock()};return count}
}
private final class RuntimeHTTPFixture: URLProtocol, @unchecked Sendable {
    static let state=RuntimeHTTPFixtureState()
    override class func canInit(with request:URLRequest)->Bool {true} // Captures every URL: no network fallback.
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let plan=Self.state.next()
        guard request.url == RuntimeAuthenticatedCoachTransport.origin else {
            client?.urlProtocol(self,didFailWithError:CoachAuthenticationError.unavailable);return
        }
        let headers=plan.length.map{["Content-Length":String($0)]} ?? [:]
        let response=HTTPURLResponse(url:request.url!,statusCode:plan.status,httpVersion:"HTTP/1.1",headerFields:headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:plan.data)
        if plan.finish {client?.urlProtocolDidFinishLoading(self)}
    }
    override func stopLoading() {}
}

final class CoachRuntimeAuthenticationTests: XCTestCase {
    private let purchase = "fixture.purchase.proof"
    private func context() -> CoachContextBundle {
        CoachContextBundle(phase:"discipline",requestedMinutes:20,chainPositions:[],recentPatterns:["push"],
                           consistency:.init(currentScore:63,direction:.rising),strengthJourney:[])
    }
    private func client(_ transport: RuntimeAuthenticatedCoachTransport, timeout: Double = 30, diagnostics: CoachDiagnostics = .live) -> CoachProxyClient {
        CoachProxyClient(endpoint:RuntimeAuthenticatedCoachTransport.origin, timeoutSeconds:timeout,
                         safetyIdentifier:testCoachSafetyIdentifier,transport:transport,diagnostics:diagnostics)
    }
    func testPurchaseProofAllowsOnlyAppleProductionAndSandboxEnvironments() {
        XCTAssertTrue(StoreKitCoachPurchaseProof.serverProofEnvironmentAllowed(.production))
        XCTAssertTrue(StoreKitCoachPurchaseProof.serverProofEnvironmentAllowed(.sandbox))
        XCTAssertFalse(StoreKitCoachPurchaseProof.serverProofEnvironmentAllowed(.xcode))
        XCTAssertFalse(StoreKitCoachPurchaseProof.serverProofEnvironmentAllowed(.init(rawValue: "LocalTesting")))
        XCTAssertFalse(StoreKitCoachPurchaseProof.serverProofEnvironmentAllowed(.init(rawValue: "FutureEnvironment")))
    }
    func testProofOnlyUsesExactEmptyBodyThenIdenticalReplayWithOneSignatureAndNoBearer() async throws {
        let http = FixtureCoachHTTP(finalResponses: [
            (Data(#"{"error":"invalid_context"}"#.utf8), 400),
            (Data(#"{"error":"unauthorized"}"#.utf8), 401)])
        let attester = FixtureCoachAttester()
        let transport = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                                                           keys: FixtureCoachKeyStore(), http: http)
        try await transport.verifyProofOnly(timeoutSeconds: 30)
        let calls = await http.calls, appleCalls = await attester.calls
        XCTAssertEqual(calls.count, 5); XCTAssertEqual(appleCalls, ["key", "attest", "assert"])
        let originals = Array(calls.suffix(2))
        XCTAssertEqual(originals[0].body, Data("{}".utf8)); XCTAssertEqual(originals[1].body, originals[0].body)
        XCTAssertEqual(originals[1].headers, originals[0].headers)
        XCTAssertTrue(calls.allSatisfy { $0.headers["Authorization"] == nil })
        XCTAssertTrue(calls.prefix(3).allSatisfy { $0.headers.isEmpty })
        let proof = try JSONDecoder().decode([String: String].self, from: Data(try XCTUnwrap(originals[0].headers["X-RepToday-Coach-Auth"]).utf8))
        XCTAssertEqual(proof["operation"], "reply"); XCTAssertEqual(proof["transactionJws"], purchase)
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = try encoder.encode([RuntimeAuthenticatedCoachTransport.protocolVersion, "POST",
                                         RuntimeAuthenticatedCoachTransport.origin.absoluteString, "reply", attester.key,
                                         http.challenge, hex(Data("{}".utf8)), hex(Data(purchase.utf8))])
        let hashes = await attester.hashes
        XCTAssertEqual(hashes.last, Data(SHA256.hash(data: payload)))
    }
    func testProofOnlyRefusesUnexpectedAdmissionAndDoesNotReplayAFailure() async {
        for (data, status) in [(#"{"error":"unauthorized"}"#, 401), (#"{"error":"auth_unavailable"}"#, 503),
                               (#"{"error":"invalid_context"}"#, 200), (#"{"reply":"fixture"}"#, 400),
                               (#"{"error":"invalid_context","extra":"fixture"}"#, 400)] {
            let http = FixtureCoachHTTP(finalResponses: [(Data(data.utf8), status)])
            let attester = FixtureCoachAttester()
            let transport = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                                                               keys: FixtureCoachKeyStore(attester.key), http: http)
            do { try await transport.verifyProofOnly(timeoutSeconds: 1); XCTFail("must reject") } catch {}
            let calls = await http.calls; XCTAssertEqual(calls.count, 2)
            XCTAssertEqual(calls.last?.body, Data("{}".utf8))
        }
    }
    func testProofOnlyRequiresExactReplayDenialAndNeverRetriesReplay() async {
        for (data, status) in [(#"{"error":"unauthorized"}"#, 503), (#"{"error":"key_unavailable"}"#, 401),
                               (#"{"error":"invalid_context"}"#, 400)] {
            let http = FixtureCoachHTTP(finalResponses: [(Data(#"{"error":"invalid_context"}"#.utf8), 400), (Data(data.utf8), status)])
            let attester = FixtureCoachAttester()
            let transport = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                                                               keys: FixtureCoachKeyStore(attester.key), http: http)
            do { try await transport.verifyProofOnly(timeoutSeconds: 1); XCTFail("must reject") } catch {}
            let calls = await http.calls; XCTAssertEqual(calls.count, 3)
            let appleCalls = await attester.calls; XCTAssertEqual(appleCalls, ["assert"])
        }
    }
    func testProofOnlyMissingPurchaseAndOfflineHandshakeRemainBoundedWithoutReplay() async {
        for missing in [true, false] {
            let http = FixtureCoachHTTP(failureAt: 1), attester = FixtureCoachAttester()
            let transport = RuntimeAuthenticatedCoachTransport(attester: attester,
                purchase: FixtureCoachPurchase(proof: missing ? nil : purchase), keys: FixtureCoachKeyStore(), http: http)
            do { try await transport.verifyProofOnly(timeoutSeconds: 1); XCTFail("must fail") } catch {}
            let calls = await http.calls; XCTAssertEqual(calls.count, missing ? 0 : 1)
            XCTAssertTrue(calls.allSatisfy { $0.headers.isEmpty })
        }
    }
    func testActualClientEnrollsAndBindsExactBodyAndPurchaseWithoutBearer() async throws {
        let http = FixtureCoachHTTP(); let keys = FixtureCoachKeyStore(); let attester = FixtureCoachAttester()
        let transport = RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        let reply = try await client(transport).reply(to:"Why did I get squats?",context:context())
        XCTAssertEqual(reply,"Fixture supplied-context reply")
        let calls = await http.calls; XCTAssertEqual(calls.count,4)
        XCTAssertTrue(calls.prefix(3).allSatisfy { $0.headers.isEmpty })
        XCTAssertTrue(calls.allSatisfy { $0.headers["Authorization"] == nil && $0.timeout > 0 && $0.timeout <= 30 })
        let final = try XCTUnwrap(calls.last)
        let header = try XCTUnwrap(final.headers["X-RepToday-Coach-Auth"])
        let proof = try JSONDecoder().decode([String:String].self,from:Data(header.utf8))
        let key = attester.key; let challenge = http.challenge
        XCTAssertEqual(keys.load(),key); XCTAssertEqual(proof["transactionJws"],purchase)
        func hex(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
        let encoder=JSONEncoder();encoder.outputFormatting=[.withoutEscapingSlashes]
        let payload=try encoder.encode(["reptoday-coach-auth-v1","POST","https://coach.reptoday.app/coach","reply",key,challenge,
                                       hex(final.body),hex(Data(purchase.utf8))])
        let hashes=await attester.hashes
        XCTAssertEqual(hashes.last,Data(SHA256.hash(data:payload)))
        let body=try JSONSerialization.jsonObject(with:final.body) as? [String:Any]
        XCTAssertEqual(Set(body?.keys.map{$0} ?? []),["context","message","safetyIdentifier"])
        XCTAssertFalse(String(decoding:final.body,as:UTF8.self).contains(purchase))
    }
    func testExistingKeyUsesFreshChallengePerTurnAndDoesNotReenroll() async throws {
        let attester=FixtureCoachAttester();let key=attester.key;let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:FixtureCoachKeyStore(key),http:http)
        _ = try await client(transport).reply(to:"Why squats?",context:context())
        _ = try await client(transport).reply(to:"How is pistol-squat form?",context:context())
        let calls=await http.calls;let appleCalls=await attester.calls
        XCTAssertEqual(calls.count,4);XCTAssertEqual(appleCalls,["assert","assert"])
    }
    func testExpiredServerKeyEnrollsAFreshKeyOnceWithoutPaidRetry() async throws {
        let old=Data(repeating:1,count:32).base64EncodedString();let keys=FixtureCoachKeyStore(old);let http=FixtureCoachHTTP(expireFirstKey:true)
        let transport=RuntimeAuthenticatedCoachTransport(attester:FixtureCoachAttester(),purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        _ = try await client(transport).reply(to:"Why squats?",context:context())
        XCTAssertNotEqual(keys.load(),old);let calls=await http.calls
        XCTAssertEqual(calls.count,5);XCTAssertEqual(calls.filter{!$0.headers.isEmpty}.count,1)
    }
    func testDeviceCheckErrorClassifierRecognizesOnlyTheInvalidKeyDomainAndCode() {
        XCTAssertEqual(DeviceCoachAppAttester.authenticationError(
            NSError(domain:DCErrorDomain,code:DCError.invalidKey.rawValue)),.invalidKey)
        XCTAssertEqual(DeviceCoachAppAttester.authenticationError(
            NSError(domain:"FixtureDeviceCheck",code:DCError.invalidKey.rawValue)),.unavailable)
        XCTAssertEqual(DeviceCoachAppAttester.authenticationError(NSError(domain:DCErrorDomain,code:999)),.unavailable)
    }
    func testInvalidRestoredKeyEnrollsOnceBeforeTheOnlyPaidRequest() async throws {
        let old=Data(repeating:1,count:32).base64EncodedString();let keys=FixtureCoachKeyStore(old)
        let attester=FixtureCoachAttester(assertionFailures:[.invalidKey]);let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        _ = try await client(transport).reply(to:"Why squats?",context:context())
        let calls=await http.calls;let appleCalls=await attester.calls
        XCTAssertEqual(keys.load(),attester.key);XCTAssertEqual(appleCalls,["assert","key","attest","assert"])
        XCTAssertEqual(calls.count,5);XCTAssertTrue(calls.prefix(4).allSatisfy{$0.headers.isEmpty})
        XCTAssertEqual(calls.filter{!$0.headers.isEmpty}.count,1)
    }
    func testGenericAssertionFailureKeepsExistingKeyAndDoesNotEnrollOrCallModel() async {
        let old=Data(repeating:1,count:32).base64EncodedString();let keys=FixtureCoachKeyStore(old)
        let attester=FixtureCoachAttester(assertionFailures:[.unavailable]);let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        do {_ = try await client(transport).reply(to:"Why squats?",context:context());XCTFail("expected failure")} catch {}
        let calls=await http.calls;let appleCalls=await attester.calls
        XCTAssertEqual(keys.load(),old);XCTAssertEqual(appleCalls,["assert"])
        XCTAssertEqual(calls.count,1);XCTAssertTrue(calls.allSatisfy{$0.headers.isEmpty})
    }
    func testSecondInvalidKeyFailureStopsAfterOneEnrollmentWithoutCallingModel() async {
        let old=Data(repeating:1,count:32).base64EncodedString();let keys=FixtureCoachKeyStore(old)
        let attester=FixtureCoachAttester(assertionFailures:[.invalidKey,.invalidKey]);let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        do {_ = try await client(transport).reply(to:"Why squats?",context:context());XCTFail("expected failure")} catch {}
        let calls=await http.calls;let appleCalls=await attester.calls
        XCTAssertNil(keys.load());XCTAssertEqual(appleCalls,["assert","key","attest","assert"])
        XCTAssertEqual(calls.count,4);XCTAssertTrue(calls.allSatisfy{$0.headers.isEmpty})
    }
    func testMissingPurchaseOrUnsupportedAttestMakesZeroHTTPCalls() async {
        for supported in [true,false] {
            let http=FixtureCoachHTTP();let attester=FixtureCoachAttester(supported:supported)
            let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:supported ? nil : purchase),keys:FixtureCoachKeyStore(),http:http)
            do { _ = try await client(transport).reply(to:"Why squats?",context:context());XCTFail("expected denial") } catch {}
            let calls=await http.calls;let appleCalls=await attester.calls
            XCTAssertTrue(calls.isEmpty);XCTAssertTrue(appleCalls.isEmpty)
        }
    }
    func testEveryHandshakeFailureStopsAndFinalFailureNeverRetries() async {
        for index in 1...4 {
            let keys=FixtureCoachKeyStore();let http=FixtureCoachHTTP(failureAt:index)
            let transport=RuntimeAuthenticatedCoachTransport(attester:FixtureCoachAttester(),purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
            do { _ = try await client(transport).reply(to:"Why squats?",context:context());XCTFail("expected failure") } catch {}
            let calls=await http.calls;XCTAssertEqual(calls.count,index)
            if index <= 2 { XCTAssertNil(keys.load()) }
        }
    }
    func testNonCancellableAppleCallbackIsBoundedAndLateCompletionCannotSendOrStore() async throws {
        let attester=FixtureCoachAttester(hangKey:true);let http=FixtureCoachHTTP();let keys=FixtureCoachKeyStore()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        let started=ProcessInfo.processInfo.systemUptime
        do { _ = try await client(transport,timeout:0.05).reply(to:"Why squats?",context:context());XCTFail("expected timeout") } catch {}
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,1)
        await attester.releaseKey();try await Task.sleep(nanoseconds:20_000_000)
        let calls=await http.calls;XCTAssertTrue(calls.isEmpty);XCTAssertNil(keys.load())
    }
    func testAccountResetPreventsLateEnrollmentAndKeepsCoreDeletionNonBlocking() async throws {
        let attester=FixtureCoachAttester(hangKey:true);let http=FixtureCoachHTTP();let keys=FixtureCoachKeyStore()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        let send=Task {try await self.client(transport).reply(to:"Why squats?",context:self.context())}
        while await attester.calls.isEmpty { await Task.yield() }
        let started=ProcessInfo.processInfo.systemUptime;await transport.resetAccount()
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,0.5)
        await attester.releaseKey();_ = try? await send.value
        let calls=await http.calls;XCTAssertTrue(calls.isEmpty);XCTAssertNil(keys.load())
    }
    func testAccountResetPreventsLateInvalidKeyCallbackFromReenrolling() async throws {
        let old=Data(repeating:1,count:32).base64EncodedString();let keys=FixtureCoachKeyStore(old)
        let attester=FixtureCoachAttester(hangInvalidAssertion:true);let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        let send=Task {try await self.client(transport).reply(to:"Why squats?",context:self.context())}
        while !(await attester.calls.contains("assert")) {await Task.yield()}
        await transport.resetAccount();await attester.releaseAssertion();_ = try? await send.value
        let calls=await http.calls;let appleCalls=await attester.calls
        XCTAssertNil(keys.load());XCTAssertEqual(appleCalls,["assert"])
        XCTAssertEqual(calls.count,1);XCTAssertTrue(calls.allSatisfy{$0.headers.isEmpty})
    }
    func testConcurrentTurnFailsPromptlyWithoutReplacingAnInFlightHandshake() async throws {
        let attester=FixtureCoachAttester(hangKey:true);let http=FixtureCoachHTTP();let keys=FixtureCoachKeyStore()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:purchase),keys:keys,http:http)
        let first=Task {try await self.client(transport).reply(to:"Why squats?",context:self.context())}
        while await attester.calls.isEmpty { await Task.yield() }
        let started=ProcessInfo.processInfo.systemUptime
        do { _ = try await client(transport).reply(to:"Pistol-squat form?",context:context());XCTFail("concurrent turn must fail") } catch {}
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,0.5)
        let callsBefore=await http.calls;XCTAssertTrue(callsBefore.isEmpty)
        await attester.releaseKey();_ = try await first.value
        let calls=await http.calls;XCTAssertEqual(calls.count,4);XCTAssertEqual(calls.filter{!$0.headers.isEmpty}.count,1)
    }
    func testAccountResetAttemptsOnlyDeviceAuthenticatedMetadataDeletionWithoutPurchase() async throws {
        let attester=FixtureCoachAttester();let key=attester.key;let keys=FixtureCoachKeyStore(key);let http=FixtureCoachHTTP()
        let transport=RuntimeAuthenticatedCoachTransport(attester:attester,purchase:FixtureCoachPurchase(proof:nil),keys:keys,http:http)
        await transport.resetAccount();XCTAssertNil(keys.load())
        let deadline=ProcessInfo.processInfo.systemUptime+1
        while await http.calls.count < 2,ProcessInfo.processInfo.systemUptime < deadline { await Task.yield() }
        let calls=await http.calls;XCTAssertEqual(calls.count,2)
        let final=try XCTUnwrap(calls.last);XCTAssertEqual(final.body,Data("{}".utf8))
        let proof=try JSONDecoder().decode([String:String].self,from:Data(try XCTUnwrap(final.headers["X-RepToday-Coach-Auth"]).utf8))
        XCTAssertEqual(proof["operation"],"delete");XCTAssertEqual(proof["transactionJws"],"")
    }
    func testProductionConfigRequiresModeAndRejectsEmbeddedGate() {
        let origin=RuntimeAuthenticatedCoachTransport.origin
        XCTAssertTrue(CoachProxyClient.productionConfigurationAllowed(origin:origin,mode:"app-attest-storekit-v1",secret:nil))
        XCTAssertFalse(CoachProxyClient.productionConfigurationAllowed(origin:origin,mode:nil,secret:nil))
        XCTAssertFalse(CoachProxyClient.productionConfigurationAllowed(origin:origin,mode:"bearer",secret:nil))
        XCTAssertFalse(CoachProxyClient.productionConfigurationAllowed(origin:origin,mode:"app-attest-storekit-v1",secret:"fixture"))
        XCTAssertFalse(CoachProxyClient.productionConfigurationAllowed(origin:URL(string:origin.absoluteString+"?x=1")!,mode:"app-attest-storekit-v1",secret:nil))
    }
    private func boundedHTTP()->BoundedCoachHTTPTransport {
        BoundedCoachHTTPTransport(configuration:{let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[RuntimeHTTPFixture.self];return c})
    }
    func testActualHTTPTransportBoundsStreamAndDeclaredLengthAndRejectsRedirectResponse() async throws {
        let transport=boundedHTTP(),origin=RuntimeAuthenticatedCoachTransport.origin
        RuntimeHTTPFixture.state.set(.init(data:Data(repeating:120,count:16_384)))
        let accepted=try await transport.post(to:origin,jsonBody:Data("{}".utf8),headers:[:],timeoutSeconds:1)
        XCTAssertEqual(accepted.data.count,16_384)
        for plan in [RuntimeHTTPFixtureState.Plan(status:302),.init(data:Data(repeating:120,count:16_385)),.init(length:16_385)] {
            RuntimeHTTPFixture.state.set(plan)
            do {_ = try await transport.post(to:origin,jsonBody:Data("{}".utf8),headers:[:],timeoutSeconds:1);XCTFail("must reject response")} catch {}
            XCTAssertEqual(RuntimeHTTPFixture.state.requests,1)
        }
    }
    func testActualHTTPTransportRejectsForeignOriginBearerAndOversizedBodyBeforeAnyHTTP() async {
        let transport=boundedHTTP(),origin=RuntimeAuthenticatedCoachTransport.origin
        RuntimeHTTPFixture.state.set(.init())
        for (url,body,headers) in [(URL(string:"https://foreign.invalid/coach")!,Data("{}".utf8),[:]),
            (origin,Data("{}".utf8),["Authorization":"Bearer fixture"]),(origin,Data(repeating:120,count:32_769),[:])] {
            do {_ = try await transport.post(to:url,jsonBody:body,headers:headers,timeoutSeconds:1);XCTFail("must reject input")} catch {}
        }
        XCTAssertEqual(RuntimeHTTPFixture.state.requests,0)
    }
    func testActualHTTPTransportPartialBodyTimeoutDoesNotBlockCaller() async {
        RuntimeHTTPFixture.state.set(.init(data:Data("{".utf8),finish:false));let started=ProcessInfo.processInfo.systemUptime
        do {_ = try await boundedHTTP().post(to:RuntimeAuthenticatedCoachTransport.origin,jsonBody:Data("{}".utf8),headers:[:],timeoutSeconds:0.05);XCTFail("must time out")} catch {}
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,1)
    }
}

/// Captures the exact string passed to the production OSLog sink, not intermediate enums.
final class CoachDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    var diagnostics: CoachDiagnostics { CoachDiagnostics { self.append($0) } }
    private func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
}

extension CoachRuntimeAuthenticationTests {
    func testDiagnosticsSeparateHandshake401FromFinal401WithoutChangingErrorsOrKey() async {
        for handshake in [true, false] {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
            let keys = FixtureCoachKeyStore(attester.key)
            let http = FixtureCoachHTTP(failureAt: handshake ? 1 : 2,
                injectedResponse: (Data(#"{"error":"unauthorized"}"#.utf8), 401))
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                keys: keys, http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "SECRET_USER_TEXT", context: context())
                XCTFail("must fail")
            } catch {
                if handshake { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
                else { XCTAssertEqual(error as? CoachProxyClient.CoachError, .badStatus(401)) }
            }
            XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=\(handshake ? "challenge" : "http") category=http status=401 error=unauthorized"])
            let calls = await http.calls, appleCalls = await attester.calls
            XCTAssertEqual(calls.count, handshake ? 1 : 2)
            XCTAssertEqual(appleCalls, handshake ? [] : ["assert"])
            XCTAssertEqual(keys.load(), attester.key)
        }
    }

    func testDiagnosticsOnlyClassifyStrictBoundedFinalErrorsAndNeverLeakSentinels() async {
        let cases: [(Data, String)] = [
            (Data(#"{"error":"unauthorized"}"#.utf8), "unauthorized"),
            (Data(" \n{ \"error\" : \"key_unavailable\" }\t".utf8), "key_unavailable"),
            (Data(#"{"error":"auth_unavailable"}"#.utf8), "auth_unavailable"),
            (Data(#"{"error":"SECRET_TOKEN"}"#.utf8), "other"),
            (Data(#"{"error":"unauthorized","private":"SECRET_JWS"}"#.utf8), "other"),
            (Data(#"{"error":"unauthorized","error":"unauthorized"}"#.utf8), "other"),
            (Data(#"{"error":"unauthorized"} SECRET_BODY"#.utf8), "other"),
            (Data(#"{"error":"unauthorized""#.utf8), "other"),
            (Data(#"["unauthorized","SECRET_ACCOUNT"]"#.utf8), "other"),
            (Data(#"{"error":{"token":"SECRET_HEADER"}}"#.utf8), "other"),
            (Data([0xff, 0xfe]), "other"),
            (Data((#"{"error":"unauthorized"}"# + String(repeating: " ", count: 257)).utf8), "other"),
            (Data((#"{"error":"unauthorized"}"# + String(repeating: " ", count: 232)).utf8), "unauthorized")
        ]
        for (payload, classification) in cases {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
            let status = classification == "auth_unavailable" ? 503 : 401
            let http = FixtureCoachHTTP(finalResponses: [(payload, status)])
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: "SECRET_JWS"),
                keys: FixtureCoachKeyStore(attester.key), http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "SECRET_USER_TEXT", context: context())
                XCTFail("must fail")
            } catch { XCTAssertEqual(error as? CoachProxyClient.CoachError, .badStatus(status)) }
            XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=http category=http status=\(status) error=\(classification)"])
            for secret in ["SECRET", attester.key, http.challenge, testCoachSafetyIdentifier.rawValue,
                           RuntimeAuthenticatedCoachTransport.origin.absoluteString] {
                XCTAssertFalse(recorder.lines.joined().contains(secret))
            }
            XCTAssertTrue(recorder.lines.allSatisfy { $0.utf8.count < 200 })
            let calls = await http.calls; XCTAssertEqual(calls.count, 2) // Final 401 never reenrolls/retries.
        }
    }

    func testDiagnosticsURLFailuresSurviveRuntimeErasureWithSafeCodesOnly() async {
        for (code, category) in [(-1001, "timeout"), (-1009, "offline"), (-1200, "tls"), (-1003, "url"), (987654321, "url")] {
            for failureAt in [1, 2] {
                let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
                let error = NSError(domain: NSURLErrorDomain, code: code,
                    userInfo: [NSLocalizedDescriptionKey: "SECRET_DESCRIPTION", NSURLErrorFailingURLErrorKey: URL(string: "https://secret.invalid/SECRET_URL")!,
                               NSUnderlyingErrorKey: NSError(domain: "SECRET_DOMAIN", code: 123)])
                let http = FixtureCoachHTTP(failureAt: failureAt, injectedError: error)
                let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                    keys: FixtureCoachKeyStore(attester.key), http: http, diagnostics: recorder.diagnostics)
                do {
                    _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
                    XCTFail("must fail")
                } catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
                let suffix = code == 987654321 ? "" : " url_code=\(code)"
                XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=\(failureAt == 1 ? "challenge" : "transport") category=\(category)\(suffix)"])
                let calls = await http.calls; XCTAssertEqual(calls.count, failureAt)
            }
        }
    }

    func testDiagnosticsLocalProofAndUnsupportedDeviceFailBeforeHTTP() async {
        for supported in [true, false] {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester(supported: supported)
            let http = FixtureCoachHTTP(), keys = FixtureCoachKeyStore(attester.key)
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: nil),
                keys: keys, http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
                XCTFail("must fail")
            } catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
            XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=\(supported ? "purchase" : "configuration") category=unavailable"])
            let calls = await http.calls, appleCalls = await attester.calls
            XCTAssertTrue(calls.isEmpty); XCTAssertTrue(appleCalls.isEmpty)
            XCTAssertEqual(keys.load(), attester.key)
        }
    }

    func testDiagnosticsEnrollmentAndAssertionFailuresHaveDistinctStages() async {
        for enrollment in [true, false] {
            let recorder = CoachDiagnosticRecorder()
            let attester = FixtureCoachAttester(assertionFailures: enrollment ? [] : [.unavailable])
            let keys = FixtureCoachKeyStore(enrollment ? nil : attester.key)
            let http = FixtureCoachHTTP(failureAt: enrollment ? 2 : nil,
                injectedResponse: (Data(#"{"error":"auth_unavailable"}"#.utf8), 503))
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                keys: keys, http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
                XCTFail("must fail")
            } catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
            XCTAssertEqual(recorder.lines, [enrollment
                ? "[RepTodayCoach] transport=runtime endpoint=production stage=enrollment category=http status=503 error=auth_unavailable"
                : "[RepTodayCoach] transport=runtime endpoint=production stage=assertion category=unavailable"])
            XCTAssertEqual(keys.load(), enrollment ? nil : attester.key)
            let calls = await http.calls; XCTAssertEqual(calls.count, enrollment ? 2 : 1)
        }
    }

    func testDiagnosticsMalformedAndOversizedHandshakeNeverLeak() async {
        for data in [Data(#"{"error":"unauthorized","private":"SECRET_KEY"}"#.utf8),
                     Data((#"{"error":"unauthorized"}"# + String(repeating: " ", count: 1025)).utf8)] {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
            let http = FixtureCoachHTTP(failureAt: 1, injectedResponse: (data, 401))
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                keys: FixtureCoachKeyStore(attester.key), http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
                XCTFail("must fail")
            } catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
            XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=challenge category=http status=401 error=other"])
        }
    }

    func testDiagnosticsCancellationIsSilentAndDoesNotChangeErrorOrLateState() async {
        let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester(hangKey: true)
        let http = FixtureCoachHTTP(), keys = FixtureCoachKeyStore()
        let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
            keys: keys, http: http, diagnostics: recorder.diagnostics)
        let task = Task { try await self.client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: self.context()) }
        for _ in 0..<1000 {
            if await attester.calls == ["key"] { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let before = await attester.calls; XCTAssertEqual(before, ["key"])
        task.cancel()
        do { _ = try await task.value; XCTFail("must cancel") }
        catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
        await attester.releaseKey()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(recorder.lines.isEmpty); XCTAssertNil(keys.load())
        let calls = await http.calls; XCTAssertTrue(calls.isEmpty)
    }

    func testDiagnosticsURLCancellationIsSilentAtHandshakeAndFinalTransport() async {
        for failureAt in [1, 2] {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
            let http = FixtureCoachHTTP(failureAt: failureAt, injectedError: NSError(domain: NSURLErrorDomain, code: -999))
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                keys: FixtureCoachKeyStore(attester.key), http: http, diagnostics: recorder.diagnostics)
            do {
                _ = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
                XCTFail("must cancel")
            } catch { XCTAssertEqual(error as? CoachAuthenticationError, .unavailable) }
            XCTAssertTrue(recorder.lines.isEmpty)
        }
    }

    func testDiagnosticsDeadlineIsOneFailureAndLateCallbackStaysSilent() async {
        let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester(hangKey: true)
        let http = FixtureCoachHTTP(), keys = FixtureCoachKeyStore()
        let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
            keys: keys, http: http, diagnostics: recorder.diagnostics)
        do {
            _ = try await client(runtime, timeout: 0.1, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
            XCTFail("must time out")
        } catch { XCTAssertEqual(error as? CoachAuthenticationError, .timeout) }
        let before = await attester.calls; XCTAssertEqual(before, ["key"])
        await attester.releaseKey()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=runtime endpoint=production stage=enrollment category=timeout"])
        XCTAssertNil(keys.load()); let calls = await http.calls; XCTAssertTrue(calls.isEmpty)
    }

    func testDiagnosticsSuccessfulRepliesAndExistingKeyRecoveryStaySilent() async throws {
        for recovery in [false, true] {
            let recorder = CoachDiagnosticRecorder(), attester = FixtureCoachAttester()
            let http = FixtureCoachHTTP(expireFirstKey: recovery), keys = FixtureCoachKeyStore(recovery ? attester.key : nil)
            let runtime = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: FixtureCoachPurchase(proof: purchase),
                keys: keys, http: http, diagnostics: recorder.diagnostics)
            let reply = try await client(runtime, diagnostics: recorder.diagnostics).reply(to: "fixture", context: context())
            XCTAssertEqual(reply, "Fixture supplied-context reply"); XCTAssertTrue(recorder.lines.isEmpty)
            XCTAssertEqual(keys.load(), attester.key)
            let calls = await http.calls; XCTAssertEqual(calls.count, recovery ? 5 : 4)
        }
    }
}

private struct DirectDiagnosticHTTP: CoachProxyTransport {
    let error: NSError?
    let data: Data
    let status: Int
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        if let error { throw error }
        return (data, status)
    }
}

extension CoachRuntimeAuthenticationTests {
    func testDiagnosticsDirectTransportPreservesURLErrorIdentityAndCancellationSilence() async {
        for code in [-1009, -999] {
            let recorder = CoachDiagnosticRecorder()
            let original = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "SECRET_DESCRIPTION"])
            let direct = DirectDiagnosticHTTP(error: original, data: Data(), status: 200)
            let client = CoachProxyClient(endpoint: URL(string: "https://SECRET_HOST.invalid/SECRET_PATH")!,
                sharedSecret: "SECRET_BEARER", safetyIdentifier: testCoachSafetyIdentifier, transport: direct, diagnostics: recorder.diagnostics)
            do { _ = try await client.reply(to: "SECRET_MESSAGE", context: context()); XCTFail("must fail") }
            catch { XCTAssertTrue(error as NSError === original) }
            XCTAssertEqual(recorder.lines, code == -999 ? [] : ["[RepTodayCoach] transport=direct endpoint=other stage=transport category=offline url_code=-1009"])
        }
    }

    func testDiagnosticsMalformedSuccessfulResponsePreservesDecodeErrorWithoutPayload() async {
        let recorder = CoachDiagnosticRecorder()
        let direct = DirectDiagnosticHTTP(error: nil, data: Data("SECRET_RESPONSE".utf8), status: 200)
        let client = CoachProxyClient(endpoint: URL(string: "https://SECRET_HOST.invalid/SECRET_PATH")!,
            safetyIdentifier: testCoachSafetyIdentifier, transport: direct, diagnostics: recorder.diagnostics)
        do { _ = try await client.reply(to: "SECRET_MESSAGE", context: context()); XCTFail("must fail") }
        catch { XCTAssertTrue(error is DecodingError) }
        XCTAssertEqual(recorder.lines, ["[RepTodayCoach] transport=direct endpoint=other stage=response category=other status=200 error=other"])
    }
}

extension CoachRuntimeAuthenticationTests {
    func testDiagnosticsEmptyReplyAndRefusalKeepTheirOriginalSemantics() async {
        for refusal in [true, false] {
            let recorder = CoachDiagnosticRecorder()
            let data = Data((refusal ? #"{"outcome":"safety_refusal","reply":"SECRET_REFUSAL"}"# : #"{"reply":"  "}"#).utf8)
            let client = CoachProxyClient(endpoint: URL(string: "https://fixture.invalid/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: DirectDiagnosticHTTP(error: nil, data: data, status: 200), diagnostics: recorder.diagnostics)
            do { _ = try await client.reply(to: "fixture", context: context()); XCTFail("must fail") }
            catch { XCTAssertEqual(error as? CoachProxyClient.CoachError, refusal ? .safetyRefusal : .emptyReply) }
            XCTAssertEqual(recorder.lines, refusal ? [] : ["[RepTodayCoach] transport=direct endpoint=other stage=response category=other status=200 error=other"])
        }
    }
}
