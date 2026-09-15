import Foundation

/// The real StoreKit 2 subscription service (US-N04).
///
/// It composes one seam - a `StoreKitFacade` (the App Store ceremony) - and owns the domain mapping
/// from raw store entitlements/products to the app's `Subscription`/`SubscriptionPlan` types. Because
/// the ceremony lives in the seam, the service itself is a pure, `Sendable` composition, unit-testable
/// end to end with a stub facade.
///
/// Design principles:
/// - **Never gates the loop.** Premium only unlocks the depth layer (US-M02). Free is unlimited core
///   workouts forever; a failure anywhere here resolves to the free tier rather than blocking anything.
/// - **Entitlement is a local read.** `currentSubscription()` reads StoreKit's cached current
///   entitlements, so it resolves fast and offline; it drives the US-M02 gate.
/// - **Purchase and restore both re-resolve.** A completed purchase and an `AppStore.sync()` restore
///   each re-read current entitlements, so the returned `Subscription` reflects the real granted state.
/// - **Conversions come from transactions, not time.** The lifetime listener proves the free-trial
///   origin and first paid renewal from verified StoreKit history before emitting `subscribe`.
struct StoreKitSubscriptionService: SubscriptionServiceProtocol {

    private let facade: any StoreKitFacade
    private let productIDs: [String]
    private let trialConversionObserver: TrialConversionObserver

    init(
        facade: any StoreKitFacade,
        productIDs: [String] = SubscriptionPlan.ProductID.all,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.facade = facade
        self.productIDs = productIDs
        self.trialConversionObserver = TrialConversionObserver(
            productIDs: productIDs,
            analytics: analytics,
            userDefaults: userDefaults
        )
    }

    // MARK: - Entitlement

    func currentSubscription() async throws -> Subscription {
        Self.subscription(from: await facade.currentEntitlements())
    }

    func refreshEntitlements() async throws -> Subscription {
        // Identical to `currentSubscription()`: the facade always reads live current entitlements, so
        // there is no stale cache to bust. The distinct method exists for callers that want to signal
        // intent (e.g. a pull-to-refresh) and to leave room for a future forced revalidation.
        Self.subscription(from: await facade.currentEntitlements())
    }

    // MARK: - Paywall

    func premiumPlans() async throws -> [SubscriptionPlan] {
        let products = try await facade.loadProducts(ids: productIDs)
        guard !products.isEmpty else { throw SubscriptionError.productsUnavailable }
        return products.map(Self.plan(from:)).sorted(by: SubscriptionPlan.displayOrder)
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        switch try await facade.purchase(productID: plan.id) {
        case .success(let entitlements):
            return .resolved(Self.subscription(from: entitlements))
        case .userCancelled:
            // A cancel is not an error: the entitlement is simply unchanged, so report current state.
            return .resolved(Self.subscription(from: await facade.currentEntitlements()))
        case .pending:
            // Awaiting external approval (e.g. Ask to Buy). Nothing is granted yet; the paywall
            // reassures the user and the approval is picked up out-of-band by the transaction listener.
            return .pending
        }
    }

    func purchasePremium() async throws -> Subscription {
        let plans = try await premiumPlans()
        // The PRD-named convenience purchases the primary (monthly) plan; callers that want plan
        // selection use `premiumPlans()` + `purchase(_:)` from the paywall.
        guard let plan = plans.first(where: { $0.period == .monthly }) ?? plans.first else {
            throw SubscriptionError.productsUnavailable
        }
        switch try await purchase(plan) {
        case .resolved(let subscription):
            return subscription
        case .pending:
            // Deferred: report the (unchanged) current entitlement; the approval lands out-of-band.
            return Self.subscription(from: await facade.currentEntitlements())
        }
    }

    func restorePurchases() async throws -> Subscription {
        await trialConversionObserver.beginRestore()
        do {
            try await facade.sync()
            // A restore may surface old signed transactions through `Transaction.updates`. Baseline
            // any already-completed trial conversion from the verified history before ending the
            // restore window, so restoring ownership can never masquerade as a new conversion.
            let history = await facade.transactionHistory()
            await trialConversionObserver.completeRestore(history: history)
            return Self.subscription(from: await facade.currentEntitlements())
        } catch {
            // If sync failed, an update that happened independently while it was in flight is still a
            // live transaction and must be judged normally rather than silently discarded.
            await trialConversionObserver.failRestore()
            throw error
        }
    }

