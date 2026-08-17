import XCTest
import SwiftUI
@testable import RepToday

/// The first-run explainer for the self-driving continuous-circuit player (US-CC13): a hosted-surface
/// accessibility check that its four points and its one dismiss control are actually reachable and
/// announced by VoiceOver, plus a unit check that "Got it" dismisses through the production callback.
///
/// The one-shot *gating* (unseen -> shows, seen -> never again, persisted across relaunch) is proved in
/// `AppStateTests`; this suite proves the surface itself reads correctly and is dismissible.
@MainActor
final class ContinuousCircuitExplainerTests: XCTestCase {

    private let surfaceSize = CGSize(width: 393, height: 852)

    func testAllFourPointsAreVoiceOverReadable() {
        let (host, window) = HostedSurface.host(
            ContinuousCircuitExplainerView(onDismiss: {}), size: surfaceSize
        )
        defer { window.isHidden = true }

        let spoken = AccessibilityTree.spokenStrings(in: host.view).joined(separator: " • ")

        // 1. The session auto-advances.
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("flows into the next"),
            "the auto-advance point must be announced; spoke: \(spoken)"
        )
        // 2. + More time never rushes you - named as the control, without its markdown asterisks.
        XCTAssertTrue(spoken.contains("+ More time"), "the '+ More time' point must name the control; spoke: \(spoken)")
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("never rushes you"),
            "the '+ More time' reassurance must be announced; spoke: \(spoken)"
        )
        // 3. Done jumps ahead.
        XCTAssertTrue(spoken.contains("Done"), "the 'Done' point must name the control; spoke: \(spoken)")
        // 4. Tones mark state changes.
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("tone") || spoken.localizedCaseInsensitiveContains("cue"),
            "the tones point must be announced; spoke: \(spoken)"
        )
    }

    func testDismissControlIsPresentAndLabeled() {
        let (host, window) = HostedSurface.host(
            ContinuousCircuitExplainerView(onDismiss: {}), size: surfaceSize
        )
        defer { window.isHidden = true }

        XCTAssertNotNil(
            AccessibilityTree.element(labeled: "Got it", in: host.view),
            "the dismiss control must be a labeled, hittable VoiceOver element"
        )
    }

    func testCopyIsIdentityFramedNotLossFramed() {
        let (host, window) = HostedSurface.host(
            ContinuousCircuitExplainerView(onDismiss: {}), size: surfaceSize
        )
        defer { window.isHidden = true }

        let spoken = AccessibilityTree.spokenStrings(in: host.view).joined(separator: " ").lowercased()

        // Non-loss-framed: it never mentions a removed manual mode or apologises for a change.
        for lossPhrase in ["manual mode", "no longer", "used to", "gone", "removed", "sorry"] {
            XCTAssertFalse(spoken.contains(lossPhrase), "explainer copy must not be loss-framed ('\(lossPhrase)')")
        }
    }

    func testDismissInvokesTheProductionCallback() {
        var dismissed = false
        let view = ContinuousCircuitExplainerView(onDismiss: { dismissed = true })
        view.onDismiss()

        XCTAssertTrue(dismissed, "the 'Got it' action calls back to dismiss the explainer")
    }
}
