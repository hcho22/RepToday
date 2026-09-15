import XCTest
@testable import RepToday

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
/// - the listener emits one durable-deduplicated `subscribe` for a verified trial -> first paid
///   renewal and rejects every adjacent StoreKit state that is not that transition.
final class StoreKitSubscriptionServiceTests: XCTestCase {

    private var observerDefaults: UserDefaults!
    private var observerDefaultsSuite: String!

    override func setUp() {
        super.setUp()
        observerDefaultsSuite = "StoreKitSubscriptionServiceTests.\(UUID().uuidString)"
        observerDefaults = UserDefaults(suiteName: observerDefaultsSuite)
        observerDefaults.removePersistentDomain(forName: observerDefaultsSuite)
    }

    override func tearDown() {
        observerDefaults.removePersistentDomain(forName: observerDefaultsSuite)
        observerDefaults = nil
        observerDefaultsSuite = nil
        super.tearDown()
    }

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

        func transactionHistory() async -> [StoreSubscriptionTransaction] { [] }

        func listenForTransactions(
            onUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> Void
        ) -> Task<Void, Never> { Task {} }
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

    private struct ObservingFacade: StoreKitFacade {
        var entitlements: [StoreEntitlement] = []
        var history: [StoreSubscriptionTransaction] = []
        var updates: [StoreTransactionUpdate] = []
        var purchaseResult: StorePurchaseResult = .userCancelled

        func loadProducts(ids: [String]) async throws -> [StoreProduct] { [] }
        func currentEntitlements() async -> [StoreEntitlement] { entitlements }
        func purchase(productID: String) async throws -> StorePurchaseResult { purchaseResult }
        func sync() async throws {}
        func transactionHistory() async -> [StoreSubscriptionTransaction] { history }

        func listenForTransactions(
            onUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> Void
        ) -> Task<Void, Never> {
            let updates = updates
            return Task {
                for update in updates {
                    guard !Task.isCancelled else { return }
                    await onUpdate(update)
                }
            }
        }
    }

    private func storeTransaction(
        id: UInt64,
        originalID: UInt64,
        productID: String = SubscriptionPlan.ProductID.monthly,
        day: TimeInterval,
        reason: StoreSubscriptionTransaction.Reason,
        payment: StoreSubscriptionTransaction.Payment,
        isAutoRenewable: Bool = true,
        isPurchased: Bool = true,
        isRevoked: Bool = false,
        isUpgraded: Bool = false
    ) -> StoreSubscriptionTransaction {
        StoreSubscriptionTransaction(
            id: id,
            originalID: originalID,
            productID: productID,
            purchaseDate: Date(timeIntervalSince1970: day * 86_400),
            reason: reason,
            payment: payment,
            isAutoRenewable: isAutoRenewable,
            isPurchased: isPurchased,
            isRevoked: isRevoked,
            isUpgraded: isUpgraded
        )
    }

    private func observedEvents(
        facade: ObservingFacade,
        analytics: MockAnalyticsService = MockAnalyticsService(),
        defaults: UserDefaults? = nil
    ) async -> [AnalyticsEvent] {
        let service = StoreKitSubscriptionService(
            facade: facade,
            analytics: analytics,
            userDefaults: defaults ?? observerDefaults
        )
        let task = service.startObservingTransactions()
        await task.value
        return await analytics.recordedEvents
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

    // MARK: - Trial-to-paid conversion telemetry

    func testDirectPaidPurchaseUpdateDoesNotEmitSubscribeFromObserver() async {
        let purchase = storeTransaction(
            id: 100, originalID: 100, day: 1, reason: .purchase, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(history: [purchase], updates: [.verified(purchase)])
        )

        XCTAssertTrue(events.isEmpty, "the paywall owns direct-purchase subscribe; the observer never duplicates it")
    }

    func testInitialTrialUpdateDoesNotEmitAnotherMonetizationEvent() async {
        let trial = storeTransaction(
            id: 200, originalID: 200, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )

        let events = await observedEvents(
            facade: ObservingFacade(history: [trial], updates: [.verified(trial)])
        )

        XCTAssertTrue(events.isEmpty, "the paywall emits trial_started once; the observer emits neither event at trial start")
    }

    func testFirstPaidRenewalAfterFreeTrialEmitsSubscribeWithCanonicalPlan() async {
        let trial = storeTransaction(
            id: 300, originalID: 300, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 301, originalID: 300, day: 15,
            reason: .renewal, payment: .paid
        )

        // History deliberately stops before the live update. The classifier includes that verified
        // update itself, matching StoreKit's point-in-time history contract without a timing guess.
        let events = await observedEvents(
            facade: ObservingFacade(history: [trial], updates: [.verified(conversion)])
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, .subscribe)
        XCTAssertEqual(events.first?.properties, ["plan": .string(SubscriptionPlan.ProductID.monthly)])
        XCTAssertEqual(events.first?.timestampMs, Int(conversion.purchaseDate.timeIntervalSince1970 * 1_000))
        XCTAssertTrue(events.allSatisfy { $0.name != .trialStarted }, "conversion never repeats trial_started")
    }

    func testRepeatedConversionUpdateEmitsExactlyOnce() async {
        let trial = storeTransaction(
            id: 400, originalID: 400, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 401, originalID: 400, day: 15,
            reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, conversion],
                updates: [.verified(conversion), .verified(conversion)]
            )
        )

