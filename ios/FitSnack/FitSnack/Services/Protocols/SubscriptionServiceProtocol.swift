import Foundation

protocol SubscriptionServiceProtocol {
    var isPremium: Bool { get }
    func loadProducts() async throws
    func purchase(productId: String) async throws -> Bool
    func restorePurchases() async throws
}
