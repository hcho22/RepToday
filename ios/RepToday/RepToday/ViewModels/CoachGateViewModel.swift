import Foundation
import Observation

/// Resolves whether the AI coach is unlocked for the current user (US-AC03). The talking coach
/// (US-AC02) is a Premium feature; this view model reads the StoreKit 2 entitlement through the
/// existing `SubscriptionServiceProtocol` - the same plumbing the paywall and the Progress-tab deep
/// layer use, no new billing path - and exposes a single `isPremium` the coach entry point branches
/// on: Premium navigates into the coach, free opens the paywall.
///
/// The read is best-effort and defaults to the safe, non-unlocking state: a fresh application-session
/// authority starts free, and a throwing read cannot fabricate an unlock. Once a stronger verified
/// grant or update exists, a weaker failed/lagging read also cannot erase it. Nothing here touches or
/// blocks the core loop - it is read off the Profile tab, not the Home/Ready critical path.
///
/// Purchase/restore handoff, signed snapshots, and verified StoreKit updates converge on the shared
/// `PremiumSessionAuthority`, so reconstructed Coach gates in the same process see the same decision.
@Observable
final class CoachGateViewModel {

    /// The entitlement currently backing the Coach gate. Keeping the full value is what lets the
    /// paywall hand off its exact verified purchase/restore result rather than collapsing it into a
    /// Boolean and immediately reconstructing it from a potentially lagging projection.
    var subscription: Subscription { premiumSessionAuthority.subscription }

    /// Whether the coach is unlocked. Free until a successful entitlement read or verified paywall
    /// grant proves Premium, so the fail-safe is always "show the upsell".
    var isPremium: Bool { subscription.tier == .premium }

    private let subscriptionService: any SubscriptionServiceProtocol
    private let premiumSessionAuthority: PremiumSessionAuthority

    init(
        subscriptionService: any SubscriptionServiceProtocol,
        premiumSessionAuthority: PremiumSessionAuthority = PremiumSessionAuthority()
    ) {
        self.subscriptionService = subscriptionService
        self.premiumSessionAuthority = premiumSessionAuthority
    }

    /// Read the current entitlement with signed provenance when the live StoreKit service supplies it.
    /// A missing or throwing first read fails safe; an accepted stronger authority is preserved.
    @MainActor
    func load() async {
        let token = premiumSessionAuthority.beginRead()
        do {
            let grant = try await subscriptionService.currentSubscriptionGrant()
            premiumSessionAuthority.acceptSnapshot(grant, token: token)
        } catch {
            premiumSessionAuthority.acceptReadFailure(token: token)
        }
    }

    /// Compatibility seam for applying a Premium result directly to this gate. Production paywalls
    /// first accept the full provenance-bearing `SubscriptionGrant` into the shared authority, then
    /// call their subscription-only presentation callback.
    @MainActor
    func acceptAuthoritativeGrant(_ subscription: Subscription) {
        premiumSessionAuthority.acceptGrant(subscription)
    }

    /// Re-read StoreKit after an authoritative grant without treating a lagging empty projection as
    /// a revocation. Every read shares one generation, so the latest-started operation owns the commit.
    @MainActor
    func reconcileAfterAuthoritativeGrant() async {
        guard isPremium else { return }
        let token = premiumSessionAuthority.beginRead()
        guard let grant = try? await subscriptionService.currentSubscriptionGrant() else { return }
        if grant.subscription.tier == .premium {
            premiumSessionAuthority.acceptSnapshot(grant, token: token)
        }
    }
}
