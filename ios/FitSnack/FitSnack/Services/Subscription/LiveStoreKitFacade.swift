import Foundation
import StoreKit

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
            guard transaction.productType == .autoRenewable else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            result.append(
                StoreEntitlement(
                    productID: transaction.productID,
                    expiresAt: transaction.expirationDate,
                    isInTrialPeriod: Self.isInTrial(transaction)
                )
            )
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
            return .success(await currentEntitlements())
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

    func listenForTransactions() -> Task<Void, Never> {
        // StoreKit 2 delivers transactions that happen outside a direct `purchase()` - auto-renewals,
        // refunds, cross-device purchases, and deferred Ask-to-Buy approvals - only through
        // `Transaction.updates`. Finish each verified update so it is acknowledged and never lingers
        // unfinished; the entitlement-gated surfaces re-read `currentEntitlements()` on their next open.
        Task.detached {
            for await verification in Transaction.updates {
                guard case .verified(let transaction) = verification else { continue }
                await transaction.finish()
            }
        }
    }

    // MARK: - Mapping

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

    /// Whether a transaction is currently inside its introductory free-trial window.
    private static func isInTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        } else {
            return transaction.offerType == .introductory
        }
    }
}
