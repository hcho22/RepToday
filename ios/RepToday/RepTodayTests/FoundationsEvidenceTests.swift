import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Reviewer-visible evidence for ADR-0006, "Foundations are Push, Pull, Legs, Core": the production
/// Progress tab, its one-time note, and the Strength graduation reveal, rendered in a real key window
/// over realistic seeded history through the real evaluator, real analytics, and the real catalog.
///
/// Three users are seeded, each rendered in light, dark and at a large Dynamic Type size:
///
/// - **fresh** - a brand-new install with a first session: every foundation "not started", and no
///   foundations note (they onboarded on this build, so there is nothing to explain);
/// - **mid-climb** - an existing install whose count drops under the new rules: Push, Core and the
///   Squat side of Legs cleared under the old four, but Pull never trained on its horizontal chain (only
///   the postural chain, which never counts) and Legs' Hinge side still open, so 2 of 4 now and the
///   one-time note explains it;
/// - **Strength** - an earned Strength user whose recalculated history would not clear Pull, kept in
///   Strength by the ratchet, with no climb card and no note.
///
/// Assertions read the live accessibility tree; PNGs go through `EvidenceOutput` (temporary directory
/// on a plain run, `artifacts/reports/foundations-ppl/` with `REPTODAY_WRITE_EVIDENCE=1`).
@MainActor
final class FoundationsEvidenceTests: XCTestCase {

    private let story = "foundations-ppl"
    private var window: UIWindow?

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - Seeded history

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    private func showUps(weeks: Int) -> [WorkoutLog] {
        (0..<weeks).flatMap { w in
            (0..<3).map { d in
                WorkoutLog(
                    id: UUID(), workoutId: UUID(), completedAt: date(weeksAgo: w, dayOffset: d + 3),
                    requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
                    shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight, exercises: []
                )
            }
        }
    }

