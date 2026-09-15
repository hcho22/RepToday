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
            guard let observation = await observer.capture(update) else { return nil }
            return {
                let history = await facade.transactionHistory()
                await observer.observe(observation, history: history)
            }
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
/// Dedup is durable and minimal: qualifying conversion transaction ids and their signed purchase
/// instants are persisted, never a receipt, product, price, or transaction history. The timestamps are
/// bounded ordering metadata for retaining the newest 32 ids across relaunches and App Store account
/// changes; the oldest is replaced on the 33rd distinct conversion.
actor TrialConversionObserver {
    static let emittedTransactionIDsKey = "telemetry.trialConversionTransactionIDs"
    static let emittedTransactionPurchaseDatesKey = "telemetry.trialConversionTransactionPurchaseDates"
    static let retentionLimit = 32

    struct TransactionObservation: Sendable {
        fileprivate let sequence: UInt64
        fileprivate let transaction: StoreSubscriptionTransaction
        fileprivate let restoreEpoch: UInt64?
    }

    private enum RestoreOutcome: Equatable {
        case succeeded
        case failed
    }

    private let productIDs: Set<String>
    private let analytics: (any AnalyticsServiceProtocol)?
    private let userDefaults: UserDefaults
    private var nextObservationSequence: UInt64 = 0
    private var nextRestoreEpoch: UInt64 = 0
    private var activeRestoreEpoch: UInt64?
    private var inFlightObservations: [UInt64: TransactionObservation] = [:]
    private var restoreOutcomes: [UInt64: RestoreOutcome] = [:]
    private var deferredRestoreBaselines: [UInt64: StoreSubscriptionTransaction] = [:]
    private var conversionsPendingDuringRestore: [StoreSubscriptionTransaction] = []
    private var retainedPurchaseDates: [String: Date]

    init(
        productIDs: [String],
        analytics: (any AnalyticsServiceProtocol)?,
        userDefaults: UserDefaults
    ) {
        self.productIDs = Set(productIDs)
        self.analytics = analytics
        self.userDefaults = userDefaults
        self.retainedPurchaseDates = Self.persistedPurchaseDates(in: userDefaults)
    }

    func capture(_ update: StoreTransactionUpdate) -> TransactionObservation? {
        guard analytics != nil else { return nil }
        guard case .verified(let transaction) = update else { return nil }

        nextObservationSequence &+= 1
        let observation = TransactionObservation(
            sequence: nextObservationSequence,
            transaction: transaction,
            restoreEpoch: activeRestoreEpoch
        )
        inFlightObservations[observation.sequence] = observation
        return observation
    }

    func observe(_ update: StoreTransactionUpdate, history: [StoreSubscriptionTransaction]) async {
        guard let observation = capture(update) else { return }
        await observe(observation, history: history)
    }

    func observe(
        _ observation: TransactionObservation,
        history: [StoreSubscriptionTransaction]
    ) async {
        guard inFlightObservations.removeValue(forKey: observation.sequence) != nil else { return }
        guard let analytics else { return }

        let transaction = observation.transaction
        let qualifies = Self.isQualifyingConversion(
            transaction,
            history: history,
            productIDs: productIDs
        )
        let deliveredIntoActiveRestore = observation.restoreEpoch == activeRestoreEpoch
            && activeRestoreEpoch != nil
        let completedRestoreOutcome = observation.restoreEpoch.flatMap { restoreOutcomes[$0] }
        let deferredBaseline = deferredRestoreBaselines.removeValue(forKey: transaction.id)
        discardRestoreOutcomeIfFinished(observation.restoreEpoch)

        guard qualifies else {
            if let deferredBaseline {
                retainAsEmitted([deferredBaseline], referenceTransactions: history)
            }
            return
        }

        if deliveredIntoActiveRestore {
            // `AppStore.sync()` can redeliver historical transactions. Hold a qualifying update until
            // the restore outcome is known: successful restore baselines it without telemetry; failed
            // restore releases it through the ordinary live-update path.
            rememberPurchaseDates(
                from: history,
                for: Set(emittedTransactionIDs)
            )
            if !conversionsPendingDuringRestore.contains(where: { $0.id == transaction.id }) {
                conversionsPendingDuringRestore.append(transaction)
            }
            return
        }

        if completedRestoreOutcome == .succeeded {
            retainAsEmitted([transaction], referenceTransactions: history)
            return
        }

        await emitIfNeeded([transaction], referenceTransactions: history, analytics: analytics)
    }

    func beginRestore() {
        nextRestoreEpoch &+= 1
        activeRestoreEpoch = nextRestoreEpoch
        conversionsPendingDuringRestore = []
    }

    func completeRestore(history: [StoreSubscriptionTransaction]) {
        guard let restoreEpoch = activeRestoreEpoch else { return }
        let historicalConversions = history.filter {
            Self.isQualifyingConversion($0, history: history, productIDs: productIDs)
        }
        let independentInFlightTransactionIDs = Set(
            inFlightObservations.values.compactMap {
                $0.restoreEpoch == restoreEpoch ? nil : $0.transaction.id
            }
        )
        let conversionsToBaseline = historicalConversions.filter {
            if independentInFlightTransactionIDs.contains($0.id) {
                deferredRestoreBaselines[$0.id] = $0
                return false
            }
            return true
        }
        let pendingTransactions = conversionsPendingDuringRestore
        retainAsEmitted(
            conversionsToBaseline + pendingTransactions,
            referenceTransactions: history + pendingTransactions
        )
        concludeRestore(restoreEpoch, outcome: .succeeded)
    }

    func failRestore() async {
        guard let restoreEpoch = activeRestoreEpoch else { return }
        let pendingTransactions = conversionsPendingDuringRestore
        concludeRestore(restoreEpoch, outcome: .failed)

        guard let analytics else { return }
        await emitIfNeeded(
            pendingTransactions,
            referenceTransactions: pendingTransactions,
            analytics: analytics
        )
    }

    private func emitIfNeeded(
        _ transactions: [StoreSubscriptionTransaction],
        referenceTransactions: [StoreSubscriptionTransaction],
        analytics: any AnalyticsServiceProtocol
    ) async {
        let orderedTransactions = Self.normalized(transactions)
        let previouslyEmittedIDs = Set(emittedTransactionIDs)
        let newTransactions = orderedTransactions.filter {
            !previouslyEmittedIDs.contains(String($0.id))
        }

        // Persist before handing off to the fire-and-forget analytics boundary. A cancellation or
        // relaunch after this point may lose delivery (the transport owns reliability), but can never
        // turn StoreKit redelivery into a second emission attempt.
        retainAsEmitted(orderedTransactions, referenceTransactions: referenceTransactions)

        for transaction in newTransactions {
            await analytics.record(
                AnalyticsEvent(
                    name: .subscribe,
                    timestampMs: Int(transaction.purchaseDate.timeIntervalSince1970 * 1_000),
                    properties: ["plan": .string(transaction.productID)]
                )
            )
        }
    }

    private func concludeRestore(_ restoreEpoch: UInt64, outcome: RestoreOutcome) {
        activeRestoreEpoch = nil
        conversionsPendingDuringRestore = []
        if inFlightObservations.values.contains(where: { $0.restoreEpoch == restoreEpoch }) {
            restoreOutcomes[restoreEpoch] = outcome
        } else {
            restoreOutcomes.removeValue(forKey: restoreEpoch)
        }
    }

    private func discardRestoreOutcomeIfFinished(_ restoreEpoch: UInt64?) {
        guard let restoreEpoch else { return }
        guard !inFlightObservations.values.contains(where: { $0.restoreEpoch == restoreEpoch }) else { return }
        restoreOutcomes.removeValue(forKey: restoreEpoch)
    }

    private var emittedTransactionIDs: [String] {
        userDefaults.stringArray(forKey: Self.emittedTransactionIDsKey) ?? []
    }

    private func retainAsEmitted(
        _ transactions: [StoreSubscriptionTransaction],
        referenceTransactions: [StoreSubscriptionTransaction]
    ) {
        let orderedTransactions = Self.normalized(transactions)
        let storedIDs = emittedTransactionIDs
        var candidateIDs: [String] = []
        var seenIDs = Set<String>()
        for id in storedIDs + orderedTransactions.map({ String($0.id) }) {
            if seenIDs.insert(id).inserted {
                candidateIDs.append(id)
            }
        }

        let candidateIDSet = Set(candidateIDs)
        rememberPurchaseDates(
            from: referenceTransactions + orderedTransactions,
            for: candidateIDSet
        )

        var storedOrder: [String: Int] = [:]
        for (index, id) in storedIDs.enumerated() where storedOrder[id] == nil {
            storedOrder[id] = index
        }
        candidateIDs.sort {
            retainedID($0, sortsBefore: $1, storedOrder: storedOrder)
        }

        let retainedIDs = Array(candidateIDs.suffix(Self.retentionLimit))
        let retainedIDSet = Set(retainedIDs)
        retainedPurchaseDates = retainedPurchaseDates.filter { retainedIDSet.contains($0.key) }
        userDefaults.set(
            retainedPurchaseDates.mapValues(\.timeIntervalSince1970),
            forKey: Self.emittedTransactionPurchaseDatesKey
        )
        userDefaults.set(retainedIDs, forKey: Self.emittedTransactionIDsKey)
    }

    private static func persistedPurchaseDates(in userDefaults: UserDefaults) -> [String: Date] {
        let retainedIDs = Set(
            userDefaults.stringArray(forKey: Self.emittedTransactionIDsKey) ?? []
        )
        guard let storedDates = userDefaults.dictionary(
            forKey: Self.emittedTransactionPurchaseDatesKey
        ) else { return [:] }

        var result: [String: Date] = [:]
        for (id, value) in storedDates {
            guard retainedIDs.contains(id),
                  let seconds = (value as? NSNumber)?.doubleValue,
                  seconds.isFinite else { continue }
            result[id] = Date(timeIntervalSince1970: seconds)
        }
        return result
    }

    private func rememberPurchaseDates(
        from transactions: [StoreSubscriptionTransaction],
        for transactionIDs: Set<String>
    ) {
        for transaction in transactions {
            let id = String(transaction.id)
            guard transactionIDs.contains(id) else { continue }
            retainedPurchaseDates[id] = min(
                retainedPurchaseDates[id] ?? transaction.purchaseDate,
                transaction.purchaseDate
            )
        }
    }

    private func retainedID(
        _ lhs: String,
        sortsBefore rhs: String,
        storedOrder: [String: Int]
    ) -> Bool {
        switch (retainedPurchaseDates[lhs], retainedPurchaseDates[rhs]) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return Self.transactionID(lhs, sortsBefore: rhs)
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            let lhsIndex = storedOrder[lhs] ?? Int.max
            let rhsIndex = storedOrder[rhs] ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return Self.transactionID(lhs, sortsBefore: rhs)
        }
    }

    private static func transactionID(_ lhs: String, sortsBefore rhs: String) -> Bool {
        if let lhsID = UInt64(lhs), let rhsID = UInt64(rhs), lhsID != rhsID {
            return lhsID < rhsID
        }
        return lhs < rhs
    }

    private static func normalized(
        _ transactions: [StoreSubscriptionTransaction]
    ) -> [StoreSubscriptionTransaction] {
        let orderedTransactions = transactions.sorted {
            if $0.purchaseDate != $1.purchaseDate { return $0.purchaseDate < $1.purchaseDate }
            return $0.id < $1.id
        }
        var seenTransactionIDs = Set<UInt64>()
        return orderedTransactions.filter { seenTransactionIDs.insert($0.id).inserted }
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
              transaction.reason == .renewal,
              transaction.payment == .paid,
              transaction.id != transaction.originalID else {
            return false
        }

        // Include the update itself because `Transaction.all` is a point-in-time snapshot and the
        // update may have arrived just after that snapshot began. Dedup by transaction id before
        // determining the first paid transaction.
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

        let possiblePaidBoundaryTransactions = chain.filter {
            if $0.payment == .paid { return true }
            return $0.payment == .unknown
                && ($0.reason == .purchase || $0.reason == .renewal)
        }
        let firstPossiblePaidBoundaryTransaction = possiblePaidBoundaryTransactions.min {
            if $0.purchaseDate != $1.purchaseDate { return $0.purchaseDate < $1.purchaseDate }
            return $0.id < $1.id
        }
        return firstPossiblePaidBoundaryTransaction?.id == transaction.id
    }
}

extension StoreKitSubscriptionService {
    /// Production wiring: the real StoreKit 2 facade. `mock()` keeps `MockSubscriptionService` so the
    /// suite and previews stay off the App Store and deterministic.
    static func live(analytics: any AnalyticsServiceProtocol) -> StoreKitSubscriptionService {
        StoreKitSubscriptionService(facade: LiveStoreKitFacade(), analytics: analytics)
    }
}
