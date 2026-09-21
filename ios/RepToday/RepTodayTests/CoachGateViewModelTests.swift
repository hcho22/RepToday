import XCTest
@testable import RepToday

/// US-AC03: the premium gate on the AI coach entry point. These pin the decision the coach entry row
/// branches on - a free user is blocked (shown the upsell), a Premium user is allowed through - and
/// that a failed entitlement read falls back to the safe not-Premium state rather than unlocking a
/// paid surface or surfacing an error.
@MainActor
final class CoachGateViewModelTests: XCTestCase {

    private final class MutableSubscriptionService: SubscriptionServiceProtocol {
        var subscription: Subscription

        init(subscription: Subscription) {
            self.subscription = subscription
        }

        func currentSubscription() async throws -> Subscription { subscription }
        func refreshEntitlements() async throws -> Subscription { subscription }
        func premiumPlans() async throws -> [SubscriptionPlan] { SubscriptionPlan.samples }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { .resolved(subscription) }
        func purchasePremium() async throws -> Subscription { subscription }
        func restorePurchases() async throws -> Subscription { subscription }
    }

    private actor SuspendedSubscriptionService: SubscriptionServiceProtocol {
        private var nextRequestID = 0
        private var reads: [Int: CheckedContinuation<Subscription, Error>] = [:]
        private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        func currentSubscription() async throws -> Subscription {
            let requestID = nextRequestID
            nextRequestID += 1
            return try await withCheckedThrowingContinuation { continuation in
                reads[requestID] = continuation
                resumeRequestWaiters()
            }
        }

        func waitForRequestCount(_ count: Int) async {
            guard reads.count < count else { return }
            await withCheckedContinuation { continuation in
                requestWaiters.append((count, continuation))
            }
        }

        func resolveRequest(_ requestID: Int, with subscription: Subscription) {
            reads.removeValue(forKey: requestID)?.resume(returning: subscription)
        }

        private func resumeRequestWaiters() {
            var pending: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
            for waiter in requestWaiters {
                if reads.count >= waiter.count {
                    waiter.continuation.resume()
                } else {
                    pending.append(waiter)
                }
            }
            requestWaiters = pending
        }

        func refreshEntitlements() async throws -> Subscription { .free }
        func premiumPlans() async throws -> [SubscriptionPlan] { SubscriptionPlan.samples }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { .resolved(.free) }
        func purchasePremium() async throws -> Subscription { .free }
        func restorePurchases() async throws -> Subscription { .free }
    }

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

    /// A verified purchase/restore grant remains authoritative for the gate's lifetime, including
    /// repeated appearances whose cached entitlement reads are empty or fail.
    func testAuthoritativeGrantSurvivesTabReentryWithEmptyOrFailedReads() async {
        let vm = CoachGateViewModel(subscriptionService: ThrowingSubscriptionService())
        let grant = premiumSubscription()
        vm.acceptAuthoritativeGrant(grant)

        await vm.reconcileAfterAuthoritativeGrant()
        XCTAssertTrue(vm.isPremium)

        await vm.load()
        await vm.load()
        XCTAssertTrue(vm.isPremium)
        XCTAssertEqual(vm.subscription, grant)
    }

    /// Ordinary reads remain authoritative for out-of-band StoreKit changes: renewal/approval unlocks,
    /// and a later expiry/refund locks the gate again.
    func testReloadReflectsEntitlementChange() async {
        let service = MutableSubscriptionService(subscription: .free)
        let vm = CoachGateViewModel(subscriptionService: service)
        await vm.load()
        XCTAssertFalse(vm.isPremium)

        service.subscription = premiumSubscription()
        await vm.load()
        XCTAssertTrue(vm.isPremium)

        service.subscription = .free
        await vm.load()
        XCTAssertFalse(vm.isPremium)
    }

    /// A just-returned verified purchase/restore result wins over every lagging cache projection in
    /// this gate session, including the ordinary reads triggered by tab re-entry.
    func testAuthoritativeGrantSurvivesLaggingReconciliationAndTabReentry() async {
        let service = MutableSubscriptionService(subscription: .free)
        let vm = CoachGateViewModel(subscriptionService: service)

        vm.acceptAuthoritativeGrant(premiumSubscription())
        await vm.reconcileAfterAuthoritativeGrant()
        await vm.load()
        await vm.load()
        XCTAssertTrue(vm.isPremium)
        XCTAssertEqual(vm.subscription, premiumSubscription())
    }

    func testSessionGrantSurvivesGateReconstructionButFreshSessionStartsFromEntitlements() async {
        let service = MutableSubscriptionService(subscription: .free)
        let sessionAuthority = PremiumSessionAuthority()
        let grantedGate = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: sessionAuthority
        )
        grantedGate.acceptAuthoritativeGrant(premiumSubscription())
        await grantedGate.load()
        XCTAssertTrue(grantedGate.isPremium)

        let reconstructedGate = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: sessionAuthority
        )
        await reconstructedGate.load()
        XCTAssertTrue(reconstructedGate.isPremium)
        XCTAssertEqual(reconstructedGate.subscription, premiumSubscription())

        let freshGate = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: PremiumSessionAuthority()
        )
        await freshGate.load()
        XCTAssertFalse(freshGate.isPremium)
    }

    func testExplicitStoreKitRevocationClearsSessionGrant() async {
        let service = MutableSubscriptionService(subscription: premiumSubscription())
        let sessionAuthority = PremiumSessionAuthority()
        let vm = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: sessionAuthority
        )
        vm.acceptAuthoritativeGrant(premiumSubscription())

        sessionAuthority.acceptStoreKitUpdate(.free)
        await vm.load()

        XCTAssertFalse(vm.isPremium)
        XCTAssertEqual(vm.subscription, .free)
    }

    /// All asynchronous reads share one generation: a reconciliation that started first cannot
    /// overwrite a later tab-entry load, even when the older result finishes last.
    func testOlderReconciliationCannotOverwriteNewerAuthoritativeLoad() async {
        let service = SuspendedSubscriptionService()
        let sessionAuthority = PremiumSessionAuthority()
        let firstGate = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: sessionAuthority
        )
        let reconstructedGate = CoachGateViewModel(
            subscriptionService: service,
            premiumSessionAuthority: sessionAuthority
        )
        let originalGrant = Subscription(
            tier: .premium,
            provider: .apple,
            expiresAt: Date(timeIntervalSince1970: 1_000),
            trialEndsAt: nil
        )
        let staleReconciliation = Subscription(
            tier: .premium,
            provider: .apple,
            expiresAt: Date(timeIntervalSince1970: 2_000),
            trialEndsAt: nil
        )
        firstGate.acceptAuthoritativeGrant(originalGrant)

        let reconciliation = Task { await firstGate.reconcileAfterAuthoritativeGrant() }
        await service.waitForRequestCount(1)
        let newerLoad = Task { await reconstructedGate.load() }
        await service.waitForRequestCount(2)

        await service.resolveRequest(1, with: .free)
        await newerLoad.value
        await service.resolveRequest(0, with: staleReconciliation)
        await reconciliation.value

        XCTAssertEqual(firstGate.subscription, originalGrant)
        XCTAssertEqual(reconstructedGate.subscription, originalGrant)
        XCTAssertTrue(firstGate.isPremium)
        XCTAssertTrue(reconstructedGate.isPremium)
    }
}
