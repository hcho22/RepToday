import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// US-AU02/US-AU04: the account screens rendered from the production views - onboarding's "Save your
/// plan" step, the one-time sign-in an existing user meets, and the Account screen - in light and dark,
/// at the largest text size on a 375x667 phone, with what VoiceOver says asserted on the live tree.
@MainActor
final class AccountScreensEvidenceTests: XCTestCase {
    private let story = EvidenceOutput.Story.accounts
    private let phone = CGSize(width: 393, height: 852)
    private let smallPhone = CGSize(width: 375, height: 667)

    override func tearDown() {
        HostedSurface.dismantleAllHostedWindows()
        super.tearDown()
    }

    private func saveYourPlan() -> OnboardingView {
        let viewModel = OnboardingViewModel(userService: MockUserService(), sessionPolicyService: MockSessionPolicyService())
        viewModel.displayName = "Riley"
        while viewModel.step != .saveYourPlan { viewModel.advance() }
        return OnboardingView(viewModel: viewModel, accountAuth: StubAccountAuthService(isConfigured: true))
    }

    private func waitFor(_ label: String, in root: UIView, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while AccessibilityTree.element(labeled: label, in: root) == nil, Date() < deadline {
            HostedSurface.pump(for: 0.1)
        }
        HostedSurface.pump(for: 0.3)
    }

    /// Every sign-in control is a labelled button inside the screen and keeps its touch target.
    private func assertControls(_ labels: [String], in root: UIView, window: UIWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        for label in labels {
            let element = try XCTUnwrap(AccessibilityTree.element(labeled: label, in: root), "\(label) missing: \(AccessibilityTree.labels(in: root))", file: file, line: line)
            XCTAssertTrue(element.accessibilityTraits.contains(.button), "\(label) is a button", file: file, line: line)
            let frame = element.accessibilityFrame
            XCTAssertGreaterThanOrEqual(frame.minX, window.frame.minX - 0.5, "\(label) runs off the leading edge", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, window.frame.maxX + 0.5, "\(label) runs off the trailing edge", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.height, Theme.Spacing.minTouchTarget, "\(label) keeps its touch target", file: file, line: line)
        }
    }

