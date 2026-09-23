import XCTest
import StoreKit
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import RepToday

/// Real error projection + paywall/service composition, with no Apple operation or analytics sink.
@MainActor
final class StoreKitPaywallDiagnosticsTests: XCTestCase {
    private static let privateText = "PRIVATE-TEST-DESCRIPTION-DO-NOT-DISPLAY"

    private actor Facade: StoreKitFacade {
        enum Catalog { case available, empty, failure }
        let catalog: Catalog
        let failsSync: Bool
        let ownsPremium: Bool
        var calls: [String] = []

        init(catalog: Catalog = .available, failsSync: Bool = false, ownsPremium: Bool = false) {
            self.catalog = catalog
            self.failsSync = failsSync
            self.ownsPremium = ownsPremium
        }

        func loadProducts(ids: [String]) async throws -> [StoreProduct] {
            calls.append("products")
            switch catalog {
            case .available:
                return [StoreProduct(id: SubscriptionPlan.ProductID.monthly,
                                     displayPrice: "$1", period: .monthly, trialDescription: nil)]
            case .empty: return []
            case .failure:
                throw LiveStoreKitFacade.requestFailure(NSError(
                    domain: "ASDErrorDomain", code: 101,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE-CATALOG-DESCRIPTION"]
                ))
            }
        }
        func sync() async throws {
            calls.append("sync")
            if failsSync {
                throw LiveStoreKitFacade.requestFailure(NSError(
                    domain: "AMSErrorDomain", code: 202,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE-SYNC-DESCRIPTION"]
                ))
            }
        }
        func currentEntitlements() async -> [StoreEntitlement] {
            calls.append("entitlements")
            return ownsPremium ? [StoreEntitlement(productID: SubscriptionPlan.ProductID.monthly,
                                                  expiresAt: nil, isInTrialPeriod: false)] : []
        }
        func transactionHistory() async -> StoreTransactionHistory {
            calls.append("history")
            return .verified([])
        }
        func purchase(productID: String) async throws -> StorePurchaseResult {
            calls.append("purchase")
            return .success(await currentEntitlements())
        }
        nonisolated func listenForTransactions(
            prepareUpdate: @escaping @Sendable (StoreTransactionUpdate) async -> StoreTransactionProcessing?
        ) -> Task<Void, Never> { Task {} }
    }

    private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
        private var values: [String: Any] = [:]
        init() { super.init(suiteName: "StoreKitPaywallDiagnosticsTests.memory-only")! }
        override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
        override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
        override func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private func model(_ facade: Facade) -> PaywallViewModel {
        PaywallViewModel(subscriptionService: StoreKitSubscriptionService(
            facade: facade, userDefaults: MemoryDefaults()
        ))
    }

    func testCatalogAndRestoreMatrixKeepsCallsAndGrantOutcomesUnchanged() async {
        for catalog in [Facade.Catalog.available, .empty, .failure] {
            for failsSync in [false, true] {
                for owns in [false, true] {
                    let facade = Facade(catalog: catalog, failsSync: failsSync, ownsPremium: owns)
                    let vm = model(facade)
                    await vm.load()
                    let plans = vm.plans
                    await vm.restore()
                    XCTAssertEqual(vm.plans, plans)
                    XCTAssertEqual(vm.didUnlockPremium, !failsSync && owns)
                    XCTAssertEqual(vm.message, failsSync
                        ? "We couldn't restore right now. Please try again later."
                        : owns ? nil : "No previous purchase found on this Apple ID.")
                    XCTAssertFalse(vm.isBusy)
                    XCTAssertFalse(vm.isLoading)
                    let calls = await facade.calls
                    XCTAssertEqual(calls, failsSync
                        ? ["products", "sync", "history"]
                        : ["products", "sync", "history", "entitlements"])
                }
            }
        }
    }

    func testPurchaseStillUsesOnePurchaseAndPreservesTheGrant() async {
        let facade = Facade(ownsPremium: true)
        let vm = model(facade)
        await vm.load()
        await vm.purchase(vm.plans[0])
        XCTAssertTrue(vm.didUnlockPremium)
        XCTAssertNil(vm.message)
        let calls = await facade.calls
        XCTAssertEqual(calls, ["products", "purchase", "entitlements"])
    }

