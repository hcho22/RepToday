import Foundation
import StoreKit

private actor StoreTransactionProcessingQueue {
    private var pending: [StoreTransactionProcessing] = []
    private var nextWaiter: CheckedContinuation<StoreTransactionProcessing?, Never>?
    private var acceptsWork = true

    func enqueue(_ processing: StoreTransactionProcessing) -> Bool {
        guard acceptsWork else { return false }
        if let nextWaiter {
            self.nextWaiter = nil
            nextWaiter.resume(returning: processing)
        } else {
            pending.append(processing)
        }
        return true
    }

    func next() async -> StoreTransactionProcessing? {
        if !pending.isEmpty {
            return pending.removeFirst()
        }
        guard acceptsWork else { return nil }
        return await withCheckedContinuation { nextWaiter = $0 }
    }

    func finish() {
        acceptsWork = false
        let nextWaiter = self.nextWaiter
        self.nextWaiter = nil
        nextWaiter?.resume(returning: nil)
    }

    func cancel() async {
        acceptsWork = false
        let abandoned = pending
        pending = []
        let nextWaiter = self.nextWaiter
        self.nextWaiter = nil
        for processing in abandoned {
            await processing.dispose()
        }
        nextWaiter?.resume(returning: nil)
    }
}

/// Production `StoreKitFacade`: drives the real StoreKit 2 API and projects its types into the plain
/// values the service maps. Stateless and `Sendable`.
///
/// Notes on correctness:
/// - Only **verified** transactions count. An unverified purchase result throws `notVerified`; an
///   unverified entitlement in `currentEntitlements` is skipped, so a jailbroken/forged receipt never
///   grants premium.
/// - Finished transactions are acknowledged with `transaction.finish()` so StoreKit stops re-delivering
///   them.
/// - Reads never prompt: `currentEntitlements()` is a cheap local read of StoreKit's cached state.
final class LiveStoreKitFacade: StoreKitFacade {

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        do {
            let products = try await Product.products(for: ids)
            return products.compactMap(Self.storeProduct(from:))
        } catch {
            throw SubscriptionError.failed(error.localizedDescription)
        }
    }

    func currentEntitlements() async -> [StoreEntitlement] {
        var result: [StoreEntitlement] = []
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            if let entitlement = Self.entitlement(from: transaction) {
                result.append(entitlement)
            }
        }
        return result
    }

    func purchase(productID: String) async throws -> StorePurchaseResult {
        let products: [Product]
        do {
            products = try await Product.products(for: [productID])
        } catch {
            throw SubscriptionError.failed(error.localizedDescription)
        }
        guard let product = products.first else { throw SubscriptionError.productsUnavailable }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw SubscriptionError.failed(error.localizedDescription)
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SubscriptionError.notVerified
            }
            await transaction.finish()
            // Trust the just-verified transaction as the authoritative source of the grant and merge it
            // into the current-entitlements read: StoreKit's cached `currentEntitlements` can briefly lag
            // a just-completed purchase (a documented first-purchase timing quirk), and relying on it
            // alone would resolve a paying buyer to `.free` - indistinguishable from a silent cancel.
            let entitlements = await currentEntitlements()
            return .success(Self.merged(entitlements, with: Self.entitlement(from: transaction)))
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func sync() async throws {
        do {
            try await AppStore.sync()
        } catch {
            throw SubscriptionError.failed(error.localizedDescription)
        }
    }

    func transactionHistory() async -> StoreTransactionHistory {
        var result: [StoreSubscriptionTransaction] = []
        var containsUnverifiedTransactions = false
        for await verification in Transaction.all {
            switch verification {
            case .verified(let transaction):
                result.append(Self.subscriptionTransaction(from: transaction))
            case .unverified:
                containsUnverifiedTransactions = true
            }
        }
        return StoreTransactionHistory(
            transactions: result,
            containsUnverifiedTransactions: containsUnverifiedTransactions
        )
    }

    func listenForTransactions(
        prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
    ) -> Task<Void, Never> {
        // StoreKit 2 delivers transactions that happen outside a direct `purchase()` - auto-renewals,
        // refunds, cross-device purchases, and deferred Ask-to-Buy approvals - only through
        // `Transaction.updates`. Project every result and let the service capture its delivery order,
        // then finish every verified update before queueing its inspection: analytics can never delay
        // transaction acknowledgement. The task remains the app-owned lifetime handle; cancelling it
        // stops the sequence and its owned processing worker.
        Task.detached(priority: .background) {
            await Self.processUpdates(
                Transaction.updates,
                project: { verification in
                    guard case .verified(let transaction) = verification else {
                        return .unverified
                    }
                    return StoreTransactionUpdate.verified(
                        Self.subscriptionTransaction(from: transaction)
                    )
                },
                acknowledge: { verification in
                    guard case .verified(let transaction) = verification else { return }
                    await transaction.finish()
                },
                prepareUpdate: prepareUpdate
            )
        }
    }

    static func processUpdates<Updates: AsyncSequence>(
        _ updates: Updates,
        project: (Updates.Element) -> StoreTransactionUpdate,
        acknowledge: (Updates.Element) async -> Void,
        prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
    ) async {
        let processingQueue = StoreTransactionProcessingQueue()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    while let processing = await processingQueue.next() {
                        guard !Task.isCancelled else {
                            await processing.dispose()
                            await processingQueue.cancel()
                            return
                        }
                        await withTaskCancellationHandler {
                            await processing()
                        } onCancel: {
                            Task { await processing.dispose() }
                        }
                        if Task.isCancelled {
                            await processing.dispose()
                            await processingQueue.cancel()
                            return
                        }
                    }
                } onCancel: {
                    Task { await processingQueue.cancel() }
                }
            }

            do {
                for try await element in updates {
                    guard !Task.isCancelled else { break }
                    let update = project(element)
                    let processing = await prepareUpdate(update)
                    await acknowledge(element)
                    guard !Task.isCancelled else {
                        await processing?.dispose()
                        break
                    }
                    if let processing,
                       !(await processingQueue.enqueue(processing)) {
                        await processing.dispose()
                    }
                }
            } catch {
                if Task.isCancelled {
                    await processingQueue.cancel()
                } else {
                    await processingQueue.finish()
                }
                return
            }
            if Task.isCancelled {
                await processingQueue.cancel()
            } else {
                await processingQueue.finish()
            }
        }
    }

    // MARK: - Mapping

    /// Project a verified transaction into a premium `StoreEntitlement`, or `nil` when it does not grant
    /// premium (not auto-renewable, revoked, or lapsed). The single mapping rule both `currentEntitlements`
    /// and the purchase-success merge share, so a just-purchased transaction is graded exactly like a
    /// cached entitlement.
    private static func entitlement(from transaction: Transaction) -> StoreEntitlement? {
        guard transaction.productType == .autoRenewable else { return nil }
        guard transaction.revocationDate == nil else { return nil }
        if let expiry = transaction.expirationDate, expiry <= Date() { return nil }
        return StoreEntitlement(
            productID: transaction.productID,
            expiresAt: transaction.expirationDate,
            isInTrialPeriod: isInTrial(transaction)
        )
    }

    private static func subscriptionTransaction(from transaction: Transaction) -> StoreSubscriptionTransaction {
        let reason: StoreSubscriptionTransaction.Reason
        if transaction.reason == .purchase {
            reason = .purchase
        } else if transaction.reason == .renewal {
            reason = .renewal
        } else {
            reason = .other
        }

        return StoreSubscriptionTransaction(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            reason: reason,
            payment: payment(for: transaction),
            isAutoRenewable: transaction.productType == .autoRenewable,
            isPurchased: transaction.ownershipType == .purchased,
            isRevoked: transaction.revocationDate != nil,
            isUpgraded: transaction.isUpgraded
        )
    }

    /// Union `fresh` into `entitlements`, de-duplicated by `productID` so a just-purchased entitlement is
    /// always present even when the current-entitlements read lags. When both carry the same product, the
    /// later-expiring one wins; ordering is otherwise preserved. `nil` (the transaction did not grant
    /// premium) is a pass-through. Pure, so it is unit-testable without a live store.
    static func merged(_ entitlements: [StoreEntitlement], with fresh: StoreEntitlement?) -> [StoreEntitlement] {
        guard let fresh else { return entitlements }
        if let index = entitlements.firstIndex(where: { $0.productID == fresh.productID }) {
            var result = entitlements
            result[index] = laterExpiring(entitlements[index], fresh)
            return result
        }
        return entitlements + [fresh]
    }

    private static func laterExpiring(_ lhs: StoreEntitlement, _ rhs: StoreEntitlement) -> StoreEntitlement {
        (lhs.expiresAt ?? .distantFuture) >= (rhs.expiresAt ?? .distantFuture) ? lhs : rhs
    }

    private static func storeProduct(from product: Product) -> StoreProduct? {
        guard let subscription = product.subscription else { return nil }
        let period: SubscriptionPlan.Period = subscription.subscriptionPeriod.unit == .year ? .yearly : .monthly
        return StoreProduct(
            id: product.id,
            displayPrice: product.displayPrice,
            period: period,
            trialDescription: trialDescription(for: subscription.introductoryOffer)
        )
    }

    /// A friendly free-trial phrase from an introductory offer, or `nil` when the offer is not a free
    /// trial. Weeks are rendered in days so a 2-week intro reads as "14-day free trial".
    private static func trialDescription(for offer: Product.SubscriptionOffer?) -> String? {
        guard let offer, offer.paymentMode == .freeTrial else { return nil }
        let value = offer.period.value
        switch offer.period.unit {
        case .day: return "\(value)-day free trial"
        case .week: return "\(value * 7)-day free trial"
        case .month: return "\(value)-month free trial"
        case .year: return "\(value)-year free trial"
        @unknown default: return "Free trial"
        }
    }

    /// Whether a transaction is an introductory **free-trial** period. Introductory pay-as-you-go
    /// and pay-up-front offers are paid periods and must not emit `trial_started` or seed a later
    /// trial-conversion event.
    private static func isInTrial(_ transaction: Transaction) -> Bool {
        payment(for: transaction) == .introductoryFreeTrial
    }

    private static func payment(for transaction: Transaction) -> StoreSubscriptionTransaction.Payment {
        if #available(iOS 17.2, *) {
            if transaction.offer?.type == .introductory,
               transaction.offer?.paymentMode == .freeTrial {
                return .introductoryFreeTrial
            }
        } else {
            // `Transaction.Offer` arrived in iOS 17.2. On 17.0/17.1 the deprecated offer API exposes
            // the introductory type but not a typed payment mode; StoreKit's signed price separates a
            // genuinely free period (zero) from pay-as-you-go/pay-up-front introductory offers.
            if transaction.offerType == .introductory, transaction.price == 0 {
                return .introductoryFreeTrial
            }
        }

        if let price = transaction.price {
            if price > 0 { return .paid }
            if price == 0 { return .nonPaid }
        }
        return .unknown
    }
}
