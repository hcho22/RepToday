import SwiftUI

@Observable
final class SubscriptionViewModel {
    var isPremium = false
    var isLoading = false
    var selectedPlan: Plan = .annual

    enum Plan: String, CaseIterable {
        case monthly, annual

        var productId: String {
            switch self {
            case .monthly: SubscriptionService.monthlyProductId
            case .annual: SubscriptionService.annualProductId
            }
        }

        var price: String {
            switch self {
            case .monthly: "$7.99/mo"
            case .annual: "$59.99/yr"
            }
        }

        var monthlyPrice: String {
            switch self {
            case .monthly: "$7.99"
            case .annual: "$4.99"
            }
        }
    }

    func loadStatus(services: ServiceContainer?) async {
        guard let services else { return }
        isPremium = services.subscription.isPremium
    }

    func purchase(services: ServiceContainer?) async {
        guard let services else { return }
        isLoading = true
        let success = (try? await services.subscription.purchase(productId: selectedPlan.productId)) ?? false
        if success { isPremium = true }
        isLoading = false
    }

    func restore(services: ServiceContainer?) async {
        guard let services else { return }
        isLoading = true
        try? await services.subscription.restorePurchases()
        isPremium = services.subscription.isPremium
        isLoading = false
    }
}
