import XCTest
@testable import RepToday

@MainActor
final class CoachSyntheticQAViewModelTests: XCTestCase {
    private final class Transport: CoachProxyTransport, @unchecked Sendable {
        var bodies: [Data] = []
        var headers: [[String: String]] = []
        var result = Data(#"{"reply":"Offline test reply; semantics are unverified."}"#.utf8)
        var status = 200
        var failure: Error?
        var onPost: (() async -> Void)?
        func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
            XCTAssertEqual(url.absoluteString, CoachProxyClient.productionOrigin)
            XCTAssertGreaterThan(timeoutSeconds, 0)
            XCTAssertLessThanOrEqual(timeoutSeconds, 30)
            bodies.append(jsonBody)
            self.headers.append(headers)
            await onPost?()
            if let failure { throw failure }
            return (result, status)
        }
    }

    private final class SubscriptionDouble: SubscriptionServiceProtocol {
        var value = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        var failure: Error?
        var onRead: (() async -> Void)?
        var writes = 0
        func currentSubscription() async throws -> Subscription {
            await onRead?()
            if let failure { throw failure }
            return value
        }
        func refreshEntitlements() async throws -> Subscription { try await currentSubscription() }
        func premiumPlans() async throws -> [SubscriptionPlan] { [] }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { writes += 1; return .resolved(value) }
        func purchasePremium() async throws -> Subscription { writes += 1; return value }
        func restorePurchases() async throws -> Subscription { writes += 1; return value }
    }

