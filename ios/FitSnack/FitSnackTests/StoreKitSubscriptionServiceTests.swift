import XCTest
@testable import FitSnack

/// Tests the real StoreKit 2 subscription service (US-N04).
///
/// The service composes one seam - a `StoreKitFacade` (the App Store ceremony) - and owns the domain
/// mapping from raw store entitlements/products to `Subscription`/`SubscriptionPlan`. The facade is
/// stubbed here, so these tests cover the real composition end to end without a live store:
/// - the entitlement mapping (no entitlement is free; an active one is premium; the trial window sets
///   `trialEndsAt`; the latest-expiring entitlement wins);
/// - `premiumPlans()` maps and orders products, and throws when the store has none;
/// - a purchase unlocks premium (PRD validation), a cancel leaves the entitlement unchanged;
/// - a restore re-grants an owned entitlement (PRD validation) and is free when nothing is owned.
final class StoreKitSubscriptionServiceTests: XCTestCase {

    // MARK: - Stub

    private struct StubFacade: StoreKitFacade {
        var products: [StoreProduct] = []
        var loadError: SubscriptionError?
        var entitlements: [StoreEntitlement] = []
        var purchaseResult: StorePurchaseResult = .userCancelled
        var purchaseError: SubscriptionError?
        var syncError: SubscriptionError?

        func loadProducts(ids: [String]) async throws -> [StoreProduct] {
            if let loadError { throw loadError }
            return products
        }

        func currentEntitlements() async -> [StoreEntitlement] { entitlements }

        func purchase(productID: String) async throws -> StorePurchaseResult {
            if let purchaseError { throw purchaseError }
            return purchaseResult
        }

        func sync() async throws {
            if let syncError { throw syncError }
        }

        func listenForTransactions() -> Task<Void, Never> { Task {} }
    }

    private func service(_ facade: StubFacade) -> StoreKitSubscriptionService {
        StoreKitSubscriptionService(facade: facade)
    }

    private let monthlyProduct = StoreProduct(
        id: SubscriptionPlan.ProductID.monthly,
        displayPrice: "$7.99",
        period: .monthly,
        trialDescription: "14-day free trial"
    )
    private let yearlyProduct = StoreProduct(
        id: SubscriptionPlan.ProductID.yearly,
        displayPrice: "$59.99",
        period: .yearly,
        trialDescription: nil
    )

    private func premiumEntitlement(
        productID: String = SubscriptionPlan.ProductID.monthly,
        expiresAt: Date? = Date(timeIntervalSince1970: 2_000_000),
        isInTrialPeriod: Bool = false
    ) -> StoreEntitlement {
        StoreEntitlement(productID: productID, expiresAt: expiresAt, isInTrialPeriod: isInTrialPeriod)
    }

    // MARK: - Entitlement mapping

    func testNoEntitlementsIsFree() async throws {
        let subscription = try await service(StubFacade(entitlements: [])).currentSubscription()
        XCTAssertEqual(subscription, .free, "a user with no active entitlement is on the free tier")
    }

