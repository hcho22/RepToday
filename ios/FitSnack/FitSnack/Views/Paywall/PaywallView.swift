import SwiftUI

struct PaywallView: View {
    @Bindable var viewModel: SubscriptionViewModel
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    private let features = [
        "Unlimited AI workouts",
        "Detailed progress analytics",
        "AI coaching insights",
        "Unlimited streak freezes",
        "Shareable workout cards",
    ]

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("Unlock Your Full Potential")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.xl)

            // Features
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text(feature)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)

            // Plan selection
            VStack(spacing: AppSpacing.md) {
                // Annual
                planCard(
                    plan: .annual,
                    badge: "BEST VALUE",
                    title: "Annual: $59.99/year",
                    subtitle: "That's just $4.99/month — Save 37%"
                )

                // Monthly
                planCard(
                    plan: .monthly,
                    badge: nil,
                    title: "Monthly: $7.99/month",
                    subtitle: nil
                )
            }
            .padding(.horizontal, AppSpacing.lg)

            // Subscribe
            if viewModel.isLoading {
                ProgressView()
                    .frame(height: AppSpacing.buttonHeight)
            } else {
                PrimaryButton(title: "Start 14-Day Free Trial") {
                    Task { await viewModel.purchase(services: services) }
                }
                .padding(.horizontal, AppSpacing.lg)
            }

            // Restore
            Button("Restore Purchases") {
                Task { await viewModel.restore(services: services) }
            }
            .font(AppTypography.subheadline)
            .foregroundStyle(AppColors.textSecondary)

            Spacer()
        }
    }

    private func planCard(plan: SubscriptionViewModel.Plan, badge: String?, title: String, subtitle: String?) -> some View {
        Button {
            viewModel.selectedPlan = plan
        } label: {
            VStack(spacing: AppSpacing.xs) {
                if let badge {
                    Text(badge)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 2)
                        .background(AppColors.success)
                        .clipShape(Capsule())
                }

                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(viewModel.selectedPlan == plan ? .white : AppColors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(viewModel.selectedPlan == plan ? .white.opacity(0.8) : AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .background(viewModel.selectedPlan == plan ? AppColors.brand : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                    .stroke(viewModel.selectedPlan == plan ? AppColors.brand : AppColors.divider, lineWidth: 2)
            )
        }
    }
}
