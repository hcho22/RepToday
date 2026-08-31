import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// US-T06's two consent surfaces, read off the production views rather than described (the Settings
/// toggle and the onboarding disclosure).
///
/// Both are hosted in a real key window through `HostedSurface`, so what is asserted is what is drawn
/// and what VoiceOver speaks. The toggle is also *activated* the way VoiceOver's double-tap activates
/// it, which is what proves the control writes the persisted flag rather than merely rendering it -
/// "the toggle reflects the real current state" is a criterion, and a switch wired to nothing would
/// look identical in a screenshot.
@MainActor
final class TelemetryConsentSurfaceTests: XCTestCase {

    private let screenSize = CGSize(width: 393, height: 852)

    /// Held for the test's lifetime - a released window takes the hosted view down with it, and one
    /// test hosts two surfaces at once to compare them.
    private var renderWindows: [UIWindow] = []

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RepToday.TelemetryConsentSurfaceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        renderWindows = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Settings

    /// The toggle is reachable, labelled, and speaks its state and its reason - and the explanation
    /// beside it says what is collected and what it is not tied to, rather than arguing the user out
    /// of turning it off.
    func testSettingsSpeaksTheToggleItsReasonAndThePrivacyPolicy() throws {
        let root = hostSettings(analyticsEnabled: true)
        let labels = AccessibilityTree.labels(in: root)

        XCTAssertTrue(
            labels.contains(SettingsView.toggleTitle),
            "the opt-out toggle is unlabelled or unreachable: \(labels)"
        )
        XCTAssertTrue(labels.contains("Privacy Policy"), "no privacy-policy link in Settings: \(labels)")
        XCTAssertTrue(
            labels.contains { $0 == SettingsView.explanation },
            "the explanatory sentence is not on screen: \(labels)"
        )

        // Present once, not once per place it happens to be attached. It used to be both the
        // section's text *and* the toggle's hint, so VoiceOver read the whole paragraph twice in a
        // row. Counted over labels and hints together rather than pinned to whichever view renders
        // it, so a future re-duplication fails here in whatever shape it takes.
        let spoken = AccessibilityTree.spokenStrings(in: root)
        XCTAssertEqual(
            spoken.filter { $0 == SettingsView.explanation }.count,
            1,
            "the explanation is announced more than once: \(spoken)"
        )

        // A hint says what activating the control does; it is not a second copy of the body copy.
        let toggle = try XCTUnwrap(
            AccessibilityTree.element(labeled: SettingsView.toggleTitle, in: root),
            "the toggle is not an accessibility element"
        )
        let hint = try XCTUnwrap(toggle.accessibilityHint, "the toggle vends no hint to VoiceOver")
        XCTAssertNotEqual(hint, SettingsView.explanation, "the toggle's hint restates the body copy")
        XCTAssertLessThan(hint.count, 80, "a VoiceOver hint should be one short clause: \"\(hint)\"")

        // Identity-framed and honest: it names what the data is for and what it is *not* attached to.
        XCTAssertTrue(SettingsView.explanation.contains("helps us see whether Rep Today is working"))
        XCTAssertTrue(SettingsView.explanation.contains("never your name"))
        // Never dark-patterned: no loss framing, and no pleading.
        for forbidden in ["lose", "Lose", "miss out", "Are you sure", "hurt"] {
            XCTAssertFalse(
                SettingsView.explanation.contains(forbidden),
                "the consent copy is loss-framed: it contains \"\(forbidden)\""
            )
        }
    }

    /// The switch shows the real stored answer, in both directions - not a hard-coded "on".
    func testTheToggleReflectsTheStoredChoice() throws {
        let optedIn = hostSettings(analyticsEnabled: true)
        XCTAssertEqual(try switchValue(in: optedIn), "1", "an opted-in install shows the toggle off")

        let optedOut = hostSettings(analyticsEnabled: false)
        XCTAssertEqual(try switchValue(in: optedOut), "0", "an opted-out install shows the toggle on")
    }

    /// Activating the switch the way VoiceOver does writes the persisted flag, so the control is
    /// wired to the gate rather than to a local copy of it.
    func testActivatingTheToggleWritesThePersistedFlag() throws {
        let appState = AppState(userDefaults: defaults)
        XCTAssertTrue(appState.analyticsEnabled, "precondition: a fresh install is opted in")

        let root = hostSettings(appState: appState)
        let element = try XCTUnwrap(
            AccessibilityTree.element(labeled: SettingsView.toggleTitle, in: root),
            "the toggle is not an accessibility element"
        )

        XCTAssertTrue(element.accessibilityActivate(), "VoiceOver could not activate the toggle")
        HostedSurface.pump(for: 0.5)

        XCTAssertFalse(appState.analyticsEnabled, "activating the toggle did not turn telemetry off")
        XCTAssertFalse(
            AppState.isAnalyticsEnabled(in: defaults),
            "the toggle moved the view's copy without persisting the choice"
        )
    }

