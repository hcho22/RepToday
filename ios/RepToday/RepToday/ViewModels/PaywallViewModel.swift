import Foundation
import Observation

/// Backs the premium paywall (US-N04) - the sheet a free user opens from the Progress tab's upsell.
///
/// It loads the purchasable plans (priced by StoreKit), drives a purchase or a restore, and reflects
/// the resulting entitlement. Nothing here gates the core loop: the paywall is a dismissible sheet, a
/// load/purchase failure surfaces a gentle message (never a wall), and the free tier keeps working
/// unlimited. On a successful unlock `unlockedGrant` carries the exact verified subscription and
/// transaction provenance back to the presenter, so a lagging entitlement projection cannot erase it.
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

    /// The exact Premium subscription returned by a successful purchase or restore. The presenter
    /// observes this to dismiss and hand the authoritative grant directly to its gate instead of
    /// reconstructing it from an immediately repeated (and potentially lagging) entitlement read.
    private(set) var unlockedGrant: SubscriptionGrant?

    var unlockedSubscription: Subscription? { unlockedGrant?.subscription }

    /// Compatibility projection used by the focused view-model tests and any non-presentational
    /// consumers that only need the unlock decision.
    var didUnlockPremium: Bool { unlockedSubscription?.tier == .premium }

    /// A gentle, user-facing message when a load/purchase/restore fails or a restore finds nothing.
    /// Never a blocking error - the sheet stays dismissible and the free tier is unaffected.
    private(set) var message: String?

    #if COACH_IPHONE_QA
    enum ProductsDiagnostic: Equatable {
        case loading, loaded(Int), noUsableProducts, failure(StoreKitFailureDiagnostic?)

        var summary: String {
            switch self {
            case .loading: return "loading"
            case .loaded(let count): return "loaded \(count) plans"
            case .noUsableProducts: return "no usable products"
            case .failure(let diagnostic): return diagnostic?.summary ?? "unclassified failure"
            }
        }
    }

    enum RestoreDiagnostic: Equatable {
        case notAttempted, inProgress, premium, noCurrentEntitlement, failure(StoreKitFailureDiagnostic?)

        var summary: String {
            switch self {
            case .notAttempted: return "not attempted"
            case .inProgress: return "in progress"
            case .premium: return "Premium success"
            case .noCurrentEntitlement: return "no current entitlement"
            case .failure(let diagnostic): return diagnostic?.summary ?? "unclassified failure"
            }
        }
    }

    // Separate latest results, held only by this paywall. Restore must not erase catalog evidence.
    private(set) var productsDiagnostic: ProductsDiagnostic = .loading
    private(set) var restoreDiagnostic: RestoreDiagnostic = .notAttempted

    private static func diagnostic(from error: Error) -> StoreKitFailureDiagnostic? {
        guard let error = error as? SubscriptionError,
              case .diagnosticFailure(let diagnostic) = error else { return nil }
        return diagnostic
    }
    #endif

    /// Whether any purchase/restore is currently in flight (drives disabling the plan buttons).
    var isBusy: Bool { purchasingPlanID != nil || isRestoring }

    private let subscriptionService: any SubscriptionServiceProtocol

    /// Anonymous product telemetry sink (US-T12). Optional exactly like `ReadyViewModel.analytics`,
    /// defaulted `nil`, so previews and the unit suite inject a mock (or nothing) while production
    /// threads `services.analyticsService` in. Emission performs only bounded synchronous acceptance;
    /// storage and delivery never gate the paywall, purchase, or dismissal.
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
    /// because each new view model represents a distinct paywall presentation. Transport retries of
    /// one accepted emission are deduplicated separately by its stable `eventId`.
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
        // re-emit and inflate the funnel base. The sink swallows local/network failures and does not
        // await delivery here, so telemetry never gates plans loading or the purchase.
        if !hasEmittedPaywallShown {
            hasEmittedPaywallShown = true
            analytics?.record(
                AnalyticsEvent(
                    name: .paywallShown,
                    timestampMs: timestampMs(),
                    properties: ["entry_point": .string(entryPoint.rawValue)]
                )
            )
        }

        isLoading = true
        message = nil
        #if COACH_IPHONE_QA
        productsDiagnostic = .loading
        #endif
        defer { isLoading = false }

        do {
            plans = try await subscriptionService.premiumPlans()
            #if COACH_IPHONE_QA
            productsDiagnostic = plans.isEmpty ? .noUsableProducts : .loaded(plans.count)
            #endif
            if plans.isEmpty {
                message = "Plans aren't available right now. Your workouts are always free - try again later."
            }
        } catch {
            plans = []
            #if COACH_IPHONE_QA
            if let error = error as? SubscriptionError, error == .productsUnavailable {
                productsDiagnostic = .noUsableProducts
            } else {
                productsDiagnostic = .failure(Self.diagnostic(from: error))
            }
            #endif
            message = "We couldn't load plans right now. Your workouts are always free - try again later."
        }
    }

    /// Purchase the selected plan. A user cancel is silent (no message, no unlock); a purchase left
    /// awaiting approval (Ask to Buy) surfaces a gentle "waiting" note without unlocking; a real
    /// failure surfaces a gentle message. On a granted entitlement `unlockedGrant` retains the exact
    /// verified value and provenance for the presenter.
    func purchase(_ plan: SubscriptionPlan) async {
        guard !isBusy else { return }
        purchasingPlanID = plan.id
        message = nil
        defer { purchasingPlanID = nil }

        do {
            switch try await subscriptionService.purchase(plan) {
            case .resolved(let grant):
                reflect(grant)
                // US-T12: emit the monetization event only on a real grant. A user-cancel resolves
                // here too but with an unchanged (typically `.free`) entitlement, so keying off the
                // granted `.premium` tier means a cancelled or failed purchase emits nothing.
                if grant.subscription.tier == .premium {
                    await emitPurchaseTelemetry(for: grant.subscription, plan: plan)
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
        #if COACH_IPHONE_QA
        restoreDiagnostic = .inProgress
        #endif
        defer { isRestoring = false }

        do {
            let grant = try await subscriptionService.restorePurchaseGrant()
            #if COACH_IPHONE_QA
            restoreDiagnostic = grant.subscription.tier == .premium ? .premium : .noCurrentEntitlement
            #endif
            reflect(grant)
            if grant.subscription.tier != .premium {
                message = "No previous purchase found on this Apple ID."
            }
        } catch {
            #if COACH_IPHONE_QA
            restoreDiagnostic = .failure(Self.diagnostic(from: error))
            #endif
            message = "We couldn't restore right now. Please try again later."
        }
    }

    private func reflect(_ grant: SubscriptionGrant) {
        if grant.subscription.tier == .premium {
            unlockedGrant = grant
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
    /// The schema defines `subscribe` as "paid subscription starts (trial converts or direct)". This
    /// call site owns the direct-purchase half. The later trial-to-paid half is deliberately separate:
    /// `TrialConversionObserver` receives verified StoreKit transaction updates and emits only for the
    /// first positive-price renewal of an introductory-free-trial chain. Keeping the sites distinct is
    /// what prevents the initial trial transaction from emitting both events.
    private func emitPurchaseTelemetry(for subscription: Subscription, plan: SubscriptionPlan) async {
        guard let analytics else { return }
        if subscription.trialEndsAt != nil {
            analytics.record(AnalyticsEvent(name: .trialStarted, timestampMs: timestampMs()))
        } else {
            analytics.record(
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