    private final class Consent { var acknowledged = true }
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "CoachSyntheticQA-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func model(_ transport: Transport, subscription: SubscriptionDouble = SubscriptionDouble(),
                       consent: Consent = Consent(), available: Bool = true, timeout: Double = 30) async -> CoachSyntheticQAViewModel {
        let client = CoachProxyClient(endpoint: URL(string: CoachProxyClient.productionOrigin)!, timeoutSeconds: timeout,
                                      safetyIdentifier: testCoachSafetyIdentifier, transport: transport)
        let vm = CoachSyntheticQAViewModel(client: available ? client : nil, subscription: subscription,
                                          consent: { consent.acknowledged }, budget: CoachSyntheticQABudget(defaults: defaults))
        vm.readinessConfirmed = true
        await vm.loadEligibility()
        return vm
    }

    func testTwoExplicitTurnsUseApprovedFixturesInOrderWithoutBearerOrPurchaseWrites() async throws {
        let transport = Transport()
        let subscription = SubscriptionDouble()
        let vm = await model(transport, subscription: subscription)
        XCTAssertEqual(transport.bodies.count, 0, "appearing/eligibility never sends")
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 1)
        XCTAssertNotNil(vm.reply)
        XCTAssertEqual(vm.budget.stage, .whyAttempted, "a return is not semantic success")
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 1, "review is required before a second turn")
        vm.reviewReturnedReply(passed: true)
        XCTAssertNil(vm.reply)
        XCTAssertEqual(vm.budget.next, .pistolForm)
        await vm.sendNext()
        vm.reviewReturnedReply(passed: true)
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 2)
        XCTAssertEqual(vm.budget.stage, .complete)
        XCTAssertEqual(subscription.writes, 0)
        XCTAssertTrue(transport.headers.allSatisfy(\.isEmpty))
        for (index, selection) in CoachSyntheticFixtures.Selection.allCases.enumerated() {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.bodies[index]) as? [String: Any])
            let context = try JSONSerialization.jsonObject(with: JSONEncoder().encode(selection.context)) as! NSDictionary
            XCTAssertTrue(body["context"] as? NSDictionary == context, "exact shared context reaches the wire")
            XCTAssertTrue(body["message"] as? String == selection.prompt, "exact approved prompt reaches the wire")
            XCTAssertEqual(Set(body.keys), ["context", "message", "safetyIdentifier"])
        }
        let reopened = await model(transport)
        await reopened.sendNext()
        XCTAssertEqual(transport.bodies.count, 2, "relaunch never resets the budget")
        // Only an enum stage is retained, no request body or model reply.
        let persisted = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.values.first as? String, "complete")
    }

    func testConsentPremiumReadinessAndMissingClientAllSendNothing() async {
        let transport = Transport()
        let consent = Consent()
        consent.acknowledged = false
        let vm = await model(transport, consent: consent)
        await vm.sendNext()
        XCTAssertFalse(vm.canSend)
        consent.acknowledged = true
        vm.readinessConfirmed = false
        await vm.sendNext()
        let free = SubscriptionDouble()
        free.value = .free
        await (await model(transport, subscription: free)).sendNext()
        free.failure = URLError(.notConnectedToInternet)
        await (await model(transport, subscription: free)).sendNext()
        await (await model(transport, available: false)).sendNext()
        XCTAssertEqual(transport.bodies.count, 0)
        XCTAssertEqual(vm.budget.stage, .ready)
    }

    func testPremiumLossAndConsentRevocationDuringRecheckStopBeforeClientSend() async {
        let transport = Transport()
        let subscription = SubscriptionDouble()
        let consent = Consent()
        let vm = await model(transport, subscription: subscription, consent: consent)
        subscription.onRead = { consent.acknowledged = false }
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 0)
        XCTAssertEqual(vm.budget.stage, .stopped)
        XCTAssertFalse(vm.isSending)
        defaults.removePersistentDomain(forName: suite)
        consent.acknowledged = true
        subscription.onRead = nil
        let next = await model(transport, subscription: subscription, consent: consent)
        subscription.value = .free
        await next.sendNext()
        XCTAssertEqual(transport.bodies.count, 0)
        XCTAssertEqual(next.budget.stage, .stopped)
    }

    func testEveryFailureStopsWithoutRetryOrPrivateErrorOutput() async {
        for scenario in 0..<7 {
            defaults.removePersistentDomain(forName: suite)
            let transport = Transport()
            switch scenario {
            case 0: transport.failure = URLError(.timedOut)
            case 1: transport.failure = URLError(.notConnectedToInternet)
            case 2: transport.status = 401
            case 3: transport.status = 502
            case 4: transport.result = Data(#"{"reply":" "}"#.utf8)
            case 5: transport.result = Data(#"{"outcome":"safety_refusal"}"#.utf8)
            default: transport.result = Data("PRIVATE_ERROR_CONTENT".utf8)
            }
            let vm = await model(transport)
            await vm.sendNext()
            await vm.sendNext()
            let reopened = await model(transport)
            await reopened.sendNext()
            XCTAssertEqual(transport.bodies.count, 1)
            XCTAssertEqual(vm.budget.stage, .stopped)
            XCTAssertNil(vm.reply)
            XCTAssertFalse(vm.isSending)
            XCTAssertFalse(vm.status.contains("PRIVATE_ERROR_CONTENT"))
        }
    }

    func testFailedReviewAndLeavingBeforeReviewConsumeBudget() async {
        let transport = Transport()
        let vm = await model(transport)
        await vm.sendNext()
        vm.reviewReturnedReply(passed: false)
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 1)
        defaults.removePersistentDomain(forName: suite)
        let next = await model(transport)
        await next.sendNext()
        next.close()
        XCTAssertNil(next.reply)
        XCTAssertFalse(next.readinessConfirmed)
        await (await model(transport)).sendNext()
        XCTAssertEqual(transport.bodies.count, 2)
    }

    func testReentrantSendAndCloseDiscardLateReply() async {
        let transport = Transport()
        let vm = await model(transport)
        transport.onPost = {
            await vm.sendNext()
            vm.close()
        }
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 1)
        XCTAssertNil(vm.reply)
        XCTAssertEqual(vm.budget.stage, .stopped)
    }

    func testTotalTimeoutDoesNotRetryOrExposeLateResponse() async {
        let transport = Transport()
        transport.onPost = { try? await Task.sleep(nanoseconds: 100_000_000) }
        let vm = await model(transport, timeout: 0.01)
        await vm.sendNext()
        XCTAssertEqual(vm.budget.stage, .stopped)
        XCTAssertNil(vm.reply)
        await vm.sendNext()
        XCTAssertEqual(transport.bodies.count, 1)
    }

    func testInterruptedAttemptAndTwoIndependentModelsCannotRepeatPrompt() async {
        let transport = Transport()
        let first = await model(transport)
        let second = await model(transport)
        XCTAssertTrue(first.budget.begin(.whySquats)) // Simulate interruption after reservation.
        await second.sendNext()
        XCTAssertEqual(transport.bodies.count, 0)
        XCTAssertNil(CoachSyntheticQABudget(defaults: defaults).next)
    }

    func testReviewCannotResurrectABudgetStoppedByAnotherScreen() async {
        let transport = Transport()
        let first = await model(transport)
        await first.sendNext()
        CoachSyntheticQABudget(defaults: defaults).stop()
        first.reviewReturnedReply(passed: true)
        await first.sendNext()
        XCTAssertEqual(transport.bodies.count, 1)
        XCTAssertEqual(first.budget.stage, .stopped)
    }

    func testReviewedFirstTurnSurvivesRelaunchButSecondFailureEndsRun() async {
        let transport = Transport()
        let first = await model(transport)
        await first.sendNext()
        first.reviewReturnedReply(passed: true)
        first.close()
        let reopened = await model(transport)
        XCTAssertEqual(reopened.budget.next, .pistolForm)
        transport.failure = URLError(.timedOut)
        await reopened.sendNext()
        await (await model(transport)).sendNext()
        XCTAssertEqual(transport.bodies.count, 2)
        XCTAssertEqual(reopened.budget.stage, .stopped)
    }
}
