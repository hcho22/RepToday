import StoreKit
import StoreKitTest
import XCTest
@testable import RepToday

/// Restore Purchases and a fresh purchase through the production StoreKit path (`LiveStoreKitFacade` ->
/// `StoreKitSubscriptionService` -> `PaywallViewModel`) against a real StoreKit test session over the
/// local `RepToday.storekit` - the Xcode environment a build run from the `RepToday` scheme uses.
///
/// Restore finds exactly what the store the build talks to holds: a subscription bought in this store
/// comes back and unlocks Premium, while one bought elsewhere (TestFlight, the App Store) is not in it.
/// Every outcome is a clear answer on screen - Premium, nothing found, or could not restore - never a
/// silent return (`PaywallResultMessageLayoutTests` owns where the answer is drawn).
///
/// Skips where the session never takes control of StoreKit, exactly as
/// `IntroOfferEligibilityStoreKitTests` does: iOS 26.3+ simulators never receive the configuration under
/// `xcodebuild test`, so StoreKit would ask Apple's live Sandbox instead. The iOS 18 lane runs it.
@MainActor
final class RestorePurchasesStoreKitTests: XCTestCase {
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
        try await session?.setSimulatedError(nil, forAPI: .appStoreSync)
        session?.clearTransactions()
        session = nil
    }

    /// A paywall over the live StoreKit service, as a fresh app process builds it, with an in-memory
    /// account entitlement standing in for the server link.
    private func paywall() async -> (PaywallViewModel, MockPremiumEntitlementService) {
        let entitlements = MockPremiumEntitlementService()
        let model = PaywallViewModel(
            subscriptionService: StoreKitSubscriptionService(facade: LiveStoreKitFacade()),
            entryPoint: .coachUpsell,
            entitlements: entitlements
        )
        await model.load()
        return (model, entitlements)
    }

    func testARestoreWithNothingInTheStoreSaysNoneWasFoundOnScreen() async throws {
        let (model, entitlements) = await paywall()

        await model.restore()

        XCTAssertFalse(model.didUnlockPremium)
        XCTAssertEqual(model.message, "No active Premium subscription was found.")
        let linked = await entitlements.linked
        XCTAssertTrue(linked.isEmpty, "nothing is sent to the account when nothing was found")
        try await PaywallResultMessageLayoutTests.assertMessageIsOnScreen(
            model, on: .iPhone16, capturing: "storekit-restore-found-nothing"
        )
    }

    func testARestoreFindsASubscriptionBoughtInThisStoreAndUnlocksPremium() async throws {
        try await session.buyProduct(identifier: SubscriptionPlan.ProductID.monthly)
        let (model, entitlements) = await paywall()

        await model.restore()

        XCTAssertNil(model.message)
        let grant = try XCTUnwrap(model.unlockedGrant, "the restored subscription unlocks Premium")
        XCTAssertEqual(grant.subscription.tier, .premium)
        XCTAssertEqual(grant.provenance?.productID, SubscriptionPlan.ProductID.monthly)
        let linked = await entitlements.linked
        XCTAssertEqual(linked.count, 1, "the restored transaction is linked to the account")
        let status = try await entitlements.status()
        XCTAssertTrue(status.premium)
    }

    func testARestoreOfALapsedSubscriptionSaysNoneWasFound() async throws {
        try await session.buyProduct(identifier: SubscriptionPlan.ProductID.monthly)
        try session.expireSubscription(productIdentifier: SubscriptionPlan.ProductID.monthly)
        let (model, entitlements) = await paywall()

        await model.restore()

        XCTAssertFalse(model.didUnlockPremium)
        XCTAssertEqual(model.message, "No active Premium subscription was found.")
        let linked = await entitlements.linked
        XCTAssertTrue(linked.isEmpty)
    }

    func testARestoreWhoseAppStoreSyncFailsSaysItCouldNotRestoreOnScreen() async throws {
        try await session.buyProduct(identifier: SubscriptionPlan.ProductID.monthly)
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync
        )
        let (model, entitlements) = await paywall()

        await model.restore()

        XCTAssertFalse(model.didUnlockPremium, "a sync that failed looked nothing up, so it grants nothing")
        XCTAssertEqual(model.message, "We couldn't restore right now. Please try again later.")
        let linked = await entitlements.linked
        XCTAssertTrue(linked.isEmpty)
        try await PaywallResultMessageLayoutTests.assertMessageIsOnScreen(
            model, on: .iPhone16, capturing: "storekit-restore-failed"
        )
    }

    func testAFreshPurchaseStillUnlocksPremium() async throws {
        let (model, entitlements) = await paywall()
        let monthly = try XCTUnwrap(model.plans.first { $0.id == SubscriptionPlan.ProductID.monthly })

        await model.purchase(monthly)

        XCTAssertNil(model.message)
        let grant = try XCTUnwrap(model.unlockedGrant, "a completed purchase unlocks Premium")
        XCTAssertEqual(grant.subscription.tier, .premium)
        let linked = await entitlements.linked
        XCTAssertEqual(linked.count, 1, "the purchase is linked to the account")
    }
}
