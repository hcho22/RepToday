import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AC08: a health signal is answered with an **offer to route**, not a
/// silent filter change, and the injury flag itself is set in a real, explicit, reversible control.
///
/// Two things here can only be proved on a rendered surface: that the offer's copy never claims the
/// coach has already changed something (the on-device half of "the coach's language never implies it
/// has removed movements" - the proxy persona is the other half, pinned in `proxy/test/worker.test.js`),
/// and that both the accept and decline affordances are reachable, labeled VoiceOver elements. The
/// behavioral guarantees - no write on either answer - live in `CoachViewModelTests` and
/// `InjuryFlagsViewModelTests`.
///
/// PNGs land under `artifacts/reports/US-AC08/`.
@MainActor
final class InjuryRoutingEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-AC08"
    private let surfaceSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func spoken(in root: UIView) -> String {
        AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")
    }

    // MARK: - The offer never claims a change was made

    /// The claims the coach must never make on this surface. Each is a first-person assertion that the
    /// app has *already* altered what the user will be shown - exactly what US-AC08 exists to prevent.
    private static let forbiddenClaims = [
        "i've removed", "i have removed", "i removed",
        "i've taken out", "i took out",
        "i've swapped", "i swapped",
        "i've changed", "i have changed", "i changed",
        "i've adjusted", "i adjusted",
        "i've updated", "i updated",
        "i've flagged", "i flagged",
        "no longer include", "won't see squats", "removed squats",
    ]

    func testOfferCopyNeverImpliesAChangeWasAlreadyMade() {
        for area in InjuryOption.allCases {
            let offer = CoachInjuryOfferCopy.offer(for: area).lowercased()
            for claim in Self.forbiddenClaims {
                XCTAssertFalse(offer.contains(claim),
                               "the \(area) offer must not claim \"\(claim)\"; copy was: \(offer)")
            }
            XCTAssertTrue(offer.contains("haven't changed anything"),
                          "the \(area) offer must say plainly that nothing has changed; copy was: \(offer)")
            XCTAssertTrue(offer.contains("want to flag"),
                          "the \(area) offer must ask rather than announce; copy was: \(offer)")
        }
    }

    /// The accept control names a navigation to a named screen, never a setting, so tapping it cannot
    /// be read as the flag having been applied - and the offer, the control, and the Settings row that
    /// also reaches it all name the same destination.
    func testAcceptControlNamesANavigationToTheRealControl() {
        let accept = CoachInjuryOfferCopy.accept
        XCTAssertTrue(accept.lowercased().hasPrefix("open"), "the accept control opens a screen; it was: \(accept)")
        XCTAssertTrue(accept.contains(InjuryFlagsCopy.title), "it names the screen it opens; it was: \(accept)")
        XCTAssertFalse(accept.lowercased().contains("flag it"), "it must not read as performing the flag itself")
        XCTAssertTrue(CoachInjuryOfferCopy.offer(for: .knees).contains(InjuryFlagsCopy.title),
                      "the offer names the same destination the control opens")
    }

    // MARK: - Evidence: the offer card

    func testOfferCardOffersBothAffordances() throws {
        let (host, hostedWindow) = HostedSurface.host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                CoachInjuryOfferView(area: .knees, onAccept: {}, onDecline: {})
                    .padding()
            },
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("knees are bothering you"),
                      "the offer names the area it noticed; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("haven't changed anything"),
                      "the offer states nothing has changed; spoke: \(spoken)")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachInjuryOfferCopy.accept, in: root),
                        "the accept control is a labeled, hittable element")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachInjuryOfferCopy.decline, in: root),
                        "the decline control is a labeled, hittable element")

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "01-coach-injury-offer.png", for: story)
        print("US-AC08 EVIDENCE: 01-coach-injury-offer.png -> \(path)")
    }

    // MARK: - Evidence: the offer on the real coach surface

    /// A canned transport so the real `CoachView` can complete a turn and raise the offer exactly as it
    /// does in production.
    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            (Data(#"{"reply":"Sore knees don't love deep flexion - ease off and stop if it pinches."}"#.utf8), 200)
        }
    }

    func testRealCoachSurfaceShowsTheOfferAfterAnInjuryMessage() async throws {
        var user = MockPersistence.sampleUser
        user.profile.injuries = []
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://proxy.example.com/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: StubTransport()
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
        viewModel.grantDataSharingConsent()
        viewModel.draft = "my knee hurts on squats"
        await viewModel.send()
        XCTAssertEqual(viewModel.injuryRoutingOffer?.area, .knees)

        let (host, hostedWindow) = HostedSurface.host(
            NavigationStack { CoachView(viewModel: viewModel) }
                .environment(\.services, ServiceContainer.mock()),
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("knees are bothering you"),
                      "the offer renders in the real conversation; spoke: \(spoken)")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachInjuryOfferCopy.accept, in: root),
                        "the route is reachable from the real surface")

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "02-coach-conversation-offer.png", for: story)
        print("US-AC08 EVIDENCE: 02-coach-conversation-offer.png -> \(path)")
    }

    // MARK: - Evidence: the injury control the offer routes to

    func testInjuryControlPresentsTheRoutedAreaAsAnUnconfirmedChange() async throws {
        let viewModel = InjuryFlagsViewModel(userService: MockUserService(user: MockPersistence.sampleUser))
        // Arrive at the routed state *before* hosting, so the first frame drawn is the final one. The
        // screen's own `.task` still runs and is what makes this valid: its load is idempotent, so it
        // returns without re-staging. Capturing a state that lands after hosting would composite a row
        // that changed only its text and colours from its already-drawn contents.
        await viewModel.load(preselecting: .knees)

        let (host, hostedWindow) = HostedSurface.host(
            NavigationStack {
                InjuryFlagsView(viewModel: viewModel, preselect: .knees, dismissesOnSave: true)
            },
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        // Every protectable area is a control on this screen, so the flag is reversible from here.
        for area in InjuryOption.allCases {
            XCTAssertNotNil(AccessibilityTree.element(labeled: area.label, in: root),
                            "\(area.label) must be switchable on this screen; spoke: \(spoken)")
        }
        // The routed area arrives staged and named, with an explicit confirmation still owed.
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("Will start working around: Knees"),
                      "the pending change is named before it is confirmed; spoke: \(spoken)")
        XCTAssertNotNil(AccessibilityTree.element(labeled: InjuryFlagsCopy.confirm, in: root),
                        "the confirmation control is a labeled, hittable element")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("switch any of these back off"),
                      "the screen states the change is reversible; spoke: \(spoken)")
        // Backing out is the "I changed my mind after accepting the route" path, so on the sheet it is
        // an explicit control rather than only a swipe-down.
        XCTAssertNotNil(AccessibilityTree.element(labeled: InjuryFlagsCopy.cancel, in: root),
                        "the routed sheet offers an explicit way out that writes nothing; spoke: \(spoken)")
        XCTAssertTrue(viewModel.hasUnsavedChanges, "arriving from the coach lands one explicit tap short of the change")
        // Live rather than merely present: the screen re-runs its load task, and a re-run that reset
        // the loaded state would render the confirmation inert while still showing the staged change.
        XCTAssertTrue(viewModel.canSave, "the confirmation is live on the hosted surface")

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "03-injury-control-routed.png", for: story)
        print("US-AC08 EVIDENCE: 03-injury-control-routed.png -> \(path)")
    }

    /// The Settings footer that names who may change these - the coach may suggest, only the user sets.
    func testSettingsCopyNamesWhoMayChangeTheFlag() {
        let footer = InjuryFlagsCopy.settingsFooter.lowercased()
        XCTAssertTrue(footer.contains("only you set these"), "the footer was: \(footer)")
        XCTAssertTrue(footer.contains("never turns one on or off for you"), "the footer was: \(footer)")
    }
}
