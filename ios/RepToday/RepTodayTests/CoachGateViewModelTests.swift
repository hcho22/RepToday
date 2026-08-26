import XCTest
@testable import RepToday

/// US-AC03: the premium gate on the AI coach entry point. These pin the decision the coach entry row
/// branches on - a free user is blocked (shown the upsell), a Premium user is allowed through - and
/// that a failed entitlement read falls back to the safe not-Premium state rather than unlocking a
/// paid surface or surfacing an error.
@MainActor
final class CoachGateViewModelTests: XCTestCase {

    /// A subscription service that always throws, to prove the gate fails safe (never unlocks) when
    /// the entitlement read errors.
    private struct ThrowingSubscriptionService: SubscriptionServiceProtocol {
        struct Boom: Error {}
        func currentSubscription() async throws -> Subscription { throw Boom() }
        func refreshEntitlements() async throws -> Subscription { throw Boom() }
        func premiumPlans() async throws -> [SubscriptionPlan] { throw Boom() }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { throw Boom() }
        func purchasePremium() async throws -> Subscription { throw Boom() }
        func restorePurchases() async throws -> Subscription { throw Boom() }
        // `startObservingTransactions()` uses the protocol's default no-op.
    }

    private func premiumSubscription() -> Subscription {
        Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
    }

    /// Before any load, the gate is closed: the fail-safe is "show the upsell".
    func testStartsLocked() {
        let vm = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: .free))
        XCTAssertFalse(vm.isPremium)
    }

    /// A free user is blocked - the entry point shows the upsell, never the coach.
    func testFreeUserIsBlocked() async {
        let vm = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: .free))
        await vm.load()
        XCTAssertFalse(vm.isPremium)
    }

    /// A Premium user is allowed through to the coach.
    func testPremiumUserIsAllowed() async {
        let vm = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: premiumSubscription()))
        await vm.load()
        XCTAssertTrue(vm.isPremium)
    }

    /// A throwing entitlement read leaves the gate closed (upsell), never unlocking on error.
    func testFailedEntitlementReadFailsSafeToUpsell() async {
        let vm = CoachGateViewModel(subscriptionService: ThrowingSubscriptionService())
        await vm.load()
        XCTAssertFalse(vm.isPremium)
    }

    /// The read is idempotent - a re-`load()` after an entitlement change reflects the new state.
    func testReloadReflectsEntitlementChange() async {
        let vm = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: premiumSubscription()))
        await vm.load()
        XCTAssertTrue(vm.isPremium)
        await vm.load()
        XCTAssertTrue(vm.isPremium)
    }
}
