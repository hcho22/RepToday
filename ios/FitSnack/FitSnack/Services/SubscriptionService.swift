import StoreKit

final class SubscriptionService: SubscriptionServiceProtocol {
    static let monthlyProductId = "com.fitsnack.premium.monthly"
    static let annualProductId = "com.fitsnack.premium.annual"

    private var products: [Product] = []
    private var purchasedProductIDs: Set<String> = []
    private var updateTask: Task<Void, Never>?

    var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func loadProducts() async throws {
        products = try await Product.products(for: [
            Self.monthlyProductId,
            Self.annualProductId,
        ])
        await updatePurchasedProducts()
    }

    func purchase(productId: String) async throws -> Bool {
        guard let product = products.first(where: { $0.id == productId }) else {
            return false
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
                await updatePurchasedProducts()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