    #if COACH_IPHONE_QA
    private func projected(_ error: Error) throws -> StoreKitFailureDiagnostic {
        guard case .diagnosticFailure(let diagnostic) = LiveStoreKitFacade.requestFailure(error) else {
            XCTFail("QA must retain only the projected error fields")
            throw NSError(domain: "Test", code: 1)
        }
        return diagnostic
    }

    func testTypedCancellationAndNetworkCategoryDoNotGuessFromDescriptions() throws {
        XCTAssertEqual(try projected(StoreKitError.userCancelled).category, .cancelled)
        XCTAssertEqual(try projected(SKError(.paymentCancelled)).category, .cancelled)
        XCTAssertEqual(try projected(CancellationError()).category, .cancelled)
        let diagnostic = try projected(StoreKitError.networkError(URLError(.notConnectedToInternet)))
        XCTAssertEqual(diagnostic.category, .network)
        XCTAssertEqual(diagnostic.underlying?.domain, .url)
        XCTAssertEqual(diagnostic.underlying?.code, URLError.notConnectedToInternet.rawValue)
        let misleading = NSError(domain: "ASDErrorDomain", code: 42,
                                 userInfo: [NSLocalizedDescriptionKey: "user cancelled network error"])
        XCTAssertEqual(try projected(misleading).category, .unclassified)
    }

    func testTypedSystemCauseIsRetainedWithoutRecursingOrExposingDescriptions() throws {
        let nested = NSError(domain: "AMSErrorDomain", code: 999,
                             userInfo: [NSLocalizedDescriptionKey: Self.privateText])
        let cause = NSError(domain: "ASDErrorDomain", code: 17,
                            userInfo: [NSUnderlyingErrorKey: nested,
                                       NSLocalizedDescriptionKey: Self.privateText])
        let diagnostic = try projected(StoreKitError.systemError(cause))
        XCTAssertEqual(diagnostic.category, .system)
        XCTAssertEqual(diagnostic.error.domain, .storeKit)
        XCTAssertEqual(diagnostic.underlying?.domain, .appStore)
        XCTAssertEqual(diagnostic.underlying?.code, 17)
        XCTAssertFalse(diagnostic.summary.contains("999"))
        XCTAssertFalse(String(reflecting: diagnostic).contains(Self.privateText))
    }

    func testNSErrorUnderlyingCodeAndUnknownDomainRedaction() throws {
        let cause = NSError(domain: Self.privateText, code: 23,
                            userInfo: [NSLocalizedDescriptionKey: Self.privateText])
        let error = NSError(domain: "AMSErrorDomain", code: 18,
                            userInfo: [NSUnderlyingErrorKey: cause,
                                       NSLocalizedDescriptionKey: Self.privateText])
        let diagnostic = try projected(error)
        XCTAssertEqual(diagnostic.error.domain, .appleMediaServices)
        XCTAssertEqual(diagnostic.error.code, 18)
        XCTAssertEqual(diagnostic.underlying?.domain, .other)
        XCTAssertEqual(diagnostic.underlying?.code, 23)
        XCTAssertEqual(diagnostic.summary,
                       "unclassified — AMSErrorDomain / 18; underlying other / 23")
        XCTAssertEqual(try projected(cause).error.domain, .other)
        XCTAssertFalse(String(reflecting: diagnostic).contains(Self.privateText))
    }

    func testProductAndRestoreErrorsRemainIndependentlyVisible() async throws {
        let facade = Facade(catalog: .failure, failsSync: true)
        let vm = model(facade)
        XCTAssertEqual(vm.productsDiagnostic, .loading)
        XCTAssertEqual(vm.restoreDiagnostic, .notAttempted)
        await vm.load()
        let products = vm.productsDiagnostic
        XCTAssertEqual(products.summary, "unclassified — ASDErrorDomain / 101")
        await vm.restore()
        XCTAssertEqual(vm.productsDiagnostic, products)
        XCTAssertEqual(vm.restoreDiagnostic.summary, "unclassified — AMSErrorDomain / 202")
        // A subsequent catalog load likewise cannot erase the independent latest restore result.
        let restore = vm.restoreDiagnostic
        await vm.load()
        XCTAssertEqual(vm.restoreDiagnostic, restore)
    }