    /// A session whose one exercise is `sets` sets of `exerciseId`, each `value` reps (or seconds).
    private func work(_ exerciseId: String, _ pattern: MovementPattern, hold: Bool = false, value: Int, weeksAgo: Int, day: Int = 0) -> WorkoutLog {
        let sets = (0..<3).map { _ in CompletedSet(reps: hold ? nil : value, durationSeconds: hold ? value : nil) }
        return WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: date(weeksAgo: weeksAgo, dayOffset: day),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight,
            exercises: [LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                                       movementPattern: pattern, completedSets: sets, skipped: false)]
        )
    }

    private var freshLogs: [WorkoutLog] {
        [work("push_wall", .push, value: 8, weeksAgo: 0)]
    }

    /// Eight steady weeks. Push climbs wall -> knee -> standard (entry cleared), the squat side climbs
    /// from the wall sit (cleared) to the bodyweight squat, core clears its forearm plank, and hinge sits
    /// short of its bridge criteria for weeks. Pull has only postural work, which never counts.
    private var midClimbLogs: [WorkoutLog] {
        showUps(weeks: 8) + [
            work("push_wall", .push, value: 15, weeksAgo: 7, day: 1),
            work("push_knee", .push, value: 12, weeksAgo: 4, day: 1),
            work("push_standard", .push, value: 12, weeksAgo: 1, day: 1),
            work("squat_wall_sit", .squat, hold: true, value: 45, weeksAgo: 6, day: 1),
            work("squat_bodyweight", .squat, value: 20, weeksAgo: 2, day: 1),
            work("hinge_glute_bridge", .hinge, value: 14, weeksAgo: 5, day: 1),
            work("hinge_glute_bridge", .hinge, value: 16, weeksAgo: 0, day: 1),
            work("core_forearm_plank", .core, hold: true, value: 45, weeksAgo: 6, day: 2),
            work("pull_superman", .pull, hold: true, value: 30, weeksAgo: 3, day: 1),
            work("pull_reverse_snow_angel", .pull, value: 15, weeksAgo: 1, day: 2),
        ]
    }

    /// Everything cleared except Pull's horizontal chain, with a Strength-Phase rung already in use.
    private var strengthLogs: [WorkoutLog] {
        showUps(weeks: 10) + [
            work("push_wall", .push, value: 15, weeksAgo: 9, day: 1),
            work("push_archer", .push, value: 8, weeksAgo: 3, day: 1),
            work("push_one_arm_assisted", .push, value: 6, weeksAgo: 0, day: 1),
            work("squat_wall_sit", .squat, hold: true, value: 45, weeksAgo: 8, day: 1),
            work("squat_pistol_assisted", .squat, value: 6, weeksAgo: 0, day: 2),
            work("hinge_glute_bridge", .hinge, value: 20, weeksAgo: 8, day: 2),
            work("hinge_long_lever_bridge", .hinge, value: 8, weeksAgo: 1, day: 2),
            work("core_forearm_plank", .core, hold: true, value: 45, weeksAgo: 8, day: 3),
            work("core_tuck_l_sit", .core, hold: true, value: 20, weeksAgo: 2, day: 3),
            work("pull_superman", .pull, hold: true, value: 30, weeksAgo: 4, day: 1),
        ]
    }

    // MARK: - Harness

    private func makeViewModel(logs: [WorkoutLog], phase: Phase, premium: Bool) -> ProgressViewModel {
        var user = MockPersistence.sampleUser
        user.phase = phase
        return ProgressViewModel(
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: premium ? Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil) : .free),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
    }

    private func makeAppState(existingInstall: Bool, suite: String) -> AppState {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if existingInstall { defaults.set(true, forKey: "AppState.isOnboarded") }
        let appState = AppState(userDefaults: defaults)
        // A brand-new install onboards on this build.
        if !existingInstall { appState.isOnboarded = true }
        return appState
    }

    private enum Look: String, CaseIterable {
        case light, dark, large

        var style: UIUserInterfaceStyle { self == .light ? .light : .dark }
        var typeSize: DynamicTypeSize { self == .large ? .accessibility2 : .large }
    }

    /// Hosts `view` in `look`, returning the host view for reading and the cropped capture.
    ///
    /// Async on purpose: the tab's own `.task` and the climb card's note presentation run on the main
    /// actor, which a synchronous test never yields, so the render yields between pumps.
    /// `ready` names the state the caller wants on screen (e.g. the one-time note having appeared);
    /// the render waits, bounded, for it before capturing.
    ///
    /// The appearance is set once, through `HostedSurface.host(style:)`, and never again on the window:
    /// overriding the window's style after hosting left a dark surface resolving the app's accent colour
    /// for the light appearance (dark teal on near-black), so the dark evidence was not faithful to the app.
    private func render<V: View>(
        _ view: V, look: Look, width: CGFloat = 393, height: CGFloat, until ready: () -> Bool = { true }
    ) async -> (root: UIView, image: UIImage) {
        let (host, hostedWindow) = HostedSurface.host(view.dynamicTypeSize(look.typeSize), size: CGSize(width: width, height: height), settleFor: 0.5, style: look.style)
        var pumps = 0
        while pumps < 15 || (!ready() && pumps < 55) {
            await Task.yield()
            HostedSurface.pump(for: 0.3)
            pumps += 1
        }
        window?.isHidden = true
        window = hostedWindow
        let root = host.view!
        root.setNeedsLayout()
        root.layoutIfNeeded()
        HostedSurface.pump(for: 0.5)
        var captureHeight = height
        if let scroll = firstScrollView(in: root) {
            let bottom = scroll.convert(CGPoint(x: 0, y: scroll.contentSize.height), to: root).y + scroll.adjustedContentInset.bottom
            if bottom > 0 { captureHeight = min(height, ceil(bottom)) }
        }
        // `layer.render(in:)` resolves dynamic colours against the *current* trait collection.
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: look.style).performAsCurrent {
            image = HostedSurface.capture(root, size: CGSize(width: width, height: captureHeight))
        }
        // These are full scrolling surfaces (up to ~10,000pt tall), so they are committed at 1x rather
        // than the shared 3x to keep the repository small; text stays legible.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let committed = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return (root, committed)
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private func labels(_ root: UIView) -> [String] { AccessibilityTree.labels(in: root) }

    private func has(_ needle: String, in root: UIView) -> Bool {
        labels(root).contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Fresh user

    func testFreshInstallSeesNotStartedFoundationsAndNoNote() async throws {
        let viewModel = makeViewModel(logs: freshLogs, phase: .discipline, premium: false)
        await viewModel.load()
        let appState = makeAppState(existingInstall: false, suite: "FoundationsEvidence.fresh")

        for look in Look.allCases {
            let (root, image) = await render(ProgressTabView(viewModel: viewModel).environment(appState), look: look, height: 7000)

            XCTAssertTrue(has("0 of 4 cleared", in: root), "\(look): \(labels(root))")
            XCTAssertTrue(has("Push, in progress", in: root))
            XCTAssertTrue(has("Legs, 0 of 2 sides cleared", in: root))
            XCTAssertTrue(has("Pull, in progress", in: root))
            XCTAssertFalse(has("Your foundations are now", in: root), "a brand-new install never sees the note")
            XCTAssertTrue(has("Legs, hinge side, not started yet", in: root), "\(look)")
            try EvidenceOutput.write(image, named: "01-fresh-\(look.rawValue).png", for: story)
        }
        XCTAssertTrue(appState.hasSeenFoundationsUpdateNote)
    }

    func testExistingEmptyInstallKeepsNoteUntilClimbCardAppears() async {
        let appState = makeAppState(existingInstall: true, suite: "FoundationsEvidence.emptyThenClimb")
        let emptyViewModel = makeViewModel(logs: [], phase: .discipline, premium: false)

        let (emptyRoot, _) = await render(
            ProgressTabView(viewModel: emptyViewModel).environment(appState),
            look: .light,
            height: 1200
        )

        XCTAssertFalse(has("Your climb to Strength", in: emptyRoot))
        XCTAssertFalse(has("Your foundations are now", in: emptyRoot))
        XCTAssertTrue(appState.shouldShowFoundationsUpdateNote)

        let historyViewModel = makeViewModel(logs: showUps(weeks: 1), phase: .discipline, premium: false)
        let (historyRoot, _) = await render(
            ProgressTabView(viewModel: historyViewModel).environment(appState),
            look: .light,
            height: 7000,
            until: { !appState.shouldShowFoundationsUpdateNote }
        )

        XCTAssertTrue(has("Your climb to Strength", in: historyRoot))
        XCTAssertTrue(has("Your foundations are now Push, Pull, Legs, and Core", in: historyRoot))
        XCTAssertFalse(appState.shouldShowFoundationsUpdateNote)

        let (laterRoot, _) = await render(
            ProgressTabView(viewModel: historyViewModel).environment(appState),
            look: .light,
            height: 7000
        )
        XCTAssertFalse(has("Your foundations are now", in: laterRoot))
    }

    // MARK: - Mid-climb user whose count drops

    func testMidClimbUserSeesTheNoteOnceAndTheRecalculatedFoundations() async throws {
        let viewModel = makeViewModel(logs: midClimbLogs, phase: .discipline, premium: true)
        await viewModel.load()

        // Recalculated: push, core cleared; pull (postural only) and legs (squat only) not.
        let progress = try XCTUnwrap(viewModel.phaseProgress)
        XCTAssertEqual(progress.foundations.map(\.isCleared), [true, false, false, true])
        XCTAssertEqual(progress.foundations[2].clearedLineCount, 1)
        XCTAssertTrue(viewModel.isFoundationsUpdateNoteEligible)

        let appState = makeAppState(existingInstall: true, suite: "FoundationsEvidence.midClimb")
        XCTAssertTrue(appState.shouldShowFoundationsUpdateNote)

        // First appearance: the note is on the climb card, and the one-shot flag flips immediately.
        let (firstRoot, firstImage) = await render(
            ProgressTabView(viewModel: viewModel).environment(appState), look: .light, height: 9000,
            until: { !appState.shouldShowFoundationsUpdateNote }
        )
        XCTAssertTrue(has("Your foundations are now Push, Pull, Legs, and Core", in: firstRoot), "\(labels(firstRoot))")
        XCTAssertTrue(has("2 of 4 cleared (Push, Core)", in: firstRoot), "the note states where the user stands")
        XCTAssertTrue(has("Got it", in: firstRoot))
        XCTAssertFalse(appState.shouldShowFoundationsUpdateNote, "shown once: the flag flips when the note appears")
        try EvidenceOutput.write(firstImage, named: "02-mid-climb-note-light.png", for: story)

        // The tab, the map, and the journey read the same recalculated standing.
        XCTAssertTrue(has("2 of 4 cleared", in: firstRoot))
        XCTAssertTrue(has("Legs, 1 of 2 sides cleared", in: firstRoot))
        XCTAssertTrue(has("Legs, squat side, Bodyweight Squat", in: firstRoot))
        XCTAssertTrue(has("Pull, not started yet", in: firstRoot), "postural work never becomes Pull's current movement")
        XCTAssertTrue(has("Pull ladder. Not started yet", in: firstRoot))
        XCTAssertTrue(has("Supine Floor Row, Coming up", in: firstRoot), "Pull's ladder is always the horizontal chain")
        XCTAssertFalse(has("Superman Hold", in: firstRoot), "the postural chain is not on the Pull ladder or journey")
        XCTAssertTrue(has("Legs, squat side journey", in: firstRoot))
        XCTAssertFalse(has("Pull journey", in: firstRoot), "no Pull journey without horizontal work")

        // A later appearance (a new view over the same AppState): the note is gone, the climb card stays.
        for look in Look.allCases {
            let (root, _) = await render(ProgressTabView(viewModel: viewModel).environment(appState), look: look, height: 9000)
            XCTAssertFalse(has("Your foundations are now", in: root), "\(look): the note does not return")
            XCTAssertTrue(has("Your climb to Strength", in: root))
        }

        // The large-type render with the note up, to check the note itself at accessibility sizes.
        let noteAgain = makeAppState(existingInstall: true, suite: "FoundationsEvidence.midClimbLarge")
        let (largeRoot, largeImage) = await render(
            ProgressTabView(viewModel: viewModel).environment(noteAgain), look: .large, height: 16000,
            until: { !noteAgain.shouldShowFoundationsUpdateNote }
        )
        XCTAssertTrue(has("Your foundations are now Push, Pull, Legs, and Core", in: largeRoot))
        try EvidenceOutput.write(largeImage, named: "04-mid-climb-note-large.png", for: story)
        let darkAgain = makeAppState(existingInstall: true, suite: "FoundationsEvidence.midClimbDark")
        let (_, darkImage) = await render(
            ProgressTabView(viewModel: viewModel).environment(darkAgain), look: .dark, height: 9000,
            until: { !darkAgain.shouldShowFoundationsUpdateNote }
        )
        try EvidenceOutput.write(darkImage, named: "05-mid-climb-note-dark.png", for: story)
    }

    // MARK: - Strength user

    func testStrengthUserKeepsTheirPhaseWithNoClimbCardOrNote() async throws {
        let viewModel = makeViewModel(logs: strengthLogs, phase: .strength, premium: true)
        await viewModel.load()
        let appState = makeAppState(existingInstall: true, suite: "FoundationsEvidence.strength")

        // The real evaluator, asked directly about this history, would not clear Pull...
        let evaluated = try XCTUnwrap(viewModel.phaseProgress)
        XCTAssertFalse(evaluated.foundations[1].isCleared)
        XCTAssertFalse(evaluated.hasEarnedStrength)
        // ...but the persisted phase is what the tab reads, and it is never revoked.
        XCTAssertEqual(viewModel.phase, .strength)

        for look in Look.allCases {
            let (root, image) = await render(ProgressTabView(viewModel: viewModel).environment(appState), look: look, height: 9000)
            XCTAssertFalse(has("Your climb to Strength", in: root), "an earned Strength user has no climb card")
            XCTAssertFalse(has("Your foundations are now", in: root))
            XCTAssertTrue(has("Assisted One-Arm Push-Up, You're here", in: root), "\(look): \(labels(root))")
            XCTAssertTrue(has("One-Arm Push-Up, Strength skill - unlocked", in: root), "the summit reads unlocked, not locked")
            XCTAssertTrue(has("Pull ladder. Not started yet", in: root), "postural-only Pull has not started its horizontal ladder")
            try EvidenceOutput.write(image, named: "06-strength-\(look.rawValue).png", for: story)
        }
    }

    // MARK: - Graduation reveal

    func testGraduationRevealNamesLaddersThatHaveAStrengthTop() async throws {
        for look in Look.allCases {
            let (root, image) = await render(StrengthGraduationRevealView(onDismiss: {}), look: look, height: look == .large ? 2600 : 852)
            let spoken = AccessibilityTree.spokenStrings(in: root).joined(separator: " ").lowercased()
            XCTAssertTrue(spoken.contains("push, legs, and core ladders"), "\(look): \(spoken)")
            XCTAssertFalse(spoken.contains("top of each foundation"), "no copy promises a Strength top on every foundation")
            XCTAssertFalse(spoken.contains("skill at the top"), spoken)
            try EvidenceOutput.write(image, named: "07-graduation-\(look.rawValue).png", for: story)
        }
    }
}
