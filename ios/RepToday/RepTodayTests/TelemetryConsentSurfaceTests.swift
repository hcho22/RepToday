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

    // MARK: - The one privacy-policy URL

    /// Three surfaces link to the privacy policy for two unrelated reasons - the paywall because App
    /// Store Review 3.1.2 requires it, and the onboarding disclosure and Settings because an opt-out
    /// consent model has to say what is collected. They share one constant, so the *sharing* is
    /// structural rather than asserted here (there is no second URL to compare against). What is
    /// asserted is that the shared value is usable, and that it is still the obvious placeholder it
    /// claims to be - so replacing it before submission stays a visible, deliberate act.
    func testTheSharedPrivacyPolicyURLIsUsableAndStillAnObviousPlaceholder() throws {
        XCTAssertEqual(LegalLinks.privacyPolicy.scheme, "https")
        XCTAssertNotNil(LegalLinks.privacyPolicy.host)
        XCTAssertTrue(
            LegalLinks.privacyPolicy.absoluteString.contains("PLACEHOLDER"),
            "the privacy-policy URL is no longer self-evidently a placeholder - if it is now real, "
                + "drop this assertion deliberately rather than letting it be edited around"
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
