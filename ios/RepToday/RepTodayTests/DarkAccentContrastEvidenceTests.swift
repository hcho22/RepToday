import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for the dark-appearance accent contrast fix: white labels on filled
/// accent controls now sit on `Theme.Colors.accentFill` (#637988 in dark, 4.54:1) instead of the
/// text-weight accent (#788F9E, 3.38:1), and the three spots that already fell short reach 4.5:1.
///
/// Each test hosts a production surface in dark appearance and captures it under
/// `artifacts/reports/dark-accent-contrast/`. The filled controls are also read back off the rendered
/// pixels, so the evidence proves the fill the screen actually draws - not only the token's value,
/// which `AccentContrastTests` pins.
@MainActor
final class DarkAccentContrastEvidenceTests: XCTestCase {

    private var window: UIWindow?
    private let story = "dark-accent-contrast"
    private let size = CGSize(width: 393, height: 852)

    /// `AccentFill` in dark appearance, as 8-bit sRGB.
    private let darkFill = (red: 0x63, green: 0x79, blue: 0x88)

    override func tearDown() {
        window = nil
        super.tearDown()
    }

    // MARK: - Hosting and reading

    private func host<V: View>(_ view: V, level: UIUserInterfaceLevel = .base, size: CGSize? = nil) {
        window = nil
        let (_, hosted) = HostedSurface.host(view, size: size ?? self.size, settleFor: 1.5, level: level)
        window = hosted
    }

    private func root() -> UIView? { window?.rootViewController?.view }

    private func labels() -> [String] {
        guard let root = root() else { return [] }
        return AccessibilityTree.labels(in: root)
    }