    /// The three sign-in choices share one height, so no choice looks bigger or smaller than another
    /// at any text size.
    private func assertChoicesMatch(in root: UIView, file: StaticString = #filePath, line: UInt = #line) throws {
        let heights = try ["Continue with Apple", "Continue with Google", "Continue with email"].map { label in
            try XCTUnwrap(AccessibilityTree.element(labeled: label, in: root), "\(label) missing", file: file, line: line)
                .accessibilityFrame.height
        }
        XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 0.5, "choice heights differ: \(heights)", file: file, line: line)
    }

    private func assertDisciplineFirstCopy(_ root: UIView, file: StaticString = #filePath, line: UInt = #line) {
        let spoken = AccessibilityTree.spokenStrings(in: root).joined(separator: " ").lowercased()
        for word in ["streak", "lose", "lost", "don't miss", "last chance"] {
            XCTAssertFalse(spoken.contains(word), "no streak or guilt framing (\(word))", file: file, line: line)
        }
    }

    // MARK: - Save your plan

    func testSaveYourPlanInLightAndDark() throws {
        for (style, name) in [(UIUserInterfaceStyle.light, "save-your-plan-light.png"), (.dark, "save-your-plan-dark.png")] {
            let (host, window) = HostedSurface.host(saveYourPlan(), size: phone, style: style)
            let root = host.view!
            waitFor("Continue with email", in: root)
            XCTAssertNotNil(AccessibilityTree.element(labeled: "Save your plan", in: root), "\(AccessibilityTree.labels(in: root))")
            XCTAssertNotNil(AccessibilityTree.element(labeled: "Step 8 of 8", in: root))
            try assertControls(["Continue with Apple", "Continue with Google", "Continue with email", "Back"], in: root, window: window)
            try assertChoicesMatch(in: root)
            XCTAssertNil(AccessibilityTree.element(labeled: "Continue", in: root), "signing in is the only way forward")
            assertDisciplineFirstCopy(root)
            try EvidenceOutput.write(HostedSurface.capture(root, size: phone), named: name, for: story)
        }
    }

    func testSaveYourPlanFitsASmallPhoneAtTheLargestTextSize() throws {
        let tall = CGSize(width: smallPhone.width, height: 2200)
        let (host, window) = HostedSurface.host(
            saveYourPlan().environment(\.dynamicTypeSize, .accessibility5), size: tall, style: .light
        )
        let root = host.view!
        waitFor("Continue with email", in: root)
        try assertControls(["Continue with Apple", "Continue with Google", "Continue with email", "Back"], in: root, window: window)
        try assertChoicesMatch(in: root)
        try EvidenceOutput.write(HostedSurface.capture(root, size: tall), named: "save-your-plan-ax5-375.png", for: story)
        let (darkHost, _) = HostedSurface.host(
            saveYourPlan().environment(\.dynamicTypeSize, .accessibility5), size: tall, style: .dark
        )
        waitFor("Continue with email", in: darkHost.view)
        try assertChoicesMatch(in: darkHost.view)
        try EvidenceOutput.write(HostedSurface.capture(darkHost.view, size: tall), named: "save-your-plan-ax5-375-dark.png", for: story)

        // The real 375x667 screen: the heading and the first choice are on the first screenful.
        let (smallHost, _) = HostedSurface.host(saveYourPlan(), size: smallPhone, style: .light,
                                                emulatingSafeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0))
        waitFor("Continue with email", in: smallHost.view)
        try EvidenceOutput.write(HostedSurface.capture(smallHost.view, size: smallPhone), named: "save-your-plan-375x667.png", for: story)
    }

    func testTheEmailCodeStepsReadClearly() async throws {
        let auth = StubAccountAuthService(isConfigured: true)
        let viewModel = AccountSignInViewModel(auth: auth, context: .onboarding) { _ in }
        let (host, window) = HostedSurface.host(
            ScrollView { AccountSignInPanel(viewModel: viewModel).padding(Theme.Spacing.lg) }.background(Theme.Colors.background),
            size: phone, style: .dark
        )
        viewModel.chooseEmail()
        try await HostedSurface.settle(until: { AccessibilityTree.element(labeled: "Send code", in: host.view) != nil })
        try assertControls(["Send code", "Back to all sign-in options"], in: host.view, window: window)
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Email address", in: host.view))
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "email-entry-dark.png", for: story)

        viewModel.email = "riley@example.com"
        await viewModel.sendCode()
        try await HostedSurface.settle(until: { AccessibilityTree.element(labeled: "Sign in", in: host.view) != nil })
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Code from your email", in: host.view))
        XCTAssertTrue(AccessibilityTree.spokenStrings(in: host.view).contains("Enter the code we sent to riley@example.com."))
        try assertControls(["Sign in", "Send a new code", "Use a different email"], in: host.view, window: window)
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "email-code-dark.png", for: story)
    }

    // MARK: - The existing user's one-time sign-in

    func testTheOneTimeSignInForAnExistingUser() throws {
        for (style, name) in [(UIUserInterfaceStyle.light, "keep-your-history-light.png"), (.dark, "keep-your-history-dark.png")] {
            let (host, window) = HostedSurface.host(
                AccountRequiredView(auth: StubAccountAuthService(isConfigured: true)) { _ in },
                size: phone, style: style
            )
            let root = host.view!
            waitFor("Continue with email", in: root)
            XCTAssertNotNil(AccessibilityTree.element(labeled: "Keep your history", in: root))
            try assertControls(["Continue with Google", "Continue with email"], in: root, window: window)
            XCTAssertNil(AccessibilityTree.element(whereLabel: { $0.contains("Skip") }, in: root), "the one-time sign-in is required")
            assertDisciplineFirstCopy(root)
            try EvidenceOutput.write(HostedSurface.capture(root, size: phone), named: name, for: story)
        }
        let tall = CGSize(width: smallPhone.width, height: 2000)
        let (host, window) = HostedSurface.host(
            AccountRequiredView(auth: StubAccountAuthService(isConfigured: true)) { _ in }.environment(\.dynamicTypeSize, .accessibility5),
            size: tall, style: .light
        )
        waitFor("Continue with email", in: host.view)
        try assertControls(["Continue with Google", "Continue with email"], in: host.view, window: window)
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: tall), named: "keep-your-history-ax5-375.png", for: story)
    }

    // MARK: - The Account screen

    func testTheAccountScreenSaysWhatIsSaved() throws {
        let suite = "AccountScreensEvidenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appState = AppState(userDefaults: defaults)
        appState.linkAccount(AccountIdentity(userId: "user_1", email: "riley@example.com", method: .apple))
        appState.isOnboarded = true
        for (style, name) in [(UIUserInterfaceStyle.light, "account-light.png"), (.dark, "account-dark.png")] {
            let (host, _) = HostedSurface.host(
                NavigationStack { AccountView() }
                    .environment(\.services, ServiceContainer.mock())
                    .environment(appState),
                size: phone, style: style
            )
            waitFor("Signed in with Apple, riley@example.com", in: host.view)
            XCTAssertNotNil(AccessibilityTree.element(whereLabel: { $0.contains("Signed in with Apple") && $0.contains("riley@example.com") }, in: host.view),
                            "\(AccessibilityTree.labels(in: host.view))")
            XCTAssertNotNil(AccessibilityTree.element(whereLabel: { $0.contains("keeps your data on this phone only") }, in: host.view),
                            "with no account backend the screen says the data stays on the phone")
            try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: name, for: story)
        }
    }
}
