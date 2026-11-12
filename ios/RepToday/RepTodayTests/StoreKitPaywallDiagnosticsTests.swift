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
                                     displayPrice: "$1", period: .monthly, trialDescription: nil,
                                     isEligibleForIntroOffer: false)]
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
        let restore = Task { await vm.restore() }
        let deadline = Date().addingTimeInterval(2)
        while !(await facade.calls).contains("sync"), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(vm.isBusy)
        XCTAssertTrue(vm.isRestoring)
        await vm.restore()
        await vm.load()
        await vm.purchase(try XCTUnwrap(vm.plans.first))
        let inFlightCalls = await facade.calls
        XCTAssertEqual(inFlightCalls, ["products", "sync"])
        await facade.resumeSync()
        await restore.value
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(vm.message, "No active Premium subscription was found.")
        let calls = await facade.calls
        XCTAssertEqual(calls, ["products", "sync", "history", "entitlements"])
    }

    func testOrdinaryRequestFailurePreservesExistingWrapping() {
        let error = NSError(domain: "ASDErrorDomain", code: 101,
                            userInfo: [NSLocalizedDescriptionKey: Self.privateText])
        XCTAssertEqual(LiveStoreKitFacade.requestFailure(error), .failed(Self.privateText))
    }

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
        XCTAssertFalse(labels.contains { $0.hasPrefix("Products: ") || $0.hasPrefix("Restore: ") })
        XCTAssertFalse(labels.joined().contains("PRIVATE"))
        let calls = await facade.calls
        XCTAssertEqual(calls, ["products", "sync", "history"], "One user tap adds only the existing restore sequence")
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
