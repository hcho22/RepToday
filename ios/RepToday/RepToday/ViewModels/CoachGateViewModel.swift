import Foundation
import Observation

/// Resolves whether the AI coach is unlocked for the current user (US-AC03). The talking coach
/// (US-AC02) is a Premium feature; this view model reads the StoreKit 2 entitlement through the
/// existing `SubscriptionServiceProtocol` - the same plumbing the paywall and the Progress-tab deep
/// layer use, no new billing path - and exposes a single `isPremium` the coach entry point branches
/// on: Premium navigates into the coach, free opens the paywall.
///
/// The read is best-effort and defaults to the safe, non-unlocking state: `isPremium` starts `false`
/// and a throwing entitlement read leaves it `false`, so a transient failure shows the upsell rather
/// than silently unlocking a paid surface. Nothing here touches or blocks the core loop - it is read
/// off the Profile tab, not the Home/Ready critical path.
///
/// It mirrors `ProgressViewModel`'s one-line entitlement read exactly, so the two gates cannot drift.
@Observable
final class CoachGateViewModel {

    /// Whether the coach is unlocked. `false` until a successful entitlement read proves Premium, so
    /// the fail-safe is always "show the upsell", never "silently unlock the coach".
    private(set) var isPremium = false

    private let subscriptionService: any SubscriptionServiceProtocol

    init(subscriptionService: any SubscriptionServiceProtocol) {
        self.subscriptionService = subscriptionService
    }

    /// Read the current entitlement. Idempotent and safe to call on every appear; best-effort, so a
    /// throwing read leaves `isPremium == false` (the upsell) rather than surfacing an error or gating
    /// anything. Identical to `ProgressViewModel`'s deep-layer entitlement read.
    @MainActor
    func load() async {
        isPremium = (try? await subscriptionService.currentSubscription().tier) == .premium
    }
}
