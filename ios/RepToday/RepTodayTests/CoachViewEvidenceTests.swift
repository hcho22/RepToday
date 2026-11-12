import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Evidence for the Coach tab (M4, US-CA06): the production `CoachTabView` hosted in a real window over
/// the shared `CoachFixture`, read through the accessibility tree and captured to PNGs.
///
/// It covers a Premium conversation with a proposal card of each kind and a Custom Workout card, the
/// free preview with its paywall entry, the not-in-this-build and offline states - in light and dark, at
/// the largest accessibility text size and on a 375x667 screen. Behavior is proved in
/// `CoachViewModelTests`; this suite proves what the user sees and what VoiceOver says. PNGs go to
/// `EvidenceOutput`'s folder for "US-CA06".
@MainActor
final class CoachViewEvidenceTests: XCTestCase {

    private var windows: [UIWindow] = []
    private let story = "US-CA06"
    private static let phone = CGSize(width: 393, height: 852)
    private static let small = CGSize(width: 375, height: 667)

    override func tearDown() {
        windows.forEach(HostedSurface.dismantle)
        windows = []
        super.tearDown()
    }

    private func host<V: View>(
        _ view: V, size: CGSize = CoachViewEvidenceTests.phone, style: UIUserInterfaceStyle = .light,
        textSize: DynamicTypeSize = .large
    ) -> UIView {
        let (host, window) = HostedSurface.host(
            view
                .environment(\.services, ServiceContainer.mock())
                .environment(\.dynamicTypeSize, textSize),
            size: size,
            style: style
        )
        windows.append(window)
        return host.view
    }

    private func spoken(_ root: UIView) -> String {
        AccessibilityTree.spokenStrings(in: root).joined(separator: " • ")
    }

    private func capture(_ root: UIView, _ name: String, size: CGSize = CoachViewEvidenceTests.phone) throws {
        let path = try EvidenceOutput.write(HostedSurface.capture(root, size: size), named: name, for: story)
        print("US-CA06 EVIDENCE: \(name) -> \(path)")
    }