    private func pump(until predicate: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            HostedSurface.pump(for: 0.1)
        }
        return predicate()
    }

    /// An element's frame in the hosted window's own coordinates.
    private func frame(_ predicate: (String) -> Bool) -> CGRect? {
        guard let root = root(), let window,
              let element = AccessibilityTree.element(whereLabel: predicate, in: root) else { return nil }
        return element.accessibilityFrame.offsetBy(dx: -window.frame.origin.x, dy: -window.frame.origin.y)
    }

    private func activate(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let root = root(), let control = AccessibilityTree.element(labeled: label, in: root) else {
            return XCTFail("no \"\(label)\" control; tree reads \(labels())", file: file, line: line)
        }
        XCTAssertTrue(control.accessibilityActivate(), "\"\(label)\" did not activate", file: file, line: line)
    }

    @discardableResult
    private func capture(_ name: String, size: CGSize? = nil) throws -> UIImage {
        let size = size ?? self.size
        guard let root = root() else {
            XCTFail("no hosted surface")
            return UIImage()
        }
        HostedSurface.pump(for: 0.6)
        let image = HostedSurface.capture(root, size: size, afterScreenUpdates: true)
        let path = try EvidenceOutput.write(image, named: "\(name).png", for: story)
        print("DARK-ACCENT EVIDENCE: \(path)")
        return image
    }

    /// The 8-bit sRGB color the capture drew at `point` (in points).
    private func pixel(at point: CGPoint, in image: UIImage) throws -> (red: Int, green: Int, blue: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private func contrastWithWhite(_ color: (red: Int, green: Int, blue: Int)) -> Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        return 1.05 / (luminance + 0.05)
    }

    private func assertClose(
        _ actual: (red: Int, green: Int, blue: Int), _ expected: (red: Int, green: Int, blue: Int),
        _ what: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let close = abs(actual.red - expected.red) <= 2 && abs(actual.green - expected.green) <= 2
            && abs(actual.blue - expected.blue) <= 2
        XCTAssertTrue(close, "\(what) drew \(actual), expected \(expected)", file: file, line: line)
    }

    /// Reads the fill a filled control drew just inside its leading edge, clear of its centered label,
    /// and asserts it is the dark `AccentFill` with a white label at 4.5:1 or better.
    private func assertAccentFill(
        of label: String, in image: UIImage, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let control = try XCTUnwrap(frame { $0 == label }, "no \"\(label)\"; tree reads \(labels())", file: file, line: line)
        let fill = try pixel(at: CGPoint(x: control.minX + 8, y: control.midY), in: image)
        assertClose(fill, darkFill, "\"\(label)\"'s fill", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            contrastWithWhite(fill), 4.5, "white on \"\(label)\"'s drawn fill must reach 4.5:1", file: file, line: line
        )
    }

    // MARK: - Fixtures

    private func exercise(_ id: String) throws -> Exercise {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "Exercises", withExtension: "json"))
        let list = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        return try XCTUnwrap(list.first { $0.id == id }, "no \(id) in the catalog")
    }

    private func strengthSession() throws -> Workout {
        let prescriptions = try ["push_wall", "squat_bodyweight"].map { id -> PrescribedExercise in
            let exercise = try exercise(id)
            return PrescribedExercise(
                id: UUID(), exercise: exercise, sets: 2, reps: exercise.defaultReps,
                durationSeconds: nil, restSeconds: 30
            )
        }
        return Workout(
            id: UUID(), createdAt: Date(), shape: .blend, focusPillar: nil, requestedMinutes: 15,
            wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: prescriptions)]
        )
    }

    private final class StubTransport: CoachProxyTransport, @unchecked Sendable {
        let fails: Bool
        init(fails: Bool) { self.fails = fails }
        func post(
            to url: URL, jsonBody: Data, headers: [String: String], timeoutSeconds: Double
        ) async throws -> (data: Data, statusCode: Int) {
            if fails { throw URLError(.notConnectedToInternet) }
            return (Data(#"{"reply":"Squats came up because they were your stalest pattern this week."}"#.utf8), 200)
        }
    }

    private func coachViewModel(fails: Bool) -> CoachViewModel {
        let viewModel = CoachViewModel(
            client: CoachProxyClient(
                endpoint: URL(string: "https://coach.reptoday.app/coach")!,
                safetyIdentifier: testCoachSafetyIdentifier,
                transport: StubTransport(fails: fails)
            ),
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(),
            exerciseService: try! MockExerciseService()
        )
        viewModel.grantDataSharingConsent()
        return viewModel
    }

    // MARK: - Filled accent controls

    /// Onboarding's last step: the selected duration chip and the "Start moving" button.
    func testOnboardingFilledControls() throws {
        let viewModel = OnboardingViewModel(userService: MockUserService(), sessionPolicyService: MockSessionPolicyService())
        while viewModel.step != .duration { viewModel.advance() }
        host(OnboardingView(viewModel: viewModel))
        XCTAssertTrue(pump(until: { self.labels().contains("Start moving") }), "\(labels())")
        let image = try capture("01-onboarding-duration")
        try assertAccentFill(of: "Start moving", in: image)
    }

    /// The Ready Screen: the selected duration chip and the pinned Start button.
    func testReadyScreenFilledControls() throws {
        let services = ServiceContainer.mock()
        let saved = expectation(description: "a user to build today's session for")
        Task {
            try await services.userService.save(MockPersistence.sampleUser)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        host(ReadyView(services: services))
        XCTAssertTrue(pump(until: { self.labels().contains("Start") }, timeout: 8), "\(labels())")
        let image = try capture("02-ready")
        try assertAccentFill(of: "Start", in: image)
    }

    /// The player's work window (Done) and the rest overlay that follows it (Skip rest).
    func testPlayerAndRestOverlayFilledControls() throws {
        host(ActiveSessionView(workout: try strengthSession(), user: MockPersistence.sampleUser))
        XCTAssertTrue(pump(until: { self.labels().contains("Done") }), "\(labels())")
        let player = try capture("03-player-work-window")
        try assertAccentFill(of: "Done", in: player)

        activate("Done")
        XCTAssertTrue(pump(until: { self.labels().contains("Skip rest") }), "\(labels())")
        let rest = try capture("04-rest-overlay")
        try assertAccentFill(of: "Skip rest", in: rest)
    }

    /// The paywall, rendered as the sheet it is presented as: the plan cards (white name, and the
    /// price line in full white in dark appearance) and the accent links on the sheet's #1C1C1E.
    func testPaywallPlanCards() throws {
        let tall = CGSize(width: 393, height: 1100)
        host(
            PaywallView(viewModel: PaywallViewModel(subscriptionService: MockSubscriptionService())),
            level: .elevated, size: tall
        )
        XCTAssertTrue(pump(until: { self.labels().contains("Restore purchases") }), "\(labels())")
        XCTAssertTrue(pump(until: { self.labels().contains { $0.localizedCaseInsensitiveContains("year") } }), "\(labels())")
        let image = try capture("05-paywall-sheet", size: tall)
        let plan = try XCTUnwrap(frame { $0.localizedCaseInsensitiveContains("year") }, "\(labels())")
        let fill = try pixel(at: CGPoint(x: plan.minX + 6, y: plan.midY), in: image)
        assertClose(fill, darkFill, "the plan card's fill")
    }

    /// The coach: the user's bubble on the fill, and the failure banner's accent "Try again".
    func testCoachBubbleAndRetry() async throws {
        let viewModel = coachViewModel(fails: true)
        viewModel.draft = "Why did I get squats today?"
        await viewModel.send()
        XCTAssertTrue(viewModel.canRetry)
        host(NavigationStack { CoachView(viewModel: viewModel) })
        XCTAssertTrue(labels().contains { $0.hasPrefix("You said:") }, "\(labels())")
        try capture("06-coach-bubble-and-retry")
    }

    /// The coach's in-flow decisions use the filled button.
    func testCoachOfferFilledButton() throws {
        host(
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                CoachInjuryOfferView(area: .knees, onAccept: {}, onDecline: {}).padding()
            }
        )
        let image = try capture("07-coach-injury-offer")
        try assertAccentFill(of: CoachInjuryOfferCopy.accept, in: image)
    }

    // MARK: - The three spots that already fell short

    /// The Profile tab's "Premium" badge on its (now 8%) accent wash.
    func testProfilePremiumBadge() async throws {
        let gate = CoachGateViewModel(subscriptionService: MockSubscriptionService(subscription: .free))
        await gate.load()
        host(
            NavigationStack {
                ZStack {
                    Theme.Colors.background.ignoresSafeArea()
                    VStack { CoachEntryRow(viewModel: gate) }.padding(.horizontal, Theme.Spacing.lg)
                }
            },
            size: CGSize(width: 393, height: 300)
        )
        // The row reads as one "Coach" element; the badge is visual, so the capture is the evidence and
        // `AccentContrastTests` pins its ratio.
        XCTAssertTrue(labels().contains("Coach"), "\(labels())")
        try capture("08-profile-premium-badge", size: CGSize(width: 393, height: 300))
    }

    /// The injury screen as the coach's sheet, after a failed read: Retry on the raised #2C2C2E row.
    func testInjuryRetryOnTheSheetsRaisedRow() async throws {
        let viewModel = InjuryFlagsViewModel(userService: MockUserService(user: nil))
        await viewModel.load()
        XCTAssertTrue(viewModel.loadFailed)
        host(
            NavigationStack { InjuryFlagsView(viewModel: viewModel, preselect: .knees, dismissesOnSave: true) },
            level: .elevated, size: CGSize(width: 393, height: 1000)
        )
        XCTAssertTrue(pump(until: { self.labels().contains(InjuryFlagsCopy.retry) }), "\(labels())")
        let image = try capture("09-injury-retry-sheet", size: CGSize(width: 393, height: 1000))
        let retry = try XCTUnwrap(frame { $0 == InjuryFlagsCopy.retry })
        let row = try pixel(at: CGPoint(x: retry.maxX - 4, y: retry.midY), in: image)
        assertClose(row, (0x2C, 0x2C, 0x2E), "the sheet's raised row behind Retry")
    }
}