    @discardableResult
    func startObservingTransactions() -> Task<Void, Never> {
        let facade = facade
        let observer = trialConversionObserver
        return facade.listenForTransactions { update in
            // No history read for an unverified update: it can neither grant access nor prove a
            // conversion. Verified updates are processed off the core loop by the app-owned listener.
            guard case .verified = update else { return }
            let history = await facade.transactionHistory()
            await observer.observe(update, history: history)
        }
    }

    // MARK: - Mapping

    /// Resolve the app's `Subscription` from the store's current entitlements. Any active premium
    /// entitlement grants `.premium`; with several, the one expiring latest wins (its `expiresAt` and
    /// trial state carry through). No entitlement is the free tier.
    static func subscription(from entitlements: [StoreEntitlement]) -> Subscription {
        guard let best = entitlements.max(by: { keyDate($0) < keyDate($1) }) else {
            return .free
        }
        return Subscription(
            tier: .premium,
            provider: .apple,
            expiresAt: best.expiresAt,
            trialEndsAt: best.isInTrialPeriod ? best.expiresAt : nil
        )
    }

    private static func keyDate(_ entitlement: StoreEntitlement) -> Date {
        entitlement.expiresAt ?? .distantFuture
    }

    private static func plan(from product: StoreProduct) -> SubscriptionPlan {
        SubscriptionPlan(
            id: product.id,
            displayPrice: product.displayPrice,
            period: product.period,
            trialDescription: product.trialDescription
        )
    }
}