        XCTAssertEqual(events.filter { $0.name == .subscribe }.count, 1)
    }

    func testPaidRenewalAfterAnAlreadyPaidPeriodDoesNotEmit() async {
        let trial = storeTransaction(
            id: 500, originalID: 500, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 501, originalID: 500, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterRenewal = storeTransaction(
            id: 502, originalID: 500, day: 45,
            reason: .renewal, payment: .paid
        )

        var events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, firstPaidRenewal, laterRenewal],
                updates: [.verified(laterRenewal)]
            )
        )
        XCTAssertTrue(events.isEmpty, "only the first paid renewal after the trial is a conversion")

        let directPurchase = storeTransaction(
            id: 510, originalID: 510, day: 1, reason: .purchase, payment: .paid
        )
        let ordinaryRenewal = storeTransaction(
            id: 511, originalID: 510, day: 31, reason: .renewal, payment: .paid
        )
        events = await observedEvents(
            facade: ObservingFacade(
                history: [directPurchase, ordinaryRenewal],
                updates: [.verified(ordinaryRenewal)]
            )
        )
        XCTAssertTrue(events.isEmpty, "a direct-paid chain has no trial conversion to infer")

        let refundedFirstPaidRenewal = storeTransaction(
            id: 521, originalID: 500, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let postRefundRenewal = storeTransaction(
            id: 522, originalID: 500, day: 45,
            reason: .renewal, payment: .paid
        )
        events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, refundedFirstPaidRenewal, postRefundRenewal],
                updates: [.verified(postRefundRenewal)]
            )
        )
        XCTAssertTrue(events.isEmpty,
                      "a revoked first charge still proves that a later renewal is not the conversion boundary")
    }

    func testCurrentEntitlementAndRestoreReadsNeverEmitConversion() async throws {
        let trial = storeTransaction(
            id: 600, originalID: 600, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 601, originalID: 600, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let facade = ObservingFacade(
            entitlements: [premiumEntitlement()],
            history: [trial, conversion],
            updates: []
        )
        let service = StoreKitSubscriptionService(
            facade: facade,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        _ = try await service.currentSubscription()
        _ = try await service.refreshEntitlements()
        _ = try await service.restorePurchases()

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty,
                      "foreground/current-entitlement/restore reads are not conversion emission sites")
        XCTAssertEqual(observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey), ["601"],
                       "restore baselines an historical conversion so a later redelivery stays inert")
    }

    func testConversionUpdateDeliveredDuringRestoreIsBaselinedWithoutEmission() async {
        let trial = storeTransaction(
            id: 610, originalID: 610, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 611, originalID: 610, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(conversion), history: [trial, conversion])
        await observer.completeRestore(history: [trial, conversion])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty, "a restore-delivered historical transaction is not a new conversion")
        XCTAssertEqual(observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey), ["611"])
    }

    func testReverseOrderedRestoreRetainsTheNewestConversionForRedeliveryDeduplication() async {
        var history: [StoreSubscriptionTransaction] = []
        var conversions: [StoreSubscriptionTransaction] = []
        for offset in 0...TrialConversionObserver.retentionLimit {
            let originalID = UInt64(620 + offset * 2)
            let trial = storeTransaction(
                id: originalID, originalID: originalID, day: TimeInterval(offset * 20 + 1),
                reason: .purchase, payment: .introductoryFreeTrial
            )
            let conversion = storeTransaction(
                id: originalID + 1, originalID: originalID, day: TimeInterval(offset * 20 + 15),
                reason: .renewal, payment: .paid
            )
            history.append(contentsOf: [trial, conversion])
            conversions.append(conversion)
        }

        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let reverseOrderedHistory = Array(history.reversed())

        await observer.beginRestore()
        await observer.completeRestore(history: reverseOrderedHistory)

        let storedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        let oldestConversion = conversions[0]
        let newestConversion = conversions[TrialConversionObserver.retentionLimit]
        XCTAssertEqual(storedIDs?.count, TrialConversionObserver.retentionLimit)
        XCTAssertFalse(storedIDs?.contains(String(oldestConversion.id)) == true)
        XCTAssertTrue(storedIDs?.contains(String(newestConversion.id)) == true)

        await observer.observe(.verified(newestConversion), history: reverseOrderedHistory)

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty, "the latest restored conversion remains baselined when redelivered")
    }

    func testUnverifiedAndRevokedUpdatesDoNotEmit() async {
        let trial = storeTransaction(
            id: 700, originalID: 700, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let revokedConversion = storeTransaction(
            id: 701, originalID: 700, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, revokedConversion],
                updates: [.unverified, .verified(revokedConversion)]
            )
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testPendingPurchaseDoesNotEmitFromConversionObserver() async throws {
        let analytics = MockAnalyticsService()
        let service = StoreKitSubscriptionService(
            facade: ObservingFacade(purchaseResult: .pending),
            analytics: analytics,
            userDefaults: observerDefaults
        )

        let outcome = try await service.purchase(SubscriptionPlan.samples[0])
        let events = await analytics.recordedEvents
        XCTAssertEqual(outcome, .pending)
        XCTAssertTrue(events.isEmpty)
    }

    func testRelaunchSuppressesRedeliveryOfTheSameConversion() async {
        let trial = storeTransaction(
            id: 800, originalID: 800, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 801, originalID: 800, day: 15,
            reason: .renewal, payment: .paid
        )
        let facade = ObservingFacade(
            history: [trial, conversion],
            updates: [.verified(conversion)]
        )

        let firstAnalytics = MockAnalyticsService()
        let firstEvents = await observedEvents(
            facade: facade, analytics: firstAnalytics, defaults: observerDefaults
        )
        XCTAssertEqual(firstEvents.filter { $0.name == .subscribe }.count, 1)

        // A new service/observer over the same defaults is the app-relaunch boundary.
        let relaunchedAnalytics = MockAnalyticsService()
        let relaunchedEvents = await observedEvents(
            facade: facade, analytics: relaunchedAnalytics, defaults: observerDefaults
        )
        XCTAssertTrue(relaunchedEvents.isEmpty, "the durable conversion guard survives relaunch")
    }

    func testConversionDedupRetainsOnlyTheNewestBoundedTransactionIDs() async {
        var history: [StoreSubscriptionTransaction] = []
        var updates: [StoreTransactionUpdate] = []
        for offset in 0...TrialConversionObserver.retentionLimit {
            let originalID = UInt64(900 + offset * 2)
            let trial = storeTransaction(
                id: originalID, originalID: originalID, day: TimeInterval(offset * 20 + 1),
                reason: .purchase, payment: .introductoryFreeTrial
            )
            let conversion = storeTransaction(
                id: originalID + 1, originalID: originalID, day: TimeInterval(offset * 20 + 15),
                reason: .renewal, payment: .paid
            )
            history.append(contentsOf: [trial, conversion])
            updates.append(.verified(conversion))
        }

        let events = await observedEvents(facade: ObservingFacade(history: history, updates: updates))

        XCTAssertEqual(events.count, TrialConversionObserver.retentionLimit + 1,
                       "distinct qualifying conversion chains remain independently countable")
        let storedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        XCTAssertEqual(storedIDs?.count, TrialConversionObserver.retentionLimit)
        XCTAssertFalse(storedIDs?.contains("901") == true, "the oldest id is replaced at the bound")
        XCTAssertEqual(storedIDs?.last, String(900 + TrialConversionObserver.retentionLimit * 2 + 1))
    }
}
