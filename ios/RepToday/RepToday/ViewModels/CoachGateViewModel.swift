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
/// A verified purchase/restore result is more recent than an immediately repeated StoreKit entitlement
/// projection. `acceptAuthoritativeGrant(_:)` therefore opens the gate synchronously, while
/// `reconcileAfterAuthoritativeGrant()` refreshes in the background without allowing that one lagging
/// projection to revoke the grant. A later ordinary `load()` remains authoritative, preserving
/// out-of-band renewal/refund behavior on the next appearance.
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

    /// Changes whenever this instance accepts a newer authoritative paywall result. An entitlement
    /// read that started before the change is stale by definition and must not overwrite the grant.
    private var authoritativeGrantRevision = 0

    init(subscriptionService: any SubscriptionServiceProtocol) {
        self.subscriptionService = subscriptionService
    }

    /// Read the current entitlement. Idempotent and safe to call on every appear; best-effort, so a
    /// throwing read fails safe to the locked state rather than surfacing an error or gating anything.
    /// (The one bounded post-grant reconciliation has separate, non-revoking semantics below.)
    ///
    /// Capturing the revision before suspension prevents a read already in flight when a purchase
    /// completes from overwriting the newer verified result when it resumes.
    @MainActor
    func load() async {
        let revisionAtStart = authoritativeGrantRevision
        do {
            let subscription = try await subscriptionService.currentSubscription()
            guard revisionAtStart == authoritativeGrantRevision else { return }
            self.subscription = subscription
        } catch {
            guard revisionAtStart == authoritativeGrantRevision else { return }
            self.subscription = .free
        }
    }

    /// Apply the exact verified Premium result returned by a purchase or restore. This is synchronous
    /// so the paywall handoff cannot briefly re-lock the Coach between dismissal and reconciliation.
    @MainActor
    func acceptAuthoritativeGrant(_ subscription: Subscription) {
        guard subscription.tier == .premium else { return }
        authoritativeGrantRevision &+= 1
        self.subscription = subscription
    }

    /// Re-read StoreKit after an authoritative grant without treating an immediately lagging free
    /// projection as a revocation. A later ordinary `load()` still reflects the then-current state,
    /// including an out-of-band expiry/refund, while a Premium result here confirms the gate.
    @MainActor
    func reconcileAfterAuthoritativeGrant() async {
        let revisionAtStart = authoritativeGrantRevision
        guard isPremium else { return }
        guard let subscription = try? await subscriptionService.currentSubscription() else { return }
        guard revisionAtStart == authoritativeGrantRevision else { return }
        if subscription.tier == .premium {
            self.subscription = subscription
        }
    }
}
