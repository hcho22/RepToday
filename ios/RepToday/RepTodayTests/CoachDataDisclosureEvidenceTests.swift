import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Evidence for the Coach data disclosure (US-AC04, updated for the Coach agent in M4, US-CA07): before
/// first use, a plain disclosure states that the user's message and their training records - workout
/// history and injury history among them - reach OpenAI to write the reply, that the conversation and
/// accepted Custom Workouts are saved to the account, what is never sent, and that declining sends
/// nothing.
///
/// It drives the production `CoachTabView` in a real window with a fresh `AppState`, so the overlay
/// presents exactly as on a first open; the send-path gate itself is proved in `CoachViewModelTests`.
/// PNGs go to `EvidenceOutput`'s folder for "US-CA07".
@MainActor
final class CoachDataDisclosureEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-CA07"
    private let surfaceSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        if let window { HostedSurface.dismantle(window) }
        window = nil
        super.tearDown()
    }

    private func freshAppState() -> AppState {
        let suite = "RepToday.US-CA07.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppState(userDefaults: defaults)
    }

    private func hostCoach(_ viewModel: CoachViewModel, appState: AppState) -> UIView {
        let (host, hostedWindow) = HostedSurface.host(
            CoachTabView(viewModel: viewModel)
                .environment(appState)
                .environment(\.services, ServiceContainer.mock()),
            size: surfaceSize
        )
        window = hostedWindow
        return host.view
    }

    private func spoken(in root: UIView) -> String {
        AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")
    }

    /// The disclosure names everything that reaches the model provider - the workout and injury history
    /// included - what is saved, what is never sent, and offers both controls.
    func testDisclosureNamesWorkoutAndInjuryHistoryAndOffersBothControls() throws {
        let (host, hostedWindow) = HostedSurface.host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                CoachDataDisclosureView(onAcknowledge: {}, onDecline: {})
            },
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        for fact in ["OpenAI", "workout history", "injury areas you've flagged", "whether you're 18 or over",
                     "today's plan", "saved to your Rep Today account", "Deleting your account deletes them",
                     "name, email, height and weight are never sent", "up to 30 days", "never your name or email",
                     "until you confirm it", "never gives medical advice"] {
            XCTAssertTrue(spoken.localizedCaseInsensitiveContains(fact), "the disclosure must say \"\(fact)\"; spoke: \(spoken)")
        }
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.acknowledge, in: root))
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.decline, in: root))

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "01-coach-data-disclosure.png", for: story)
        print("US-CA07 EVIDENCE: 01-coach-data-disclosure.png -> \(path)")
    }

    /// The Settings mirror says the same facts, apart from the telemetry control.
    func testSettingsFooterMirrorsTheDisclosure() {
        let footer = CoachDataDisclosureCopy.settingsFooter
        for fact in ["OpenAI", "workout history", "flagged injury", "18 or over", "never sent", "30 days", "deleted with it",
                     "separate from the anonymous usage data"] {
            XCTAssertTrue(footer.localizedCaseInsensitiveContains(fact), "the Settings footer must say \"\(fact)\"")
        }
    }

    /// On a fresh install the real Coach tab presents the disclosure before first use, and nothing has
    /// been sent behind it.
    func testRealCoachTabPresentsTheDisclosureBeforeFirstUse() async throws {
        let fixture = CoachFixture(consent: false)
        await fixture.viewModel.load()
        let appState = freshAppState()
        XCTAssertTrue(appState.shouldShowCoachDataDisclosure)

        let root = hostCoach(fixture.viewModel, appState: appState)
        try await HostedSurface.settle(until: { self.spoken(in: root).localizedCaseInsensitiveContains("OpenAI") })
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.acknowledge, in: root))

        let sent = await fixture.coach.sent
        XCTAssertTrue(sent.isEmpty, "no turn leaves the device while the disclosure is up")
        XCTAssertTrue(fixture.viewModel.needsDataSharingConsent)
        XCTAssertFalse(fixture.viewModel.canSend)
    }

    /// Declining sends nothing and records nothing; the chat offers the disclosure again.
    func testDecliningSendsNothing() async throws {
        let fixture = CoachFixture(consent: false)
        await fixture.viewModel.load()
        let appState = freshAppState()
        _ = hostCoach(fixture.viewModel, appState: appState)

        fixture.viewModel.draft = "why squats today?"
        await fixture.viewModel.send()
        await fixture.viewModel.sendQuickAction(CoachViewModel.quickActions[0])

        let sent = await fixture.coach.sent
        XCTAssertTrue(sent.isEmpty, "declining sends nothing")
        XCTAssertFalse(appState.hasAcknowledgedCoachDataSharing, "declining records no consent")
    }

    /// An install that acknowledged this contract skips the disclosure.
    func testAcknowledgedInstallSeesNoDisclosure() async throws {
        let fixture = CoachFixture(consent: false)
        await fixture.viewModel.load()
        let appState = freshAppState()
        appState.markCoachDataSharingAcknowledged()

        let root = hostCoach(fixture.viewModel, appState: appState)
        try await HostedSurface.settle(until: { !fixture.viewModel.needsDataSharingConsent })
        let spoken = spoken(in: root)
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains(CoachDataDisclosureCopy.title), "spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("Message to the coach"), "spoke: \(spoken)")
    }
}
