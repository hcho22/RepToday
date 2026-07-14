import Foundation

/// A purchasable premium plan, as the paywall (US-N04) renders it.
///
/// This is the presentation-facing projection of a StoreKit `Product` - just the id, a localized
/// price string, the billing period, and any introductory free-trial description - so the paywall
/// view never touches StoreKit types directly and previews/tests can build plans by hand. The real
/// values are resolved from StoreKit by `StoreKitSubscriptionService`; the mock supplies the same
/// sample plans so the paywall renders identically offline.
struct SubscriptionPlan: Identifiable, Equatable, Hashable {

    /// The billing cadence, used to order and label plans (monthly first, then yearly).
    enum Period: String, Equatable, Hashable {
        case monthly
        case yearly

        /// Short suffix for the price line, e.g. "$7.99 / month".
        var perUnitLabel: String {
            switch self {
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }

        /// Display name for the plan, e.g. "Monthly".
        var displayName: String {
            switch self {
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
    }

    /// The StoreKit product id this plan purchases.
    let id: String
    /// Localized price for the whole period, e.g. "$7.99" or "$59.99".
    let displayPrice: String
    let period: Period
    /// A human-readable free-trial phrase (e.g. "14-day free trial"), or `nil` when the plan has no
    /// introductory offer. Naming it here keeps the paywall honest - the badge only shows when the
    /// underlying product actually carries a trial.
    let trialDescription: String?

    /// The price line the paywall shows, e.g. "$7.99 / month".
    var priceLine: String { "\(displayPrice) / \(period.perUnitLabel)" }

    /// The canonical FitSnack premium product ids. The `.storekit` configuration and the App Store
    /// Connect products must use exactly these.
    enum ProductID {
        static let monthly = "com.fitsnack.app.premium.monthly"
        static let yearly = "com.fitsnack.app.premium.yearly"
        static let all = [monthly, yearly]
    }

    /// Ordering for display: monthly before yearly, then by id for determinism.
    static func displayOrder(_ lhs: SubscriptionPlan, _ rhs: SubscriptionPlan) -> Bool {
        if lhs.period != rhs.period { return lhs.period == .monthly }
        return lhs.id < rhs.id
    }

    /// Sample plans matching the seeded `.storekit` prices, used by the mock service and previews so
    /// the paywall renders without a live StoreKit environment.
    static let samples: [SubscriptionPlan] = [
        SubscriptionPlan(
            id: ProductID.monthly,
            displayPrice: "$7.99",
            period: .monthly,
            trialDescription: "14-day free trial"
        ),
        SubscriptionPlan(
            id: ProductID.yearly,
            displayPrice: "$59.99",
            period: .yearly,
            trialDescription: nil
        ),
    ]
}
