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

    private var window: UIWindow?
    private let story = "US-AC03"

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    private func premiumSubscription() -> Subscription {
        Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
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
}