    func testActiveEntitlementIsPremium() async throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000)
        let subscription = try await service(
            StubFacade(entitlements: [premiumEntitlement(expiresAt: expiry)])
        ).currentSubscription()

        XCTAssertEqual(subscription.tier, .premium)
        XCTAssertEqual(subscription.provider, .apple)
        XCTAssertEqual(subscription.expiresAt, expiry, "the entitlement's expiry carries through")
        XCTAssertNil(subscription.trialEndsAt, "not in a trial, so no trial end")
    }

    func testTrialEntitlementSetsTrialEndsAt() async throws {
        let expiry = Date(timeIntervalSince1970: 1_500_000)
        let subscription = try await service(
            StubFacade(entitlements: [premiumEntitlement(expiresAt: expiry, isInTrialPeriod: true)])
        ).currentSubscription()

        XCTAssertEqual(subscription.tier, .premium)
        XCTAssertEqual(subscription.trialEndsAt, expiry, "in trial, the trial ends when the entitlement lapses")
    }

    func testLatestExpiringEntitlementWins() async throws {
        let early = premiumEntitlement(productID: SubscriptionPlan.ProductID.monthly, expiresAt: Date(timeIntervalSince1970: 1_000_000))
        let late = premiumEntitlement(productID: SubscriptionPlan.ProductID.yearly, expiresAt: Date(timeIntervalSince1970: 9_000_000))

        let subscription = try await service(StubFacade(entitlements: [early, late])).currentSubscription()

        XCTAssertEqual(subscription.expiresAt, late.expiresAt, "with several entitlements the latest expiry wins")
    }

    func testRefreshEntitlementsMatchesCurrent() async throws {
        let facade = StubFacade(entitlements: [premiumEntitlement()])
        let current = try await service(facade).currentSubscription()
        let refreshed = try await service(facade).refreshEntitlements()
        XCTAssertEqual(current, refreshed)
    }

    // MARK: - Plans

    func testPremiumPlansMapsAndOrders() async throws {
        // Deliberately yearly-first to prove the service sorts monthly ahead of yearly.
        let plans = try await service(StubFacade(products: [yearlyProduct, monthlyProduct])).premiumPlans()

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].period, .monthly, "monthly is ordered first")
        XCTAssertEqual(plans[0].displayPrice, "$7.99")
        XCTAssertEqual(plans[0].trialDescription, "14-day free trial")
        XCTAssertEqual(plans[0].priceLine, "$7.99 / month")
        XCTAssertEqual(plans[1].period, .yearly)
        XCTAssertNil(plans[1].trialDescription)
    }

    func testPremiumPlansThrowsWhenNoProducts() async throws {
        do {
            _ = try await service(StubFacade(products: [])).premiumPlans()
            XCTFail("no products should surface productsUnavailable")
        } catch {
            XCTAssertEqual(error as? SubscriptionError, .productsUnavailable)
        }
    }

    // MARK: - Purchase

    func testPurchaseSuccessUnlocksPremium() async throws {
        // PRD validation: purchasing premium unlocks the entitlement that drives the US-M02 gate.
        let facade = StubFacade(
            products: [monthlyProduct],
            entitlements: [],
            purchaseResult: .success([premiumEntitlement()])
        )
        let outcome = try await service(facade).purchase(SubscriptionPlan.samples[0])

        XCTAssertEqual(outcome, .resolved(Subscription(tier: .premium, provider: .apple, expiresAt: premiumEntitlement().expiresAt, trialEndsAt: nil)), "a completed purchase resolves to premium")
    }

    func testPurchaseCancelledKeepsFreeTier() async throws {
        let facade = StubFacade(entitlements: [], purchaseResult: .userCancelled)
        let outcome = try await service(facade).purchase(SubscriptionPlan.samples[0])

        XCTAssertEqual(outcome, .resolved(.free), "a user cancel is not an error and grants nothing")
    }

    func testPurchaseCancelledKeepsExistingPremium() async throws {
        // A cancel re-reads current entitlements, so an already-premium user stays premium.
        let facade = StubFacade(entitlements: [premiumEntitlement()], purchaseResult: .userCancelled)
        let outcome = try await service(facade).purchase(SubscriptionPlan.samples[0])

        guard case .resolved(let subscription) = outcome else { return XCTFail("a cancel resolves") }
        XCTAssertEqual(subscription.tier, .premium)
    }

    func testPurchasePendingReportsPending() async throws {
        // Ask to Buy / deferred approval: nothing is granted yet, and the outcome is distinctly pending
        // (not a silent cancel) so the paywall can reassure the user.
        let facade = StubFacade(entitlements: [], purchaseResult: .pending)
        let outcome = try await service(facade).purchase(SubscriptionPlan.samples[0])

        XCTAssertEqual(outcome, .pending, "a deferred purchase reports pending, not a resolved free tier")
    }

    func testPurchasePremiumBuysMonthly() async throws {
        let facade = StubFacade(
            products: [monthlyProduct, yearlyProduct],
            purchaseResult: .success([premiumEntitlement()])
        )
        let subscription = try await service(facade).purchasePremium()

        XCTAssertEqual(subscription.tier, .premium, "the convenience buys the monthly plan and unlocks premium")
    }

    func testPurchaseErrorPropagates() async throws {
        let facade = StubFacade(purchaseError: .failed("network"))
        do {
            _ = try await service(facade).purchase(SubscriptionPlan.samples[0])
            XCTFail("a purchase failure should propagate for the paywall to surface")
        } catch {
            XCTAssertEqual(error as? SubscriptionError, .failed("network"))
        }
    }

    // MARK: - Purchase-success entitlement merge (first-purchase timing quirk)

    func testMergedIncludesFreshEntitlementWhenCurrentReadIsEmpty() {
        // The device's cached currentEntitlements can lag a just-completed purchase, returning empty; the
        // verified transaction's entitlement must still be present so the buyer resolves to premium.
        let fresh = premiumEntitlement()
        let merged = LiveStoreKitFacade.merged([], with: fresh)

        XCTAssertEqual(merged, [fresh], "the just-purchased entitlement is trusted even when the read lags")
        XCTAssertEqual(StoreKitSubscriptionService.subscription(from: merged).tier, .premium)
    }

    func testMergedDeduplicatesKeepingLaterExpiry() {
        let stale = premiumEntitlement(expiresAt: Date(timeIntervalSince1970: 1_000_000))
        let renewed = premiumEntitlement(expiresAt: Date(timeIntervalSince1970: 9_000_000))
        let merged = LiveStoreKitFacade.merged([stale], with: renewed)

        XCTAssertEqual(merged, [renewed], "the same product is de-duplicated to its later-expiring entitlement")
    }

    func testMergedPreservesOtherEntitlements() {
        let owned = premiumEntitlement(productID: SubscriptionPlan.ProductID.yearly, expiresAt: Date(timeIntervalSince1970: 5_000_000))
        let fresh = premiumEntitlement(productID: SubscriptionPlan.ProductID.monthly)
        let merged = LiveStoreKitFacade.merged([owned], with: fresh)

        XCTAssertEqual(merged, [owned, fresh], "a distinct product is appended, existing entitlements preserved")
    }

    func testMergedNilFreshIsPassThrough() {
        let owned = premiumEntitlement()
        XCTAssertEqual(LiveStoreKitFacade.merged([owned], with: nil), [owned], "a non-granting transaction leaves the read untouched")
    }

    // MARK: - Restore

    func testRestoreRegrantsEntitlement() async throws {
        // PRD validation: restore re-grants a previously-owned entitlement.
        let facade = StubFacade(entitlements: [premiumEntitlement()])
        let subscription = try await service(facade).restorePurchases()

        XCTAssertEqual(subscription.tier, .premium, "restore re-grants the owned entitlement")
    }

    func testRestoreWithNoEntitlementIsFree() async throws {
        let subscription = try await service(StubFacade(entitlements: [])).restorePurchases()
        XCTAssertEqual(subscription, .free, "restore with nothing owned leaves the user free")
    }

    func testRestoreSyncErrorPropagates() async throws {
        let facade = StubFacade(syncError: .failed("sync failed"))
        do {
            _ = try await service(facade).restorePurchases()
            XCTFail("a sync failure should propagate")
        } catch {
            XCTAssertEqual(error as? SubscriptionError, .failed("sync failed"))
        }
    }
}
