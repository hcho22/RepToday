import SwiftUI

struct PaywallView: View {
    @Bindable var viewModel: SubscriptionViewModel
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    private struct PremiumFeature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }

    // Ordered by perceived value
    private let features: [PremiumFeature] = [
        PremiumFeature(
            icon: "sparkles",
            title: "AI-Powered Insights",
            description: "Personalized post-workout analysis and weekly training reports"
        ),
        PremiumFeature(
            icon: "snowflake",
            title: "Streak Freezes",
            description: "2 monthly freezes to protect your streak when life gets busy"
        ),
        PremiumFeature(
            icon: "chart.line.uptrend.xyaxis",
            title: "Progression Tracking",
            description: "Track strength gains and see how you improve over time"
        ),
        PremiumFeature(
            icon: "square.and.arrow.up",
            title: "Clean Shareable Cards",
            description: "Share workout achievements without watermarks"
        ),
        PremiumFeature(
            icon: "chart.bar.fill",
            title: "Detailed Progress Analytics",
            description: "In-depth stats on your fitness journey"
        ),
    ]

    private let sampleInsightText = "Great 15-min upper body session! Your push-up reps are up 20% this month. Consider adding pike push-ups next week to target shoulders more."

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Text("Unlock Your Full Potential")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppSpacing.xl)

                // AI insight teaser with blur overlay
                sampleInsightTeaser
                    .padding(.horizontal, AppSpacing.lg)

                // Premium features
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(features) { feature in
                        HStack(alignment: .top, spacing: AppSpacing.smMd) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(AppColors.brand)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(AppTypography.headline)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(feature.description)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                // Plan selection
                VStack(spacing: AppSpacing.md) {
                    planCard(
                        plan: .annual,
                        badge: "BEST VALUE",
                        title: "Annual: $59.99/year",
                        subtitle: "That's just $4.99/month — Save 37%"
                    )

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
    }

    // MARK: - AI Insight Teaser

    private var sampleInsightTeaser: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.brand)
                    Text("AI Insight")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Text(sampleInsightText)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .blur(radius: 4)
        .overlay {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                Text("Upgrade to unlock")
                    .font(AppTypography.headline)
            }
            .foregroundStyle(AppColors.brand)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .accessibilityLabel("AI insight preview — upgrade to unlock personalized insights")
    }

    // MARK: - Plan Card

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
