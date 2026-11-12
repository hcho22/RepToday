import XCTest
@testable import RepToday

/// The wire between the app and `convex/coach.ts` / `convex/entitlements.ts` (M4): the request shapes the
/// backend's validators accept, the replies it sends, and how each refusal reads. Answered in process by
/// the same stub `URLProtocol` the sync wire tests use; nothing reaches the network.
final class ConvexCoachServiceTests: XCTestCase {
    private let deployment = URL(string: "https://example-dev-123.convex.cloud")!

    override func tearDown() {
        StubConvexProtocol.reset()
        super.tearDown()
    }

    private func client() -> ConvexHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubConvexProtocol.self]
        return ConvexHTTPClient(deploymentURL: deployment, session: URLSession(configuration: configuration)) { "session-token" }
    }

    private func sentJSON() throws -> [String: Any] {
        let body = try XCTUnwrap(StubConvexProtocol.bodies.last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testATurnSendsTheMessageItsIdAndTodayAsAnActionWithALongerTimeout() async throws {
        StubConvexProtocol.respond(json: #"""
        {"status":"success","value":{
          "user":{"id":"7c9e6679-7425-40de-944b-e07fc1f90ae7","role":"user","text":"hi","createdAt":1794000000000,"proposals":[]},
          "coach":{"id":"c1","role":"coach","text":"Hello.","createdAt":1794000000001,"proposals":[
            {"id":"p1","kind":"outsideActivity","status":"proposed","activityType":"run","minutes":30,"distanceMeters":5000,"day":"today"}]}}}
        """#)
        let today = CoachTodaySnapshot(localDate: "2026-11-11", utcOffsetMinutes: -480, kind: .train, trainingDay: .push, minutes: 20,
                                       movements: [.init(id: "push_incline", name: "Incline Push-Up")])
        let id = try XCTUnwrap(UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7"))
        let turn = try await ConvexCoachService(client: client()).send(clientMessageId: id, message: "hi", today: today)

        XCTAssertEqual(turn.coach.text, "Hello.")
        XCTAssertEqual(turn.coach.proposals.first?.action, .outsideActivity(type: .run, minutes: 30, distanceMeters: 5000, day: .today))
        let request = try XCTUnwrap(StubConvexProtocol.requests.last)
        XCTAssertEqual(request.url?.path, "/api/action")
        XCTAssertEqual(request.timeoutInterval, ConvexCoachService.turnTimeout)
        let json = try sentJSON()
        XCTAssertEqual(json["path"] as? String, "coach:send")
        let args = try XCTUnwrap(json["args"] as? [String: Any])
        XCTAssertEqual(args["clientMessageId"] as? String, "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        let sentToday = try XCTUnwrap(args["today"] as? [String: Any])
        XCTAssertEqual(sentToday["trainingDay"] as? String, "push")
        XCTAssertEqual((sentToday["movements"] as? [[String: Any]])?.first?["id"] as? String, "push_incline")
    }

    func testATurnWithoutTodayOmitsItRatherThanSendingNull() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"user":{"id":"u","role":"user","text":"hi","createdAt":1,"proposals":[]},"coach":{"id":"c","role":"coach","text":"ok","createdAt":2,"proposals":[]}}}"#)
        _ = try await ConvexCoachService(client: client()).send(clientMessageId: UUID(), message: "hi", today: nil)
        let args = try XCTUnwrap(try sentJSON()["args"] as? [String: Any])
        XCTAssertEqual(Set(args.keys), ["clientMessageId", "message"])
    }

    func testRefusalsReadInTheCoachsTerms() async throws {
        let cases: [(String, CoachServiceError)] = [
            ("not_premium", .notPremium), ("limit_reached", .limitReached), ("invalid_message", .invalidMessage),
            ("coach_unavailable", .unavailable), ("unauthenticated", .signedOut), ("account_deleting", .accountDeleting),
        ]
        for (code, expected) in cases {
            StubConvexProtocol.respond(json: #"{"status":"error","errorMessage":"x","errorData":{"code":"\#(code)","message":"x"}}"#)
            do {
                _ = try await ConvexCoachService(client: client()).history()
                XCTFail("\(code) should throw")
            } catch {
                XCTAssertEqual(error as? CoachServiceError, expected, code)
            }
        }
        StubConvexProtocol.fail(with: URLError(.notConnectedToInternet))
        do {
            _ = try await ConvexCoachService(client: client()).history()
            XCTFail("offline should throw")
        } catch {
            XCTAssertEqual(error as? CoachServiceError, .offline)
        }
    }

    func testRecordingAnOutcomeSendsTheMessageProposalAndStatus() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"status":"undone"}}"#)
        try await ConvexCoachService(client: client()).recordOutcome(messageId: "m1", proposalId: "p1", status: .undone)
        let json = try sentJSON()
        XCTAssertEqual(json["path"] as? String, "coach:recordProposalOutcome")
        XCTAssertEqual(json["args"] as? [String: String], ["messageId": "m1", "proposalId": "p1", "status": "undone"])
    }

    // MARK: - The entitlement (US-CA02)

    func testTheAppAccountTokenAndStatusAreRead() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":"0d9d1a54-3b2a-4b8e-9f00-1c2d3e4f5a6b"}"#)
        let token = try await ConvexPremiumEntitlementService(client: client()).appAccountToken()
        XCTAssertEqual(token.uuidString.lowercased(), "0d9d1a54-3b2a-4b8e-9f00-1c2d3e4f5a6b")
        XCTAssertEqual(try sentJSON()["path"] as? String, "entitlements:appAccountToken")

        StubConvexProtocol.respond(json: #"{"status":"success","value":{"premium":true,"expiresAt":1794000000000,"productId":"com.reptoday.app.premium.monthly"}}"#)
        let status = try await ConvexPremiumEntitlementService(client: client()).status()
        XCTAssertTrue(status.premium)
    }

    func testLinkingSendsTheSignedTransactionAndReadsAnotherAccountsSubscription() async throws {
        StubConvexProtocol.respond(json: #"{"status":"success","value":{"premium":true,"expiresAt":null,"productId":null}}"#)
        let linked = try await ConvexPremiumEntitlementService(client: client()).link(transactions: ["a.b.c"])
        XCTAssertTrue(linked.premium)
        let json = try sentJSON()
        XCTAssertEqual(json["path"] as? String, "entitlements:linkTransaction")
        XCTAssertEqual(json["args"] as? [String: String], ["jws": "a.b.c"])

        StubConvexProtocol.respond(json: #"{"status":"error","errorMessage":"x","errorData":{"code":"linked_to_other_account"}}"#)
        do {
            _ = try await ConvexPremiumEntitlementService(client: client()).link(transactions: ["a.b.c"])
            XCTFail("a subscription on another account is refused")
        } catch {
            XCTAssertEqual(error as? PremiumEntitlementError, .linkedToOtherAccount)
        }
    }
}
