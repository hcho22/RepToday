import Foundation
import Observation

/// Backs the premium paywall (US-N04) - the sheet a free user opens from the Progress tab's upsell.
///
/// It loads the purchasable plans (priced by StoreKit), drives a purchase or a restore, and reflects
/// the resulting entitlement. Nothing here gates the core loop: the paywall is a dismissible sheet, a
/// load/purchase failure surfaces a gentle message (never a wall), and the free tier keeps working
/// unlimited. On a successful unlock `didUnlockPremium` flips so the presenter can dismiss and refresh
/// the US-M02 gate.
///
/// Like the other v6 view models it is `@Observable` and takes its service as a protocol, so previews
/// and tests inject the mock.
@Observable
final class PaywallViewModel {

    /// The purchasable plans, priced and ordered (monthly first). Empty until loaded or when the store
    /// has none available.
    private(set) var plans: [SubscriptionPlan] = []

    /// True while the plans are loading.
    private(set) var isLoading = false

    /// The plan id currently being purchased, or `nil` when idle - lets the view show a spinner on the
    /// tapped plan and disable the others without gating dismissal.
    private(set) var purchasingPlanID: String?

    /// True while a restore is in flight.
    private(set) var isRestoring = false

    /// True once a purchase or restore has granted premium. The presenter observes this to dismiss and
    /// refresh the entitlement-gated surfaces.
    private(set) var didUnlockPremium = false

    /// A gentle, user-facing message when a load/purchase/restore fails or a restore finds nothing.
    /// Never a blocking error - the sheet stays dismissible and the free tier is unaffected.
    private(set) var message: String?

    /// Whether any purchase/restore is currently in flight (drives disabling the plan buttons).
    var isBusy: Bool { purchasingPlanID != nil || isRestoring }

    private let subscriptionService: any SubscriptionServiceProtocol

    /// Anonymous product telemetry sink (US-T12). Optional exactly like `ReadyViewModel.analytics`,
    /// defaulted `nil`, so previews and the unit suite inject a mock (or nothing) while production
    /// threads `services.analyticsService` in. Emission is strictly fire-and-forget and never gates
    /// the paywall, the purchase, or dismissal.
    private let analytics: (any AnalyticsServiceProtocol)?

    /// Where this paywall was opened from - the closed `entry_point` the `paywall_shown` event
    /// carries. Today there is exactly one presentation path (the Progress-tab upsell), so it
    /// defaults to `.progressUpsell`.
    private let entryPoint: EntryPoint

    /// Injected clock so the emitted millisecond client timestamps are deterministic under test,
    /// mirroring `ReadyViewModel`/`OnboardingViewModel`.
    private let now: () -> Date

    /// One-shot guard so a re-`load()` (the paywall's `.task` can run again on a re-appear) does not
    /// re-emit `paywall_shown`. Modeled on `ReadyViewModel.hasEmittedReadyScreenShown`; not persisted,
    /// because the funnel counts distinct paywall presentations and the backend dedups by `installId`.
    private var hasEmittedPaywallShown = false

    init(
        subscriptionService: any SubscriptionServiceProtocol,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        entryPoint: EntryPoint = .progressUpsell,
        now: @escaping () -> Date = { Date() }
    ) {
        self.subscriptionService = subscriptionService
        self.analytics = analytics
        self.entryPoint = entryPoint
        self.now = now
    }

