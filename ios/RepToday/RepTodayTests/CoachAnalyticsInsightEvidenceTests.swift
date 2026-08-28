import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AN02: a progress inquiry on a stalled strength journey is answered
/// with a concrete insight and a bounded **offer to act**, not a silent change - and the offered action
/// is a preference nudge, never a workout edit.
///
/// Two things here can only be proved on a rendered surface: that the offer's copy narrates a real
/// insight (a climbing pattern beside a stalled one) while promising nothing has changed until the user
/// accepts, and that both the accept and decline affordances are reachable, labeled VoiceOver elements.
/// The behavioral guarantees - the offer routes through the bounded US-AC07 write and nothing is written
/// until acceptance - live in `CoachViewModelTests`; the classification lives in
/// `CoachAnalyticsInsightTests`.
///
/// PNGs land under `artifacts/reports/US-AN02/`.
@MainActor
final class CoachAnalyticsInsightEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-AN02"
    private let surfaceSize = CGSize(width: 393, height: 852)

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func spoken(in root: UIView) -> String {
        AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")
    }

    private let sampleOffer = CoachAnalyticsInsightOffer(stalledPattern: .hinge, stalledWeeks: 3, climbingPattern: .push)

    // MARK: - The offer copy is a real insight that never claims a change

    /// The claims the coach must never make: a first-person assertion that the program has *already*
    /// changed. The offer asks; it does not announce.
    private static let forbiddenClaims = [
        "i've changed", "i have changed", "i changed",
        "i've adjusted", "i adjusted",
        "i've swapped", "i swapped",
        "i've updated", "i updated",
        "i've edited", "i edited",
        "i've removed", "i removed",
    ]

    func testOfferCopyNarratesAnInsightAndClaimsNoChange() {
        let copy = CoachAnalyticsInsightCopy.offer(for: sampleOffer).lowercased()
        for claim in Self.forbiddenClaims {
            XCTAssertFalse(copy.contains(claim), "the offer must not claim \"\(claim)\"; copy was: \(copy)")
        }
        // A concrete insight, not a generic summary: it names both the climb and the stall.
        XCTAssertTrue(copy.contains("push is climbing"), "names the climbing pattern; copy was: \(copy)")
        XCTAssertTrue(copy.contains("hinge has been flat"), "names the stalled pattern; copy was: \(copy)")
        // It offers a preference nudge and states the app still owns the session.
        XCTAssertTrue(copy.contains("lean your sessions toward hinge"), "offers to emphasize the stall; copy was: \(copy)")
        XCTAssertTrue(copy.contains("app still builds every session"), "states the app owns the workout; copy was: \(copy)")
    }

    /// The accept control names leaning the program toward the stalled pattern, a preference - never a
    /// workout edit.
    func testAcceptControlNamesAPreferenceNudge() {
        let accept = CoachAnalyticsInsightCopy.accept(for: sampleOffer).lowercased()
        XCTAssertTrue(accept.contains("lean into hinge"), "the accept control leans toward the stall; it was: \(accept)")
        XCTAssertFalse(accept.contains("change"), "it must not read as editing the workout")
    }

    // MARK: - Evidence: the offer card

    func testOfferCardOffersBothAffordances() throws {
        let (host, hostedWindow) = HostedSurface.host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                CoachAnalyticsInsightView(offer: sampleOffer, onAccept: {}, onDecline: {})
                    .padding()
            },
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("push is climbing"),
                      "the card narrates the climb; spoke: \(spoken)")
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("hinge has been flat"),
                      "the card narrates the stall; spoke: \(spoken)")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachAnalyticsInsightCopy.accept(for: sampleOffer), in: root),
                        "the accept control is a labeled, hittable element")
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachAnalyticsInsightCopy.decline, in: root),
                        "the decline control is a labeled, hittable element")

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "01-coach-analytics-offer.png", for: story)
        print("US-AN02 EVIDENCE: 01-coach-analytics-offer.png -> \(path)")
    }

    // MARK: - Evidence: the offer on the real coach surface

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date { calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))! }

    private func log(_ exerciseId: String, _ pattern: MovementPattern, weeksAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -weeksAgo * 7, to: asOf)!,
            requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
            shape: .singleFocus, focusPillar: nil, perceivedDifficulty: nil,
            exercises: [LoggedExercise(
                id: UUID(), exerciseId: exerciseId, pillar: .strength, movementPattern: pattern,
                completedSets: [CompletedSet(reps: 10, durationSeconds: nil)], skipped: false
            )]
        )
    }

    /// A canned transport so the real `CoachView` completes a turn and raises the offer exactly as it
    /// does in production.
    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        func post(
            to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            (Data(#"{"reply":"Your push keeps climbing; hinge has plateaued for a few weeks now."}"#.utf8), 200)
        }
    }

    func testRealCoachSurfaceShowsTheOfferAfterAProgressInquiry() async throws {
        var user = MockPersistence.sampleUser
        user.id = "an02-evidence"
        let logs = [
            log("push_wall", .push, weeksAgo: 5),
            log("push_incline", .push, weeksAgo: 4),
            log("push_knee", .push, weeksAgo: 0),
            log("hinge_glute_bridge", .hinge, weeksAgo: 5),
            log("hinge_single_leg_bridge", .hinge, weeksAgo: 4),
        ]
        let viewModel = CoachViewModel(
            client: CoachProxyClient(endpoint: URL(string: "https://proxy.example.com/coach")!, transport: StubTransport()),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: InMemorySessionPolicyStore()),
            now: { self.asOf },
            calendar: calendar
        )
        viewModel.grantDataSharingConsent()
        viewModel.draft = "how am I doing?"
        await viewModel.send()
        XCTAssertEqual(viewModel.analyticsOffer?.stalledPattern, .hinge)

        let (host, hostedWindow) = HostedSurface.host(
            NavigationStack { CoachView(viewModel: viewModel) }
                .environment(\.services, ServiceContainer.mock()),
            size: surfaceSize
        )
        window = hostedWindow
        let root = host.view!
        let spoken = spoken(in: root)

        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("hinge has been flat"),
                      "the offer renders in the real conversation; spoke: \(spoken)")
        XCTAssertNotNil(
            AccessibilityTree.element(labeled: CoachAnalyticsInsightCopy.accept(for: sampleOffer), in: root),
            "the emphasis action is reachable from the real surface"
        )

        let image = HostedSurface.capture(root, size: surfaceSize)
        let path = try EvidenceOutput.write(image, named: "02-coach-conversation-offer.png", for: story)
        print("US-AN02 EVIDENCE: 02-coach-conversation-offer.png -> \(path)")
    }
}