/// Detects the one billed boundary in an introductory-free-trial subscription chain.
///
/// This actor is intentionally independent of entitlement/UI state. It emits only when a verified
/// `Transaction.updates` value is itself the first positive-price renewal in a history whose original
/// purchase is explicitly a free trial. A foreground, restore, current-entitlement read, direct paid
/// purchase, later renewal, pending purchase, revoked transaction, or unverified result cannot satisfy
/// that predicate.
///
/// Dedup is durable and minimal: only qualifying conversion transaction ids are persisted, never a
/// receipt, product, price, date, or transaction history. The newest 32 ids are retained and the oldest
/// is replaced on the 33rd distinct conversion, keeping state bounded while allowing distinct trial
/// conversions to be counted independently (for example after the App Store account changes).
actor TrialConversionObserver {
    static let emittedTransactionIDsKey = "telemetry.trialConversionTransactionIDs"
    static let retentionLimit = 32

    private let productIDs: Set<String>
    private let analytics: (any AnalyticsServiceProtocol)?
    private let userDefaults: UserDefaults
    private var restoreInProgress = false
    private var conversionsPendingDuringRestore: [StoreSubscriptionTransaction] = []

    init(
        productIDs: [String],
        analytics: (any AnalyticsServiceProtocol)?,
        userDefaults: UserDefaults
    ) {
        self.productIDs = Set(productIDs)
        self.analytics = analytics
        self.userDefaults = userDefaults
    }

    func observe(_ update: StoreTransactionUpdate, history: [StoreSubscriptionTransaction]) async {
        guard let analytics else { return }
        guard case .verified(let transaction) = update else { return }
        guard Self.isQualifyingConversion(transaction, history: history, productIDs: productIDs) else { return }

        if restoreInProgress {
            // `AppStore.sync()` can redeliver historical transactions. Hold a qualifying update until
            // the restore outcome is known: successful restore baselines it without telemetry; failed
            // restore releases it through the ordinary live-update path.
            if !conversionsPendingDuringRestore.contains(where: { $0.id == transaction.id }) {
                conversionsPendingDuringRestore.append(transaction)
            }
            return
        }

        await emitIfNeeded(transaction, analytics: analytics)
    }

    func beginRestore() {
        restoreInProgress = true
        conversionsPendingDuringRestore = []
    }

    func completeRestore(history: [StoreSubscriptionTransaction]) {
        let historicalConversions = history.filter {
            Self.isQualifyingConversion($0, history: history, productIDs: productIDs)
        }
        let orderedConversions = (historicalConversions + conversionsPendingDuringRestore).sorted {
            if $0.purchaseDate != $1.purchaseDate { return $0.purchaseDate < $1.purchaseDate }
            return $0.id < $1.id
        }
        var seenTransactionIDs = Set<UInt64>()
        for transaction in orderedConversions {
            guard seenTransactionIDs.insert(transaction.id).inserted else { continue }
            markEmitted(transaction.id)
        }
        clearRestoreState()
    }

    func failRestore() async {
        let pendingTransactions = conversionsPendingDuringRestore
        clearRestoreState()

        guard let analytics else { return }
        for transaction in pendingTransactions {
            await emitIfNeeded(transaction, analytics: analytics)
        }
    }

    private func emitIfNeeded(
        _ transaction: StoreSubscriptionTransaction,
        analytics: any AnalyticsServiceProtocol
    ) async {
        guard !emittedTransactionIDs.contains(String(transaction.id)) else { return }

        // Persist before handing off to the fire-and-forget analytics boundary. A cancellation or
        // relaunch after this point may lose delivery (the transport owns reliability), but can never
        // turn StoreKit redelivery into a second emission attempt.
        markEmitted(transaction.id)

        await analytics.record(
            AnalyticsEvent(
                name: .subscribe,
                timestampMs: Int(transaction.purchaseDate.timeIntervalSince1970 * 1_000),
                properties: ["plan": .string(transaction.productID)]
            )
        )
    }

    private func clearRestoreState() {
        restoreInProgress = false
        conversionsPendingDuringRestore = []
    }

    private var emittedTransactionIDs: [String] {
        userDefaults.stringArray(forKey: Self.emittedTransactionIDsKey) ?? []
    }

    private func markEmitted(_ transactionID: UInt64) {
        let id = String(transactionID)
        var ids = emittedTransactionIDs
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > Self.retentionLimit {
            ids.removeFirst(ids.count - Self.retentionLimit)
        }
        userDefaults.set(ids, forKey: Self.emittedTransactionIDsKey)
    }

    static func isQualifyingConversion(
        _ transaction: StoreSubscriptionTransaction,
        history: [StoreSubscriptionTransaction],
        productIDs: Set<String>
    ) -> Bool {
        guard productIDs.contains(transaction.productID),
              transaction.isAutoRenewable,
              transaction.isPurchased,
              !transaction.isRevoked,
              !transaction.isUpgraded,
              transaction.reason == .renewal,
              transaction.payment == .paid,
              transaction.id != transaction.originalID else {
            return false
        }

        // Include the update itself because `Transaction.all` is a point-in-time snapshot and the
        // update may have arrived just after that snapshot began. Dedup by transaction id before
        // determining the first paid renewal.
        let chain = (history + [transaction]).reduce(into: [UInt64: StoreSubscriptionTransaction]()) {
            $0[$1.id] = $1
        }.values.filter {
            $0.originalID == transaction.originalID && $0.isAutoRenewable && $0.isPurchased
        }

        let hasFreeTrialOrigin = chain.contains {
            $0.id == $0.originalID
                && $0.reason == .purchase
                && $0.payment == .introductoryFreeTrial
                && !$0.isRevoked
        }
        guard hasFreeTrialOrigin else { return false }

        let paidRenewals = chain.filter {
            $0.reason == .renewal
                && $0.payment == .paid
        }
        let firstPaidRenewal = paidRenewals.min {
            if $0.purchaseDate != $1.purchaseDate { return $0.purchaseDate < $1.purchaseDate }
            return $0.id < $1.id
        }
        return firstPaidRenewal?.id == transaction.id
    }
}

extension StoreKitSubscriptionService {
    /// Production wiring: the real StoreKit 2 facade. `mock()` keeps `MockSubscriptionService` so the
    /// suite and previews stay off the App Store and deterministic.
    static func live(analytics: any AnalyticsServiceProtocol) -> StoreKitSubscriptionService {
        StoreKitSubscriptionService(facade: LiveStoreKitFacade(), analytics: analytics)
    }
}
