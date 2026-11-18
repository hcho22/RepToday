import StoreKit
import StoreKitTest
import XCTest
@testable import RepToday

/// Regression for the paywall's trial line against a real StoreKit test session (the local
/// `RepToday.storekit` configuration): a fresh Apple ID is shown the monthly free trial, and one that
/// already used it is not. Runs through `LiveStoreKitFacade` and the service, the production path.
///
/// Both tests skip where the session never takes control of StoreKit: iOS 26.3+ simulators never receive
/// the configuration under `xcodebuild test` (the session logs `SKInternalErrorDomain` code 3; Apple
/// developer forums thread 826971), so StoreKit asks Apple's live Sandbox for the products over the
/// network instead, and a slow or failed Sandbox answer reads as no products at all. The iOS 18 lane
/// still runs them.
@MainActor
final class IntroOfferEligibilityStoreKitTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        // The configuration is attached to the scheme, not bundled, so read it from the source tree.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RepToday/Resources/RepToday.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        try await skipUnlessTheSessionServesTheProducts()
        try await session.waitUntilNoEntitlementRemains()
    }

    /// Proves the products come from `RepToday.storekit` by simulating a failed product load: a session
    /// in control fails the load with that exact error, while an ignored one lets it reach the network.
    private func skipUnlessTheSessionServesTheProducts() async throws {
        try await session.setSimulatedError(.generic(.notAvailableInStorefront), forAPI: .loadProducts)
        let isInControl: Bool
        do {
            _ = try await Product.products(for: SubscriptionPlan.ProductID.all)
            isInControl = false
        } catch StoreKitError.notAvailableInStorefront {
            isInControl = true
        } catch {
            isInControl = false
        }
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        guard isInControl else {
            throw XCTSkip("This simulator's StoreKit test session does not serve the local configuration")
        }
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    private func plans() async throws -> [SubscriptionPlan] {
        try await StoreKitSubscriptionService(facade: LiveStoreKitFacade()).premiumPlans()
    }

    /// Hosts the real paywall over the live StoreKit service and files a PNG (a temporary directory
    /// unless `REPTODAY_EVIDENCE_DIR` or `REPTODAY_WRITE_EVIDENCE` redirects it).
    private func paywallLabels(capturing name: String) async throws -> [String] {
        let size = CGSize(width: 393, height: 900)
        let model = PaywallViewModel(subscriptionService: StoreKitSubscriptionService(facade: LiveStoreKitFacade()))
        let (host, window) = HostedSurface.host(PaywallView(viewModel: model), size: size)
        defer { _ = (host, window) }
        try await HostedSurface.settle(until: {
            AccessibilityTree.labels(in: host.view).contains { $0.contains("/ year") }
        }, timeout: 15)
        let image = HostedSurface.capture(host.view, size: size)
        try EvidenceOutput.write(image, named: name, for: "trial-label-eligibility")
        return AccessibilityTree.labels(in: host.view)
    }

    func testFreshUserSeesTheTrialLine() async throws {
        // Read the plans before hosting the paywall: the first product load in a run waits on a cold
        // StoreKit test session, which can outlast the paywall's settle timeout. Awaiting it here, with
        // no timeout, warms the session the way the purchase does in the test below.
        let plans = try await plans()
        XCTAssertEqual(plans.first?.trialDescription, "14-day free trial")
        XCTAssertNil(plans.last?.trialDescription)
        let labels = try await paywallLabels(capturing: "fresh-user-paywall.png")
        XCTAssertTrue(labels.contains { $0.contains("14-day free trial") }, "\(labels)")
    }

    func testUserWhoAlreadyUsedTheTrialSeesNoTrialLine() async throws {
        try await session.buyProduct(identifier: SubscriptionPlan.ProductID.monthly)
        try session.expireSubscription(productIdentifier: SubscriptionPlan.ProductID.monthly)
        let labels = try await paywallLabels(capturing: "trial-used-paywall.png")
        XCTAssertFalse(labels.contains { $0.contains("free trial") }, "\(labels)")
        let plans = try await plans()
        XCTAssertEqual(plans.first?.period, .monthly)
        XCTAssertNil(plans.first?.trialDescription, "a consumed trial must not be promised again")
        XCTAssertEqual(plans.first?.priceLine, "$7.99 / month")
    }
}
