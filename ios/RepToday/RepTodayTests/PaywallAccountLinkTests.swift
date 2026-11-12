import XCTest
@testable import RepToday

/// The paywall ties purchases to the signed-in account (M4, US-CA02): every purchase carries the
/// account's App Store token, and a granted purchase - or Restore Purchases - sends its signed
/// transaction to the server, so the Coach's server-side entitlement follows the subscription.
@MainActor
final class PaywallAccountLinkTests: XCTestCase {

    private final class SpySubscriptionService: SubscriptionServiceProtocol, @unchecked Sendable {
        var subscription: Subscription = .free
        private(set) var purchaseTokens: [UUID?] = []
        private(set) var restores = 0

        func currentSubscription() async throws -> Subscription { subscription }
        func refreshEntitlements() async throws -> Subscription { subscription }
        func premiumPlans() async throws -> [SubscriptionPlan] { SubscriptionPlan.samples }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { try await purchase(plan, appAccountToken: nil) }
        func purchase(_ plan: SubscriptionPlan, appAccountToken: UUID?) async throws -> PurchaseOutcome {
            purchaseTokens.append(appAccountToken)
            subscription = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
            return .resolved(SubscriptionGrant(subscription: subscription))
        }
        func purchasePremium() async throws -> Subscription { subscription }
        func restorePurchases() async throws -> Subscription {
            restores += 1
            subscription = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
            return subscription
        }
        func premiumTransactionJWS() async -> [String] {
            subscription.tier == .premium ? ["signed.premium.transaction"] : []
        }
    }

    func testAPurchaseCarriesTheAccountsTokenAndIsLinked() async throws {
        let subscriptions = SpySubscriptionService()
        let entitlements = MockPremiumEntitlementService()
        let token = try await entitlements.appAccountToken()
        let paywall = PaywallViewModel(subscriptionService: subscriptions, entryPoint: .coachUpsell, entitlements: entitlements)

        await paywall.purchase(try XCTUnwrap(SubscriptionPlan.samples.first))

        XCTAssertEqual(subscriptions.purchaseTokens, [token], "Apple names the account in this subscription's notifications")
        let linked = await entitlements.linked
        XCTAssertEqual(linked, ["signed.premium.transaction"])
        let status = try await entitlements.status()
        XCTAssertTrue(status.premium)
        XCTAssertTrue(paywall.didUnlockPremium)
    }

    func testRestorePurchasesLinksAnExistingSubscription() async throws {
        let subscriptions = SpySubscriptionService()
        let entitlements = MockPremiumEntitlementService()
        let paywall = PaywallViewModel(subscriptionService: subscriptions, entryPoint: .coachUpsell, entitlements: entitlements)

        await paywall.restore()

        XCTAssertEqual(subscriptions.restores, 1)
        let linked = await entitlements.linked
        XCTAssertEqual(linked, ["signed.premium.transaction"])
    }

    func testALinkFailureNeverBlocksTheOnDeviceUnlock() async throws {
        let subscriptions = SpySubscriptionService()
        let entitlements = MockPremiumEntitlementService()
        await entitlements.setLinkOutcome(nil, error: .offline)
        let paywall = PaywallViewModel(subscriptionService: subscriptions, entryPoint: .progressUpsell, entitlements: entitlements)

        await paywall.purchase(try XCTUnwrap(SubscriptionPlan.samples.first))

        XCTAssertTrue(paywall.didUnlockPremium, "StoreKit still unlocks the on-device Premium surfaces")
        XCTAssertNil(paywall.message)
    }

    func testWithoutAnAccountBackendThePurchaseGoesAheadWithoutAToken() async throws {
        let subscriptions = SpySubscriptionService()
        let paywall = PaywallViewModel(subscriptionService: subscriptions)
        await paywall.purchase(try XCTUnwrap(SubscriptionPlan.samples.first))
        XCTAssertEqual(subscriptions.purchaseTokens, [nil])
        XCTAssertTrue(paywall.didUnlockPremium)
    }
}
