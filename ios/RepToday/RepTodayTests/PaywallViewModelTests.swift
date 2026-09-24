import XCTest
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import RepToday

/// Tests the paywall view model (US-N04).
///
/// It loads the purchasable plans, drives a purchase or restore, and reflects the resulting
/// entitlement - all without gating anything. A configurable stub service exercises the success and
/// failure paths:
/// - `load()` populates plans, and surfaces a gentle message (not a wall) when none are available;
/// - a successful purchase/restore preserves the exact Premium `Subscription` for its presenter; a
///   user-cancel or a nothing-owned restore does not, and a failure surfaces a gentle message.
@MainActor
final class PaywallViewModelTests: XCTestCase {

    // MARK: - Stub

    private final class StubService: SubscriptionServiceProtocol {
        var calls: [String] = []
        var beforeOperation: ((String) async -> Void)?
        var plans: [SubscriptionPlan]
        var plansError: Error?
        var purchaseOutcome: Subscription
        var purchaseIsPending: Bool
        var purchaseError: Error?
        var restoreOutcome: Subscription
        var restoreError: Error?

        init(
            plans: [SubscriptionPlan] = SubscriptionPlan.samples,
            plansError: Error? = nil,
            purchaseOutcome: Subscription = .free,
            purchaseIsPending: Bool = false,
            purchaseError: Error? = nil,
            restoreOutcome: Subscription = .free,
            restoreError: Error? = nil
        ) {
            self.plans = plans
            self.plansError = plansError
            self.purchaseOutcome = purchaseOutcome
            self.purchaseIsPending = purchaseIsPending
            self.purchaseError = purchaseError
            self.restoreOutcome = restoreOutcome
            self.restoreError = restoreError
        }

        func currentSubscription() async throws -> Subscription { .free }
        func refreshEntitlements() async throws -> Subscription { .free }

        func premiumPlans() async throws -> [SubscriptionPlan] {
            calls.append("load")
            await beforeOperation?("load")
            if let plansError { throw plansError }
            return plans
        }

        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
            calls.append("purchase")
            await beforeOperation?("purchase")
            if let purchaseError { throw purchaseError }
            return purchaseIsPending ? .pending : .resolved(purchaseOutcome)
        }

        func purchasePremium() async throws -> Subscription {
            if let purchaseError { throw purchaseError }
            return purchaseOutcome
        }

