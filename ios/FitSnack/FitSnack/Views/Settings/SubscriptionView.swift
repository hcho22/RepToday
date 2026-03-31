import SwiftUI

struct SubscriptionView: View {
    @Environment(\.services) private var services
    @State private var viewModel = SubscriptionViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if viewModel.isPremium {
                    // Premium active
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.warning)
                        Text("Premium Active")
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("You have access to all features!")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, AppSpacing.xxl)
                } else {
                    PaywallView(viewModel: viewModel)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadStatus(services: services) }
    }
}
