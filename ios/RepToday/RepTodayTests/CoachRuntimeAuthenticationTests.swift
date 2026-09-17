import XCTest
import CryptoKit
import DeviceCheck
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
    func productionPremiumProof() async throws -> String {
        guard let proof else { throw CoachAuthenticationError.unavailable }; return proof
    }
}
private actor FixtureCoachHTTP: CoachProxyTransport {
    struct Call: Sendable { let body: Data; let headers: [String: String]; let timeout: Double }
    private(set) var calls = [Call]()
    var failureAt: Int?; var expireFirstKey: Bool; var finalStatus: Int
    let challenge = "eA." + String(repeating: "A", count: 43) // Shape fixture; never a valid server HMAC.
    init(failureAt: Int? = nil, expireFirstKey: Bool = false, finalStatus: Int = 200) {
        self.failureAt = failureAt; self.expireFirstKey = expireFirstKey; self.finalStatus = finalStatus
    }
    func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        guard url == RuntimeAuthenticatedCoachTransport.origin else { throw CoachAuthenticationError.unavailable }
        calls.append(Call(body: jsonBody, headers: headers, timeout: timeoutSeconds))
        if failureAt == calls.count { throw CoachAuthenticationError.unavailable }
        if !headers.isEmpty { return (Data(#"{"reply":"Fixture supplied-context reply"}"#.utf8), finalStatus) }
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
    private func client(_ transport: RuntimeAuthenticatedCoachTransport, timeout: Double = 30) -> CoachProxyClient {
        CoachProxyClient(endpoint:RuntimeAuthenticatedCoachTransport.origin, timeoutSeconds:timeout,
                         safetyIdentifier:testCoachSafetyIdentifier,transport:transport)
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