    /// The one thing US-T06 must not do: opting out gates emission and leaves the anonymous install
    /// identity untouched, because re-minting it is the state US-T07 has to decide about first.
    func testOptingOutFromSettingsDoesNotResetTheInstallIdentity() throws {
        let appState = AppState(userDefaults: defaults)
        let originalId = appState.installId

        let root = hostSettings(appState: appState)
        let element = try XCTUnwrap(
            AccessibilityTree.element(labeled: SettingsView.toggleTitle, in: root)
        )
        _ = element.accessibilityActivate()
        HostedSurface.pump(for: 0.5)

        XCTAssertEqual(defaults.string(forKey: "AppState.installId"), originalId)
        XCTAssertEqual(AppState(userDefaults: defaults).installId, originalId)
    }

    // MARK: - Onboarding

    /// The disclosure is on the *first* onboarding screen, with the privacy-policy link beside it.
    /// First rather than last because the first event the app will emit hangs off app entry (US-T07),
    /// so a disclosure at the end of the flow would arrive after the thing it discloses.
    func testOnboardingDisclosesTelemetryOnItsFirstScreenWithAPolicyLink() throws {
        let viewModel = OnboardingViewModel(
            userService: MockUserService(),
            sessionPolicyService: MockSessionPolicyService()
        )
        XCTAssertEqual(viewModel.step, .welcome, "precondition: onboarding opens on the welcome step")

        let root = hosted(OnboardingView(viewModel: viewModel), size: screenSize)
        let labels = AccessibilityTree.labels(in: root)

        let disclosure = try XCTUnwrap(
            labels.first { $0.contains("anonymous usage data") },
            "the first onboarding screen discloses nothing about anonymous usage data: \(labels)"
        )
        XCTAssertTrue(
            disclosure.contains("Settings"),
            "the disclosure does not say where the opt-out lives: \"\(disclosure)\""
        )
        XCTAssertTrue(labels.contains("Privacy Policy"), "no privacy-policy link in onboarding: \(labels)")
    }

    // MARK: - Coach data disclosure mirror (US-AC04)

    /// Settings mirrors the coach data disclosure in its own AI Coach section: it states the same facts
    /// (message + training summary to OpenAI, not stored), it is the shared copy the pre-use modal
    /// shows, and it is separate from - and does not touch - the telemetry opt-out above it.
    func testSettingsMirrorsTheCoachDataDisclosureSeparatelyFromTelemetry() throws {
        let root = hostSettings(analyticsEnabled: true)
        let labels = AccessibilityTree.labels(in: root)
        let spoken = AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")

        // Both privacy entries coexist, distinctly: the telemetry toggle and the coach disclosure row.
        XCTAssertTrue(labels.contains(SettingsView.toggleTitle), "the telemetry toggle is still present: \(labels)")
        XCTAssertTrue(labels.contains(CoachDataDisclosureCopy.settingsRowTitle),
                      "the coach disclosure row is present: \(labels)")

        // The coach footer states the same facts as the pre-use modal.
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("OpenAI"),
                      "the Settings coach entry names OpenAI; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("not stored"),
                      "the Settings coach entry states content is not stored; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("separate from the anonymous usage data"),
                      "the Settings coach entry declares its separation from telemetry; spoke: \(spoken)")
    }

    // MARK: - The one privacy-policy URL

    /// Three surfaces link to the privacy policy for two unrelated reasons - the paywall because App
    /// Store Review 3.1.2 requires it, and the onboarding disclosure and Settings because an opt-out
    /// consent model has to say what is collected. They share one constant, so the *sharing* is
    /// structural rather than asserted here (there is no second URL to compare against). What is
    /// asserted is that the shared value is the hosted Rep Today policy at `reptoday.app/privacy`.
    /// (The earlier placeholder guard - "still an obvious placeholder" - was retired deliberately
    /// here, per its own instruction, when the real hosted policy replaced `example.com`.)
    func testTheSharedPrivacyPolicyURLIsTheHostedRepTodayPolicy() throws {
        XCTAssertEqual(LegalLinks.privacyPolicy.scheme, "https")
        XCTAssertEqual(LegalLinks.privacyPolicy.host, "reptoday.app")
        XCTAssertEqual(LegalLinks.privacyPolicy.path, "/privacy")
        XCTAssertFalse(
            LegalLinks.privacyPolicy.absoluteString.contains("PLACEHOLDER"),
            "the privacy-policy URL must no longer be the example.com placeholder"
        )
        XCTAssertEqual(LegalLinks.termsOfUse.host, "www.apple.com")
    }

    // MARK: - Hosting helpers

    private func hostSettings(analyticsEnabled: Bool) -> UIView {
        let appState = AppState(userDefaults: defaults)
        appState.analyticsEnabled = analyticsEnabled
        return hostSettings(appState: appState)
    }

    private func hostSettings(appState: AppState) -> UIView {
        hosted(
            NavigationStack { SettingsView() }
                .environment(\.services, ServiceContainer.mock())
                .environment(appState),
            size: screenSize
        )
    }

    private func hosted<V: View>(_ view: V, size: CGSize) -> UIView {
        let hosted = HostedSurface.host(view, size: size)
        renderWindows.append(hosted.window)
        return hosted.host.view
    }

    /// The value a `Toggle` vends to VoiceOver: `"1"` on, `"0"` off.
    private func switchValue(in root: UIView) throws -> String {
        let element = try XCTUnwrap(
            AccessibilityTree.element(labeled: SettingsView.toggleTitle, in: root),
            "the toggle is not an accessibility element"
        )
        return try XCTUnwrap(element.accessibilityValue, "the toggle vends no state to VoiceOver")
    }
}
