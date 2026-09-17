import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Hosted UIKit behavior checks use only a local response double. Never capture live QA content.
@MainActor
final class CoachSyntheticQASurfaceTests: XCTestCase {
    private var window: UIWindow?
    private var defaults: UserDefaults!
    private var suite: String!

    private final class Transport: CoachProxyTransport, @unchecked Sendable {
        var calls = 0
        func post(to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
            calls += 1
            return (Data(#"{"reply":"Local offline surface double"}"#.utf8), 200)
        }
    }

    override func setUp() {
        suite = "CoachSyntheticQASurface-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func host(_ vm: CoachSyntheticQAViewModel, _ state: AppState) -> UIView {
        let (_, hosted) = HostedSurface.host(NavigationStack {
            CoachSyntheticQAView(viewModel: vm, appState: state, configurationEnabled: true)
        }, size: CGSize(width: 393, height: 852))
        window = hosted
        return hosted.rootViewController!.view
    }

    private func model(_ transport: Transport, _ state: AppState) -> CoachSyntheticQAViewModel {
        CoachSyntheticQAViewModel(
            client: CoachProxyClient(endpoint: URL(string: CoachProxyClient.productionOrigin)!,
                                     safetyIdentifier: testCoachSafetyIdentifier, transport: transport),
            subscription: MockSubscriptionService(subscription: .init(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil), simulatesPurchase: false),
            consent: { state.hasAcknowledgedCoachDataSharing },
            budget: CoachSyntheticQABudget(defaults: defaults)
        )
    }

    func testAppearingLabelsSyntheticDataAndSendsNothingWithoutConsentOrReadiness() async throws {
        let state = AppState(userDefaults: defaults)
        let transport = Transport()
        let vm = model(transport, state)
        await vm.loadEligibility()
        let root = host(vm, state)
        let labels = AccessibilityTree.labels(in: root)
        XCTAssertTrue(labels.contains("Synthetic QA — not your workout data"))
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Read Coach data disclosure", in: root))
        await vm.sendNext()
        XCTAssertEqual(transport.calls, 0)
        XCTAssertFalse(vm.canSend)
        XCTAssertFalse(state.hasAcknowledgedCoachDataSharing)
    }

    func testOfflineDoubleReplyIsExplicitlySyntheticAndNeverSemanticSuccess() async {
        let state = AppState(userDefaults: defaults)
        state.markCoachDataSharingAcknowledged()
        let transport = Transport()
        let vm = model(transport, state)
        await vm.loadEligibility()
        vm.readinessConfirmed = true
        await vm.sendNext()
        let root = host(vm, state)
        let labels = AccessibilityTree.labels(in: root)
        XCTAssertTrue(labels.contains { $0.hasPrefix("Synthetic QA reply:") })
        XCTAssertTrue(labels.contains { $0.hasPrefix("Synthetic QA reply. Local offline surface double") })
        XCTAssertEqual(vm.budget.stage, .whyAttempted)
        vm.close()
        XCTAssertNil(vm.reply)
        XCTAssertNil(vm.returnedSelection)
    }

    #if COACH_IPHONE_QA
    func testQAConfigurationRoutesCoachEntryToSyntheticSurface() {
        let state = AppState(userDefaults: defaults)
        let services = ServiceContainer.mock()
        let (_, hosted) = HostedSurface.host(NavigationStack {
            List { CoachEntryRow(services: services) }
        }.environment(state).environment(\.services, services), size: CGSize(width: 393, height: 852))
        window = hosted
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Coach Synthetic QA", in: hosted.rootViewController!.view))
    }
    #endif
}
