import StoreKit
import StoreKitTest
import XCTest
@testable import RepToday

/// Regression for the paywall's trial line against a real StoreKit test session (the local
/// `RepToday.storekit` configuration): a fresh Apple ID is shown the free trial on both plans, and one
/// that already used it on either plan sees it on neither, because Apple grants one introductory offer
/// per subscription group. Runs through `LiveStoreKitFacade` and the service, the production path.
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
        XCTAssertEqual(plans.map(\.period), [.monthly, .yearly])
        XCTAssertEqual(plans.map(\.trialDescription), ["14-day free trial", "14-day free trial"])
        let labels = try await paywallLabels(capturing: "fresh-user-paywall.png")
        for priceLine in ["$7.99 / month", "$59.99 / year"] {
            XCTAssertTrue(labels.contains { $0.contains(priceLine) && $0.contains("14-day free trial") },
                          "\(priceLine) carries the trial: \(labels)")
        }
    }

    func testUserWhoUsedTheMonthlyTrialSeesNoTrialLineOnEitherPlan() async throws {
        try await assertNoTrialAfterUsingIt(on: SubscriptionPlan.ProductID.monthly,
                                            capturing: "trial-used-paywall.png")
    }

    func testUserWhoUsedTheYearlyTrialSeesNoTrialLineOnEitherPlan() async throws {
        try await assertNoTrialAfterUsingIt(on: SubscriptionPlan.ProductID.yearly,
                                            capturing: "yearly-trial-used-paywall.png")
    }

    private func assertNoTrialAfterUsingIt(on productID: String, capturing name: String) async throws {
        try await session.buyProduct(identifier: productID)
        try session.expireSubscription(productIdentifier: productID)
        let labels = try await paywallLabels(capturing: name)
        XCTAssertFalse(labels.contains { $0.contains("free trial") }, "\(labels)")
        let plans = try await plans()
        XCTAssertEqual(plans.map(\.period), [.monthly, .yearly])
        XCTAssertEqual(plans.map(\.trialDescription), [nil, nil], "a consumed trial must not be promised again")
        XCTAssertEqual(plans.map(\.priceLine), ["$7.99 / month", "$59.99 / year"])
    }
}
