import Foundation

/// Errors the subscription layer can surface. Every case is non-fatal to the core loop: the paywall
/// shows a gentle message and the free tier keeps working unlimited, so a StoreKit failure never
/// blocks a workout.
enum SubscriptionError: Error, Equatable {
    /// The store returned no products for the requested ids (offline, misconfigured, or under review).
    case productsUnavailable
    /// A purchase completed but its transaction could not be cryptographically verified.
    case notVerified
    /// Any other StoreKit failure, message attached for logs.
    case failed(String)
}

/// A purchasable product as read from StoreKit, projected to a plain value so the mapping in
/// `StoreKitSubscriptionService` is unit-testable without a live store.
struct StoreProduct: Equatable {
    let id: String
    let displayPrice: String
    let period: SubscriptionPlan.Period
    /// A free-trial phrase (e.g. "14-day free trial") when the product carries an introductory
    /// free-trial offer, else `nil`.
    let trialDescription: String?
}

/// An active premium entitlement as read from StoreKit's verified current entitlements, projected to
/// a plain value. Only non-revoked, unexpired entitlements are surfaced by the facade.
struct StoreEntitlement: Equatable {
    let productID: String
    /// When the entitlement lapses (auto-renewable expiry), or `nil` if it does not expire.
    let expiresAt: Date?
    /// Whether the user is currently inside the introductory free-trial window.
    let isInTrialPeriod: Bool
}

/// The outcome of a purchase attempt, independent of StoreKit's `Product.PurchaseResult`.
enum StorePurchaseResult: Equatable {
    /// The purchase completed and was verified; carries the resulting current entitlements.
    case success([StoreEntitlement])
    /// The user dismissed the purchase sheet - not an error.
    case userCancelled
    /// The purchase is pending external action (e.g. Ask to Buy approval).
    case pending
}

/// Seam over the StoreKit 2 ceremony.
///
/// The real StoreKit calls (`Product.products`, `Transaction.currentEntitlements`,
/// `product.purchase()`, `AppStore.sync()`) touch the App Store and cannot run in a unit test, so
/// they live behind this boundary. `StoreKitSubscriptionService` composes it and maps the plain
/// values here into the app's `Subscription`/`SubscriptionPlan` domain; tests inject a stub that
/// returns canned products, entitlements, and purchase results.
protocol StoreKitFacade: Sendable {
    /// Load the premium products for the given ids, for the paywall to price.
    func loadProducts(ids: [String]) async throws -> [StoreProduct]
    /// The user's current verified premium entitlements (empty for a free user). A read, never a
    /// prompt, so it is safe and cheap to call on demand.
    func currentEntitlements() async -> [StoreEntitlement]
    /// Run the purchase flow for a product id.
    func purchase(productID: String) async throws -> StorePurchaseResult
    /// Sync with the App Store to restore purchases across devices/reinstalls.
    func sync() async throws
}
