import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for **US-AC07**, the coach tuning the program with two-writer safety.
///
/// It drives the *production* `CoachView` in a real key window over a view model wired with the real
/// `CoachSessionPolicyService` (the same seam `ServiceContainer` wires in the app) atop the shared
/// `SessionPolicyStore` the deterministic Programmer writes through. The user sends an eligible tuning
/// request ("Focus my push for a while."); the coach both *talks* (its LLM reply) and *tunes* (a bounded,
/// clamped, preference-only policy write surfaced as an honest coach turn). The suite then:
///   - captures the chat surface to a PNG so a reviewer sees exactly what the user reads;
///   - writes a plain-language transcript of the durable policy that was actually written (push emphasized,
///     `updatedBy == .llm`), and proves two-writer safety end-to-end: after a real deterministic
///     disengagement de-load, the coach nudge preserves the de-load's eased pace and narrowed window.
///
/// The unit/integration proofs live in `CoachPolicyWriteTests` / `CoachPolicyWritePolicyTests`; this suite
/// exists to make the end-user experience and the safety guarantee visible in a committed artifact.
@MainActor
final class CoachTuningEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-AC07"

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Stub transport (no live proxy)

    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        let reply: String
        init(reply: String) { self.reply = reply }
        func post(
            to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            (Data(#"{"reply":"\#(reply)"}"#.utf8), 200)
        }
    }

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date { calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))! }
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: asOf)! }

    private func premiumUser() -> User {
        var user = MockPersistence.sampleUser
        user.id = "us-ac07-evidence"
        user.phase = .discipline
        user.subscription = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        return user
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Evidence: the coach both talks and tunes, visibly

    func testCoachTuningRequestWritesPolicyAndSurfacesHonestNote() async throws {
        let user = premiumUser()
        let store = InMemorySessionPolicyStore()
        let transport = StubTransport(reply: "Push it is - I'll lead with it and here's the why.")
        let viewModel = CoachViewModel(
            client: CoachProxyClient(endpoint: URL(string: "https://proxy.example.com/coach")!, transport: transport),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService(),
            policyService: CoachSessionPolicyService(store: store),
            now: { self.asOf }
        )
        viewModel.grantDataSharingConsent()

        viewModel.draft = "Focus my push for a while."
        await viewModel.send()

        // The durable policy the engine will read on the next open: push emphasized, coach-sourced.
        let storedPolicy = try await store.policy(for: user.id)
        let policy = try XCTUnwrap(storedPolicy)
        XCTAssertEqual(policy.updatedBy, .llm)
        let pushEmphasis = try XCTUnwrap(policy.patternEmphasis[.push])
        XCTAssertGreaterThan(pushEmphasis, SessionPolicy.neutralEmphasis)
        let note = try XCTUnwrap(policy.note)

        // The transcript carries the honest tuning note as a coach turn, alongside the talk reply.
        let coachTexts = viewModel.messages.filter { $0.author == .coach }.map(\.text)
        XCTAssertTrue(coachTexts.contains { $0.localizedCaseInsensitiveContains("push") },
                      "the honest tuning note names push; coach turns: \(coachTexts)")

        // Render the production chat surface and confirm the user reads both turns.
        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(NavigationStack { CoachView(viewModel: viewModel) }, size: size)
        window = hostedWindow
        XCTAssertTrue(labelsContain("You said: Focus my push for a while."),
                      "the user's tuning request renders as a turn; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Coach said: You asked to focus your push"),
                      "the honest policy-change note renders as a coach turn; tree reads \(labels())")

        let image = HostedSurface.capture(hostedWindow.rootViewController?.view ?? UIView(), size: size)
        let pngPath = try EvidenceOutput.write(image, named: "01-coach-tunes-focus-push.png", for: story)

        // A plain-language transcript of exactly what was written, for the PR body.
        let transcript = """
        US-AC07 - Coach tunes the program (two-writer safety)

        USER MESSAGE
          "Focus my push for a while."

        COACH CHAT (rendered in \(pngPath))
        \(viewModel.messages.map { "  [\($0.author)] \($0.text)" }.joined(separator: "\n"))

        DURABLE POLICY WRITTEN (read back from the shared SessionPolicyStore)
          updatedBy        : \(policy.updatedBy)          (coach-sourced; .deterministic reserved for the Programmer)
          patternEmphasis  : push = \(pushEmphasis)  (neutral \(SessionPolicy.neutralEmphasis), clamped to <= \(SessionPolicy.maxEmphasis))
          progressionRate  : \(policy.progressionRate)     (untouched by a focus request - a safety-only lever the coach may only ease down)
          varietyWindow    : \(policy.varietyWindow)       (untouched)
          note.source      : \(note.source)
          note.text        : "\(note.text)"
        """
        let transcriptPath = try EvidenceOutput.write(transcript, named: "01-coach-tunes-focus-push.txt", for: story)
        print("US-AC07 EVIDENCE png=\(pngPath) txt=\(transcriptPath)")
        _ = host
    }

    // MARK: - Evidence: a deterministic safety de-load survives a later coach nudge (ADR-0005)

    func testDeterministicDeLoadSurvivesACoachNudge() async throws {
        let store = InMemorySessionPolicyStore()
        let user = premiumUser()

        // Writer 1 (safety): the real deterministic Programmer diagnoses disengagement and eases.
        let deterministic = DeterministicSessionPolicyService(
            store: store, exerciseService: try! MockExerciseService(), userService: MockUserService()
        )
        let disengaging = [
            log(minutes: 20, of: 20, daysAgo: 3),
            log(minutes: 12, of: 20, daysAgo: 2),
            log(minutes: 5, of: 20, daysAgo: 1),
        ]
        let deLoad = try await deterministic.reprogram(
            user: user, recentLogs: disengaging,
            trigger: ReprogramTrigger(kind: .disengagement, detectedAt: asOf)
        )
        XCTAssertEqual(deLoad.updatedBy, .deterministic)
        XCTAssertLessThan(deLoad.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertLessThan(deLoad.varietyWindow, SessionPolicy.default.varietyWindow)

        // Writer 2 (preference): a coach "focus my push" nudge lands on the de-loaded in-force policy.
        let proposal = try XCTUnwrap(CoachIntentMapper.proposal(for: "Focus my push."))
        let afterCoachPolicy = try await CoachSessionPolicyService(store: store).applyProposal(proposal, for: user, asOf: asOf)
        let afterCoach = try XCTUnwrap(afterCoachPolicy)

        // Safety is sovereign: the de-load's eased pace and narrowed window are untouched; the preference landed.
        XCTAssertEqual(afterCoach.progressionRate, deLoad.progressionRate, "the de-load's eased pace survives")
        XCTAssertEqual(afterCoach.varietyWindow, deLoad.varietyWindow, "the de-load's narrowed window survives")
        XCTAssertGreaterThan(afterCoach.patternEmphasis[.push] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertEqual(afterCoach.updatedBy, .llm)

        let transcript = """
        US-AC07 - Two-writer safety: a coach nudge never clobbers a safety de-load (ADR-0005)

        WRITER 1  deterministic disengagement de-load (safety, sovereign)
          progressionRate : \(SessionPolicy.default.progressionRate) -> \(deLoad.progressionRate)   (eased for winnability)
          varietyWindow   : \(SessionPolicy.default.varietyWindow) -> \(deLoad.varietyWindow)       (narrowed toward familiar)
          updatedBy       : \(deLoad.updatedBy), version \(deLoad.version)

        WRITER 2  coach "Focus my push." (preference overlay, re-reads the de-loaded policy)
          patternEmphasis : push = \(afterCoach.patternEmphasis[.push] ?? 0)   (the disjoint preference lever applied)
          progressionRate : \(afterCoach.progressionRate)   (UNCHANGED - the coach cannot raise it)
          varietyWindow   : \(afterCoach.varietyWindow)     (UNCHANGED - the coach cannot widen it)
          updatedBy       : \(afterCoach.updatedBy), version \(afterCoach.version)

        RESULT  safety > preference holds structurally: the de-load survives, the preference is applied.
        """
        let path = try EvidenceOutput.write(transcript, named: "02-two-writer-safety.txt", for: story)
        print("US-AC07 EVIDENCE txt=\(path)")
    }

    private func log(minutes: Int, of requested: Int, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: day(daysAgo),
            requestedMinutes: requested, durationMinutes: minutes,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil, exercises: []
        )
    }
}
