import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for US-AC02, the talking coach: a chat surface where the user asks
/// free-text questions and the coach answers, grounded in their real history, and degrading to a
/// clear non-blocking state on failure.
///
/// This drives the *production* `CoachView` in a real key window, over a view model backed by a stub
/// transport (no live proxy), and asserts the load-bearing surface on the live accessibility tree -
/// the user's question and the coach's grounded answer both rendered as distinct turns, the input
/// control present, the graceful retryable failure banner, and the non-retryable safety outcome.
/// The story's evidence screens are captured under `artifacts/reports/US-AC02/`.
@MainActor
final class CoachViewEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "US-AC02"

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Stub transport

    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        enum Outcome {
            case success(reply: String)
            case safetyRefusal
            case failure
        }
        var outcome: Outcome
        init(_ outcome: Outcome) { self.outcome = outcome }

        struct Boom: Error {}

        func post(
            to url: URL,
            jsonBody: Data,
            headers: [String: String],
            timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            switch outcome {
            case let .success(reply):
                return (Data(#"{"reply":"\#(reply)"}"#.utf8), 200)
            case .safetyRefusal:
                return (Data(#"{"outcome":"safety_refusal"}"#.utf8), 200)
            case .failure:
                throw Boom()
            }
        }
    }

    private func makeViewModel(transport: StubTransport) -> CoachViewModel {
        var user = MockPersistence.sampleUser
        user.phase = .discipline
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://proxy.example.com/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: transport
            ),
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
        // These US-AC02 evidence surfaces exercise the answered conversation, so consent to the US-AC04
        // data disclosure is granted; the disclosure itself has its own evidence in US-AC04.
        viewModel.grantDataSharingConsent()
        return viewModel
    }

    private func labels() -> [String] {
        guard let root = window?.rootViewController?.view else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func labelsContain(_ needle: String) -> Bool {
        labels().contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func capture(named fileName: String, size: CGSize) throws {
        guard let root = window?.rootViewController?.view else { return XCTFail("no hosted surface") }
        let image = HostedSurface.capture(root, size: size)
        let path = try EvidenceOutput.write(image, named: fileName, for: story)
        print("US-AC02 EVIDENCE: \(fileName) -> \(path)")
    }

    // MARK: - Evidence

    /// A grounded answered conversation: the user asks why they got squats, the coach answers, and
    /// both turns render as distinct, VoiceOver-legible bubbles.
    func testCoachAnswersAQuestionAsDistinctTurns() async throws {
        let transport = StubTransport(.success(
            reply: "Squats came up because they were your stalest movement pattern this week."
        ))
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "Why did I get squats today?"
        await viewModel.send()

        XCTAssertEqual(viewModel.messages.count, 2)

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(NavigationStack { CoachView(viewModel: viewModel) }, size: size)
        window = hostedWindow

        XCTAssertTrue(labelsContain("You said: Why did I get squats today?"),
                      "the user's turn should be a distinct labelled bubble; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Coach said: Squats came up because they were your stalest"),
                      "the coach's grounded answer should render; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Message to the coach"), "the input control is present")
        XCTAssertTrue(labelsContain("Send"), "the send control is present")

        try capture(named: "01-coach-answered-conversation.png", size: size)
        _ = host
    }

    /// Graceful failure: a transport error becomes a clear, non-blocking, retryable banner - the
    /// user's question survives and the workout is explicitly said to be unaffected.
    func testCoachFailureIsGracefulAndRetryable() async throws {
        let transport = StubTransport(.failure)
        let viewModel = makeViewModel(transport: transport)

        viewModel.draft = "How do I do a pistol squat?"
        await viewModel.send()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.canRetry)

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(NavigationStack { CoachView(viewModel: viewModel) }, size: size)
        window = hostedWindow

        XCTAssertTrue(labelsContain("You said: How do I do a pistol squat?"),
                      "the question survives a failure; tree reads \(labels())")
        XCTAssertTrue(labelsContain("workout isn't affected"),
                      "the failure copy reassures the core loop is unaffected; tree reads \(labels())")
        XCTAssertTrue(labelsContain("Try again"), "the failure is retryable; tree reads \(labels())")

        try capture(named: "02-coach-graceful-failure.png", size: size)
        _ = host
    }

    func testSafetyRefusalShowsOwnedMessageWithoutRetryControl() async {
        let viewModel = makeViewModel(transport: StubTransport(.safetyRefusal))

        viewModel.draft = "Unsafe request"
        await viewModel.send()

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(NavigationStack { CoachView(viewModel: viewModel) }, size: size)
        window = hostedWindow

        XCTAssertTrue(labelsContain(CoachViewModel.safetyRefusalMessage),
                      "the app shows only its stable safety message; tree reads \(labels())")
        XCTAssertFalse(labelsContain("Try again"),
                       "the refusal must not offer to resend the same request; tree reads \(labels())")
        _ = host
    }

    /// The unconfigured build: no proxy origin set, so the surface shows a calm "unavailable" state
    /// rather than an error - which is the state every shipped build is in today.
    func testUnavailableStateWhenUnconfigured() async throws {
        let viewModel = CoachViewModel(
            client: nil,
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )

        let size = CGSize(width: 393, height: 852)
        let (host, hostedWindow) = HostedSurface.host(NavigationStack { CoachView(viewModel: viewModel) }, size: size)
        window = hostedWindow

        XCTAssertTrue(labelsContain("Coach isn't available right now"),
                      "the unconfigured build shows a calm unavailable state; tree reads \(labels())")
        XCTAssertTrue(labelsContain("workouts are unaffected"),
                      "the unavailable copy reassures the core loop is unaffected; tree reads \(labels())")

        try capture(named: "03-coach-unavailable.png", size: size)
        _ = host
    }
}
