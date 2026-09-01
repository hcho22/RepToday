import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AC04, the coach data disclosure: before first use, a plain,
/// unavoidable disclosure states that a coach message plus a training-context summary are sent to
/// OpenAI to answer, Rep Today's proxy stores no content, OpenAI may retain content in abuse-monitoring
/// logs for up to 30 days, a separate random abuse-prevention code is sent instead of Rep Today
/// identity and rotates on account deletion, and declining sends nothing.
///
/// This drives the *production* `CoachView` in a real key window with a fresh (un-acknowledged)
/// `AppState` in the environment, so the disclosure overlay presents exactly as it does on a first
/// open. It asserts the honest copy and both consent controls on the live accessibility tree, proves
/// the send gate is closed while the disclosure is up (declining sends nothing), and that an
/// already-acknowledged install skips straight to the chat. Then it captures the disclosure to a PNG
/// under `artifacts/reports/US-AC04/`.
///
/// The versioned gating (unacknowledged/current/mismatched, relaunch survival, account-deletion reset,
/// and independence from telemetry) is proved in `AppStateTests` and `AccountDeletionServiceTests`;
/// the send-path gate (no request before consent) in `CoachViewModelTests`. This suite proves the
/// presented surface reads correctly and behaves.
@MainActor
final class CoachDataDisclosureEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-AC04"
    private let surfaceSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - Stub transport (a coach that would answer if asked - so a closed gate is meaningful)

    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        private(set) var callCount = 0
        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            callCount += 1
            return (Data(#"{"reply":"should never be delivered before consent"}"#.utf8), 200)
        }
    }

    private func freshAppState() -> AppState {
        let suite = "RepToday.US-AC04.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppState(userDefaults: defaults)
    }

    private func makeViewModel(_ transport: StubTransport) -> CoachViewModel {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        return CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://proxy.example.com/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
    }

    private func hostCoach(_ viewModel: CoachViewModel, appState: AppState) -> UIView {
        let (_, hostedWindow) = HostedSurface.host(
            NavigationStack { CoachView(viewModel: viewModel) }
                .environment(appState)
                .environment(\.services, ServiceContainer.mock()),
            size: surfaceSize
        )
        window = hostedWindow
        return hostedWindow.rootViewController!.view
    }

    private func spoken(in root: UIView) -> String {
        AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")
    }

    // MARK: - Evidence: the disclosure surface itself

    /// The disclosure states the honest facts and offers both consent controls. Hosted directly (the
    /// same precedent as `ContinuousCircuitExplainerTests`), so the captured PNG composites the card
    /// cleanly rather than a mid-transition frame of the overlay; the *integration* proof that it
    /// actually presents on the real `CoachView` before first use is `testRealCoachViewPresentsTheDisclosureBeforeFirstUse` below.
    func testDisclosureStatesHonestFactsAndOffersBothControls() throws {
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

        // It names what leaves the device: the message *and* a training-context summary, sent to OpenAI.
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("OpenAI"),
                      "the disclosure must name OpenAI as the recipient; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("summary of your training"),
                      "it must disclose the training-context summary, not just the message; spoke: \(spoken)")
        // It is honest about the one break in the on-device posture.
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("off your"),
                      "it must state that content leaves the device; spoke: \(spoken)")
        // It distinguishes Rep Today's stateless proxy from OpenAI's standard abuse-monitoring retention.
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("proxy")
                      && spoken.localizedCaseInsensitiveContains("doesn't store"),
                      "it must state that Rep Today's proxy does not store the content; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("abuse-monitoring")
                      && spoken.localizedCaseInsensitiveContains("up to 30 days"),
                      "it must disclose OpenAI's standard abuse-monitoring retention; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("name")
                      && spoken.localizedCaseInsensitiveContains("email")
                      && spoken.localizedCaseInsensitiveContains("Rep Today identity"),
                      "it must separate the safety code from Rep Today identity; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("prevent abuse")
                      && spoken.localizedCaseInsensitiveContains("random Coach code"),
                      "it must explain the pseudonym's abuse-prevention purpose; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("delete your account"),
                      "it must disclose identifier rotation on account deletion; spoke: \(spoken)")

        // Both consent controls are reachable, labeled VoiceOver elements.
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.acknowledge, in: root),
                        "the acknowledge control must be a labeled, hittable element")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.decline, in: root),
                        "the decline control must be a labeled, hittable element")

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "01-coach-data-disclosure.png", for: story)
        print("US-AC04 EVIDENCE: 01-coach-data-disclosure.png -> \(path)")
    }

    // MARK: - Evidence: it gates the real coach

    /// On a fresh install the real production `CoachView` presents the disclosure before first use, and
    /// the coach has sent nothing behind it - the send gate is closed until the user acknowledges.
    func testRealCoachViewPresentsTheDisclosureBeforeFirstUse() {
        let transport = StubTransport()
        let viewModel = makeViewModel(transport)
        let appState = freshAppState()
        XCTAssertTrue(appState.shouldShowCoachDataDisclosure)

        let root = hostCoach(viewModel, appState: appState)
        let spoken = spoken(in: root)

        // The disclosure copy is present on the real surface's tree (only the disclosure names OpenAI).
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("OpenAI"),
                      "the disclosure must present on the real CoachView before first use; spoke: \(spoken)")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachDataDisclosureCopy.acknowledge, in: root),
                        "the acknowledge control is reachable on the real surface")

        // Nothing has been sent just by showing the disclosure.
        XCTAssertEqual(transport.callCount, 0, "no request leaves the device while the disclosure is up")
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.needsDataSharingConsent, "the coach is gated until acknowledgement")
        XCTAssertFalse(viewModel.canSend, "the send control stays disabled behind the disclosure")
    }

    /// Declining sends nothing: the send gate stays closed (the production decline additionally dismisses
    /// the view; the load-bearing fact is that no send occurs and no consent is recorded).
    func testDecliningSendsNothing() async {
        let transport = StubTransport()
        let viewModel = makeViewModel(transport)
        let appState = freshAppState()
        _ = hostCoach(viewModel, appState: appState)

        // The user never acknowledged; a send attempt (e.g. an errant tap) must not reach OpenAI.
        viewModel.draft = "why squats today?"
        await viewModel.send()

        XCTAssertEqual(transport.callCount, 0, "declining sends nothing")
        XCTAssertFalse(appState.hasAcknowledgedCoachDataSharing, "declining does not record consent")
    }

    /// An install that already acknowledged the disclosure skips it: the chat is reachable immediately,
    /// with no overlay in the way.
    func testAcknowledgedInstallSeesNoDisclosure() {
        let transport = StubTransport()
        let viewModel = makeViewModel(transport)
        let appState = freshAppState()
        appState.markCoachDataSharingAcknowledged()

        let root = hostCoach(viewModel, appState: appState)
        let spoken = spoken(in: root)

        XCTAssertFalse(spoken.localizedCaseInsensitiveContains(CoachDataDisclosureCopy.title),
                       "an acknowledged install must not see the disclosure again; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("Message to the coach"),
                      "the chat input is reachable; spoke: \(spoken)")
        XCTAssertFalse(viewModel.needsDataSharingConsent, "consent carried over from AppState opens the gate")
    }
}