    /// A conversation where the Coach has proposed one of each action and a Custom Workout.
    private func conversationFixture() async -> CoachFixture {
        let proposals: [CoachProposal] = [
            CoachFixture.proposal(.outsideActivity(type: .run, minutes: 30, distanceMeters: 5000, day: .today)),
            CoachFixture.proposal(.todayLength(minutes: 10)),
            CoachFixture.proposal(.reminder(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6])),
        ]
        let fixture = CoachFixture(coach: MockCoachService(now: { CoachFixture.now }) { message in
            message.contains("workout")
                ? ("Here's a short workout built around your recent sessions. Look it over, then accept it to play.",
                   [CoachFixture.proposal(.customWorkout(CoachFixture.draft))])
                : ("Nice work getting that run in. I've put a few things below for you to confirm.", proposals)
        })
        await fixture.viewModel.load()
        fixture.viewModel.draft = "I ran 5k this morning, keep today short and remind me on weekdays"
        await fixture.viewModel.send()
        fixture.viewModel.draft = "Write me a workout for a hotel room"
        await fixture.viewModel.send()
        return fixture
    }

    func testPremiumConversationShowsProposalCardsAndTheCustomWorkoutCard() async throws {
        let fixture = await conversationFixture()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let root = host(CoachTabView(viewModel: fixture.viewModel), size: CGSize(width: 393, height: 2200), style: style)
            let spoken = spoken(root)
            XCTAssertTrue(spoken.contains("You said: I ran 5k this morning"), spoken)
            XCTAssertTrue(spoken.contains("Coach said: Nice work getting that run in"), spoken)
            XCTAssertTrue(spoken.contains("Log a 30-minute run"), spoken)
            XCTAssertTrue(spoken.contains("Make today 10 minutes"), spoken)
            XCTAssertTrue(spoken.contains("Remind me at"), spoken)
            XCTAssertTrue(spoken.contains("Desk Reset"), spoken)
            XCTAssertTrue(spoken.contains("Incline Push-Up, 3 sets of 10 reps"), spoken)
            XCTAssertTrue(spoken.contains("Doorway Chest Opener") && spoken.contains("text only, no picture"), spoken)
            XCTAssertNotNil(AccessibilityTree.element(labeled: CoachProposalCopy.confirm, in: root))
            XCTAssertNotNil(AccessibilityTree.element(labeled: "Review and accept", in: root))
            for chip in CoachViewModel.quickActions.prefix(2) {
                XCTAssertNotNil(AccessibilityTree.element(labeled: chip.title, in: root), "chip \(chip.title)")
            }
            try capture(root, "01-conversation-\(style == .dark ? "dark" : "light").png", size: CGSize(width: 393, height: 2200))
        }
    }

    func testConversationAtTheLargestTextSizeAndOnASmallScreen() async throws {
        let fixture = await conversationFixture()
        let large = host(CoachTabView(viewModel: fixture.viewModel), size: CGSize(width: 393, height: 4000), textSize: .accessibility5)
        XCTAssertTrue(spoken(large).contains("Log a 30-minute run"))
        try capture(large, "02-conversation-largest-text.png", size: CGSize(width: 393, height: 4000))

        let small = host(CoachTabView(viewModel: fixture.viewModel), size: Self.small)
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Send", in: small), "the input stays reachable on a 375x667 screen")
        try capture(small, "03-conversation-375x667.png", size: Self.small)
    }

    func testAppliedProposalShowsDoneAndUndo() async throws {
        let fixture = await conversationFixture()
        let message = try XCTUnwrap(fixture.viewModel.messages.first { !$0.proposals.isEmpty })
        await fixture.viewModel.apply(message.proposals[0], in: message)
        let root = host(CoachTabView(viewModel: fixture.viewModel), size: CGSize(width: 393, height: 2200))
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachProposalCopy.undo, in: root), spoken(root))
        XCTAssertTrue(spoken(root).contains(CoachProposalCopy.applied))
        try capture(root, "04-applied-with-undo.png", size: CGSize(width: 393, height: 2200))
    }

    func testFreeUserSeesThePreviewAndThePaywallEntry() async throws {
        let fixture = CoachFixture(premium: false)
        await fixture.viewModel.load()
        XCTAssertEqual(fixture.viewModel.access, .free)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let root = host(CoachTabView(viewModel: fixture.viewModel), style: style)
            let spoken = spoken(root)
            XCTAssertTrue(spoken.contains(CoachCopy.previewTitle), spoken)
            XCTAssertNotNil(AccessibilityTree.element(labeled: CoachCopy.unlock, in: root))
            XCTAssertNotNil(AccessibilityTree.element(labeled: CoachCopy.restore, in: root))
            XCTAssertNil(AccessibilityTree.element(labeled: "Message to the coach", in: root), "a free user gets no chat")
            try capture(root, "05-free-preview-\(style == .dark ? "dark" : "light").png")
        }
        let large = host(CoachTabView(viewModel: fixture.viewModel), size: CGSize(width: 393, height: 2400), textSize: .accessibility5)
        XCTAssertNotNil(AccessibilityTree.element(labeled: CoachCopy.unlock, in: large))
        try capture(large, "06-free-preview-largest-text.png", size: CGSize(width: 393, height: 2400))
        let sent = await fixture.coach.sent
        XCTAssertTrue(sent.isEmpty, "the preview never talks to the Coach")
    }

    func testARestoreWithNothingToLinkSaysSoOnThePreview() async throws {
        // The phone shows Premium but holds no signed transaction to send, as an Xcode StoreKit run does
        // for a Sandbox subscription: the preview says nothing was found instead of asking for Restore again.
        let premium = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        let fixture = CoachFixture(premium: false, subscription: premium, signedTransactions: [])
        await fixture.viewModel.restorePurchases()
        XCTAssertEqual(fixture.viewModel.access, .free)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let root = host(CoachTabView(viewModel: fixture.viewModel), style: style)
            let spoken = spoken(root)
            XCTAssertTrue(spoken.contains(CoachCopy.noSubscriptionFound), spoken)
            XCTAssertFalse(spoken.contains(CoachCopy.unconfirmed), "no Restore that can only lead back here")
            XCTAssertNotNil(AccessibilityTree.element(labeled: CoachCopy.unlock, in: root))
            try capture(root, "08-restore-found-nothing-\(style == .dark ? "dark" : "light").png")
        }
        let small = host(CoachTabView(viewModel: fixture.viewModel), size: Self.small)
        XCTAssertTrue(spoken(small).contains(CoachCopy.noSubscriptionFound))
        try capture(small, "09-restore-found-nothing-small.png", size: Self.small)
    }

    func testUnavailableAndOfflineStatesAreCalm() async throws {
        let unavailable = CoachViewModel(
            coach: nil,
            entitlements: nil,
            subscriptionService: MockSubscriptionService(),
            premiumAuthority: PremiumSessionAuthority(),
            applier: CoachProposalApplier(
                userService: MockUserService(),
                outsideActivityService: InMemoryOutsideActivityService(),
                todayChoices: InMemoryTodayChoicesStore(),
                reminders: CoachFixture().reminders,
                customWorkouts: InMemoryCustomWorkoutService(),
                planInputsChanged: {}
            ),
            today: CoachTodayReader(services: ServiceContainer.mock()),
            customWorkouts: InMemoryCustomWorkoutService(),
            userService: MockUserService(),
            exerciseService: try MockExerciseService()
        )
        await unavailable.load()
        XCTAssertEqual(unavailable.access, .unavailable)
        let root = host(CoachTabView(viewModel: unavailable))
        XCTAssertTrue(spoken(root).contains(CoachCopy.unavailable), spoken(root))
        try capture(root, "07-unavailable.png")
    }
}
