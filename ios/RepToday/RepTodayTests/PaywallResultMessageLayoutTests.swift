import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The paywall's answer to a purchase or a restore is on screen where the user acted.
///
/// It used to be drawn inside the scroll area, below both plan cards: on an iPhone 16 at the default
/// text size it sat under the pinned "Restore purchases" button, off screen, so a Restore that found
/// nothing (or failed) looked like nothing happened. It now sits outside the scroll area, directly above
/// that button. These cases fail on the old layout.
@MainActor
final class PaywallResultMessageLayoutTests: XCTestCase {

    /// The two sizes the paywall is checked at: the iPhone 16 the report was reproduced on, and the
    /// smallest supported phone at the largest text size, where the pinned footer is tallest.
    struct Phone {
        let name: String
        let size: CGSize
        let safeArea: UIEdgeInsets
        let textSize: DynamicTypeSize

        static let iPhone16 = Phone(
            name: "393x852", size: CGSize(width: 393, height: 852),
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), textSize: .large
        )
        static let smallPhoneLargestText = Phone(
            name: "375x667-ax5", size: CGSize(width: 375, height: 667),
            safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0), textSize: .accessibility5
        )
    }

    /// A service whose purchase is left awaiting approval (Ask to Buy), the paywall's longest message.
    private final class PendingPurchaseService: SubscriptionServiceProtocol, @unchecked Sendable {
        func currentSubscription() async throws -> Subscription { .free }
        func refreshEntitlements() async throws -> Subscription { .free }
        func premiumPlans() async throws -> [SubscriptionPlan] { SubscriptionPlan.samples }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { .pending }
        func purchasePremium() async throws -> Subscription { .free }
        func restorePurchases() async throws -> Subscription { .free }
    }

    func testARestoreThatFindsNothingSaysSoOnScreen() async throws {
        for phone in [Phone.iPhone16, .smallPhoneLargestText] {
            let model = PaywallViewModel(subscriptionService: MockSubscriptionService(simulatesPurchase: false))
            await model.load()
            await model.restore()
            XCTAssertEqual(model.message, "No active Premium subscription was found.")
            try await Self.assertMessageIsOnScreen(model, on: phone, capturing: "restore-found-nothing")
        }
    }

    func testARestoreThatFailedSaysSoOnScreen() async throws {
        for phone in [Phone.iPhone16, .smallPhoneLargestText] {
            let model = PaywallViewModel(subscriptionService: MockSubscriptionService(restoreFails: true))
            await model.load()
            await model.restore()
            XCTAssertEqual(model.message, "We couldn't restore right now. Please try again later.")
            try await Self.assertMessageIsOnScreen(model, on: phone, capturing: "restore-failed")
        }
    }

    func testAPurchaseAwaitingApprovalSaysSoOnScreen() async throws {
        for phone in [Phone.iPhone16, .smallPhoneLargestText] {
            let model = PaywallViewModel(subscriptionService: PendingPurchaseService())
            await model.load()
            await model.purchase(try XCTUnwrap(SubscriptionPlan.samples.first))
            let message = try XCTUnwrap(model.message)
            XCTAssertTrue(message.hasPrefix("This purchase needs approval"), message)
            try await Self.assertMessageIsOnScreen(model, on: phone, capturing: "purchase-pending")
        }
    }

    /// Hosts the real paywall over `model` (which has already answered a purchase or restore) and
    /// asserts the answer is on screen, above the pinned "Restore purchases" button rather than under
    /// it, and readable by its own label. An answer that fits must be wholly visible and sit right
    /// above the button; one too long for its capped share of the sheet (the largest text sizes)
    /// scrolls in place, so it must start on screen and show at least a quarter of the screen's height
    /// of itself. Files a PNG through `EvidenceOutput`.
    static func assertMessageIsOnScreen(
        _ model: PaywallViewModel, on phone: Phone, capturing name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let message = try XCTUnwrap(model.message, "no message to look for", file: file, line: line)
        let (host, window) = HostedSurface.host(
            PaywallView(viewModel: model).environment(\.dynamicTypeSize, phone.textSize),
            size: phone.size, emulatingSafeArea: phone.safeArea
        )
        defer { _ = (host, window) }
        let visible = window.bounds.inset(by: phone.safeArea)

        struct Placement {
            let message: CGRect
            let restore: CGRect
            let shown: CGFloat
            let owed: CGFloat
            var isOnScreen: Bool { shown >= owed - 0.5 }
        }
        func placement() -> Placement? {
            guard let messageElement = AccessibilityTree.element(labeled: message, in: host.view),
                  let restoreElement = AccessibilityTree.element(labeled: "Restore purchases", in: host.view)
            else { return nil }
            let origin = window.frame.origin
            let messageFrame = messageElement.accessibilityFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let restoreFrame = restoreElement.accessibilityFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let aboveTheButton = CGRect(
                x: visible.minX, y: visible.minY,
                width: visible.width, height: max(0, restoreFrame.minY - visible.minY)
            )
            let shown = messageFrame.intersection(aboveTheButton)
            return Placement(
                message: messageFrame, restore: restoreFrame,
                shown: shown.isNull ? 0 : shown.height,
                owed: min(messageFrame.height, phone.size.height / 4)
            )
        }
        // The pinned area takes its height from the laid-out text, one layout pass after it appears.
        try await HostedSurface.settle(until: { placement()?.isOnScreen == true }, file: file, line: line)

        let laidOut = try XCTUnwrap(placement(), "no message or Restore button on the paywall", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            laidOut.message.minY, visible.minY,
            "\(phone.name): the message \(laidOut.message) starts above the visible screen \(visible)",
            file: file, line: line
        )
        XCTAssertTrue(
            laidOut.isOnScreen,
            "\(phone.name): only \(laidOut.shown)pt of the message \(laidOut.message) shows above the "
                + "Restore button \(laidOut.restore) on the visible screen \(visible)",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            laidOut.restore.minY - laidOut.message.maxY, Theme.Spacing.md,
            "\(phone.name): the message \(laidOut.message) does not sit right above the Restore button \(laidOut.restore)",
            file: file, line: line
        )

        let image = HostedSurface.capture(host.view, size: phone.size)
        try EvidenceOutput.write(image, named: "\(name)-\(phone.name).png", for: EvidenceOutput.Story.restorePurchases)
    }
}
