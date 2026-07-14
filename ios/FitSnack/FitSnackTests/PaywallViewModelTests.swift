import XCTest
@testable import FitSnack

/// Tests the paywall view model (US-N04).
///
/// It loads the purchasable plans, drives a purchase or restore, and reflects the resulting
/// entitlement - all without gating anything. A configurable stub service exercises the success and
/// failure paths:
/// - `load()` populates plans, and surfaces a gentle message (not a wall) when none are available;
/// - a successful purchase/restore flips `didUnlockPremium`; a user-cancel or a nothing-owned restore
///   does not, and a failure surfaces a gentle message.
final class PaywallViewModelTests: XCTestCase {

    // MARK: - Stub

    private final class StubService: SubscriptionServiceProtocol {
        var plans: [SubscriptionPlan]
        var plansError: Error?
        var purchaseOutcome: Subscription
        var purchaseIsPending: Bool
        var purchaseError: Error?
        var restoreOutcome: Subscription
        var restoreError: Error?

        init(
            plans: [SubscriptionPlan] = SubscriptionPlan.samples,
            plansError: Error? = nil,
            purchaseOutcome: Subscription = .free,
            purchaseIsPending: Bool = false,
            purchaseError: Error? = nil,
            restoreOutcome: Subscription = .free,
            restoreError: Error? = nil
        ) {
            self.plans = plans
            self.plansError = plansError
            self.purchaseOutcome = purchaseOutcome
            self.purchaseIsPending = purchaseIsPending
            self.purchaseError = purchaseError
            self.restoreOutcome = restoreOutcome
            self.restoreError = restoreError
        }

        func currentSubscription() async throws -> Subscription { .free }
        func refreshEntitlements() async throws -> Subscription { .free }

        func premiumPlans() async throws -> [SubscriptionPlan] {
            if let plansError { throw plansError }
            return plans
        }

        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
            if let purchaseError { throw purchaseError }
            return purchaseIsPending ? .pending : .resolved(purchaseOutcome)
        }

        func purchasePremium() async throws -> Subscription {
            if let purchaseError { throw purchaseError }
            return purchaseOutcome
        }

        func restorePurchases() async throws -> Subscription {
            if let restoreError { throw restoreError }
            return restoreOutcome
        }
    }

    private let premium = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)

    // MARK: - Load

    func testLoadPopulatesPlans() async {
        let vm = PaywallViewModel(subscriptionService: StubService())
        await vm.load()

        XCTAssertEqual(vm.plans.count, 2)
        XCTAssertNil(vm.message, "a normal load surfaces no message")
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadWithNoPlansSurfacesGentleMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(plans: []))
        await vm.load()

        XCTAssertTrue(vm.plans.isEmpty)
        XCTAssertNotNil(vm.message, "no plans shows a gentle, non-blocking message")
    }

    func testLoadFailureSurfacesGentleMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(plansError: SubscriptionError.failed("offline")))
        await vm.load()

        XCTAssertTrue(vm.plans.isEmpty)
        XCTAssertNotNil(vm.message)
        XCTAssertFalse(vm.didUnlockPremium)
    }

    // MARK: - Purchase

    func testPurchaseSuccessUnlocksPremium() async {
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: premium))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertTrue(vm.didUnlockPremium, "a granted entitlement unlocks the gate")
        XCTAssertNil(vm.message)
        XCTAssertNil(vm.purchasingPlanID, "the in-flight marker clears when done")
    }

    func testPurchaseCancelDoesNotUnlock() async {
        // A cancel returns the unchanged (free) entitlement - not an error, no unlock, no message.
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: .free))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNil(vm.message, "a silent cancel does not nag the user")
    }

    func testPurchasePendingSurfacesWaitingMessageWithoutUnlocking() async {
        // Ask to Buy / deferred approval: the tap must not look silent (like a cancel), but it also
        // must not unlock - the entitlement lands out-of-band once approved.
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseIsPending: true))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium, "a pending purchase does not unlock premium yet")
        XCTAssertNotNil(vm.message, "a pending purchase surfaces a gentle waiting message, not silence")
        XCTAssertNil(vm.purchasingPlanID, "the in-flight marker clears when done")
    }

    func testPurchaseFailureSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseError: SubscriptionError.failed("declined")))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message, "a real failure surfaces a gentle message")
    }

    // MARK: - Restore

    func testRestoreSuccessUnlocksPremium() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreOutcome: premium))
        await vm.restore()

        XCTAssertTrue(vm.didUnlockPremium)
        XCTAssertNil(vm.message)
    }

    func testRestoreNothingOwnedSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreOutcome: .free))
        await vm.restore()

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message, "nothing to restore tells the user gently")
    }

    func testRestoreFailureSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreError: SubscriptionError.failed("offline")))
        await vm.restore()

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message)
    }
}
