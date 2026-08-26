import SwiftUI

/// The premium gate and upsell entry point for the AI coach (US-AC03).
///
/// The talking coach (US-AC02) is a Premium feature. This is its single entry point on the Profile
/// tab and it enforces the gate: a Premium subscriber taps straight through into `CoachView`; a free
/// user's tap opens the existing paywall (US-N04) carrying the `coach_upsell` entry point, so the
/// funnel (US-T12) can tell a coach upsell apart from the Progress-tab one. It reuses the existing
/// StoreKit 2 plumbing through `CoachGateViewModel` - no new billing path.
///
/// Nothing here gates or blocks the core loop. The entitlement read is best-effort, off the
/// Home/Ready critical path, and defaults to the safe not-Premium state (show the upsell) on any
/// failure - a transient error never silently unlocks a paid surface.
struct CoachEntryRow: View {
    @Environment(\.services) private var services

    @State private var viewModel: CoachGateViewModel
    @State private var showPaywall = false

    /// Production entry: builds the gate over the container's subscription service.
    init(services: ServiceContainer) {
        _viewModel = State(initialValue: CoachGateViewModel(subscriptionService: services.subscriptionService))
    }

    /// Test/preview seam: inject a pre-built gate view model (e.g. one over a Premium or free mock).
    init(viewModel: CoachGateViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isPremium {
                // Unlocked: navigate straight into the talking coach.
                NavigationLink {
                    CoachView(services: services)
                } label: {
                    ProfileRowLabel(icon: "bubble.left.and.bubble.right.fill", title: "Coach")
                }
                .accessibilityLabel("Coach")
                .accessibilityHint("Ask the coach about your workouts and form")
            } else {
                // Locked: the row is the upsell - a tap opens the paywall rather than the coach.
                Button {
                    showPaywall = true
                } label: {
                    ProfileRowLabel(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Coach",
                        badge: "Premium"
                    )
                }
                .accessibilityLabel("Coach")
                .accessibilityHint("A Premium feature. Opens Premium to unlock the coach.")
            }
        }
        // Best-effort entitlement read on appear; idempotent, and never gates the tab from rendering.
        .task { await viewModel.load() }
        .sheet(isPresented: $showPaywall) {
            // Reuses the existing paywall (US-N04); the coach-specific entry point is what lets the
            // US-T12 funnel tell where the paywall opened from. `paywall_shown` is emitted by the
            // paywall itself. Nothing here blocks the core loop.
            PaywallView(
                subscriptionService: services.subscriptionService,
                analyticsService: services.analyticsService,
                entryPoint: .coachUpsell
            )
        }
    }
}

#if DEBUG
#Preview("Free - upsell") {
    NavigationStack {
        List {
            CoachEntryRow(viewModel: CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: .free)))
        }
    }
    .environment(\.services, ServiceContainer.mock())
}

#Preview("Premium - unlocked") {
    NavigationStack {
        List {
            CoachEntryRow(viewModel: CoachGateViewModel(
                subscriptionService: MockSubscriptionService(
                    subscription: Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
                )
            ))
        }
    }
    .environment(\.services, ServiceContainer.mock())
}
#endif
