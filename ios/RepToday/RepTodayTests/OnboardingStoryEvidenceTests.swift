import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The onboarding story (`screens/F02*` in the design handoff): the four value screens that open
/// onboarding, rendered from the production `OnboardingView` and read off the live accessibility tree -
/// each screen's headline and pager step, Back and Continue / "Get started", the sign-in link on the
/// first screen only, the questions' own seven-segment bar after them, and the first screen at the
/// largest text size on a 375 x 667 phone.
@MainActor
final class OnboardingStoryEvidenceTests: XCTestCase {
    private let story = EvidenceOutput.Story.onboardingStory
    private let phone = CGSize(width: 402, height: 874)
    private let smallPhone = CGSize(width: 375, height: 667)

    private let screens: [(step: OnboardingViewModel.Step, headline: String, file: String)] = [
        (.welcome, OnboardingStoryCopy.welcomeHeadline, "story-1-promise.png"),
        (.storyWho, OnboardingStoryCopy.whoHeadline, "story-2-who.png"),
        (.storyHow, OnboardingStoryCopy.howHeadline, "story-3-how.png"),
        (.storyDiscipline, OnboardingStoryCopy.disciplineHeadline, "story-4-discipline.png"),
    ]

    override func tearDown() {
        HostedSurface.dismantleAllHostedWindows()
        super.tearDown()
    }

    private func viewModel(at step: OnboardingViewModel.Step) -> OnboardingViewModel {
        let viewModel = OnboardingViewModel(userService: MockUserService(), sessionPolicyService: MockSessionPolicyService())
        viewModel.displayName = "Riley"
        while viewModel.step != step { viewModel.advance() }
        return viewModel
    }

    private func waitFor(_ label: String, in root: UIView, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while AccessibilityTree.element(labeled: label, in: root) == nil, Date() < deadline {
            HostedSurface.pump(for: 0.1)
        }
    }

    // MARK: - The four screens

    func testEachStoryScreenReadsItsHeadlineOnItsOwnFourStepPager() throws {
        for (index, screen) in screens.enumerated() {
            let (host, _) = HostedSurface.host(OnboardingView(viewModel: viewModel(at: screen.step)), size: phone)
            let root = host.view!
            waitFor(screen.headline, in: root)
            let labels = AccessibilityTree.labels(in: root)

            let headline = try XCTUnwrap(AccessibilityTree.element(labeled: screen.headline, in: root),
                                         "\(screen.step) does not read its headline: \(labels)")
            XCTAssertTrue(headline.accessibilityTraits.contains(.header), "\(screen.step)'s headline is a heading")
            XCTAssertNotNil(AccessibilityTree.element(labeled: "Step \(index + 1) of 4", in: root),
                            "\(screen.step) is on the story's four-step pager: \(labels)")

            let primary = index == screens.count - 1 ? "Get started" : "Continue"
            let button = try XCTUnwrap(AccessibilityTree.element(labeled: primary, in: root), "\(screen.step) has no \(primary): \(labels)")
            XCTAssertTrue(button.accessibilityTraits.contains(.button))
            XCTAssertEqual(AccessibilityTree.element(labeled: "Back", in: root) != nil, index > 0,
                           "Back is on every story screen but the first")
            XCTAssertEqual(AccessibilityTree.element(labeled: "Already have an account? Sign in", in: root) != nil, index == 0,
                           "only the first story screen offers signing in")

            try EvidenceOutput.write(HostedSurface.capture(root, size: phone), named: screen.file, for: story)
            HostedSurface.dismantleAllHostedWindows()
        }
    }

    /// Screen 1 keeps the anonymous-usage disclosure, read as the sentence and then a link of its own,
    /// though the link is drawn inline at the sentence's end.
    func testTheFirstScreenDisclosesUsageDataWithAPolicyLinkOfItsOwn() throws {
        let (host, _) = HostedSurface.host(OnboardingView(viewModel: viewModel(at: .welcome)), size: phone)
        let root = host.view!
        waitFor(OnboardingStoryCopy.welcomeHeadline, in: root)
        let labels = AccessibilityTree.labels(in: root)
        let disclosure = try XCTUnwrap(labels.first { $0.contains("anonymous usage data") }, "\(labels)")
        XCTAssertFalse(disclosure.contains("Privacy Policy"), "the link is its own element, not read inside the sentence")
        let link = try XCTUnwrap(AccessibilityTree.element(labeled: "Privacy Policy", in: root), "\(labels)")
        XCTAssertTrue(link.accessibilityTraits.contains(.link), "Privacy Policy is read as a link")
    }

