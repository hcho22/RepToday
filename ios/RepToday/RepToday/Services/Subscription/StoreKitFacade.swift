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

/// The StoreKit facts needed to recognize a free-trial conversion without carrying StoreKit types
/// across the test seam.
///
/// Every value comes from a verified, App Store-signed `Transaction`. `purchaseDate` is the signed
/// transaction instant, not a wall-clock estimate of when a trial should have ended. The service
/// compares transactions sharing `originalID` to prove that an update is the first paid renewal of
/// a chain whose original purchase was an introductory free trial.
struct StoreSubscriptionTransaction: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case purchase
        case renewal
        case other
    }

    enum Payment: Equatable, Sendable {
        /// An introductory offer whose payment mode is explicitly free-trial (or, on iOS 17.0/17.1,
        /// an introductory transaction whose StoreKit-recorded price is zero).
        case introductoryFreeTrial
        /// StoreKit recorded a zero price outside the introductory free-trial period.
        case nonPaid
        /// StoreKit recorded a price greater than zero for this transaction.
        case paid
        /// No price/offer combination proves either state. A candidate is ineligible, and an earlier
        /// purchased chain row with this value blocks inferring that a later renewal is first-paid.
        case unknown
    }

    let id: UInt64
    let originalID: UInt64
    let productID: String
    let purchaseDate: Date
    let reason: Reason
    let payment: Payment
    let isAutoRenewable: Bool
    let isPurchased: Bool
    let isRevoked: Bool
    let isUpgraded: Bool
}

/// A finite StoreKit history snapshot and whether any rows in that snapshot failed verification.
/// The integrity flag prevents a partial verified projection from proving a first-paid boundary.
struct StoreTransactionHistory: Equatable, Sendable {
    let transactions: [StoreSubscriptionTransaction]
    let containsUnverifiedTransactions: Bool

    static func verified(_ transactions: [StoreSubscriptionTransaction]) -> StoreTransactionHistory {
        StoreTransactionHistory(
            transactions: transactions,
            containsUnverifiedTransactions: false
        )
    }
}

/// A listener value keeps verification explicit at the service boundary. Production only constructs
/// `.verified` from StoreKit's successful cryptographic verification; tests can prove that an
/// unverified update is inert without manufacturing a StoreKit signature.
enum StoreTransactionUpdate: Equatable, Sendable {
    case verified(StoreSubscriptionTransaction)
    case unverified
}

typealias StoreTransactionProcessing = @Sendable () async -> Void

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
/// `Transaction.all`, `Transaction.updates`, `product.purchase()`, `AppStore.sync()`) touch the App
/// Store and cannot run in a unit test, so
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
    /// A finite snapshot of the customer's transaction history. Verified rows carry the signed facts
    /// used to prove a trial -> first paid renewal transition; the integrity flag records whether the
    /// snapshot also contained an unverified row that makes that boundary unprovable.
    func transactionHistory() async -> StoreTransactionHistory
    /// Begin observing StoreKit's out-of-band `Transaction.updates` (auto-renewals, refunds,
    /// cross-device purchases, deferred Ask-to-Buy approvals), asking `prepareUpdate` to capture each
    /// delivery in order before acknowledging verified updates with `finish()`. The returned processing
    /// work begins after acknowledgement and runs under the listener's ownership without delaying the
    /// next update. Returns the listener task for the caller to retain for the app's lifetime; cancelling
    /// that task cancels the sequence and its processing. A StoreKit-free implementation returns a no-op
    /// task.
    func listenForTransactions(
        prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
    ) -> Task<Void, Never>
}
