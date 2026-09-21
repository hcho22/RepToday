import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AC03, the premium gate on the AI coach entry point: a free user
/// sees an upsell that opens the paywall (never the coach), and a Premium user reaches the coach.
///
/// This drives the *production* `CoachEntryRow` in a real key window over a `CoachGateViewModel`
/// backed by a free / Premium mock subscription, and asserts the load-bearing branch on the live
/// accessibility tree - the free row is a Premium-tagged upsell, the Premium row navigates into the
/// coach - then captures each state to a PNG under `artifacts/reports/US-AC03/`.
@MainActor
final class CoachGatingEvidenceTests: XCTestCase {

    /// Models the StoreKit timing observed on the physical phone: the purchase result is already a
    /// verified Premium grant while an immediate `Transaction.currentEntitlements` projection still
    /// reports the previous free state.
    private final class LaggingGrantSubscriptionService: SubscriptionServiceProtocol {
        private(set) var currentSubscriptionReadCount = 0

        func currentSubscription() async throws -> Subscription {
            currentSubscriptionReadCount += 1
            return .free
        }

        func refreshEntitlements() async throws -> Subscription { .free }
        func premiumPlans() async throws -> [SubscriptionPlan] { SubscriptionPlan.samples }

        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
            .resolved(Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil))
        }

        func purchasePremium() async throws -> Subscription {
            Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        }

        func restorePurchases() async throws -> Subscription {
            Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        }
    }

    private var window: UIWindow?
    private let story = "US-AC03"

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func premiumSubscription() -> Subscription {
        Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
    }

    private func replacingSubscription(
        in base: ServiceContainer,
        with subscriptionService: any SubscriptionServiceProtocol
    ) -> ServiceContainer {
        ServiceContainer(
            exerciseService: base.exerciseService,
            workoutEngine: base.workoutEngine,
            sessionPolicyService: base.sessionPolicyService,
            consistencyService: base.consistencyService,
            phaseService: base.phaseService,
            userService: base.userService,
            workoutLogService: base.workoutLogService,
            activeSessionStore: base.activeSessionStore,
            sessionCompletionService: base.sessionCompletionService,
            healthKitService: base.healthKitService,
            subscriptionService: subscriptionService,
            authService: base.authService,
            analyticsService: base.analyticsService,
            accountDeletionService: base.accountDeletionService,
            coachClient: base.coachClient,
            coachPolicyService: base.coachPolicyService
        )
    }

    private func spoken() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.spokenStrings(in: root)
    }

    private func spokenContains(_ needle: String) -> Bool {
        spoken().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func capture(named fileName: String, size: CGSize) throws {
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        let image = HostedSurface.capture(root, size: size)
        let path = try EvidenceOutput.write(image, named: fileName, for: story)
        print("US-AC03 EVIDENCE: \(fileName) -> \(path)")
    }

    private func presentCoachPaywall(using subscriptionService: LaggingGrantSubscriptionService) throws -> UIView {
        let services = replacingSubscription(in: .mock(), with: subscriptionService)
        let (_, hostedWindow) = HostedSurface.host(
            NavigationStack { List { CoachEntryRow(services: services) } }
                .environment(\.services, services),
            size: CGSize(width: 393, height: 852)
        )
        window = hostedWindow

        let root = try XCTUnwrap(hostedWindow.rootViewController?.view)
        let coachUpsell = try XCTUnwrap(AccessibilityTree.element(labeled: "Coach", in: root))
        XCTAssertTrue(coachUpsell.accessibilityActivate())
        HostedSurface.pump(for: 1)
        return try XCTUnwrap(hostedWindow.rootViewController?.presentedViewController?.view)
    }

    private func assertCoachUnlockedAfterLaggingReconciliation(
        _ subscriptionService: LaggingGrantSubscriptionService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        HostedSurface.pump(for: HostedSurface.settleInterval)
        XCTAssertTrue(
            spokenContains("Ask the coach about your workouts"),
            "the verified grant must survive a lagging free cache read; tree reads \(spoken())",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            subscriptionService.currentSubscriptionReadCount,
            2,
            "the regression must include both the initial free read and the lagging post-grant read",
            file: file,
            line: line
        )
    }

    /// A free user's Coach row is the upsell: a Premium-tagged entry whose hint says it opens Premium,
    /// and it never carries the coach's "ask the coach" affordance.
    func testFreeUserSeesUpsellNotCoach() async throws {
        let viewModel = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: .free))
        await viewModel.load()
        XCTAssertFalse(viewModel.isPremium)

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(
            NavigationStack { List { CoachEntryRow(viewModel: viewModel) } }, size: size
        )
        window = hostedWindow

        XCTAssertTrue(spokenContains("Coach"), "the Coach entry is present; tree reads \(spoken())")
        XCTAssertTrue(spokenContains("Opens Premium to unlock the coach"),
                      "the free row is the paywall upsell; tree reads \(spoken())")
        XCTAssertFalse(spokenContains("Ask the coach about your workouts"),
                       "a free user's row must not offer the coach itself; tree reads \(spoken())")

        try capture(named: "01-free-user-coach-upsell.png", size: size)
        _ = host
    }

    /// A Premium user's Coach row navigates into the coach: it carries the "ask the coach" affordance
    /// and no upsell hint.
    func testPremiumUserReachesCoach() async throws {
        let viewModel = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: premiumSubscription()))
        await viewModel.load()
        XCTAssertTrue(viewModel.isPremium)

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(
            NavigationStack { List { CoachEntryRow(viewModel: viewModel) } }, size: size
        )
        window = hostedWindow

        XCTAssertTrue(spokenContains("Coach"), "the Coach entry is present; tree reads \(spoken())")
        XCTAssertTrue(spokenContains("Ask the coach about your workouts"),
                      "a Premium user's row reaches the coach; tree reads \(spoken())")
        XCTAssertFalse(spokenContains("Opens Premium to unlock the coach"),
                       "a Premium user must not see the upsell; tree reads \(spoken())")

        try capture(named: "02-premium-user-coach.png", size: size)
        _ = host
    }

    /// Regression for the physical-device purchase race: the exact production row opens the exact
    /// paywall, StoreKit returns a verified Premium subscription, and the immediate entitlement-cache
    /// read still says free. The authoritative purchase result must keep Coach unlocked.
    func testVerifiedPurchaseUnlocksCoachWhenImmediateEntitlementReadStillLags() throws {
        let subscriptionService = LaggingGrantSubscriptionService()
        let paywall = try presentCoachPaywall(using: subscriptionService)
        let monthlyPlan = try XCTUnwrap(
            AccessibilityTree.element(whereLabel: { $0.hasPrefix("Monthly, ") }, in: paywall)
        )
        XCTAssertTrue(monthlyPlan.accessibilityActivate())
        assertCoachUnlockedAfterLaggingReconciliation(subscriptionService)
    }

    /// Restore uses the same authoritative handoff as purchase; it must not regress into a second,
    /// cache-only unlock path.
    func testVerifiedRestoreUnlocksCoachWhenImmediateEntitlementReadStillLags() throws {
        let subscriptionService = LaggingGrantSubscriptionService()
        let paywall = try presentCoachPaywall(using: subscriptionService)
        let restore = try XCTUnwrap(AccessibilityTree.element(labeled: "Restore purchases", in: paywall))
        XCTAssertTrue(restore.accessibilityActivate())
        assertCoachUnlockedAfterLaggingReconciliation(subscriptionService)
    }
}
