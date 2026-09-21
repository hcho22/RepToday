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
/// A verified purchase/restore result is more recent than StoreKit's cached entitlement projection.
/// `acceptAuthoritativeGrant(_:)` therefore keeps that grant authoritative for this view-model session;
/// ordinary empty reads cannot erase it, while an explicit StoreKit update can.
@Observable
final class CoachGateViewModel {

    /// The entitlement currently backing the Coach gate. Keeping the full value is what lets the
    /// paywall hand off its exact verified purchase/restore result rather than collapsing it into a
    /// Boolean and immediately reconstructing it from a potentially lagging projection.
    private(set) var subscription: Subscription = .free

    /// Whether the coach is unlocked. Free until a successful entitlement read or verified paywall
    /// grant proves Premium, so the fail-safe is always "show the upsell".
    var isPremium: Bool { subscription.tier == .premium }

    private let subscriptionService: any SubscriptionServiceProtocol

    private var authoritativeSessionTier: SubscriptionTier?
    private var readGeneration = 0

    init(subscriptionService: any SubscriptionServiceProtocol) {
        self.subscriptionService = subscriptionService
    }

    /// Read the current entitlement. Before a purchase/restore handoff, a missing or throwing read
    /// fails safe to the locked state. After one, the verified grant remains authoritative until an
    /// explicit StoreKit update supersedes it.
    @MainActor
    func load() async {
        let generation = nextReadGeneration()
        do {
            let subscription = try await subscriptionService.currentSubscription()
            guard generation == readGeneration else { return }
            guard authoritativeSessionTier == nil || subscription.tier == authoritativeSessionTier else { return }
            self.subscription = subscription
        } catch {
            guard generation == readGeneration else { return }
            if authoritativeSessionTier == nil {
                self.subscription = .free
            }
        }
    }

    /// Apply the exact verified Premium result returned by a purchase or restore. This is synchronous
    /// so the paywall handoff cannot briefly re-lock the Coach between dismissal and reconciliation.
    @MainActor
    func acceptAuthoritativeGrant(_ subscription: Subscription) {
        guard subscription.tier == .premium else { return }
        _ = nextReadGeneration()
        authoritativeSessionTier = .premium
        self.subscription = subscription
    }

    @MainActor
    func acceptAuthoritativeStoreKitUpdate(_ subscription: Subscription) {
        _ = nextReadGeneration()
        authoritativeSessionTier = subscription.tier
        self.subscription = subscription
    }

    /// Re-read StoreKit after an authoritative grant without treating a lagging empty projection as
    /// a revocation. Every read shares one generation, so the latest-started operation owns the commit.
    @MainActor
    func reconcileAfterAuthoritativeGrant() async {
        guard isPremium else { return }
        let generation = nextReadGeneration()
        guard let subscription = try? await subscriptionService.currentSubscription() else { return }
        guard generation == readGeneration else { return }
        if subscription.tier == .premium {
            self.subscription = subscription
        }
    }

    @MainActor
    private func nextReadGeneration() -> Int {
        readGeneration &+= 1
        return readGeneration
    }
}
