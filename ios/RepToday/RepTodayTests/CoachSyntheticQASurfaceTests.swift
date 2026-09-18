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

    func testSchemaPreparationOpensThroughVoiceOverActionAndRendersBoundedOneAttemptControls() async throws {
        let state = AppState(userDefaults: defaults)
        state.markCoachDataSharingAcknowledged()
        let vm = model(Transport(), state)
        await vm.loadEligibility()
        vm.readinessConfirmed = true
        let root = host(vm, state)
        let modelSendBefore = try XCTUnwrap(AccessibilityTree.element(whereLabel: {
            $0.hasPrefix("Send synthetic ")
        }, in: root))
        XCTAssertFalse(modelSendBefore.accessibilityTraits.contains(.notEnabled))
        let title = try XCTUnwrap(AccessibilityTree.element(labeled: "Synthetic QA — not your workout data", in: root))
        let action = try XCTUnwrap(title.accessibilityCustomActions?.first {
            $0.name == "Open schema verification preparation"
        })
        let activate = try XCTUnwrap(action.actionHandler)

        XCTAssertTrue(activate(action))
        HostedSurface.pump(for: 0.5)
        root.setNeedsLayout()
        root.layoutIfNeeded()

        let labels = AccessibilityTree.labels(in: root)
        XCTAssertTrue(labels.contains("Apple proof schema — preparation only"))
        XCTAssertTrue(labels.contains("This exact schema-only operation is separately authorized"))
        XCTAssertTrue(labels.contains("Verify Apple schema once"))
        let modelSendAfter = try XCTUnwrap(AccessibilityTree.element(whereLabel: {
            $0.hasPrefix("Send synthetic ")
        }, in: root))
        XCTAssertTrue(modelSendAfter.accessibilityTraits.contains(.notEnabled))

        window?.isHidden = true
        let (panelHost, panelWindow) = HostedSurface.host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView { CoachProofSchemaProbeView() }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent),
            size: CGSize(width: 393, height: 852)
        )
        window = panelWindow
        let panelRoot = panelHost.view!
        let panelLabels = AccessibilityTree.labels(in: panelRoot)
        XCTAssertTrue(panelLabels.contains("Apple proof schema — preparation only"))
        XCTAssertTrue(panelLabels.contains("Approved App ID prefix"))
        XCTAssertTrue(panelLabels.contains("This exact schema-only operation is separately authorized"))
        XCTAssertTrue(panelLabels.contains("Verify Apple schema once"))

        let image = HostedSurface.capture(panelRoot, size: CGSize(width: 393, height: 852))
        let path = try EvidenceOutput.write(
            image,
            named: "01-qa-proof-schema-preparation.png",
            for: "coach-testflight-schema-probe"
        )
        print("COACH SCHEMA EVIDENCE: 01-qa-proof-schema-preparation.png -> \(path)")
    }

    func testServerProofPreparationOpensOnTheDedicatedPanelAndRendersItsBoundedContract() async throws {
        let state = AppState(userDefaults: defaults)
        state.markCoachDataSharingAcknowledged()
        let vm = model(Transport(), state)
        await vm.loadEligibility()
        vm.readinessConfirmed = true
        let root = host(vm, state)
        let title = try XCTUnwrap(AccessibilityTree.element(
            labeled: "Synthetic QA — not your workout data", in: root
        ))
        let action = try XCTUnwrap(title.accessibilityCustomActions?.first {
            $0.name == "Open schema verification preparation"
        })
        XCTAssertTrue(try XCTUnwrap(action.actionHandler)(action))
        HostedSurface.pump(for: 0.5)

        let selector = try XCTUnwrap(AccessibilityTree.element(
            labeled: "Server admission preparation", in: root
        ))
        XCTAssertTrue(selector.accessibilityActivate())
        HostedSurface.pump(for: 0.5)
        root.setNeedsLayout()
        root.layoutIfNeeded()

        let labels = AccessibilityTree.labels(in: root)
        XCTAssertTrue(labels.contains("Server proof admission — preparation only"))
        XCTAssertTrue(labels.contains("This exact proof-only operation is separately authorized"))
        XCTAssertTrue(labels.contains("Verify server gates once"))
        let modelSend = try XCTUnwrap(AccessibilityTree.element(whereLabel: {
            $0.hasPrefix("Send synthetic ")
        }, in: root))
        XCTAssertTrue(modelSend.accessibilityTraits.contains(.notEnabled))

        window?.isHidden = true
        let (panelHost, panelWindow) = HostedSurface.host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView { CoachRuntimeProofProbeView(transport: nil) }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.accent),
            size: CGSize(width: 393, height: 852)
        )
        window = panelWindow
        let panelRoot = panelHost.view!
        let panelLabels = AccessibilityTree.labels(in: panelRoot)
        XCTAssertTrue(panelLabels.contains("Server proof admission — preparation only"))
        XCTAssertTrue(panelLabels.contains("This exact proof-only operation is separately authorized"))
        let verify = try XCTUnwrap(AccessibilityTree.element(labeled: "Verify server gates once", in: panelRoot))
        XCTAssertTrue(verify.accessibilityTraits.contains(.notEnabled))

        let image = HostedSurface.capture(panelRoot, size: CGSize(width: 393, height: 852))
        let path = try EvidenceOutput.write(
            image,
            named: "01-server-proof-admission-preparation.png",
            for: "coach-proof-only-qa"
        )
        print("COACH PROOF EVIDENCE: 01-server-proof-admission-preparation.png -> \(path)")
    }
    #endif
}