        func restorePurchases() async throws -> Subscription {
            calls.append("restore")
            await beforeOperation?("restore")
            if let restoreError { throw restoreError }
            return restoreOutcome
        }
    }

    private let premium = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)

    // MARK: - Load

    #if canImport(UIKit)
    func testHostedRetryRecoversPlansAndPreservesNoActiveRestoreResult() async throws {
        let service = StubService(plans: [])
        let vm = PaywallViewModel(subscriptionService: service)
        let surface = HostedSurface.host(PaywallView(viewModel: vm), size: CGSize(width: 390, height: 1200))
        defer { surface.window.isHidden = true }
        surface.window.windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        surface.window.makeKeyAndVisible()

        func settle(until condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(condition())
            try await Task.sleep(nanoseconds: 700_000_000)
            surface.host.view.layoutIfNeeded()
        }

        try await settle { vm.catalogMessage != nil && !vm.isBusy }
        let unavailable = try XCTUnwrap(vm.catalogMessage)
        let restore = try XCTUnwrap(AccessibilityTree.element(labeled: "Restore purchases", in: surface.host.view))
        XCTAssertTrue(restore.accessibilityActivate())
        let noActive = "No active Premium subscription was found."
        try await settle { vm.message == noActive && !vm.isBusy }
        let labels = AccessibilityTree.labels(in: surface.host.view)
        XCTAssertTrue(labels.contains(unavailable))
        XCTAssertTrue(labels.contains(noActive))
        XCTAssertFalse(vm.didUnlockPremium)

        // Keep the retry in flight so repeated activations cannot race an instant fixture response.
        var releaseLoad: CheckedContinuation<Void, Never>?
        service.plans = SubscriptionPlan.samples
        service.beforeOperation = { operation in
            if operation == "load" {
                await withCheckedContinuation { releaseLoad = $0 }
            }
        }
        defer { releaseLoad?.resume() }
        let retry = try XCTUnwrap(AccessibilityTree.element(labeled: "Retry plans", in: surface.host.view))
        XCTAssertTrue(retry.accessibilityActivate())
        _ = retry.accessibilityActivate()
        try await settle { releaseLoad != nil }
        XCTAssertTrue(vm.isLoading)
        XCTAssertTrue(AccessibilityTree.labels(in: surface.host.view).contains(noActive))
        let busyRestore = try XCTUnwrap(AccessibilityTree.element(labeled: "Restore purchases", in: surface.host.view))
        XCTAssertTrue(busyRestore.accessibilityTraits.contains(.notEnabled))
        _ = busyRestore.accessibilityActivate()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.calls, ["load", "restore", "load"])
        releaseLoad?.resume()
        releaseLoad = nil

        try await settle { !vm.isBusy && !vm.plans.isEmpty }
        XCTAssertEqual(vm.plans, SubscriptionPlan.samples)
        XCTAssertEqual(vm.message, noActive)
        XCTAssertNil(vm.catalogMessage)
        XCTAssertNil(AccessibilityTree.element(labeled: "Retry plans", in: surface.host.view))
        let recoveredLabels = AccessibilityTree.labels(in: surface.host.view)
        XCTAssertTrue(recoveredLabels.contains(noActive))
        for plan in SubscriptionPlan.samples {
            XCTAssertTrue(recoveredLabels.contains { $0.hasPrefix("\(plan.period.displayName), \(plan.priceLine)") })
        }
        try EvidenceOutput.write(
            HostedSurface.capture(surface.host.view, size: surface.host.view.bounds.size),
            named: "paywall-recovered-plans-after-restore.png", for: "premium-access"
        )
    }
    #endif

    func testLoadPopulatesPlans() async {
        let vm = PaywallViewModel(subscriptionService: StubService())
        await vm.load()

        XCTAssertEqual(vm.plans.count, 2)
        XCTAssertNil(vm.message, "a normal load surfaces no message")
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadWithNoPlansSurfacesGentleMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(plans: []))
        await vm.load()

        XCTAssertTrue(vm.plans.isEmpty)
        XCTAssertNotNil(vm.catalogMessage, "no plans shows a gentle, non-blocking message")
    }

    func testLoadFailureSurfacesGentleMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(plansError: SubscriptionError.failed("offline")))
        await vm.load()

        XCTAssertTrue(vm.plans.isEmpty)
        XCTAssertNotNil(vm.catalogMessage)
        XCTAssertFalse(vm.didUnlockPremium)
    }

    func testRetryRecoversCatalogWithoutErasingRestoreOutcome() async {
        let service = StubService(plans: [])
        let vm = PaywallViewModel(subscriptionService: service)
        await vm.load()
        let unavailable = vm.catalogMessage
        await vm.restore()
        XCTAssertEqual(vm.catalogMessage, unavailable)
        XCTAssertEqual(vm.message, "No active Premium subscription was found.")
        service.plans = SubscriptionPlan.samples
        await vm.load()
        XCTAssertEqual(vm.plans, SubscriptionPlan.samples)
        XCTAssertNil(vm.catalogMessage)
        XCTAssertEqual(vm.message, "No active Premium subscription was found.")
        XCTAssertFalse(vm.didUnlockPremium)
    }

    func testAllStoreOperationsExcludeEachOtherWhileSuspended() async throws {
        for operation in ["load", "purchase", "restore"] {
            let service = StubService()
            let vm = PaywallViewModel(subscriptionService: service)
            var continuation: CheckedContinuation<Void, Never>?
            service.beforeOperation = { _ in
                await withCheckedContinuation { continuation = $0 }
            }
            let task = Task {
                switch operation {
                case "load": await vm.load()
                case "purchase": await vm.purchase(SubscriptionPlan.samples[0])
                default: await vm.restore()
                }
            }
            for _ in 0..<200 where continuation == nil {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let resume = continuation else {
                task.cancel()
                XCTFail("Operation did not reach the suspended service")
                return
            }
            XCTAssertTrue(vm.isBusy)
            await vm.load()
            await vm.purchase(SubscriptionPlan.samples[0])
            await vm.restore()
            XCTAssertEqual(service.calls, [operation])
            resume.resume()
            await task.value
            XCTAssertFalse(vm.isBusy)
        }
    }

    // MARK: - Purchase

    func testPurchaseSuccessUnlocksPremium() async {
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: premium))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertTrue(vm.didUnlockPremium, "a granted entitlement unlocks the gate")
        XCTAssertEqual(vm.unlockedSubscription, premium, "the exact verified purchase grant is handed off")
        XCTAssertNil(vm.message)
        XCTAssertNil(vm.purchasingPlanID, "the in-flight marker clears when done")
    }

    func testPurchaseCancelDoesNotUnlock() async {
        // A cancel returns the unchanged (free) entitlement - not an error, no unlock, no message.
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: .free))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNil(vm.message, "a silent cancel does not nag the user")
    }

    func testPurchasePendingSurfacesWaitingMessageWithoutUnlocking() async {
        // Ask to Buy / deferred approval: the tap must not look silent (like a cancel), but it also
        // must not unlock - the entitlement lands out-of-band once approved.
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseIsPending: true))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium, "a pending purchase does not unlock premium yet")
        XCTAssertNotNil(vm.message, "a pending purchase surfaces a gentle waiting message, not silence")
        XCTAssertNil(vm.purchasingPlanID, "the in-flight marker clears when done")
    }

    func testPurchaseFailureSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseError: SubscriptionError.failed("declined")))
        await vm.purchase(SubscriptionPlan.samples[0])

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message, "a real failure surfaces a gentle message")
    }

    // MARK: - Restore

    func testRestoreSuccessUnlocksPremium() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreOutcome: premium))
        await vm.restore()

        XCTAssertTrue(vm.didUnlockPremium)
        XCTAssertEqual(vm.unlockedSubscription, premium, "restore uses the same exact-subscription handoff")
        XCTAssertNil(vm.message)
    }

    func testRestoreNothingOwnedSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreOutcome: .free))
        await vm.restore()

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message, "nothing to restore tells the user gently")
    }

    func testRestoreFailureSurfacesMessage() async {
        let vm = PaywallViewModel(subscriptionService: StubService(restoreError: SubscriptionError.failed("offline")))
        await vm.restore()

        XCTAssertFalse(vm.didUnlockPremium)
        XCTAssertNotNil(vm.message)
    }

    // MARK: - Telemetry (US-T12)
    //
    // These prove the monetization funnel emissions through `MockAnalyticsService` (in-process, no
    // network per FR-13). The live StoreKit purchase legs verify only on device / the `.storekit`
    // test configuration; what these unit tests prove is the view model's emission decisions - which
    // event fires, with which property, on which outcome - given a resolved purchase, not that a real
    // App Store purchase resolves.

    private let trialPremium = Subscription(
        tier: .premium,
        provider: .apple,
        expiresAt: nil,
        trialEndsAt: Date(timeIntervalSince1970: 10_000)
    )

    func testLoadEmitsPaywallShownOnceWithEntryPoint() async {
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(
            subscriptionService: StubService(),
            analytics: analytics,
            entryPoint: .progressUpsell
        )

        await vm.load()
        await vm.load() // a re-appear must not re-emit

        let events = await analytics.recordedEvents
        let shown = events.filter { $0.name == .paywallShown }
        XCTAssertEqual(shown.count, 1, "paywall_shown fires once per presentation, not per load()")
        XCTAssertEqual(shown.first?.properties["entry_point"], .string(EntryPoint.progressUpsell.rawValue))
    }

    func testDirectPaidPurchaseEmitsSubscribeWithPlan() async {
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: premium), analytics: analytics)
        let plan = SubscriptionPlan.samples[0]

        await vm.purchase(plan)

        let events = await analytics.recordedEvents
        let subscribe = events.filter { $0.name == .subscribe }
        XCTAssertEqual(subscribe.count, 1, "a direct paid purchase emits subscribe")
        XCTAssertEqual(subscribe.first?.properties["plan"], .string(plan.id))
        XCTAssertTrue(events.allSatisfy { $0.name != .trialStarted }, "a non-trial purchase never emits trial_started")
    }

    func testTrialPurchaseEmitsTrialStartedNotSubscribe() async {
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: trialPremium), analytics: analytics)

        await vm.purchase(SubscriptionPlan.samples[0])

        let events = await analytics.recordedEvents
        let trial = events.filter { $0.name == .trialStarted }
        XCTAssertEqual(trial.count, 1, "a trial-bearing purchase emits trial_started")
        XCTAssertTrue(trial.first?.properties.isEmpty ?? false, "trial_started carries no properties")
        XCTAssertTrue(events.allSatisfy { $0.name != .subscribe }, "a trial start does not also emit subscribe")
    }

    func testCancelledPurchaseEmitsNoMonetizationEvent() async {
        // A cancel resolves to the unchanged (free) entitlement - no grant, so nothing fires.
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseOutcome: .free), analytics: analytics)

        await vm.purchase(SubscriptionPlan.samples[0])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.allSatisfy { $0.name != .subscribe && $0.name != .trialStarted },
                      "a cancelled purchase emits neither subscribe nor trial_started")
    }

    func testPendingPurchaseEmitsNoMonetizationEvent() async {
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(subscriptionService: StubService(purchaseIsPending: true), analytics: analytics)

        await vm.purchase(SubscriptionPlan.samples[0])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.allSatisfy { $0.name != .subscribe && $0.name != .trialStarted },
                      "a pending purchase grants nothing yet, so it emits no monetization event")
    }

    func testFailedPurchaseEmitsNoMonetizationEvent() async {
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(
            subscriptionService: StubService(purchaseError: SubscriptionError.failed("declined")),
            analytics: analytics
        )

        await vm.purchase(SubscriptionPlan.samples[0])

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.allSatisfy { $0.name != .subscribe && $0.name != .trialStarted },
                      "a failed purchase emits no monetization event")
    }

    func testRestoreDoesNotEmitSubscribeOrTrialStarted() async {
        // Restore re-grants an already-owned entitlement; it is not a new purchase, so it must not
        // re-emit the monetization funnel events.
        let analytics = MockAnalyticsService()
        let vm = PaywallViewModel(subscriptionService: StubService(restoreOutcome: premium), analytics: analytics)

        await vm.restore()

        let events = await analytics.recordedEvents
        XCTAssertTrue(events.allSatisfy { $0.name != .subscribe && $0.name != .trialStarted },
                      "restoring a prior purchase does not emit subscribe or trial_started")
    }
}