    func testEmptyCatalogAndThrownCatalogHaveDistinctDiagnostics() async {
        let empty = model(Facade(catalog: .empty))
        let failed = model(Facade(catalog: .failure))
        await empty.load()
        await failed.load()
        XCTAssertEqual(empty.productsDiagnostic, .noUsableProducts)
        XCTAssertNotEqual(empty.productsDiagnostic, failed.productsDiagnostic)
        XCTAssertEqual(empty.message, failed.message, "ordinary copy is deliberately unchanged")
    }

    func testSuccessfulSyncWithNoEntitlementDiffersFromThrownSync() async {
        let empty = model(Facade(catalog: .empty))
        let premium = model(Facade(catalog: .empty, ownsPremium: true))
        let failed = model(Facade(failsSync: true))
        await empty.restore()
        await premium.restore()
        await failed.restore()
        XCTAssertEqual(empty.restoreDiagnostic, .noCurrentEntitlement)
        XCTAssertEqual(premium.restoreDiagnostic, .premium)
        XCTAssertNotEqual(failed.restoreDiagnostic, .noCurrentEntitlement)
        XCTAssertTrue(premium.didUnlockPremium, "missing products cannot prevent a verified restore")
    }

    private final class UnprojectedService: SubscriptionServiceProtocol {
        func currentSubscription() async throws -> Subscription { .free }
        func refreshEntitlements() async throws -> Subscription { .free }
        func premiumPlans() async throws -> [SubscriptionPlan] { throw SubscriptionError.failed("PRIVATE") }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { .resolved(.free) }
        func purchasePremium() async throws -> Subscription { .free }
        func restorePurchases() async throws -> Subscription { throw SubscriptionError.failed("PRIVATE") }
    }

    func testUnprojectedErrorsUseFixedTextAndNewPaywallHasNoOldDiagnostics() async {
        let vm = PaywallViewModel(subscriptionService: UnprojectedService())
        await vm.load()
        await vm.restore()
        XCTAssertEqual(vm.productsDiagnostic.summary, "unclassified failure")
        XCTAssertEqual(vm.restoreDiagnostic.summary, "unclassified failure")
        let fresh = PaywallViewModel(subscriptionService: UnprojectedService())
        XCTAssertEqual(fresh.productsDiagnostic, .loading)
        XCTAssertEqual(fresh.restoreDiagnostic, .notAttempted)
    }
    #else
    func testOrdinaryRequestFailurePreservesExistingWrapping() {
        let error = NSError(domain: "ASDErrorDomain", code: 101,
                            userInfo: [NSLocalizedDescriptionKey: Self.privateText])
        XCTAssertEqual(LiveStoreKitFacade.requestFailure(error), .failed(Self.privateText))
    }
    #endif

    #if canImport(UIKit)
    func testHostedPaywallDiagnosticRowsFollowTheBuildConfiguration() async throws {
        let vm = model(Facade(catalog: .failure, failsSync: true))
        let surface = HostedSurface.host(PaywallView(viewModel: vm), size: CGSize(width: 390, height: 1800))
        defer { surface.window.isHidden = true }
        // Hosting pumps layout synchronously. Yield the actor too, so the view's asynchronous
        // catalog task has completed before simulating the user's subsequent Restore tap.
        let deadline = Date().addingTimeInterval(2)
        while (vm.isLoading || vm.message == nil) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard vm.message == "We couldn't load plans right now. Your workouts are always free - try again later.",
              !vm.isLoading else {
            XCTFail("Paywall catalog task did not settle before Restore")
            return
        }
        await vm.restore()
        HostedSurface.pump(for: 0.2)
        let labels = AccessibilityTree.labels(in: surface.host.view)
        XCTAssertTrue(labels.contains("We couldn't restore right now. Please try again later."))
        #if COACH_IPHONE_QA
        XCTAssertTrue(labels.contains("Products: unclassified — ASDErrorDomain / 101"))
        XCTAssertTrue(labels.contains("Restore: unclassified — AMSErrorDomain / 202"))
        #else
        XCTAssertFalse(labels.contains { $0.hasPrefix("Products: ") || $0.hasPrefix("Restore: ") })
        #endif
        XCTAssertFalse(labels.joined().contains("PRIVATE"))
    }
    #endif
}
