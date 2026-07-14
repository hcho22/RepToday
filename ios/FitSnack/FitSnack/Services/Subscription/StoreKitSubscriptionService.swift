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
struct StoreKitSubscriptionService: SubscriptionServiceProtocol {

    private let facade: any StoreKitFacade
    private let productIDs: [String]

    init(facade: any StoreKitFacade, productIDs: [String] = SubscriptionPlan.ProductID.all) {
        self.facade = facade
        self.productIDs = productIDs
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
        try await facade.sync()
        return Self.subscription(from: await facade.currentEntitlements())
    }

    @discardableResult
    func startObservingTransactions() -> Task<Void, Never> {
        facade.listenForTransactions()
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

extension StoreKitSubscriptionService {
    /// Production wiring: the real StoreKit 2 facade. `mock()` keeps `MockSubscriptionService` so the
    /// suite and previews stay off the App Store and deterministic.
    static func live() -> StoreKitSubscriptionService {
        StoreKitSubscriptionService(facade: LiveStoreKitFacade())
    }
}