    /// Load the purchasable plans. Idempotent - safe to call on every appear.
    func load() async {
        // US-T12: `paywall_shown` fires once per paywall presentation, on the first `load()`,
        // carrying `entry_point`. Guarded like `ReadyViewModel`'s one-shots so a re-appear cannot
        // re-emit and inflate the funnel base. Fire-and-forget: it returns immediately and swallows
        // any failure, so telemetry never gates the plans loading or the purchase.
        if !hasEmittedPaywallShown {
            hasEmittedPaywallShown = true
            await analytics?.record(
                AnalyticsEvent(
                    name: .paywallShown,
                    timestampMs: timestampMs(),
                    properties: ["entry_point": .string(entryPoint.rawValue)]
                )
            )
        }

        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            plans = try await subscriptionService.premiumPlans()
            if plans.isEmpty {
                message = "Plans aren't available right now. Your workouts are always free - try again later."
            }
        } catch {
            plans = []
            message = "We couldn't load plans right now. Your workouts are always free - try again later."
        }
    }

    /// Purchase the selected plan. A user cancel is silent (no message, no unlock); a purchase left
    /// awaiting approval (Ask to Buy) surfaces a gentle "waiting" note without unlocking; a real
    /// failure surfaces a gentle message. On a granted entitlement `didUnlockPremium` flips.
    func purchase(_ plan: SubscriptionPlan) async {
        guard !isBusy else { return }
        purchasingPlanID = plan.id
        message = nil
        defer { purchasingPlanID = nil }

        do {
            switch try await subscriptionService.purchase(plan) {
            case .resolved(let subscription):
                reflect(subscription)
                // US-T12: emit the monetization event only on a real grant. A user-cancel resolves
                // here too but with an unchanged (typically `.free`) entitlement, so keying off the
                // granted `.premium` tier means a cancelled or failed purchase emits nothing.
                if subscription.tier == .premium {
                    await emitPurchaseTelemetry(for: subscription, plan: plan)
                }
            case .pending:
                message = "This purchase needs approval before it unlocks. We'll switch on Premium as soon as it's approved - your workouts stay free in the meantime."
            }
        } catch {
            message = "The purchase didn't go through. No charge was made - your workouts stay free."
        }
    }

    /// Restore an existing purchase (App Store sync). Grants premium if the account owns it, else a
    /// gentle "nothing to restore" message.
    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }

        do {
            let subscription = try await subscriptionService.restorePurchases()
            reflect(subscription)
            if subscription.tier != .premium {
                message = "No previous purchase found on this Apple ID."
            }
        } catch {
            message = "We couldn't restore right now. Please try again later."
        }
    }

    private func reflect(_ subscription: Subscription) {
        if subscription.tier == .premium {
            didUnlockPremium = true
        }
    }

    /// Emit the monetization funnel event for a granted premium subscription (US-T12), branching on
    /// whether it carries a free trial. Called only from `purchase(_:)`'s resolved branch on a real
    /// `.premium` grant - never from `restore()`, which re-grants an already-owned entitlement rather
    /// than starting a new one, so restoring does not re-emit a subscribe.
    ///
    /// - A **trial-bearing** subscription (`trialEndsAt != nil`) emits `trial_started` (no
    ///   properties, per the schema).
    /// - A **direct paid** subscription (no trial) emits `subscribe` carrying `plan`.
    ///
    /// The schema defines `subscribe` as "paid subscription starts (trial converts or direct)", so a
    /// trial that *later converts* to paid should also emit `subscribe` at conversion. That
    /// conversion leg is **not** wired here: the only signal of a trial converting is an out-of-band
    /// StoreKit transaction update, which `LiveStoreKitFacade.listenForTransactions()` consumes
    /// internally to refresh the entitlement but does not surface to any emission-capable seam. Wiring
    /// it would require new conversion-tracking machinery (a listener callback carrying the converting
    /// transaction to a sink, plus dedup), which US-T12 explicitly scopes out. Recorded in the PRD's
    /// US-T12 note; the direct-purchase and trial-start legs below are fully covered.
    private func emitPurchaseTelemetry(for subscription: Subscription, plan: SubscriptionPlan) async {
        guard let analytics else { return }
        if subscription.trialEndsAt != nil {
            await analytics.record(AnalyticsEvent(name: .trialStarted, timestampMs: timestampMs()))
        } else {
            await analytics.record(
                AnalyticsEvent(
                    name: .subscribe,
                    timestampMs: timestampMs(),
                    properties: ["plan": .string(plan.id)]
                )
            )
        }
    }

    /// The current millisecond client timestamp off the injected clock (US-T12) - the same encoding
    /// `AnalyticsEvent` uses everywhere.
    private func timestampMs() -> Int {
        Int(now().timeIntervalSince1970 * 1000)
    }
}
