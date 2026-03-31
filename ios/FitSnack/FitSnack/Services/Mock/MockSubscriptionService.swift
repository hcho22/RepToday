import Foundation

final class MockSubscriptionService: SubscriptionServiceProtocol {
    var isPremium: Bool = true // Dev mode: all features unlocked

    func loadProducts() async throws {}
    func purchase(productId: String) async throws -> Bool { true }
    func restorePurchases() async throws {}
}
