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
    private let restoreGate: RestoreOperationGate

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
        self.restoreGate = RestoreOperationGate()
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
        await restoreGate.acquire()
        do {
            let subscription = try await performRestore()
            await restoreGate.release()
            return subscription
        } catch {
            await restoreGate.release()
            throw error
        }
    }

    private func performRestore() async throws -> Subscription {
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
            let history = await facade.transactionHistory()
            await trialConversionObserver.failRestore(history: history)
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
            return StoreTransactionProcessing(
                operation: {
                    let history = await facade.transactionHistory()
                    await observer.observe(observation, history: history)
                },
                disposal: {
                    await observer.discard(observation)
                }
            )
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

private actor RestoreOperationGate {
    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            isAcquired = false
            return
        }
        waiters.removeFirst().resume()
    }
}

/// Detects the one billed boundary in an introductory-free-trial subscription chain.
///
/// This actor is intentionally independent of entitlement/UI state. It emits only when a verified
/// `Transaction.updates` value is itself the first positive-price renewal in a history whose original
/// purchase is explicitly a free trial. A foreground, restore, current-entitlement read, direct paid
/// purchase, later renewal, pending purchase, revoked transaction, or unverified result cannot satisfy
/// that predicate. A revoked first-paid period still blocks a later renewal from being misclassified
/// as the conversion boundary.
///
/// Dedup is durable and minimal: qualifying conversion transaction ids and their signed purchase
/// instants are persisted, never a receipt, product, price, or transaction history. The timestamps are
/// bounded ordering metadata for retaining the newest 32 ids across relaunches and App Store account
/// changes; the oldest is replaced on the 33rd distinct conversion. Legacy id-only entries preserve
/// their durable relative order until signed dates make them comparable.
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

    private enum RestoreWaitResolution: Equatable {
        case finalized
        case cancelled
    }

    private struct CompletedRestore {
        let outcome: RestoreOutcome
        let history: StoreTransactionHistory
        let independentTransactionIDs: Set<UInt64>
    }

    private struct RestoreFinalization {
        let history: StoreTransactionHistory
        let independentTransactionIDs: Set<UInt64>
        let pendingTransactions: [StoreSubscriptionTransaction]
    }

    private let productIDs: Set<String>
    private let analytics: (any AnalyticsServiceProtocol)?
    private let userDefaults: UserDefaults
    private var nextObservationSequence: UInt64 = 0
    private var nextRestoreEpoch: UInt64 = 0
    private var activeRestoreEpoch: UInt64?
    private var inFlightObservations: [UInt64: TransactionObservation] = [:]
    private var completedRestores: [UInt64: CompletedRestore] = [:]
    private var terminalHistoriesByObservationSequence: [UInt64: StoreTransactionHistory] = [:]
    private var restoreFinalizationWaiters: [
        UInt64: [CheckedContinuation<RestoreWaitResolution, Never>]
    ] = [:]
    private var deferredRestoreBaselines: [UInt64: StoreSubscriptionTransaction] = [:]
    private var restoreCandidates: [UInt64: StoreSubscriptionTransaction] = [:]
    private var restoreCandidateHistories: [UInt64: StoreTransactionHistory] = [:]
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
        if observation.restoreEpoch != nil {
            restoreCandidates[observation.sequence] = transaction
        }
        return observation
    }

    func discard(_ observation: TransactionObservation) {
        cancelObservation(observation.sequence)
    }

    func observe(_ update: StoreTransactionUpdate, history: [StoreSubscriptionTransaction]) async {
        await observe(update, history: .verified(history))
    }

    func observe(_ update: StoreTransactionUpdate, history: StoreTransactionHistory) async {
        guard let observation = capture(update) else { return }
        await observe(observation, history: history)
    }

    func observe(
        _ observation: TransactionObservation,
        history: [StoreSubscriptionTransaction]
    ) async {
        await observe(observation, history: .verified(history))
    }

    func observe(
        _ observation: TransactionObservation,
        history: StoreTransactionHistory
    ) async {
        guard inFlightObservations[observation.sequence] != nil else { return }
        while let restoreEpoch = activeRestoreEpoch,
              observation.restoreEpoch != restoreEpoch {
            guard await waitForRestoreFinalization(observation) else { return }
        }
        guard !Task.isCancelled else {
            cancelObservation(observation.sequence)
            return
        }
        guard inFlightObservations.removeValue(forKey: observation.sequence) != nil else { return }
        guard let analytics else { return }

        let transaction = observation.transaction
        let deliveredIntoActiveRestore = observation.restoreEpoch == activeRestoreEpoch
            && activeRestoreEpoch != nil
        if deliveredIntoActiveRestore {
            restoreCandidateHistories[observation.sequence] = history
            rememberPurchaseDates(
                from: history.transactions,
                for: Set(emittedTransactionIDs)
            )
            return
        }

        let terminalHistory = terminalHistoriesByObservationSequence.removeValue(
            forKey: observation.sequence
        )
        let completedRestore = observation.restoreEpoch.flatMap { completedRestores[$0] }
        let yieldsToIndependentObservation = completedRestore?.independentTransactionIDs
            .contains(transaction.id) == true
        let classificationHistory = Self.mergedHistory(
            [completedRestore?.history, terminalHistory, history].compactMap { $0 }
        )
        let qualifies = Self.isQualifyingConversion(
            transaction,
            history: classificationHistory,
            productIDs: productIDs
        )
        let deferredBaseline = yieldsToIndependentObservation
            ? nil
            : deferredRestoreBaselines.removeValue(forKey: transaction.id)
        discardCompletedRestoreIfFinished(observation.restoreEpoch)

        guard !yieldsToIndependentObservation else { return }

        guard qualifies else {
            if let deferredBaseline {
                retainAsEmitted(
                    [deferredBaseline],
                    referenceTransactions: classificationHistory.transactions
                )
            }
            return
        }

        if completedRestore?.outcome == .succeeded {
            retainAsEmitted(
                [transaction],
                referenceTransactions: classificationHistory.transactions
            )
            return
        }

        await emitIfNeeded(
            [transaction],
            referenceTransactions: classificationHistory.transactions,
            analytics: analytics
        )
    }

    private func waitForRestoreFinalization(_ observation: TransactionObservation) async -> Bool {
        let sequence = observation.sequence
        let resolution = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<RestoreWaitResolution, Never>) in
                guard !Task.isCancelled,
                      inFlightObservations[sequence] != nil,
                      let restoreEpoch = activeRestoreEpoch,
                      observation.restoreEpoch != restoreEpoch else {
                    let resolution: RestoreWaitResolution = Task.isCancelled
                        ? .cancelled
                        : .finalized
                    continuation.resume(returning: resolution)
                    return
                }
                restoreFinalizationWaiters[sequence, default: []].append(continuation)
            }
        } onCancel: {
            Task { await self.cancelObservation(sequence) }
        }

        guard resolution == .finalized, !Task.isCancelled else {
            cancelObservation(sequence)
            return false
        }
        return inFlightObservations[sequence] != nil
    }

    private func cancelObservation(_ sequence: UInt64) {
        let observation = inFlightObservations.removeValue(forKey: sequence)
        restoreCandidates.removeValue(forKey: sequence)
        restoreCandidateHistories.removeValue(forKey: sequence)
        let terminalHistory = terminalHistoriesByObservationSequence.removeValue(forKey: sequence)
        if let observation,
           let deferredBaseline = deferredRestoreBaselines.removeValue(
               forKey: observation.transaction.id
           ) {
            retainAsEmitted(
                [deferredBaseline],
                referenceTransactions: terminalHistory?.transactions ?? [deferredBaseline]
            )
        }
        discardCompletedRestoreIfFinished(observation?.restoreEpoch)

        let continuations = restoreFinalizationWaiters.removeValue(forKey: sequence) ?? []
        continuations.forEach { $0.resume(returning: .cancelled) }
    }

    func beginRestore() {
        nextRestoreEpoch &+= 1
        activeRestoreEpoch = nextRestoreEpoch
        restoreCandidates = [:]
        restoreCandidateHistories = [:]
    }

    func completeRestore(history: [StoreSubscriptionTransaction]) {
        completeRestore(history: .verified(history))
    }

    func completeRestore(history: StoreTransactionHistory) {
        guard let restoreEpoch = activeRestoreEpoch else { return }
        let finalization = restoreFinalization(
            restoreEpoch: restoreEpoch,
            history: history
        )
        let classificationHistory = finalization.history
        let historicalConversions = classificationHistory.transactions.filter {
            Self.isQualifyingConversion(
                $0,
                history: classificationHistory,
                productIDs: productIDs
            )
        }
        let conversionsToBaseline = historicalConversions.filter {
            if finalization.independentTransactionIDs.contains($0.id) {
                deferredRestoreBaselines[$0.id] = $0
                return false
            }
            return true
        }
        retainAsEmitted(
            conversionsToBaseline + finalization.pendingTransactions,
            referenceTransactions: classificationHistory.transactions
        )
        concludeRestore(
            restoreEpoch,
            outcome: .succeeded,
            history: classificationHistory,
            independentTransactionIDs: finalization.independentTransactionIDs
        )
    }

    func failRestore(history: StoreTransactionHistory) async {
        guard let restoreEpoch = activeRestoreEpoch else { return }
        let finalization = restoreFinalization(
            restoreEpoch: restoreEpoch,
            history: history
        )
        concludeRestore(
            restoreEpoch,
            outcome: .failed,
            history: finalization.history,
            independentTransactionIDs: finalization.independentTransactionIDs
        )

        guard let analytics else { return }
        await emitIfNeeded(
            finalization.pendingTransactions,
            referenceTransactions: finalization.history.transactions,
            analytics: analytics
        )
    }

    private func restoreFinalization(
        restoreEpoch: UInt64,
        history: StoreTransactionHistory
    ) -> RestoreFinalization {
        let observations = inFlightObservations.values.sorted { $0.sequence < $1.sequence }
        let independentObservations = observations.filter { $0.restoreEpoch != restoreEpoch }
        let independentTransactionIDs = Set(independentObservations.map(\.transaction.id))
        let inFlightRestoreTransactionIDs = Set(
            observations.compactMap {
                $0.restoreEpoch == restoreEpoch ? $0.transaction.id : nil
            }
        )
        let restoreCandidateSequences = restoreCandidates.keys.sorted()
        let candidateTransactions = restoreCandidateSequences.compactMap {
            restoreCandidates[$0]
        }
        let candidateHistories = restoreCandidateSequences.compactMap {
            restoreCandidateHistories[$0]
        }
        let capturedTransactions = StoreTransactionHistory(
            transactions: observations.map(\.transaction) + candidateTransactions,
            containsUnverifiedTransactions: false
        )
        let classificationHistory = Self.mergedHistory(
            [capturedTransactions] + candidateHistories + [history]
        )
        for observation in independentObservations {
            terminalHistoriesByObservationSequence[observation.sequence] = classificationHistory
        }

        let candidateTransactionIDs = Set(restoreCandidates.values.map(\.id))
        let pendingTransactions = classificationHistory.transactions.filter {
            candidateTransactionIDs.contains($0.id)
                && !independentTransactionIDs.contains($0.id)
                && !inFlightRestoreTransactionIDs.contains($0.id)
                && Self.isQualifyingConversion(
                    $0,
                    history: classificationHistory,
                    productIDs: productIDs
                )
        }
        return RestoreFinalization(
            history: classificationHistory,
            independentTransactionIDs: independentTransactionIDs,
            pendingTransactions: pendingTransactions
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

        // Persist before handing off to the synchronous analytics acceptance boundary. This makes
        // StoreKit redelivery at-most-one emission attempt; once accepted, durable delivery and retry
        // belong to the analytics service, while consent or missing configuration may still discard it.
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

    private func concludeRestore(
        _ restoreEpoch: UInt64,
        outcome: RestoreOutcome,
        history: StoreTransactionHistory,
        independentTransactionIDs: Set<UInt64>
    ) {
        activeRestoreEpoch = nil
        restoreCandidates = [:]
        restoreCandidateHistories = [:]
        if inFlightObservations.values.contains(where: { $0.restoreEpoch == restoreEpoch }) {
            completedRestores[restoreEpoch] = CompletedRestore(
                outcome: outcome,
                history: history,
                independentTransactionIDs: independentTransactionIDs
            )
        } else {
            completedRestores.removeValue(forKey: restoreEpoch)
        }
        for sequence in restoreFinalizationWaiters.keys.sorted() {
            let continuations = restoreFinalizationWaiters.removeValue(forKey: sequence) ?? []
            continuations.forEach { $0.resume(returning: .finalized) }
        }
    }

    private func discardCompletedRestoreIfFinished(_ restoreEpoch: UInt64?) {
        guard let restoreEpoch else { return }
        guard !inFlightObservations.values.contains(where: { $0.restoreEpoch == restoreEpoch }) else { return }
        completedRestores.removeValue(forKey: restoreEpoch)
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

        var retentionOrder = candidateIDs
        let datedIDs = retentionOrder.filter { retainedPurchaseDates[$0] != nil }.sorted {
            let lhsDate = retainedPurchaseDates[$0] ?? .distantPast
            let rhsDate = retainedPurchaseDates[$1] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return Self.transactionID($0, sortsBefore: $1)
        }
        var datedIndex = 0
        for index in retentionOrder.indices where retainedPurchaseDates[retentionOrder[index]] != nil {
            retentionOrder[index] = datedIDs[datedIndex]
            datedIndex += 1
        }

        let selectedIDs = Array(retentionOrder.suffix(Self.retentionLimit))
        let selectedIDSet = Set(selectedIDs)
        let retainedIDs = candidateIDs.allSatisfy { retainedPurchaseDates[$0] != nil }
            ? selectedIDs
            : candidateIDs.filter { selectedIDSet.contains($0) }
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

    private static func mergedTransactions(
        _ transactions: [StoreSubscriptionTransaction]
    ) -> [StoreSubscriptionTransaction] {
        var transactionIDs: [UInt64] = []
        var transactionsByID: [UInt64: StoreSubscriptionTransaction] = [:]
        for transaction in transactions {
            if transactionsByID[transaction.id] == nil {
                transactionIDs.append(transaction.id)
            }
            if transactionsByID[transaction.id]?.isRevoked == true {
                continue
            }
            transactionsByID[transaction.id] = transaction
        }
        return transactionIDs.compactMap { transactionsByID[$0] }
    }

    private static func mergedHistory(
        _ histories: [StoreTransactionHistory]
    ) -> StoreTransactionHistory {
        StoreTransactionHistory(
            transactions: mergedTransactions(histories.flatMap(\.transactions)),
            containsUnverifiedTransactions: histories.contains(
                where: \.containsUnverifiedTransactions
            )
        )
    }

    static func isQualifyingConversion(
        _ transaction: StoreSubscriptionTransaction,
        history: StoreTransactionHistory,
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
        guard !history.containsUnverifiedTransactions else { return false }

        var historyByID: [UInt64: StoreSubscriptionTransaction] = [:]
        for historicalTransaction in history.transactions {
            if historyByID[historicalTransaction.id]?.isRevoked == true {
                continue
            }
            historyByID[historicalTransaction.id] = historicalTransaction
        }
        if historyByID[transaction.id] == nil {
            historyByID[transaction.id] = transaction
        }
        guard historyByID[transaction.id]?.isRevoked == false else { return false }
        let chain = historyByID.values.filter {
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
