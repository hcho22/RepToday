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
        let suspendsSync: Bool
        var calls: [String] = []
        private var syncContinuation: CheckedContinuation<Void, Never>?

        init(catalog: Catalog = .available, failsSync: Bool = false, ownsPremium: Bool = false,
             suspendsSync: Bool = false) {
            self.catalog = catalog
            self.failsSync = failsSync
            self.ownsPremium = ownsPremium
            self.suspendsSync = suspendsSync
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
            if suspendsSync {
                await withCheckedContinuation { syncContinuation = $0 }
            }
            if failsSync {
                throw LiveStoreKitFacade.requestFailure(NSError(
                    domain: "AMSErrorDomain", code: 202,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE-SYNC-DESCRIPTION"]
                ))
            }
        }
        func resumeSync() {
            syncContinuation?.resume()
            syncContinuation = nil
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
                    let catalogMessage = vm.catalogMessage
                    XCTAssertEqual(catalogMessage == nil, catalog == .available)
                    await vm.restore()
                    XCTAssertEqual(vm.plans, plans)
                    XCTAssertEqual(vm.catalogMessage, catalogMessage)
                    XCTAssertEqual(vm.didUnlockPremium, !failsSync && owns)
                    XCTAssertEqual(vm.message, failsSync
                        ? "We couldn't restore right now. Please try again later."
                        : owns ? nil : "No active Premium subscription was found.")
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

    func testRestoreInFlightPreservesCatalogAndBlocksDuplicateOperations() async throws {
        let facade = Facade(suspendsSync: true)
        let vm = model(facade)
        await vm.load()
        #if COACH_IPHONE_QA
        XCTAssertEqual(vm.productsDiagnostic, .loaded(1))
        XCTAssertEqual(vm.restoreDiagnostic, .notAttempted)
        #endif
        let restore = Task { await vm.restore() }
        let deadline = Date().addingTimeInterval(2)
        while !(await facade.calls).contains("sync"), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(vm.isBusy)
        XCTAssertTrue(vm.isRestoring)
        #if COACH_IPHONE_QA
        XCTAssertEqual(vm.productsDiagnostic, .loaded(1))
        XCTAssertEqual(vm.restoreDiagnostic, .inProgress)
        #endif
        await vm.restore()
        await vm.load()
        await vm.purchase(try XCTUnwrap(vm.plans.first))
        let inFlightCalls = await facade.calls
        XCTAssertEqual(inFlightCalls, ["products", "sync"])
        await facade.resumeSync()
        await restore.value
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(vm.message, "No active Premium subscription was found.")
        #if COACH_IPHONE_QA
        XCTAssertEqual(vm.productsDiagnostic, .loaded(1))
        XCTAssertEqual(vm.restoreDiagnostic, .noCurrentEntitlement)
        #endif
        let calls = await facade.calls
        XCTAssertEqual(calls, ["products", "sync", "history", "entitlements"])
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
        XCTAssertEqual(empty.catalogMessage, failed.catalogMessage, "ordinary copy is deliberately unchanged")
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
        var catalogError: SubscriptionError = .failed("PRIVATE")
        func currentSubscription() async throws -> Subscription { .free }
        func refreshEntitlements() async throws -> Subscription { .free }
        func premiumPlans() async throws -> [SubscriptionPlan] { throw catalogError }
        func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome { .resolved(.free) }
        func purchasePremium() async throws -> Subscription { .free }
        func restorePurchases() async throws -> Subscription { throw SubscriptionError.failed("PRIVATE") }
    }

    func testRawEmptyLookupDiffersFromProductsRejectedBySubscriptionFilter() async {
        for rawCount in [0, 2] {
            let service = UnprojectedService()
            service.catalogError = .diagnosticProductsUnavailable(rawProductCount: rawCount)
            let vm = PaywallViewModel(subscriptionService: service)
            await vm.load()
            XCTAssertEqual(vm.productsDiagnostic, .lookupWithoutSubscriptions(rawCount))
            XCTAssertEqual(vm.productsDiagnostic.summary,
                           "lookup returned \(rawCount) products; 0 usable subscriptions")
            await vm.restore()
            XCTAssertEqual(vm.productsDiagnostic, .lookupWithoutSubscriptions(rawCount))
            XCTAssertNotNil(vm.catalogMessage)
        }
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
        let facade = Facade(catalog: .failure, failsSync: true)
        let vm = model(facade)
        let surface = HostedSurface.host(PaywallView(viewModel: vm), size: CGSize(width: 390, height: 1000))
        defer { surface.window.isHidden = true }
        // The isolated SwiftUI test host uses scenes. Attach the evidence window to its live
        // scene so SwiftUI commits subsequent frames, not just the initial offscreen layout.
        surface.window.windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        surface.window.makeKeyAndVisible()
        // Hosting pumps layout synchronously. Yield the actor too, so the view's asynchronous
        // catalog task has completed before simulating the user's subsequent Restore tap.
        let deadline = Date().addingTimeInterval(2)
        while (vm.isLoading || vm.catalogMessage == nil) && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard vm.catalogMessage == "We couldn't load plans right now. Your workouts are always free - try again later.",
              !vm.isLoading else {
            XCTFail("Paywall catalog task did not settle before Restore")
            return
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        surface.host.view.setNeedsLayout()
        surface.host.view.layoutIfNeeded()
        #if COACH_IPHONE_QA
        try EvidenceOutput.write(
            HostedSurface.capture(surface.host.view, size: surface.host.view.bounds.size),
            named: "qa-before-restore.png", for: "coach-storekit-diagnostics"
        )
        #endif
        let restore = try XCTUnwrap(AccessibilityTree.element(labeled: "Restore purchases", in: surface.host.view))
        XCTAssertTrue(restore.accessibilityActivate(), "Drive the actual Restore control")
        let restoreDeadline = Date().addingTimeInterval(2)
        while vm.message != "We couldn't restore right now. Please try again later.", Date() < restoreDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // Yield the main actor for SwiftUI's render transaction, then lay out the new frame.
        // Accessibility can expose updated text before the layer tree used by capture updates.
        try await Task.sleep(nanoseconds: 700_000_000)
        surface.host.view.setNeedsLayout()
        surface.host.view.layoutIfNeeded()
        HostedSurface.pump(for: 0.2)
        let labels = AccessibilityTree.labels(in: surface.host.view)
        XCTAssertTrue(labels.contains("We couldn't restore right now. Please try again later."))
        XCTAssertTrue(labels.contains("We couldn't load plans right now. Your workouts are always free - try again later."))
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Retry plans", in: surface.host.view))
        #if COACH_IPHONE_QA
        XCTAssertTrue(labels.contains("Products: unclassified — ASDErrorDomain / 101"))
        XCTAssertTrue(labels.contains("Restore: unclassified — AMSErrorDomain / 202"))
        #else
        XCTAssertFalse(labels.contains { $0.hasPrefix("Products: ") || $0.hasPrefix("Restore: ") })
        #endif
        XCTAssertFalse(labels.joined().contains("PRIVATE"))
        let calls = await facade.calls
        XCTAssertEqual(calls, ["products", "sync", "history"], "One user tap adds only the existing restore sequence")
        #if COACH_IPHONE_QA
        try EvidenceOutput.write(
            HostedSurface.capture(surface.host.view, size: surface.host.view.bounds.size),
            named: "qa-after-restore.png", for: "coach-storekit-diagnostics"
        )
        // Render the same live state at an accessibility text size, without rehosting/reloading.
        surface.host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        surface.window.frame.size.height = 2800
        surface.host.view.frame = surface.window.bounds
        try await Task.sleep(nanoseconds: 700_000_000)
        surface.host.view.setNeedsLayout()
        surface.host.view.layoutIfNeeded()
        HostedSurface.pump(for: 0.2)
        let largeLabels = AccessibilityTree.labels(in: surface.host.view)
        XCTAssertTrue(largeLabels.contains("Products: unclassified — ASDErrorDomain / 101"))
        XCTAssertTrue(largeLabels.contains("Restore: unclassified — AMSErrorDomain / 202"))
        try EvidenceOutput.write(
            HostedSurface.capture(surface.host.view, size: surface.host.view.bounds.size),
            named: "qa-accessibility-after-restore.png", for: "coach-storekit-diagnostics"
        )
        #endif
        let retry = try XCTUnwrap(AccessibilityTree.element(labeled: "Retry plans", in: surface.host.view))
        XCTAssertTrue(retry.accessibilityActivate(), "Drive the actual accessible Retry control")
        let retryDeadline = Date().addingTimeInterval(2)
        while (await facade.calls).filter({ $0 == "products" }).count < 2, Date() < retryDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let afterRetry = await facade.calls
        XCTAssertEqual(afterRetry.filter { $0 == "products" }.count, 2)
        XCTAssertEqual(vm.message, "We couldn't restore right now. Please try again later.")
    }
    #endif
}
