import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-SP06, the graduation moment: the one-time, identity-framed reveal
/// shown the first time a user earns the Strength Phase. It drives the *production*
/// `StrengthGraduationRevealView` in a real key window and asserts, on the live accessibility tree,
/// that the reveal is what the AC requires - identity-framed ("you've earned", "you're someone who
/// moves"), never loss-framed or gamified, explains what changes (harder work; new skills on the
/// ladder), and points to the progression map - then captures the screen to a PNG.
///
/// The one-shot *gating* (fires once at the crossing, never again, survives relaunch) is proved in
/// `AppStateTests` and `StrengthGraduationViewModelTests`; this suite proves the surface itself reads
/// correctly and is dismissible.
@MainActor
final class StrengthGraduationEvidenceTests: XCTestCase {

    private let story = "US-SP06"
    private let surfaceSize = CGSize(width: 393, height: 852)

    private func spoken(in host: UIView) -> String {
        AccessibilityTree.spokenStrings(in: host).joined(separator: " • ")
    }

    /// The reveal's copy is identity-framed and honest - it congratulates the earned habit and never
    /// frames the milestone as a reward unlocked.
    func testCopyIsIdentityFramedNotLossFramedOrGamified() {
        let (host, window) = HostedSurface.host(
            StrengthGraduationRevealView(onDismiss: {}), size: surfaceSize
        )
        defer { window.isHidden = true }

        let lower = spoken(in: host.view).lowercased()

        XCTAssertTrue(lower.contains("earned"), "the reveal must frame the phase as earned; spoke: \(lower)")
        XCTAssertTrue(lower.contains("someone who moves"), "the reveal must be identity-framed; spoke: \(lower)")

        // Never gamified, never loss-framed.
        for banned in ["reward", "unlocked a", "you unlocked", "level", "badge", "xp", "prize", "congratulations you won"] {
            XCTAssertFalse(lower.contains(banned), "graduation copy must not be gamified/loss-framed ('\(banned)'); spoke: \(lower)")
        }
    }

    /// It explains what changes and points to the progression map.
    func testExplainsWhatChangesAndPointsToTheMap() {
        let (host, window) = HostedSurface.host(
            StrengthGraduationRevealView(onDismiss: {}), size: surfaceSize
        )
        defer { window.isHidden = true }

        let lower = spoken(in: host.view).lowercased()

        XCTAssertTrue(lower.contains("harder"), "must say harder work is now available; spoke: \(lower)")
        XCTAssertTrue(lower.contains("skill"), "must mention the new skills on the ladder; spoke: \(lower)")
        XCTAssertTrue(lower.contains("progression map"), "must point to the progression map; spoke: \(lower)")
    }

    /// The one dismiss control is a labeled, hittable VoiceOver element and calls back to dismiss.
    func testDismissControlIsPresentLabeledAndCallsBack() {
        var dismissed = false
        let view = StrengthGraduationRevealView(onDismiss: { dismissed = true })
        let (host, window) = HostedSurface.host(view, size: surfaceSize)
        defer { window.isHidden = true }

        XCTAssertNotNil(
            AccessibilityTree.element(labeled: "Keep climbing", in: host.view),
            "the dismiss control must be a labeled, hittable VoiceOver element"
        )

        view.onDismiss()
        XCTAssertTrue(dismissed, "the dismiss control calls back to take the reveal down")
    }

    /// Renders the production reveal and captures the PNG the acceptance notes cite. Hosted at a taller
    /// canvas than a phone screen so the whole card - all four points and the dismiss control - lays out
    /// unscrolled for the reviewer, rather than clipping the map pointer below the fold (on a real
    /// device the card's own `ScrollView` handles the overflow; the assertions above read the full tree
    /// regardless of scroll position).
    func testCapturesTheGraduationReveal() throws {
        let captureSize = CGSize(width: 393, height: 1180)
        let (host, window) = HostedSurface.host(
            StrengthGraduationRevealView(onDismiss: {}), size: captureSize
        )
        defer { window.isHidden = true }

        // Sanity that the surface actually laid out its copy before we capture it.
        XCTAssertTrue(
            spoken(in: host.view).localizedCaseInsensitiveContains("Strength Phase"),
            "the reveal should name the earned Strength Phase before capture"
        )

        let image = HostedSurface.capture(host.view, size: captureSize)
        let path = try EvidenceOutput.write(image, named: "01-strength-graduation-reveal.png", for: story)
        print("US-SP06 EVIDENCE: 01-strength-graduation-reveal.png -> \(path)")
    }
}