    /// "Already have an account? Sign in" goes to the existing sign-in on "Save your plan", and Back
    /// from there returns to the first story screen.
    func testSignInFromTheFirstScreenOpensTheExistingSignIn() throws {
        let model = viewModel(at: .welcome)
        let (host, _) = HostedSurface.host(
            OnboardingView(viewModel: model, accountAuth: StubAccountAuthService(isConfigured: true)),
            size: phone
        )
        let root = host.view!
        waitFor("Already have an account? Sign in", in: root)
        let link = try XCTUnwrap(AccessibilityTree.element(labeled: "Already have an account? Sign in", in: root))
        XCTAssertTrue(link.accessibilityTraits.contains(.button))
        _ = link.accessibilityActivate()
        waitFor("Continue with email", in: root)

        XCTAssertEqual(model.step, .saveYourPlan)
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Continue with email", in: root),
                        "the sign-in choices: \(AccessibilityTree.labels(in: root))")
        model.goBack()
        XCTAssertEqual(model.step, .welcome)
    }

    // MARK: - The questions' bar

    func testTheQuestionsShowTheirOwnSevenSegmentBar() throws {
        for (step, label) in [(OnboardingViewModel.Step.basics, "Step 1 of 7"), (.duration, "Step 6 of 7"), (.saveYourPlan, "Step 7 of 7")] {
            let (host, _) = HostedSurface.host(
                OnboardingView(viewModel: viewModel(at: step), accountAuth: StubAccountAuthService(isConfigured: true)),
                size: phone
            )
            let root = host.view!
            waitFor(label, in: root)
            XCTAssertNotNil(AccessibilityTree.element(labeled: label, in: root),
                            "\(step) reads \(label): \(AccessibilityTree.labels(in: root))")
            HostedSurface.dismantleAllHostedWindows()
        }
    }

    // MARK: - Largest text size

    /// At the largest accessibility size on a 375 x 667 phone the first screen still names itself once,
    /// keeps Continue, the sign-in link and the policy link, and nothing runs off either side.
    func testTheFirstScreenAtTheLargestTextSizeOnASmallPhone() throws {
        let (host, window) = HostedSurface.host(
            OnboardingView(viewModel: viewModel(at: .welcome)).environment(\.dynamicTypeSize, .accessibility5),
            size: smallPhone
        )
        let root = host.view!
        waitFor(OnboardingStoryCopy.welcomeHeadline, in: root)
        let spoken = AccessibilityTree.spokenStrings(in: root)
        XCTAssertEqual(spoken.filter { $0 == OnboardingStoryCopy.welcomeHeadline }.count, 1, "the headline is read once: \(spoken)")
        for label in ["Continue", "Already have an account? Sign in", "Privacy Policy"] {
            XCTAssertNotNil(AccessibilityTree.element(labeled: label, in: root), "\(label) is reachable: \(spoken)")
        }
        assertInsideTheScreenHorizontally(root: root, window: window)
        try EvidenceOutput.write(HostedSurface.capture(root, size: smallPhone), named: "story-1-promise-ax5-375.png", for: story)
    }

    /// Every story screen laid out whole at the largest text size on a 375 pt wide phone keeps every
    /// element inside the screen's width: the visuals restack rather than squeeze or spill.
    func testEveryStoryScreenStaysInsideASmallPhoneAtTheLargestTextSize() {
        for screen in screens {
            let (host, window) = HostedSurface.host(
                OnboardingView(viewModel: viewModel(at: screen.step)).environment(\.dynamicTypeSize, .accessibility5),
                size: CGSize(width: smallPhone.width, height: 3200)
            )
            let root = host.view!
            waitFor(screen.headline, in: root)
            assertInsideTheScreenHorizontally(root: root, window: window, context: "\(screen.step)")
            HostedSurface.dismantleAllHostedWindows()
        }
    }

    private func assertInsideTheScreenHorizontally(root: UIView, window: UIWindow, context: String = "",
                                                   file: StaticString = #filePath, line: UInt = #line) {
        for element in AccessibilityTree.elements(in: root) {
            let frame = element.accessibilityFrame
            guard frame.width > 0 else { continue }
            XCTAssertGreaterThanOrEqual(frame.minX, window.frame.minX - 0.5,
                                        "\(context) \(element.accessibilityLabel ?? "?") runs off the leading edge", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.frame.maxX + 0.5,
                                     "\(context) \(element.accessibilityLabel ?? "?") runs off the trailing edge", file: file, line: line)
        }
    }
}
