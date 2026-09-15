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

        func transactionHistory() async -> StoreTransactionHistory { .verified([]) }

        func listenForTransactions(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
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
        var historyContainsUnverifiedTransactions = false
        var updates: [StoreTransactionUpdate] = []
        var purchaseResult: StorePurchaseResult = .userCancelled

        func loadProducts(ids: [String]) async throws -> [StoreProduct] { [] }
        func currentEntitlements() async -> [StoreEntitlement] { entitlements }
        func purchase(productID: String) async throws -> StorePurchaseResult { purchaseResult }
        func sync() async throws {}
        func transactionHistory() async -> StoreTransactionHistory {
            StoreTransactionHistory(
                transactions: history,
                containsUnverifiedTransactions: historyContainsUnverifiedTransactions
            )
        }

        func listenForTransactions(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
        ) -> Task<Void, Never> {
            let updates = updates
            return Task {
                for update in updates {
                    guard !Task.isCancelled else { return }
                    if let process = await prepareUpdate(update) {
                        await process()
                    }
                }
            }
        }
    }

    private actor FirstHistoryReadGate {
        private let history: [StoreSubscriptionTransaction]
        private var readCount = 0
        private var firstReadStarted = false
        private var firstReadContinuation: CheckedContinuation<[StoreSubscriptionTransaction], Never>?
        private var startWaiters: [CheckedContinuation<Void, Never>] = []

        init(history: [StoreSubscriptionTransaction]) {
            self.history = history
        }

        func read() async -> [StoreSubscriptionTransaction] {
            readCount += 1
            guard readCount == 1 else { return history }

            firstReadStarted = true
            let waiters = startWaiters
            startWaiters = []
            waiters.forEach { $0.resume() }
            return await withCheckedContinuation { firstReadContinuation = $0 }
        }

        func waitUntilFirstReadStarts() async {
            guard !firstReadStarted else { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func releaseFirstRead() {
            firstReadContinuation?.resume(returning: history)
            firstReadContinuation = nil
        }
    }

    private struct RestoreRaceFacade: StoreKitFacade {
        let historyGate: FirstHistoryReadGate
        let update: StoreSubscriptionTransaction

        func loadProducts(ids: [String]) async throws -> [StoreProduct] { [] }
        func currentEntitlements() async -> [StoreEntitlement] { [] }
        func purchase(productID: String) async throws -> StorePurchaseResult { .userCancelled }
        func sync() async throws {}
        func transactionHistory() async -> StoreTransactionHistory {
            .verified(await historyGate.read())
        }

        func listenForTransactions(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
        ) -> Task<Void, Never> {
            let update = update
            return Task {
                if let process = await prepareUpdate(.verified(update)) {
                    await process()
                }
            }
        }
    }

    private actor TransactionListenerProbe {
        enum Event: Equatable, Hashable {
            case acknowledgementStarted(UInt64)
            case acknowledged(UInt64)
            case prepared(UInt64)
            case processingStarted(UInt64)
            case processingFinished(UInt64)
            case listenerFinished
        }

        private var events: [Event] = []
        private var waiters: [Event: [CheckedContinuation<Void, Never>]] = [:]

        func record(_ event: Event) {
            events.append(event)
            let continuations = waiters.removeValue(forKey: event) ?? []
            continuations.forEach { $0.resume() }
        }

        func waitUntilRecorded(_ event: Event) async {
            guard !events.contains(event) else { return }
            await withCheckedContinuation { waiters[event, default: []].append($0) }
        }

        func recordedEvents() -> [Event] { events }
    }

    private actor ProcessingGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let continuations = waiters
            waiters = []
            continuations.forEach { $0.resume() }
        }
    }

    private actor OverlappingRestoreState {
        private let history: [StoreSubscriptionTransaction]
        private let update: StoreSubscriptionTransaction
        private var prepareUpdate: (@Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?)?
        private var syncCallCount = 0
        private var startedWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
        private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
        private var releasedCalls = Set<Int>()
        private var updateDelivered = false
        private var updateWaiters: [CheckedContinuation<Void, Never>] = []

        init(history: [StoreSubscriptionTransaction], update: StoreSubscriptionTransaction) {
            self.history = history
            self.update = update
        }

        func install(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
        ) {
            self.prepareUpdate = prepareUpdate
        }

        func sync() async throws {
            syncCallCount += 1
            let call = syncCallCount
            let waiters = startedWaiters.removeValue(forKey: call) ?? []
            waiters.forEach { $0.resume() }

            if call == 2, let prepareUpdate,
               let process = await prepareUpdate(.verified(update)) {
                await process()
                updateDelivered = true
                let updateWaiters = self.updateWaiters
                self.updateWaiters = []
                updateWaiters.forEach { $0.resume() }
            }

            if releasedCalls.remove(call) == nil {
                await withCheckedContinuation { releaseContinuations[call] = $0 }
            }
            if call == 1 {
                throw SubscriptionError.failed("first restore failed")
            }
        }

        func transactionHistory() -> StoreTransactionHistory { .verified(history) }

        func waitUntilSyncStarts(_ call: Int) async {
            guard syncCallCount < call else { return }
            await withCheckedContinuation { startedWaiters[call, default: []].append($0) }
        }

        func releaseSync(_ call: Int) {
            guard let continuation = releaseContinuations.removeValue(forKey: call) else {
                releasedCalls.insert(call)
                return
            }
            continuation.resume()
        }

        func startedSyncCount() -> Int { syncCallCount }

        func waitUntilUpdateDelivered() async {
            guard !updateDelivered else { return }
            await withCheckedContinuation { updateWaiters.append($0) }
        }
    }

    private struct OverlappingRestoreFacade: StoreKitFacade {
        let state: OverlappingRestoreState

        func loadProducts(ids: [String]) async throws -> [StoreProduct] { [] }
        func currentEntitlements() async -> [StoreEntitlement] { [] }
        func purchase(productID: String) async throws -> StorePurchaseResult { .userCancelled }
        func sync() async throws { try await state.sync() }
        func transactionHistory() async -> StoreTransactionHistory {
            await state.transactionHistory()
        }

        func listenForTransactions(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
        ) -> Task<Void, Never> {
            Task { await state.install(prepareUpdate: prepareUpdate) }
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

    func testDelayedFirstPaidRenewalStillEmitsAfterTheSubscriptionWasUpgraded() async {
        let trial = storeTransaction(
            id: 320, originalID: 320, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 321, originalID: 320, day: 15,
            reason: .renewal, payment: .paid, isUpgraded: true
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, conversion],
                updates: [.verified(conversion)]
            )
        )

        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(events.first?.properties, ["plan": .string(SubscriptionPlan.ProductID.monthly)])
    }

    func testLaterPaidRenewalDoesNotEmitWhenAnEarlierRenewalHasUnknownPayment() async {
        let trial = storeTransaction(
            id: 330, originalID: 330, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let unknownFirstRenewal = storeTransaction(
            id: 331, originalID: 330, day: 15,
            reason: .renewal, payment: .unknown
        )
        let laterPaidRenewal = storeTransaction(
            id: 332, originalID: 330, day: 45,
            reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, unknownFirstRenewal, laterPaidRenewal],
                updates: [.verified(laterPaidRenewal)]
            )
        )

        XCTAssertTrue(events.isEmpty, "unknown payment leaves the first paid boundary unprovable")
    }

    func testLaterPaidRenewalDoesNotEmitWhenAnEarlierOtherTransactionHasUnknownPayment() async {
        let trial = storeTransaction(
            id: 339, originalID: 339, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let unknownTransaction = storeTransaction(
            id: 340, originalID: 339, day: 15,
            reason: .other, payment: .unknown
        )
        let laterPaidRenewal = storeTransaction(
            id: 341, originalID: 339, day: 45,
            reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, unknownTransaction, laterPaidRenewal],
                updates: [.verified(laterPaidRenewal)]
            )
        )

        XCTAssertTrue(events.isEmpty, "unknown payment leaves the first paid boundary unprovable")
    }

    func testLaterPaidRenewalDoesNotEmitWhenHistoryContainsAnUnverifiedTransaction() async {
        let trial = storeTransaction(
            id: 333, originalID: 333, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let laterPaidRenewal = storeTransaction(
            id: 335, originalID: 333, day: 45,
            reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, laterPaidRenewal],
                historyContainsUnverifiedTransactions: true,
                updates: [.verified(laterPaidRenewal)]
            )
        )

        XCTAssertTrue(events.isEmpty, "partial verified history cannot prove the first paid boundary")
    }

    func testFirstPaidRenewalAfterAFreePromotionalPeriodEmitsSubscribe() async {
        let trial = storeTransaction(
            id: 336, originalID: 336, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let freePromotionalRenewal = storeTransaction(
            id: 337, originalID: 336, day: 15,
            reason: .renewal, payment: .nonPaid
        )
        let firstPaidRenewal = storeTransaction(
            id: 338, originalID: 336, day: 45,
            reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, freePromotionalRenewal, firstPaidRenewal],
                updates: [.verified(firstPaidRenewal)]
            )
        )

        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(events.first?.properties, ["plan": .string(SubscriptionPlan.ProductID.monthly)])
    }

    func testCurrentRevokedHistoryOverridesAnEarlierCapturedUpdate() async {
        let trial = storeTransaction(
            id: 360, originalID: 360, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let capturedConversion = storeTransaction(
            id: 361, originalID: 360, day: 15,
            reason: .renewal, payment: .paid
        )
        let refundedConversion = storeTransaction(
            id: 361, originalID: 360, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, refundedConversion],
                updates: [.verified(capturedConversion)]
            )
        )

        XCTAssertTrue(events.isEmpty, "current signed revocation remains authoritative")
    }

    func testListenerAcknowledgesNextUpdateWhilePriorConversionProcessingIsSuspended() async {
        let first = storeTransaction(
            id: 340, originalID: 340, day: 1,
            reason: .renewal, payment: .paid
        )
        let second = storeTransaction(
            id: 341, originalID: 341, day: 2,
            reason: .renewal, payment: .paid
        )
        let projectedUpdates: [UInt64: StoreTransactionUpdate] = [
            first.id: .verified(first),
            second.id: .verified(second)
        ]
        let (updates, continuation) = AsyncStream<UInt64>.makeStream()
        let probe = TransactionListenerProbe()
        let gate = ProcessingGate()

        let listener = Task {
            await LiveStoreKitFacade.processUpdates(
                updates,
                project: { id in
                    projectedUpdates[id] ?? .unverified
                },
                acknowledge: { id in
                    await probe.record(.acknowledged(id))
                },
                prepareUpdate: { update in
                    guard case .verified(let transaction) = update else { return nil }
                    let id = transaction.id
                    await probe.record(.prepared(id))
                    return StoreTransactionProcessing {
                        await probe.record(.processingStarted(id))
                        if id == first.id {
                            await gate.wait()
                        }
                        await probe.record(.processingFinished(id))
                    }
                }
            )
            await probe.record(.listenerFinished)
        }

        continuation.yield(first.id)
        await probe.waitUntilRecorded(.processingStarted(first.id))
        continuation.yield(second.id)
        continuation.finish()
        await probe.waitUntilRecorded(.acknowledged(second.id))

        var events = await probe.recordedEvents()
        XCTAssertTrue(events.contains(.acknowledged(second.id)))
        XCTAssertFalse(events.contains(.processingStarted(second.id)))
        XCTAssertFalse(events.contains(.listenerFinished), "the listener owns unfinished conversion work")

        await gate.open()
        await listener.value

        events = await probe.recordedEvents()
        XCTAssertEqual(
            events,
            [
                .prepared(first.id),
                .acknowledged(first.id),
                .processingStarted(first.id),
                .prepared(second.id),
                .acknowledged(second.id),
                .processingFinished(first.id),
                .processingStarted(second.id),
                .processingFinished(second.id),
                .listenerFinished
            ]
        )
    }

    func testUpdateCapturedBeforeSuspendedAcknowledgementRemainsIndependentOfRestore() async {
        let trial = storeTransaction(
            id: 350, originalID: 350, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 351, originalID: 350, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let (updates, continuation) = AsyncStream<UInt64>.makeStream()
        let probe = TransactionListenerProbe()
        let gate = ProcessingGate()

        let listener = Task {
            await LiveStoreKitFacade.processUpdates(
                updates,
                project: { _ in .verified(conversion) },
                acknowledge: { id in
                    await probe.record(.acknowledgementStarted(id))
                    await gate.wait()
                    await probe.record(.acknowledged(id))
                },
                prepareUpdate: { update in
                    guard let observation = await observer.capture(update) else { return nil }
                    return StoreTransactionProcessing {
                        await observer.observe(observation, history: [trial, conversion])
                    }
                }
            )
        }

        continuation.yield(conversion.id)
        await probe.waitUntilRecorded(.acknowledgementStarted(conversion.id))

        await observer.beginRestore()
        await observer.completeRestore(history: [trial, conversion])

        continuation.finish()
        await gate.open()
        await listener.value

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testCancellationDuringSuspendedAcknowledgementReturnsAndDisposesPreparedObservation() async {
        let trial = storeTransaction(
            id: 352, originalID: 352, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 353, originalID: 352, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let (updates, continuation) = AsyncStream<UInt64>.makeStream()
        let probe = TransactionListenerProbe()
        let acknowledgementGate = ProcessingGate()
        let listenerFinished = expectation(description: "cancelled listener finished")
        let acknowledgementFinished = expectation(description: "background acknowledgement finished")

        let listener = Task {
            await LiveStoreKitFacade.processUpdates(
                updates,
                project: { _ in .verified(conversion) },
                acknowledge: { id in
                    await probe.record(.acknowledgementStarted(id))
                    await acknowledgementGate.wait()
                    await probe.record(.acknowledged(id))
                    acknowledgementFinished.fulfill()
                },
                prepareUpdate: { update in
                    guard let observation = await observer.capture(update) else { return nil }
                    await probe.record(.prepared(conversion.id))
                    return StoreTransactionProcessing(
                        operation: {
                            await probe.record(.processingStarted(conversion.id))
                            await observer.observe(observation, history: [trial, conversion])
                        },
                        disposal: {
                            await observer.discard(observation)
                        }
                    )
                }
            )
            listenerFinished.fulfill()
        }

        continuation.yield(conversion.id)
        continuation.finish()
        await probe.waitUntilRecorded(.acknowledgementStarted(conversion.id))
        await observer.beginRestore()

        listener.cancel()
        await fulfillment(of: [listenerFinished], timeout: 1)

        let listenerEvents = await probe.recordedEvents()
        XCTAssertFalse(listenerEvents.contains(.processingStarted(conversion.id)))
        await observer.completeRestore(history: [trial, conversion])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )

        await acknowledgementGate.open()
        await fulfillment(of: [acknowledgementFinished], timeout: 1)
        let finalEvents = await analytics.recordedEvents
        let finalListenerEvents = await probe.recordedEvents()
        XCTAssertTrue(finalEvents.isEmpty)
        XCTAssertFalse(finalListenerEvents.contains(.processingStarted(conversion.id)))
    }

    func testListenerCancellationDisposesQueuedObservations() async {
        let firstTrial = storeTransaction(
            id: 354, originalID: 354, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstConversion = storeTransaction(
            id: 355, originalID: 354, day: 15,
            reason: .renewal, payment: .paid
        )
        let secondTrial = storeTransaction(
            id: 356, originalID: 356, day: 21,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let secondConversion = storeTransaction(
            id: 357, originalID: 356, day: 35,
            reason: .renewal, payment: .paid
        )
        let history = [firstTrial, firstConversion, secondTrial, secondConversion]
        let projectedUpdates: [UInt64: StoreTransactionUpdate] = [
            firstConversion.id: .verified(firstConversion),
            secondConversion.id: .verified(secondConversion)
        ]
        let marker = UInt64.max
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let (updates, continuation) = AsyncStream<UInt64>.makeStream()
        let probe = TransactionListenerProbe()
        let firstProcessingGate = ProcessingGate()
        let listenerFinished = expectation(description: "cancelled queued listener finished")

        let listener = Task {
            await LiveStoreKitFacade.processUpdates(
                updates,
                project: { projectedUpdates[$0] ?? .unverified },
                acknowledge: { id in
                    await probe.record(.acknowledged(id))
                },
                prepareUpdate: { update in
                    guard case .verified(let transaction) = update else {
                        await probe.record(.prepared(marker))
                        return nil
                    }
                    guard let observation = await observer.capture(update) else { return nil }
                    let id = transaction.id
                    await probe.record(.prepared(id))
                    return StoreTransactionProcessing(
                        operation: {
                            await probe.record(.processingStarted(id))
                            if id == firstConversion.id {
                                await firstProcessingGate.wait()
                            }
                            await observer.observe(observation, history: history)
                            await probe.record(.processingFinished(id))
                        },
                        disposal: {
                            await observer.discard(observation)
                        }
                    )
                }
            )
            listenerFinished.fulfill()
        }

        continuation.yield(firstConversion.id)
        await probe.waitUntilRecorded(.processingStarted(firstConversion.id))
        continuation.yield(secondConversion.id)
        await probe.waitUntilRecorded(.acknowledged(secondConversion.id))
        continuation.yield(marker)
        await probe.waitUntilRecorded(.prepared(marker))
        continuation.finish()
        await observer.beginRestore()

        listener.cancel()
        await firstProcessingGate.open()
        await fulfillment(of: [listenerFinished], timeout: 1)
        await observer.completeRestore(history: history)

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(firstConversion.id), String(secondConversion.id)]
        )
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

    func testRenewalAfterAPaidUpgradePurchaseDoesNotEmit() async {
        let trial = storeTransaction(
            id: 530, originalID: 530,
            productID: SubscriptionPlan.ProductID.monthly,
            day: 1, reason: .purchase, payment: .introductoryFreeTrial
        )
        let paidUpgrade = storeTransaction(
            id: 531, originalID: 530,
            productID: SubscriptionPlan.ProductID.yearly,
            day: 10, reason: .purchase, payment: .paid
        )
        let renewal = storeTransaction(
            id: 532, originalID: 530,
            productID: SubscriptionPlan.ProductID.yearly,
            day: 40, reason: .renewal, payment: .paid
        )

        let events = await observedEvents(
            facade: ObservingFacade(
                history: [trial, paidUpgrade, renewal],
                updates: [.verified(renewal)]
            )
        )

        XCTAssertTrue(events.isEmpty, "the paid upgrade was already the chain's first paid transaction")
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

    func testSuccessfulRestoreRevalidatesPendingConversionAgainstTerminalHistory() async {
        let trial = storeTransaction(
            id: 616, originalID: 616, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let earlierPaidRenewal = storeTransaction(
            id: 617, originalID: 616, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 618, originalID: 616, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(laterPaidRenewal), history: [trial])
        await observer.completeRestore(
            history: [trial, earlierPaidRenewal, laterPaidRenewal]
        )

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(earlierPaidRenewal.id)]
        )
    }

    func testFailedRestoreRevalidatesPendingConversionAgainstTerminalRevocation() async {
        let trial = storeTransaction(
            id: 619, originalID: 619, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let capturedConversion = storeTransaction(
            id: 620, originalID: 619, day: 15,
            reason: .renewal, payment: .paid
        )
        let revokedConversion = storeTransaction(
            id: 620, originalID: 619, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(capturedConversion), history: [trial])
        await observer.failRestore(history: .verified([trial, revokedConversion]))

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testFailedRestoreClassifiesCapturedRenewalsAgainstOneTerminalUnion() async {
        let trial = storeTransaction(
            id: 6_100, originalID: 6_100, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 6_101, originalID: 6_100, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 6_102, originalID: 6_100, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(laterPaidRenewal), history: [trial])
        await observer.observe(.verified(firstPaidRenewal), history: [trial])
        await observer.failRestore(history: .verified([trial]))

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            events.first?.timestampMs,
            Int(firstPaidRenewal.purchaseDate.timeIntervalSince1970 * 1_000)
        )
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(firstPaidRenewal.id)]
        )
    }

    func testFailedRestoreKeepsLaterSameIDRevocationStickyAcrossCapturedCandidates() async {
        let trial = storeTransaction(
            id: 6_110, originalID: 6_110, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_111, originalID: 6_110, day: 15,
            reason: .renewal, payment: .paid
        )
        let revokedConversion = storeTransaction(
            id: 6_111, originalID: 6_110, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(conversion), history: [trial])
        await observer.observe(.verified(revokedConversion), history: [trial])
        await observer.failRestore(history: .verified([trial]))

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testFailedRestoreRetainsCompletedRestoreUpdatePaidBoundaryHistory() async {
        let trial = storeTransaction(
            id: 6_115, originalID: 6_115, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 6_116, originalID: 6_115, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 6_117, originalID: 6_115, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(
            .verified(laterPaidRenewal),
            history: [trial, firstPaidRenewal, laterPaidRenewal]
        )
        await observer.failRestore(history: .verified([trial, laterPaidRenewal]))

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testFailedRestoreRetainsCompletedRestoreUpdateRevocationHistory() async {
        let trial = storeTransaction(
            id: 6_118, originalID: 6_118, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_119, originalID: 6_118, day: 15,
            reason: .renewal, payment: .paid
        )
        let revokedConversion = storeTransaction(
            id: 6_119, originalID: 6_118, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(
            .verified(conversion),
            history: [trial, revokedConversion]
        )
        await observer.failRestore(history: .verified([trial, conversion]))

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testSuccessfulRestoreReclassifiesInitiallyUnprovenCandidateAtTerminalHistory() async {
        let trial = storeTransaction(
            id: 623, originalID: 623, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 624, originalID: 623, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(conversion), history: [conversion])
        await observer.completeRestore(history: [trial])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testFailedRestoreReclassifiesInitiallyUnprovenCandidateAtTerminalHistory() async {
        let trial = storeTransaction(
            id: 625, originalID: 625, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 626, originalID: 625, day: 15,
            reason: .renewal, payment: .paid
        )
        let terminalHistory = StoreTransactionHistory.verified([trial, conversion])
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        await observer.observe(.verified(conversion), history: [conversion])
        await observer.failRestore(history: terminalHistory)

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testFailedRestoreDefersInFlightCandidateUntilAcknowledgedProcessing() async {
        let trial = storeTransaction(
            id: 627, originalID: 627, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 628, originalID: 627, day: 15,
            reason: .renewal, payment: .paid
        )
        let terminalHistory = StoreTransactionHistory.verified([trial, conversion])
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.beginRestore()
        let observation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(observation)
        await observer.failRestore(history: terminalHistory)

        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        if let observation {
            await observer.observe(observation, history: [])
        }

        events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testRestoreRedeliveryCannotBaselineAnIndependentInFlightConversion() async {
        let trial = storeTransaction(
            id: 621, originalID: 621, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 622, originalID: 621, day: 15,
            reason: .renewal, payment: .paid
        )
        let terminalHistory = [trial, conversion]
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(independentObservation)

        await observer.beginRestore()
        await observer.observe(.verified(conversion), history: terminalHistory)
        await observer.completeRestore(history: terminalHistory)
        if let independentObservation {
            await observer.observe(independentObservation, history: terminalHistory)
        }

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testInFlightRestoreRedeliveryYieldsToIndependentPreRestoreCapture() async {
        let trial = storeTransaction(
            id: 629, originalID: 629, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 630, originalID: 629, day: 15,
            reason: .renewal, payment: .paid
        )
        let terminalHistory = [trial, conversion]
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(independentObservation)

        await observer.beginRestore()
        let restoreObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(restoreObservation)
        await observer.completeRestore(history: terminalHistory)
        if let restoreObservation {
            await observer.observe(restoreObservation, history: terminalHistory)
        }

        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        if let independentObservation {
            await observer.observe(independentObservation, history: terminalHistory)
        }

        events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testTerminalHistoryPreventsStaleIndependentLaterRenewalEmission() async {
        let trial = storeTransaction(
            id: 6_120, originalID: 6_120, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 6_121, originalID: 6_120, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 6_122, originalID: 6_120, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(laterPaidRenewal))
        XCTAssertNotNil(independentObservation)

        await observer.beginRestore()
        await observer.completeRestore(history: [trial, firstPaidRenewal, laterPaidRenewal])
        if let independentObservation {
            await observer.observe(independentObservation, history: [trial])
        }

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(firstPaidRenewal.id)]
        )
    }

    func testObservationHistoryAddsPaidBoundaryMissingFromRestoreSnapshot() async {
        let trial = storeTransaction(
            id: 6_140, originalID: 6_140, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 6_141, originalID: 6_140, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 6_142, originalID: 6_140, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let observation = await observer.capture(.verified(laterPaidRenewal))
        XCTAssertNotNil(observation)

        await observer.beginRestore()
        await observer.failRestore(history: .verified([trial, laterPaidRenewal]))
        if let observation {
            await observer.observe(
                observation,
                history: [trial, firstPaidRenewal, laterPaidRenewal]
            )
        }

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testObservationHistoryRevocationOverridesRestoreSnapshot() async {
        let trial = storeTransaction(
            id: 6_143, originalID: 6_143, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_144, originalID: 6_143, day: 15,
            reason: .renewal, payment: .paid
        )
        let revokedConversion = storeTransaction(
            id: 6_144, originalID: 6_143, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let observation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(observation)

        await observer.beginRestore()
        await observer.failRestore(history: .verified([trial, conversion]))
        if let observation {
            await observer.observe(observation, history: [trial, revokedConversion])
        }

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testIndependentObservationWaitsForActiveRestoreTerminalHistoryBeforeClassifying() async {
        let trial = storeTransaction(
            id: 6_125, originalID: 6_125, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let firstPaidRenewal = storeTransaction(
            id: 6_126, originalID: 6_125, day: 15,
            reason: .renewal, payment: .paid
        )
        let laterPaidRenewal = storeTransaction(
            id: 6_127, originalID: 6_125, day: 45,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(laterPaidRenewal))
        XCTAssertNotNil(independentObservation)
        await observer.beginRestore()

        let (observationStarted, observationStartedContinuation) = AsyncStream<Void>.makeStream()
        let observationTask = Task {
            observationStartedContinuation.yield(())
            observationStartedContinuation.finish()
            if let independentObservation {
                await observer.observe(independentObservation, history: [trial])
            }
        }
        for await _ in observationStarted { break }
        for _ in 0..<10 { await Task.yield() }

        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        await observer.completeRestore(history: [trial, firstPaidRenewal, laterPaidRenewal])
        await observationTask.value

        events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(firstPaidRenewal.id)]
        )
    }

    func testFailedRestoreReleasesIndependentObservationAfterEarlyHistoryReturn() async {
        let trial = storeTransaction(
            id: 6_128, originalID: 6_128, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_129, originalID: 6_128, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(independentObservation)
        await observer.beginRestore()

        let (observationStarted, observationStartedContinuation) = AsyncStream<Void>.makeStream()
        let observationTask = Task {
            observationStartedContinuation.yield(())
            observationStartedContinuation.finish()
            if let independentObservation {
                await observer.observe(independentObservation, history: [trial])
            }
        }
        for await _ in observationStarted { break }
        for _ in 0..<10 { await Task.yield() }

        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        await observer.failRestore(history: .verified([trial, conversion]))
        await observationTask.value

        events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testCancellingRestoreWaiterReturnsBeforeRestoreFinalization() async {
        let trial = storeTransaction(
            id: 6_132, originalID: 6_132, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_133, originalID: 6_132, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(independentObservation)
        await observer.beginRestore()

        let observationFinished = expectation(description: "cancelled observation finished")
        let observationTask = Task {
            if let independentObservation {
                await observer.observe(independentObservation, history: [trial])
            }
            observationFinished.fulfill()
        }
        for _ in 0..<10 { await Task.yield() }
        observationTask.cancel()

        await fulfillment(of: [observationFinished], timeout: 1)
        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)

        await observer.completeRestore(history: [trial, conversion])
        await observationTask.value

        events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testCancellingListenerReleasesRestoreWaiterWithoutLaterEmission() async {
        let trial = storeTransaction(
            id: 6_134, originalID: 6_134, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_135, originalID: 6_134, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let (updates, updatesContinuation) = AsyncStream<UInt64>.makeStream()
        let acknowledgementGate = ProcessingGate()
        let probe = TransactionListenerProbe()
        let listenerFinished = expectation(description: "cancelled listener finished")

        let listener = Task {
            await LiveStoreKitFacade.processUpdates(
                updates,
                project: { _ in .verified(conversion) },
                acknowledge: { id in
                    await probe.record(.acknowledgementStarted(id))
                    await acknowledgementGate.wait()
                    await probe.record(.acknowledged(id))
                },
                prepareUpdate: { update in
                    guard let observation = await observer.capture(update) else { return nil }
                    let id = conversion.id
                    await probe.record(.prepared(id))
                    return StoreTransactionProcessing {
                        await probe.record(.processingStarted(id))
                        await observer.observe(observation, history: [trial])
                        await probe.record(.processingFinished(id))
                    }
                }
            )
            listenerFinished.fulfill()
        }

        updatesContinuation.yield(conversion.id)
        updatesContinuation.finish()
        await probe.waitUntilRecorded(.acknowledgementStarted(conversion.id))
        await observer.beginRestore()
        await acknowledgementGate.open()
        await probe.waitUntilRecorded(.processingStarted(conversion.id))
        for _ in 0..<10 { await Task.yield() }

        listener.cancel()
        await fulfillment(of: [listenerFinished], timeout: 1)
        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)

        await observer.failRestore(history: .verified([trial, conversion]))
        await listener.value

        events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testTerminalRevocationPreventsStaleIndependentConversionEmission() async {
        let trial = storeTransaction(
            id: 6_130, originalID: 6_130, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 6_131, originalID: 6_130, day: 15,
            reason: .renewal, payment: .paid
        )
        let revokedConversion = storeTransaction(
            id: 6_131, originalID: 6_130, day: 15,
            reason: .renewal, payment: .paid, isRevoked: true
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let independentObservation = await observer.capture(.verified(conversion))
        XCTAssertNotNil(independentObservation)

        await observer.beginRestore()
        await observer.completeRestore(history: [trial, revokedConversion])
        if let independentObservation {
            await observer.observe(independentObservation, history: [trial])
        }

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(
            (observerDefaults.stringArray(
                forKey: TrialConversionObserver.emittedTransactionIDsKey
            ) ?? []).isEmpty
        )
    }

    func testOverlappingFailedAndSuccessfulRestoresRemainSerialized() async throws {
        let trial = storeTransaction(
            id: 614, originalID: 614, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 615, originalID: 614, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let state = OverlappingRestoreState(
            history: [trial, conversion],
            update: conversion
        )
        let service = StoreKitSubscriptionService(
            facade: OverlappingRestoreFacade(state: state),
            analytics: analytics,
            userDefaults: observerDefaults
        )
        let listenerTask = service.startObservingTransactions()
        await listenerTask.value

        let firstRestore = Task { () -> SubscriptionError? in
            do {
                _ = try await service.restorePurchases()
                return nil
            } catch {
                return error as? SubscriptionError
            }
        }
        await state.waitUntilSyncStarts(1)

        let secondEntered = ProcessingGate()
        let secondRestore = Task {
            await secondEntered.open()
            return try await service.restorePurchases()
        }
        await secondEntered.wait()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let startedBeforeFirstFinished = await state.startedSyncCount()
        XCTAssertEqual(startedBeforeFirstFinished, 1)

        await state.releaseSync(1)
        let firstError = await firstRestore.value
        XCTAssertEqual(firstError, .failed("first restore failed"))

        await state.waitUntilSyncStarts(2)
        await state.waitUntilUpdateDelivered()
        var events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)

        await state.releaseSync(2)
        _ = try await secondRestore.value

        events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
    }

    func testUpdateAlreadyAwaitingHistoryWhenRestoreStartsStillEmits() async throws {
        let trial = storeTransaction(
            id: 612, originalID: 612, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 613, originalID: 612, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let historyGate = FirstHistoryReadGate(history: [trial, conversion])
        let service = StoreKitSubscriptionService(
            facade: RestoreRaceFacade(historyGate: historyGate, update: conversion),
            analytics: analytics,
            userDefaults: observerDefaults
        )

        let listenerTask = service.startObservingTransactions()
        await historyGate.waitUntilFirstReadStarts()

        let restoreTask = Task { try await service.restorePurchases() }
        _ = try await restoreTask.value
        await historyGate.releaseFirstRead()
        await listenerTask.value

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            ["613"]
        )
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

    func testReverseOrderedLiveUpdatesRetainTheNewestConversionForRedeliveryDeduplication() async {
        var history: [StoreSubscriptionTransaction] = []
        var conversions: [StoreSubscriptionTransaction] = []
        for offset in 0...TrialConversionObserver.retentionLimit {
            let originalID = UInt64(1_000 + offset * 2)
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

        let firstEvents = await observedEvents(
            facade: ObservingFacade(
                history: history,
                updates: conversions.reversed().map(StoreTransactionUpdate.verified)
            )
        )
        XCTAssertEqual(firstEvents.count, TrialConversionObserver.retentionLimit + 1)

        let newestConversion = conversions[TrialConversionObserver.retentionLimit]
        let storedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        XCTAssertFalse(storedIDs?.contains(String(conversions[0].id)) == true)
        XCTAssertTrue(storedIDs?.contains(String(newestConversion.id)) == true)

        let redeliveryEvents = await observedEvents(
            facade: ObservingFacade(
                history: history,
                updates: [.verified(newestConversion)]
            )
        )
        XCTAssertTrue(redeliveryEvents.isEmpty)
    }

    func testFailedRestoreReleasesReverseOrderedUpdatesAndRetainsTheNewestConversion() async {
        var history: [StoreSubscriptionTransaction] = []
        var conversions: [StoreSubscriptionTransaction] = []
        for offset in 0...TrialConversionObserver.retentionLimit {
            let originalID = UInt64(1_100 + offset * 2)
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

        await observer.beginRestore()
        for conversion in conversions.reversed() {
            await observer.observe(.verified(conversion), history: history)
        }
        await observer.failRestore(history: .verified(history))

        var events = await analytics.recordedEvents
        XCTAssertEqual(events.count, TrialConversionObserver.retentionLimit + 1)
        let newestConversion = conversions[TrialConversionObserver.retentionLimit]
        let storedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        XCTAssertFalse(storedIDs?.contains(String(conversions[0].id)) == true)
        XCTAssertTrue(storedIDs?.contains(String(newestConversion.id)) == true)

        await observer.observe(.verified(newestConversion), history: history)

        events = await analytics.recordedEvents
        XCTAssertEqual(events.count, TrialConversionObserver.retentionLimit + 1)
    }

    func testFailedRestoreAfterRelaunchDoesNotReplaceANewerRetainedConversionWithAnOlderOne() async {
        var newerHistory: [StoreSubscriptionTransaction] = []
        var newerConversions: [StoreSubscriptionTransaction] = []
        for offset in 0..<TrialConversionObserver.retentionLimit {
            let originalID = UInt64(1_200 + offset * 2)
            let trial = storeTransaction(
                id: originalID, originalID: originalID, day: TimeInterval(offset * 20 + 101),
                reason: .purchase, payment: .introductoryFreeTrial
            )
            let conversion = storeTransaction(
                id: originalID + 1, originalID: originalID, day: TimeInterval(offset * 20 + 115),
                reason: .renewal, payment: .paid
            )
            newerHistory.append(contentsOf: [trial, conversion])
            newerConversions.append(conversion)
        }

        let baselineObserver = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: MockAnalyticsService(),
            userDefaults: observerDefaults
        )
        await baselineObserver.beginRestore()
        await baselineObserver.completeRestore(history: newerHistory)

        let olderTrial = storeTransaction(
            id: 1_100, originalID: 1_100, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let olderConversion = storeTransaction(
            id: 1_101, originalID: 1_100, day: 15,
            reason: .renewal, payment: .paid
        )
        let completeHistory = [olderTrial, olderConversion] + newerHistory
        let analytics = MockAnalyticsService()
        let relaunchedObserver = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await relaunchedObserver.beginRestore()
        await relaunchedObserver.observe(.verified(olderConversion), history: completeHistory)
        await relaunchedObserver.failRestore(history: .verified(completeHistory))

        var events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        let storedIDs = Set(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey) ?? []
        )
        XCTAssertEqual(storedIDs, Set(newerConversions.map { String($0.id) }))

        await relaunchedObserver.observe(.verified(newerConversions[0]), history: completeHistory)

        events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
    }

    func testAccountSwitchCannotEvictANewerRetainedConversionOrMakeItEmitAgain() async {
        var newerHistory: [StoreSubscriptionTransaction] = []
        var newerConversions: [StoreSubscriptionTransaction] = []
        for offset in 0..<TrialConversionObserver.retentionLimit {
            let originalID = UInt64(1_400 + offset * 2)
            let trial = storeTransaction(
                id: originalID, originalID: originalID, day: TimeInterval(offset * 20 + 201),
                reason: .purchase, payment: .introductoryFreeTrial
            )
            let conversion = storeTransaction(
                id: originalID + 1, originalID: originalID, day: TimeInterval(offset * 20 + 215),
                reason: .renewal, payment: .paid
            )
            newerHistory.append(contentsOf: [trial, conversion])
            newerConversions.append(conversion)
        }

        let baselineObserver = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: MockAnalyticsService(),
            userDefaults: observerDefaults
        )
        await baselineObserver.beginRestore()
        await baselineObserver.completeRestore(history: newerHistory)

        let olderTrial = storeTransaction(
            id: 1_300, originalID: 1_300, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let olderConversion = storeTransaction(
            id: 1_301, originalID: 1_300, day: 15,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let relaunchedObserver = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await relaunchedObserver.observe(
            .verified(olderConversion),
            history: [olderTrial, olderConversion]
        )

        var events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        let retainedIDs = Set(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey) ?? []
        )
        XCTAssertEqual(retainedIDs, Set(newerConversions.map { String($0.id) }))
        XCTAssertFalse(retainedIDs.contains(String(olderConversion.id)))

        await relaunchedObserver.observe(
            .verified(newerConversions[0]),
            history: newerHistory
        )

        events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
        let storedDates = observerDefaults.dictionary(
            forKey: TrialConversionObserver.emittedTransactionPurchaseDatesKey
        )
        XCTAssertEqual(storedDates?.count, TrialConversionObserver.retentionLimit)
    }

    func testLegacyIDOnlyStateMigratesOrderingMetadataWithoutRedelivery() async {
        let trial = storeTransaction(
            id: 1_500, originalID: 1_500, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let conversion = storeTransaction(
            id: 1_501, originalID: 1_500, day: 15,
            reason: .renewal, payment: .paid
        )
        observerDefaults.set(
            [String(conversion.id)],
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.observe(.verified(conversion), history: [trial, conversion])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            [String(conversion.id)]
        )
        let storedDates = observerDefaults.dictionary(
            forKey: TrialConversionObserver.emittedTransactionPurchaseDatesKey
        )
        let storedTimestamp = (storedDates?[String(conversion.id)] as? NSNumber)?.doubleValue
        XCTAssertEqual(storedTimestamp, conversion.purchaseDate.timeIntervalSince1970)
    }

    func testPartialLegacyMetadataMigrationPreservesTheLegacyEvictionOrder() async {
        let legacyIDs = (0..<TrialConversionObserver.retentionLimit).map {
            String(2_001 + $0)
        }
        observerDefaults.set(
            legacyIDs,
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        let oldestTrial = storeTransaction(
            id: 1_901, originalID: 1_901, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let oldestConversion = storeTransaction(
            id: 2_001, originalID: 1_901, day: 15,
            reason: .renewal, payment: .paid
        )
        let secondTrial = storeTransaction(
            id: 1_902, originalID: 1_902, day: 2,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let secondConversion = storeTransaction(
            id: 2_002, originalID: 1_902, day: 16,
            reason: .renewal, payment: .paid
        )
        let newTrial = storeTransaction(
            id: 3_000, originalID: 3_000, day: 100,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let newConversion = storeTransaction(
            id: 3_001, originalID: 3_000, day: 114,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.observe(
            .verified(oldestConversion),
            history: [oldestTrial, oldestConversion]
        )
        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            legacyIDs
        )

        await observer.observe(
            .verified(newConversion),
            history: [newTrial, newConversion]
        )

        let retainedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        XCTAssertEqual(retainedIDs?.count, TrialConversionObserver.retentionLimit)
        XCTAssertFalse(retainedIDs?.contains(String(oldestConversion.id)) == true)
        XCTAssertTrue(retainedIDs?.contains(String(secondConversion.id)) == true)
        XCTAssertEqual(retainedIDs?.last, String(newConversion.id))

        await observer.observe(
            .verified(secondConversion),
            history: [secondTrial, secondConversion]
        )

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
    }

    func testPartialLegacyMetadataMigrationRejectsAnOlderNewEvictionCandidate() async {
        let legacyIDs = (0..<TrialConversionObserver.retentionLimit).map {
            String(4_001 + $0)
        }
        observerDefaults.set(
            legacyIDs,
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        )
        let knownLegacyTrial = storeTransaction(
            id: 3_901, originalID: 3_901, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let knownLegacyConversion = storeTransaction(
            id: 4_001, originalID: 3_901, day: 100,
            reason: .renewal, payment: .paid
        )
        let olderTrial = storeTransaction(
            id: 5_000, originalID: 5_000, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let olderConversion = storeTransaction(
            id: 5_001, originalID: 5_000, day: 50,
            reason: .renewal, payment: .paid
        )
        let analytics = MockAnalyticsService()
        let observer = TrialConversionObserver(
            productIDs: SubscriptionPlan.ProductID.all,
            analytics: analytics,
            userDefaults: observerDefaults
        )

        await observer.observe(
            .verified(knownLegacyConversion),
            history: [knownLegacyTrial, knownLegacyConversion]
        )
        await observer.observe(
            .verified(olderConversion),
            history: [olderTrial, olderConversion]
        )

        XCTAssertEqual(
            observerDefaults.stringArray(forKey: TrialConversionObserver.emittedTransactionIDsKey),
            legacyIDs
        )

        await observer.observe(
            .verified(knownLegacyConversion),
            history: [knownLegacyTrial, knownLegacyConversion]
        )

        let events = await analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.subscribe])
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

    /// Produces a reviewer-readable transcript of the two monetization journeys at the application
    /// analytics boundary. StoreKit's signed-update delivery remains framework-owned and is covered by
    /// the adjacent manual recipe; this scenario executes the app-owned paywall, observer, and durable
    /// dedup behavior rather than merely recording test names.
    func testTrialConversionSubscribeEvidenceTranscript() async throws {
        let monthlyPlan = try XCTUnwrap(
            SubscriptionPlan.samples.first { $0.id == SubscriptionPlan.ProductID.monthly }
        )
        let yearlyPlan = try XCTUnwrap(
            SubscriptionPlan.samples.first { $0.id == SubscriptionPlan.ProductID.yearly }
        )
        let signedTrial = storeTransaction(
            id: 300, originalID: 300, day: 1,
            reason: .purchase, payment: .introductoryFreeTrial
        )
        let signedConversion = storeTransaction(
            id: 301, originalID: 300, day: 15,
            reason: .renewal, payment: .paid
        )
        let signedLaterRenewal = storeTransaction(
            id: 302, originalID: 300, day: 45,
            reason: .renewal, payment: .paid
        )

        let journeyAnalytics = MockAnalyticsService()
        let trialEntitlement = premiumEntitlement(
            productID: monthlyPlan.id,
            expiresAt: signedConversion.purchaseDate,
            isInTrialPeriod: true
        )
        let trialPurchaseService = StoreKitSubscriptionService(
            facade: ObservingFacade(
                purchaseResult: .success([trialEntitlement])
            ),
            analytics: journeyAnalytics,
            userDefaults: observerDefaults
        )
        let trialPaywall = PaywallViewModel(
            subscriptionService: trialPurchaseService,
            analytics: journeyAnalytics,
            now: { signedTrial.purchaseDate }
        )
        await trialPaywall.purchase(monthlyPlan)
        let afterTrialPurchase = await journeyAnalytics.recordedEvents

        _ = await observedEvents(
            facade: ObservingFacade(
                history: [signedTrial, signedConversion],
                updates: [.verified(signedConversion)]
            ),
            analytics: journeyAnalytics,
            defaults: observerDefaults
        )
        let afterFirstPaidRenewal = await journeyAnalytics.recordedEvents

        _ = await observedEvents(
            facade: ObservingFacade(
                history: [signedTrial, signedConversion],
                updates: [.verified(signedConversion)]
            ),
            analytics: journeyAnalytics,
            defaults: observerDefaults
        )
        let afterRelaunchRedelivery = await journeyAnalytics.recordedEvents

        _ = await observedEvents(
            facade: ObservingFacade(
                history: [signedTrial, signedConversion, signedLaterRenewal],
                updates: [.verified(signedLaterRenewal)]
            ),
            analytics: journeyAnalytics,
            defaults: observerDefaults
        )
        let afterLaterRenewal = await journeyAnalytics.recordedEvents

        XCTAssertEqual(afterTrialPurchase.map(\.name), [.trialStarted])
        XCTAssertEqual(afterFirstPaidRenewal.map(\.name), [.trialStarted, .subscribe])
        XCTAssertEqual(
            afterFirstPaidRenewal.last?.properties,
            ["plan": .string(SubscriptionPlan.ProductID.monthly)]
        )
        XCTAssertEqual(
            afterFirstPaidRenewal.last?.timestampMs,
            Int(signedConversion.purchaseDate.timeIntervalSince1970 * 1_000),
            "the conversion carries StoreKit's signed purchase timestamp"
        )
        XCTAssertEqual(afterRelaunchRedelivery, afterFirstPaidRenewal)
        XCTAssertEqual(afterLaterRenewal, afterFirstPaidRenewal)

        let journeyRetainedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        ) ?? []
        let journeyRetainedDates = observerDefaults.dictionary(
            forKey: TrialConversionObserver.emittedTransactionPurchaseDatesKey
        ) ?? [:]
        XCTAssertEqual(journeyRetainedIDs, [String(signedConversion.id)])
        XCTAssertEqual(
            (journeyRetainedDates[String(signedConversion.id)] as? NSNumber)?.doubleValue,
            signedConversion.purchaseDate.timeIntervalSince1970
        )

        var retentionHistory: [StoreSubscriptionTransaction] = []
        var retentionUpdates: [StoreTransactionUpdate] = []
        for offset in 0 ..< TrialConversionObserver.retentionLimit {
            let originalID = UInt64(1_000 + offset * 2)
            let trial = storeTransaction(
                id: originalID, originalID: originalID, day: TimeInterval(100 + offset * 20),
                reason: .purchase, payment: .introductoryFreeTrial
            )
            let conversion = storeTransaction(
                id: originalID + 1, originalID: originalID, day: TimeInterval(114 + offset * 20),
                reason: .renewal, payment: .paid
            )
            retentionHistory.append(contentsOf: [trial, conversion])
            retentionUpdates.append(.verified(conversion))
        }
        _ = await observedEvents(
            facade: ObservingFacade(history: retentionHistory, updates: retentionUpdates),
            analytics: MockAnalyticsService(),
            defaults: observerDefaults
        )
        let boundedRetainedIDs = observerDefaults.stringArray(
            forKey: TrialConversionObserver.emittedTransactionIDsKey
        ) ?? []
        XCTAssertEqual(boundedRetainedIDs.count, TrialConversionObserver.retentionLimit)
        XCTAssertFalse(boundedRetainedIDs.contains(String(signedConversion.id)))
        XCTAssertEqual(boundedRetainedIDs.first, "1001")
        XCTAssertEqual(boundedRetainedIDs.last, "1063")

        let durableDomain = observerDefaults.persistentDomain(forName: observerDefaultsSuite) ?? [:]
        XCTAssertEqual(
            Set(durableDomain.keys),
            Set([
                TrialConversionObserver.emittedTransactionIDsKey,
                TrialConversionObserver.emittedTransactionPurchaseDatesKey
            ]),
            "only bounded ids and signed ordering metadata are persisted"
        )

        let directAnalytics = MockAnalyticsService()
        let directEntitlement = premiumEntitlement(productID: yearlyPlan.id)
        let directPurchaseService = StoreKitSubscriptionService(
            facade: ObservingFacade(purchaseResult: .success([directEntitlement])),
            analytics: directAnalytics,
            userDefaults: observerDefaults
        )
        let directPaywall = PaywallViewModel(
            subscriptionService: directPurchaseService,
            analytics: directAnalytics,
            now: { Date(timeIntervalSince1970: 2 * 86_400) }
        )
        await directPaywall.purchase(yearlyPlan)
        let directEvents = await directAnalytics.recordedEvents
        XCTAssertEqual(directEvents.map(\.name), [.subscribe])
        XCTAssertEqual(directEvents.first?.properties, ["plan": .string(yearlyPlan.id)])
        XCTAssertFalse(directEvents.contains { $0.name == .trialStarted })

        let transcript = """
        # Trial-to-paid `subscribe` product evidence

        Executed through the production `PaywallViewModel` and `StoreKitSubscriptionService` into
        the injected application analytics boundary. The StoreKit values are deterministic verified
        facade projections; the framework-owned signed delivery leg is the separate manual recipe.

        | User journey boundary | Application analytics stream after boundary |
        | --- | --- |
        | Monthly introductory trial purchase | `trial_started` (no properties) |
        | First positive-price renewal, transaction 301 | `trial_started`, then `subscribe { plan: \(monthlyPlan.id) }` |
        | Same renewal redelivered after service relaunch | unchanged; no second event |
        | Later paid renewal, transaction 302 | unchanged; no second event |
        | Direct yearly paid purchase | `subscribe { plan: \(yearlyPlan.id) }`; no `trial_started` |

        ## Signed conversion timestamp

        `subscribe.timestampMs = \(afterFirstPaidRenewal.last?.timestampMs ?? -1)`

        ## Durable duplicate-suppression state

        - State after the journey: IDs `\(journeyRetainedIDs)`, purchase dates `\(journeyRetainedDates)`
        - State after 33 distinct conversions: count `\(boundedRetainedIDs.count)`, IDs `\(boundedRetainedIDs)`
        - Oldest ID 301 still retained: `\(boundedRetainedIDs.contains(String(signedConversion.id)))`
        - Persisted keys: `\(durableDomain.keys.sorted())`
        - Stored receipt/product/price/history: none
        """
        try EvidenceOutput.write(
            transcript + "\n",
            named: "telemetry-boundary-transcript.md",
            for: EvidenceOutput.Story.trialConversionSubscribe
        )
    }
}
