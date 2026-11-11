import XCTest
@testable import RepToday

/// The wire between the app and `convex/sync.ts` / `convex/accounts.ts` (M3): the request shape the
/// backend's validators accept, the response it sends, and how each kind of failure is read. Requests
/// are answered in process by a stub `URLProtocol`; nothing reaches the network.
final class ConvexSyncRemoteTests: XCTestCase {
    private let deployment = URL(string: "https://example-dev-123.convex.cloud")!

    override func tearDown() {
        StubConvexProtocol.reset()
        super.tearDown()
    }

    private func remote(token: String? = "session-token") -> ConvexSyncRemote {
        remote { token }
    }

    private func remote(token: @escaping @Sendable () async throws -> String?) -> ConvexSyncRemote {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubConvexProtocol.self]
        let session = URLSession(configuration: configuration)
        return ConvexSyncRemote(client: ConvexHTTPClient(deploymentURL: deployment, session: session, token: token))
    }

    /// A Clerk-shaped session token issued to `subject` (only the payload is read on the device).
    private static func sessionToken(subject: String) -> String {
        let payload = Data(#"{"sub":"\#(subject)","exp":4102444800}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
    }

    // MARK: - The linked account's token only

    /// The device is linked to A, but the Clerk session on it is B's (signed in moments before the link
    /// is refused, or left behind by a sign-out that failed): no request reaches the backend, so
    /// nothing of A's is uploaded to B and nothing of B's is pulled into A's store.
    func testAnotherAccountsSessionSendsNothing() async throws {
        let auth = StubAccountAuthService(isConfigured: true, identity: AccountIdentity(userId: "user_b", email: nil, method: .google),
                                          token: Self.sessionToken(subject: "user_b"))
        let remote = remote { try await auth.sessionToken(forLinkedAccount: "user_a") }

        do {
            _ = try await remote.pull(since: 0, limit: 10)
            XCTFail("another account's session must not be used")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .notSignedIn)
        }
        do {
            _ = try await remote.deleteAccount()
            XCTFail("another account's session must not be used")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .notSignedIn)
        }
        XCTAssertTrue(StubConvexProtocol.requests.isEmpty)
    }

    func testTheLinkedAccountsSessionIsSentAndAnUnlinkedDeviceSendsAnySession() async throws {
        let token = Self.sessionToken(subject: "user_a")
        let auth = StubAccountAuthService(isConfigured: true, identity: AccountIdentity(userId: "user_a", email: nil, method: .apple), token: token)
        let linked = try await auth.sessionToken(forLinkedAccount: "user_a")
        XCTAssertEqual(linked, token)
        let unlinked = try await auth.sessionToken(forLinkedAccount: nil)
        XCTAssertEqual(unlinked, token, "onboarding's restore runs before the device links")
        let other = try await auth.sessionToken(forLinkedAccount: "user_b")
        XCTAssertNil(other)
        let unreadable = try await StubAccountAuthService(isConfigured: true, identity: AccountIdentity(userId: "user_a", email: nil, method: .apple), token: "not-a-jwt")
            .sessionToken(forLinkedAccount: "user_a")
        XCTAssertNil(unreadable, "a token whose subject cannot be read is never sent for a linked account")
    }

    // MARK: - push

    func testPushSendsTheBackendsChangeShapeWithTheSessionToken() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"results":[],"serverSeq":3}}"#)
        let log = SyncFixtures.log(daysAgo: 1)
        let changes = [
            PendingSyncChange(type: .workoutLog, recordId: log.id.uuidString, revision: UUID(), changedAt: SyncFixtures.base,
                              content: .workoutLog(payload: "{\"a\":1}", completedAt: log.completedAt)),
            PendingSyncChange(type: .outsideActivity, recordId: "A1", revision: UUID(), changedAt: SyncFixtures.base, content: .deleted),
            PendingSyncChange(type: .profile, recordId: "U1", revision: UUID(), changedAt: SyncFixtures.base,
                              content: .profile(payload: "{}", focusAreas: ["abs"])),
            PendingSyncChange(type: .sessionPolicy, recordId: "U1", revision: UUID(), changedAt: SyncFixtures.base, content: nil),
        ]

        try await remote().push(changes)

        let request = try XCTUnwrap(StubConvexProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example-dev-123.convex.cloud/api/mutation")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
        let body = try XCTUnwrap(StubConvexProtocol.bodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, "sync:push")
        XCTAssertEqual(json["format"] as? String, "json")
        let wire = try XCTUnwrap((json["args"] as? [String: Any])?["changes"] as? [[String: Any]])
        XCTAssertEqual(wire.count, 3, "a change with nothing to upload is not sent")
        XCTAssertEqual(wire[0]["table"] as? String, "workoutLog")
        XCTAssertEqual(wire[0]["deleted"] as? Bool, false)
        XCTAssertEqual(wire[0]["completedAt"] as? Double, log.completedAt.syncMilliseconds)
        XCTAssertEqual(wire[0]["clientUpdatedAt"] as? Double, SyncFixtures.base.syncMilliseconds)
        XCTAssertEqual(Set(wire[1].keys), ["table", "recordId", "clientUpdatedAt", "deleted"], "a tombstone carries no payload or null fields")
        XCTAssertEqual(wire[2]["focusAreas"] as? [String], ["abs"])
        XCTAssertNil(wire[2]["deleted"], "a profile is never a tombstone")
    }

    func testPushOfNothingSendsNoRequest() async throws {
        try await remote().push([
            PendingSyncChange(type: .profile, recordId: "U1", revision: UUID(), changedAt: SyncFixtures.base, content: nil),
        ])
        XCTAssertTrue(StubConvexProtocol.requests.isEmpty)
    }

    func testNoSessionMeansNoRequest() async throws {
        do {
            try await remote(token: nil).push([
                PendingSyncChange(type: .workoutLog, recordId: "L1", revision: UUID(), changedAt: SyncFixtures.base, content: .deleted),
            ])
            XCTFail("no session, no upload")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .notSignedIn)
        }
        XCTAssertTrue(StubConvexProtocol.requests.isEmpty)
    }

    // MARK: - pull

    func testPullDecodesEveryKindOfRecord() async throws {
        StubConvexProtocol.respond(json: """
        {"status":"success","value":{"cursor":9,"hasMore":true,"changes":[
          {"table":"profile","recordId":"U1","serverSeq":5,"clientUpdatedAt":1000,"payload":"{}","focusAreas":["legs"]},
          {"table":"sessionPolicy","recordId":"U1","serverSeq":6,"clientUpdatedAt":1000,"payload":"{}"},
          {"table":"workoutLog","recordId":"L1","serverSeq":7,"clientUpdatedAt":1000,"deleted":false,"payload":"{}","completedAt":2000},
          {"table":"outsideActivity","recordId":"A1","serverSeq":8,"clientUpdatedAt":1000,"deleted":true,"date":3000},
          {"table":"customWorkout","recordId":"C1","serverSeq":9,"clientUpdatedAt":1000,"payload":"{}"}
        ]}}
        """)

        let page = try await remote().pull(since: 4, limit: 50)

        XCTAssertEqual(page.cursor, 9)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.records, [
            RemoteSyncRecord(type: .profile, recordId: "U1", clientUpdatedAt: Date(syncMilliseconds: 1000), content: .profile(payload: "{}", focusAreas: ["legs"])),
            RemoteSyncRecord(type: .sessionPolicy, recordId: "U1", clientUpdatedAt: Date(syncMilliseconds: 1000), content: .sessionPolicy(payload: "{}")),
            RemoteSyncRecord(type: .workoutLog, recordId: "L1", clientUpdatedAt: Date(syncMilliseconds: 1000), content: .workoutLog(payload: "{}", completedAt: Date(syncMilliseconds: 2000))),
            RemoteSyncRecord(type: .outsideActivity, recordId: "A1", clientUpdatedAt: Date(syncMilliseconds: 1000), content: .deleted),
        ], "a table this build does not know is skipped, not fatal")
        let body = try XCTUnwrap(StubConvexProtocol.bodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, "sync:pull")
        XCTAssertEqual((json["args"] as? [String: Any])?["since"] as? Double, 4)
    }

    // MARK: - Failures

    func testTheBackendsRefusalsAreReadByCode() async throws {
        let cases: [(String, SyncRemoteError)] = [
            ("unauthenticated", .unauthenticated),
            ("account_deleting", .accountDeleting),
            ("invalid_change", .rejected(code: "invalid_change", message: "bad")),
        ]
        for (code, expected) in cases {
            StubConvexProtocol.reset()
            StubConvexProtocol.respond(json: #"{"status":"error","errorMessage":"bad","errorData":{"code":"\#(code)","message":"bad"}}"#)
            do {
                _ = try await remote().pull(since: 0, limit: 10)
                XCTFail("expected \(code)")
            } catch {
                XCTAssertEqual(error as? SyncRemoteError, expected)
            }
        }
    }

    func testATokenTheDeploymentCannotVerifyIsUnauthenticated() async throws {
        StubConvexProtocol.respond(json: #"{"code":"InvalidAuthHeader","message":"Could not parse JWT payload."}"#, status: 401)
        do {
            _ = try await remote().pull(since: 0, limit: 10)
            XCTFail("expected unauthenticated")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .unauthenticated)
        }
    }

    func testOfflineAndServerTroubleAreRetryable() async throws {
        StubConvexProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await remote().pull(since: 0, limit: 10)
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .unreachable)
        }
        StubConvexProtocol.reset()
        StubConvexProtocol.respond(json: "upstream failure", status: 503)
        do {
            _ = try await remote().pull(since: 0, limit: 10)
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? SyncRemoteError, .unreachable)
        }
    }

    func testDeleteAccountCallsTheAction() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"deleted":true,"clerkUserDeleted":true}}"#)
        let outcome = try await remote().deleteAccount()
        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(StubConvexProtocol.requests.first?.url?.path, "/api/action")
        let body = try XCTUnwrap(StubConvexProtocol.bodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, "accounts:deleteAccount")
    }

    func testADeletionClerkHasNotConfirmedIsPending() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"deleted":true,"clerkUserDeleted":false}}"#)
        let outcome = try await remote().deleteAccount()
        XCTAssertEqual(outcome, .signInRemovalPending)
    }

    // MARK: - Configuration

    func testOnlyAConvexCloudOriginIsAccepted() {
        XCTAssertEqual(AccountBackendConfiguration.usableConvexURL("https://courteous-dogfish-560.convex.cloud")?.absoluteString,
                       "https://courteous-dogfish-560.convex.cloud")
        XCTAssertNotNil(AccountBackendConfiguration.usableConvexURL(" https://a-b-1.convex.cloud/ "))
        for bad in ["", "$(REPTODAY_CONVEX_URL)", "http://a-b-1.convex.cloud", "https://a-b-1.convex.site",
                    "https://convex.cloud", "https://a-b-1.convex.cloud/api", "https://user:@a-b-1.convex.cloud",
                    "https://evil.example.com/?x=.convex.cloud"] {
            XCTAssertNil(AccountBackendConfiguration.usableConvexURL(bad), bad)
        }
    }

    func testOnlyAClerkPublishableKeyIsAccepted() {
        XCTAssertNotNil(ClerkAccountAuthService.usablePublishableKey("pk_test_ZGVhci1mbG91bmRlci03NzM1LmNsZXJrLmFjY291bnRzLmRldiQ"))
        XCTAssertNotNil(ClerkAccountAuthService.usablePublishableKey("pk_live_abc"))
        for bad in ["", "pk_test_", "$(REPTODAY_CLERK_PUBLISHABLE_KEY)", "sk_test_secret", "abc"] {
            XCTAssertNil(ClerkAccountAuthService.usablePublishableKey(bad), bad)
        }
    }
}

/// Answers every request with a scripted response and records what was sent.
final class StubConvexProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var response: (Data, Int)?
    nonisolated(unsafe) private static var failure: Error?
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    nonisolated(unsafe) private(set) static var bodies: [Data] = []

    static func respond(json: String, status: Int = 200) {
        lock.lock(); defer { lock.unlock() }
        response = (Data(json.utf8), status)
        failure = nil
    }

    static func fail(with error: Error) {
        lock.lock(); defer { lock.unlock() }
        failure = error
        response = nil
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        response = nil
        failure = nil
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.bodies.append(request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data())
        let response = Self.response
        let failure = Self.failure
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let (data, status) = response ?? (Data(), 500)
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
