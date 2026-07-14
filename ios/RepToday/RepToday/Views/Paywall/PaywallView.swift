import SwiftUI

/// The premium paywall (US-N04) - a dismissible sheet the free user opens from the Progress tab's
/// upsell. It prices the plans from StoreKit, lets the user buy one or restore a prior purchase, and
/// carries the App Store-required auto-renewal disclosure.
///
/// It never gates the core loop: it is a sheet the user can dismiss at any time, and the free tier is
/// unlimited forever. On a successful unlock it calls `onUnlock` (so the presenter can dismiss and
/// refresh the entitlement-gated surfaces) and dismisses itself. Every token comes from `Theme`;
/// there is no XP, no levels, no badges.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PaywallViewModel
    private let onUnlock: () -> Void

    init(subscriptionService: any SubscriptionServiceProtocol, onUnlock: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: PaywallViewModel(subscriptionService: subscriptionService))
        self.onUnlock = onUnlock
    }

    /// Test/preview seam so a pre-seeded view model can be injected.
    init(viewModel: PaywallViewModel, onUnlock: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onUnlock = onUnlock
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didUnlockPremium) { _, unlocked in
            if unlocked {
                onUnlock()
                dismiss()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                headline
                benefits
                plansSection
                if let message = viewModel.message {
                    Text(message)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(message)
                }
                restoreButton
                disclosure
                legalLinks
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text("Go deeper with Premium")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your workouts are always free. Premium just adds the deeper view for when you want it.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            PaywallBenefitRow(icon: "chart.bar.fill", text: "Pattern-by-pattern balance across every movement")
            PaywallBenefitRow(icon: "calendar", text: "Your weekly training volume over time")
            PaywallBenefitRow(icon: "dial.medium", text: "How your sessions have felt - your difficulty mix")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plansSection: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                SwiftUI.ProgressView().tint(Theme.Colors.accent)
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.lg)
        } else {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.plans) { plan in
                    PaywallPlanButton(
                        plan: plan,
                        isPurchasing: viewModel.purchasingPlanID == plan.id,
                        isDisabled: viewModel.isBusy && viewModel.purchasingPlanID != plan.id,
                        action: { Task { await viewModel.purchase(plan) } }
                    )
                }
            }
        }
    }

    private var restoreButton: some View {
        Button(action: { Task { await viewModel.restore() } }) {
            HStack(spacing: Theme.Spacing.xs) {
                if viewModel.isRestoring {
                    SwiftUI.ProgressView().tint(Theme.Colors.accent)
                }
                Text("Restore purchases")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Spacing.minTouchTarget)
        }
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Restore purchases")
    }

    private var disclosure: some View {
        Text("Subscriptions bill through your Apple ID and renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel anytime in Settings. Any free trial's unused portion is forfeited when you buy a subscription.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Subscriptions bill through your Apple ID and renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel anytime in Settings.")
    }

    /// The Terms of Use (EULA) and Privacy Policy links App Store Review Guideline 3.1.2 requires on an
    /// auto-renewable subscription paywall. Terms points at Apple's standard EULA; the Privacy Policy URL
    /// is an obvious placeholder to replace with Rep Today's real policy before App Store submission.
    private var legalLinks: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Link(destination: PaywallView.termsOfUseURL) {
                Text("Terms of Use")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
            }
            .accessibilityLabel("Terms of Use")

            Link(destination: PaywallView.privacyPolicyURL) {
                Text("Privacy Policy")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
            }
            .accessibilityLabel("Privacy Policy")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Apple's standard auto-renewable-subscription EULA, the default Terms of Use when the app ships no
    /// custom EULA.
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// PLACEHOLDER - replace with Rep Today's real privacy-policy URL before App Store submission.
    private static let privacyPolicyURL = URL(string: "https://example.com/reptoday-privacy-policy-PLACEHOLDER")!
}

// MARK: - Benefit row

private struct PaywallBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Plan button

private struct PaywallPlanButton: View {
    let plan: SubscriptionPlan
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(plan.period.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.onAccent)
                    Text(plan.priceLine)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.onAccent.opacity(0.9))
                    if let trial = plan.trialDescription {
                        Text(trial)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.onAccent.opacity(0.9))
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                if isPurchasing {
                    SwiftUI.ProgressView().tint(Theme.Colors.onAccent)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.Colors.onAccent.opacity(0.9))
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.buttonHeight, alignment: .leading)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isPurchasing)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.period.displayName), \(plan.priceLine)\(plan.trialDescription.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Plans") {
    PaywallView(subscriptionService: MockSubscriptionService())
}

#Preview("Unavailable") {
    PaywallView(subscriptionService: MockSubscriptionService(plans: [], simulatesPurchase: false))
}
