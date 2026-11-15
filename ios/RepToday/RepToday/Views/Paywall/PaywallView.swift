import SwiftUI

/// The premium paywall (US-N04) - a dismissible sheet the free user opens from the Progress tab's
/// upsell. It prices the plans from StoreKit, lets the user buy one or restore a prior purchase, and
/// carries the App Store-required auto-renewal disclosure.
///
/// It never gates the core loop: it is a sheet the user can dismiss at any time, and the free tier is
/// unlimited forever. On a successful unlock it synchronously accepts the exact verified
/// `SubscriptionGrant` into the shared application-session authority before passing its Subscription
/// projection to `onUnlock` and dismissing. Every token comes from `Theme`;
/// there is no XP, no levels, no badges.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PaywallViewModel
    private let premiumSessionAuthority: PremiumSessionAuthority
    private let onUnlock: (Subscription) -> Void

    init(
        subscriptionService: any SubscriptionServiceProtocol,
        premiumSessionAuthority: PremiumSessionAuthority,
        analyticsService: (any AnalyticsServiceProtocol)? = nil,
        entryPoint: EntryPoint = .progressUpsell,
        entitlements: (any PremiumEntitlementServiceProtocol)? = nil,
        onUnlock: @escaping (Subscription) -> Void = { _ in }
    ) {
        _viewModel = State(
            initialValue: PaywallViewModel(
                subscriptionService: subscriptionService,
                analytics: analyticsService,
                entryPoint: entryPoint,
                entitlements: entitlements
            )
        )
        self.premiumSessionAuthority = premiumSessionAuthority
        self.onUnlock = onUnlock
    }

    /// Test/preview seam so a pre-seeded view model can be injected.
    init(
        viewModel: PaywallViewModel,
        premiumSessionAuthority: PremiumSessionAuthority = PremiumSessionAuthority(),
        onUnlock: @escaping (Subscription) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.premiumSessionAuthority = premiumSessionAuthority
        self.onUnlock = onUnlock
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Premium")
            // The sheet draws its own top row (Close and the "Premium" title), so the bar stays hidden.
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.unlockedGrant) { _, grant in
            guard let grant else { return }
            premiumSessionAuthority.acceptGrant(grant)
            onUnlock(grant.subscription)
            dismiss()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    topRow
                    headline
                    benefits
                    plansSection
                    if let message = viewModel.catalogMessage {
                        Text(message)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry plans") { Task { await viewModel.load() } }
                            .font(Theme.Typography.callout.weight(.bold))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(minHeight: Theme.Spacing.minTouchTarget)
                            .disabled(viewModel.isBusy)
                            .accessibilityHint("Loads available Premium plans from the App Store")
                    }
                    if let message = viewModel.message {
                        Text(message)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(message)
                    }
                    disclosure
                    legalLinks
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            restoreButton
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
        }
    }

    /// Close on the left, the sheet's name centered over the whole row.
    private var topRow: some View {
        ZStack {
            Text("Premium")
                .font(Theme.Typography.headline.weight(.bold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.minTouchTarget + Theme.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    IconView(icon: .close, size: 22)
                }
                .circleIconButtonStyle()
                .accessibilityLabel("Close")
                Spacer(minLength: 0)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            DayMarkView(mark: .bubble, color: Theme.Colors.sun, size: 84)
                .padding(.bottom, Theme.Spacing.sm)
            Text("Go deeper with Premium")
                .cappedDisplayFont(size: 44)
                .foregroundStyle(Theme.Colors.textPrimary)
                .keepsWordsWhole("Go deeper with Premium")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your workouts are always free. Premium adds the coach and the deeper view for when you want them.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The Coach (M4): the one Premium surface that acts, always waiting for the user's OK.
            PaywallBenefitRow(icon: .coach,
                              text: "A coach that knows your training - it logs a run, adjusts today and writes workouts, with your OK")
            PaywallBenefitRow(icon: .chart, text: "Pattern-by-pattern balance across every movement")
            PaywallBenefitRow(icon: .calendar, text: "Your weekly training volume over time")
            PaywallBenefitRow(icon: .spark, text: "How your sessions have felt - your difficulty mix")
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
            VStack(spacing: Theme.Spacing.sm) {
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
                    SwiftUI.ProgressView().tint(Theme.Colors.textSecondary)
                }
                Text("Restore purchases")
                    .font(Theme.Typography.callout.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Spacing.minTouchTarget)
        }
        .ghostButtonStyle()
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Restore purchases")
    }

    private var disclosure: some View {
        Text("Subscriptions bill through your Apple ID and renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel anytime in Settings. Any free trial's unused portion is forfeited when you buy a subscription.")
            .font(ThemeFont(Theme.Typography.FontName.textRegular, size: 12, relativeTo: .caption))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Subscriptions bill through your Apple ID and renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel anytime in Settings.")
    }

    /// The Terms of Use (EULA) and Privacy Policy links App Store Review Guideline 3.1.2 requires on an
    /// auto-renewable subscription paywall. Both come from `LegalLinks`, which is also what the US-T06
    /// telemetry disclosure links to - one privacy-policy URL for the whole app, so the placeholder
    /// cannot be replaced in one surface and left stale in the other.
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.lg) {
                termsLink
                privacyLink
            }
            VStack(spacing: 0) {
                termsLink
                privacyLink
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var termsLink: some View {
        Link(destination: LegalLinks.termsOfUse) {
            Text("Terms of Use")
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
        }
        .accessibilityLabel("Terms of Use")
    }

    private var privacyLink: some View {
        Link(destination: LegalLinks.privacyPolicy) {
            Text("Privacy Policy")
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
        }
        .accessibilityLabel("Privacy Policy")
    }
}

// MARK: - Benefit row

private struct PaywallBenefitRow: View {
    let icon: AppIcon
    let text: String

    var body: some View {
        IconTextRow(icon: icon, text: text)
            .accessibilityLabel(text)
    }
}

// MARK: - Plan button

/// A plan, tapped to buy it: a `sun` card (a primary action outside a session) with the period, the
/// price in Bricolage and any trial, in black.
private struct PaywallPlanButton: View {
    let plan: SubscriptionPlan
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.smd) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.period.displayName)
                        .font(Theme.Typography.callout.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.priceLine)
                        .font(ThemeFont(Theme.Typography.FontName.displaySmall, size: 24, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.onAccentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let trial = plan.trialDescription {
                        Text(trial)
                            .font(Theme.Typography.footnote.weight(.bold))
                            .foregroundStyle(Theme.Colors.onAccentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isPurchasing {
                    SwiftUI.ProgressView().tint(Theme.Colors.onAccent)
                } else {
                    IconView(icon: .chevr, size: 22)
                        .foregroundStyle(Theme.Colors.onAccentSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.Colors.accentFill, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
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
    PaywallView(
        subscriptionService: MockSubscriptionService(),
        premiumSessionAuthority: PremiumSessionAuthority()
    )
}

#Preview("Unavailable") {
    PaywallView(
        subscriptionService: MockSubscriptionService(plans: [], simulatesPurchase: false),
        premiumSessionAuthority: PremiumSessionAuthority()
    )
}
