import Foundation
import Observation

/// Backs the premium paywall (US-N04) - the sheet a free user opens from the Progress tab's upsell.
///
/// It loads the purchasable plans (priced by StoreKit), drives a purchase or a restore, and reflects
/// the resulting entitlement. Nothing here gates the core loop: the paywall is a dismissible sheet, a
/// load/purchase failure surfaces a gentle message (never a wall), and the free tier keeps working
/// unlimited. On a successful unlock `didUnlockPremium` flips so the presenter can dismiss and refresh
/// the US-M02 gate.
///
/// Like the other v6 view models it is `@Observable` and takes its service as a protocol, so previews
/// and tests inject the mock.
@Observable
final class PaywallViewModel {

    /// The purchasable plans, priced and ordered (monthly first). Empty until loaded or when the store
    /// has none available.
    private(set) var plans: [SubscriptionPlan] = []

    /// True while the plans are loading.
    private(set) var isLoading = false

    /// The plan id currently being purchased, or `nil` when idle - lets the view show a spinner on the
    /// tapped plan and disable the others without gating dismissal.
    private(set) var purchasingPlanID: String?

    /// True while a restore is in flight.
    private(set) var isRestoring = false

    /// True once a purchase or restore has granted premium. The presenter observes this to dismiss and
    /// refresh the entitlement-gated surfaces.
    private(set) var didUnlockPremium = false

    /// A gentle, user-facing message when a load/purchase/restore fails or a restore finds nothing.
    /// Never a blocking error - the sheet stays dismissible and the free tier is unaffected.
    private(set) var message: String?

    /// Whether any purchase/restore is currently in flight (drives disabling the plan buttons).
    var isBusy: Bool { purchasingPlanID != nil || isRestoring }

    private let subscriptionService: any SubscriptionServiceProtocol

    init(subscriptionService: any SubscriptionServiceProtocol) {
        self.subscriptionService = subscriptionService
    }

    /// Load the purchasable plans. Idempotent - safe to call on every appear.
    func load() async {
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            plans = try await subscriptionService.premiumPlans()
            if plans.isEmpty {
                message = "Plans aren't available right now. Your workouts are always free - try again later."
            }
        } catch {
            plans = []
            message = "We couldn't load plans right now. Your workouts are always free - try again later."
        }
    }

    /// Purchase the selected plan. A user cancel is silent (no message, no unlock); a purchase left
    /// awaiting approval (Ask to Buy) surfaces a gentle "waiting" note without unlocking; a real
    /// failure surfaces a gentle message. On a granted entitlement `didUnlockPremium` flips.
    func purchase(_ plan: SubscriptionPlan) async {
        guard !isBusy else { return }
        purchasingPlanID = plan.id
        message = nil
        defer { purchasingPlanID = nil }

        do {
            switch try await subscriptionService.purchase(plan) {
            case .resolved(let subscription):
                reflect(subscription)
            case .pending:
                message = "This purchase needs approval before it unlocks. We'll switch on Premium as soon as it's approved - your workouts stay free in the meantime."
            }
        } catch {
            message = "The purchase didn't go through. No charge was made - your workouts stay free."
        }
    }

    /// Restore an existing purchase (App Store sync). Grants premium if the account owns it, else a
    /// gentle "nothing to restore" message.
    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }

        do {
            let subscription = try await subscriptionService.restorePurchases()
            reflect(subscription)
            if subscription.tier != .premium {
                message = "No previous purchase found on this Apple ID."
            }
        } catch {
            message = "We couldn't restore right now. Please try again later."
        }
    }

    private func reflect(_ subscription: Subscription) {
        if subscription.tier == .premium {
            didUnlockPremium = true
        }
    }
}
