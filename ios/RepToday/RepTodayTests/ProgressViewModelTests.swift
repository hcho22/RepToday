import XCTest
import SwiftUI
import UIKit
@testable import RepToday

/// Tests the Progress tab view model (US-M01).
///
/// The Progress tab reads the real `WorkoutLog` history and the real forgiving Consistency Score and
/// derives three surfaces: the headline score with its earned `longestChain`, the score trend over
/// time, and the set of completed days for the calendar. These tests verify each surface is populated
/// from real history, an empty history is a valid encouraging state (not an error), and no-user
/// degrades gracefully.
final class ProgressViewModelTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    private func week(weeksAgo: Int, count: Int) -> [WorkoutLog] {
        (0..<count).map { i in
            WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: date(weeksAgo: weeksAgo, dayOffset: i),
                requestedMinutes: 15, durationMinutes: 15,
                wasReturn: false, shape: .singleFocus, focusPillar: .strength,
                perceivedDifficulty: nil, exercises: []
            )
        }
    }

    private func makeViewModel(user: User?, logs: [WorkoutLog], premium: Bool = false) -> ProgressViewModel {
        let subscription = Subscription(
            tier: premium ? .premium : .free,
            provider: .apple,
            expiresAt: nil,
            trialEndsAt: nil
        )
        return ProgressViewModel(
            userService: MockUserService(user: user),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
    }

    private func onboardedUser() -> User { MockPersistence.sampleUser }

    // MARK: - Populated history

    /// Three weeks of logged sessions populate the score, the trend, and the calendar days.
    func testLoadPopulatesAllSurfacesFromHistory() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertTrue(vm.hasHistory)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.consistency)
        XCTAssertEqual(vm.consistency?.totalWorkoutsCompleted, 9)
        // Nine sessions on nine distinct days -> nine marked days.
        XCTAssertEqual(vm.completedDays.count, 9)
        // Three active weeks -> a three-point trajectory.
        XCTAssertEqual(vm.trend.count, 3)
    }

    /// `longestChain` is surfaced as earned pride: a sustained on-goal run shows a positive number.
    func testLongestChainSurfacedAsPositiveAchievement() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertEqual(vm.consistency?.longestChain, 3)
    }

    /// The completed days are start-of-day normalized, so a session marks exactly its calendar day.
    func testCompletedDaysAreStartOfDayNormalized() async {
        let logs = week(weeksAgo: 0, count: 1)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        let day = vm.completedDays.first
        XCTAssertNotNil(day)
        XCTAssertEqual(day, calendar.startOfDay(for: logs[0].completedAt))
    }

    /// The headline score matches the newest trend point, so the card and chart agree.
    func testHeadlineScoreMatchesNewestTrendPoint() async {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 2) + week(weeksAgo: 2, count: 3)
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertEqual(vm.consistency!.score, vm.trend.last!.score, accuracy: 0.0001)
    }

    // MARK: - Empty history

    /// A fresh onboarded user with no logs is a valid, encouraging empty state - not an error.
    func testEmptyHistoryIsNotAnError() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [])

        await vm.load()

        XCTAssertFalse(vm.hasHistory)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.trend.isEmpty)
        XCTAssertTrue(vm.completedDays.isEmpty)
    }

    // MARK: - No user

    /// With no profile, the view model surfaces a message and touches no history.
    func testNoUserSurfacesMessage() async {
        let vm = makeViewModel(user: nil, logs: [])

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.hasHistory)
    }

    // MARK: - Refresh

    /// Loading twice refreshes rather than duplicating, so returning to the tab reflects new history.
    func testReloadRefreshes() async {
        let vm = makeViewModel(user: onboardedUser(), logs: week(weeksAgo: 0, count: 2))
        await vm.load()
        XCTAssertEqual(vm.completedDays.count, 2)

        await vm.load()
        XCTAssertEqual(vm.completedDays.count, 2)
    }

    // MARK: - US-M02: analytics + premium gating

    /// A log carrying a worked strength push so the analytics layer has real content to summarize.
    private func pushLog(weeksAgo: Int, dayOffset: Int = 0, reps: Int = 12) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 15, durationMinutes: 12, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: .justRight,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: "push_knee", pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: reps, durationSeconds: nil)], skipped: false
                )
            ]
        )
    }

    /// `load` computes the legibility layer (US-M02) from real history: pillar balance, chain
    /// position for the trained pattern, and personal bests.
    func testLoadPopulatesAnalyticsFromHistory() async {
        let logs = [pushLog(weeksAgo: 0), pushLog(weeksAgo: 1, reps: 15)]
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        let analytics = vm.analytics
        XCTAssertNotNil(analytics)
        // All the training was push (strength), so strength owns the whole pillar balance.
        let strength = analytics?.pillarBalance.first { $0.pillar == .strength }
        XCTAssertEqual(strength?.fraction ?? 0, 1.0, accuracy: 0.0001)
        // The push foundation reports the worked movement; the untrained ones are "not started".
        let push = analytics?.chainPositions.first { $0.pattern == .push }
        XCTAssertEqual(push?.currentExercise?.id, "push_knee")
        let squat = analytics?.chainPositions.first { $0.pattern == .squat }
        XCTAssertEqual(squat?.hasStarted, false)
        // The best single set is the 15-rep set.
        XCTAssertEqual(analytics?.personalBests.bestReps?.value, 15)
    }

    /// A free user's entitlement leaves the deep layer gated (`isPremium == false`); the free
    /// analytics surfaces are still computed.
    func testFreeUserIsNotPremiumButStillGetsBasicAnalytics() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [pushLog(weeksAgo: 0)], premium: false)

        await vm.load()

        XCTAssertFalse(vm.isPremium)
        XCTAssertNotNil(vm.analytics)
    }

    /// A premium user's entitlement unlocks the deep layer (`isPremium == true`).
    func testPremiumUserUnlocksDeepLayer() async {
        let vm = makeViewModel(user: onboardedUser(), logs: [pushLog(weeksAgo: 0)], premium: true)

        await vm.load()

        XCTAssertTrue(vm.isPremium)
        XCTAssertNotNil(vm.analytics?.deep)
    }

    // MARK: - US-SP04: phase-progress ("the visible climb")

    /// A log clearing the entry tier of `exerciseId` in the real catalog - three sets each meeting
    /// `value`.
    private func clearingLog(exerciseId: String, pattern: MovementPattern, isHold: Bool, value: Int) -> WorkoutLog {
        let sets = (0..<3).map { _ in
            CompletedSet(reps: isHold ? nil : value, durationSeconds: isHold ? value : nil)
        }
        return WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: date(weeksAgo: 0, dayOffset: 1),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                               movementPattern: pattern, completedSets: sets, skipped: false)
            ]
        )
    }

    /// `load` computes the phase-progress signals from the same `PhaseEvaluator` logic that gates the
    /// phase, over the same full history: five sustained weeks with push+squat cleared surfaces five
    /// of eight weeks and two of four foundations - and, crucially, agrees with the gate that Strength
    /// is not yet earned.
    func testLoadPopulatesPhaseProgressMatchingTheGate() async {
        var logs = (0..<5).flatMap { week(weeksAgo: $0, count: 3) }
        logs.append(clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15))
        logs.append(clearingLog(exerciseId: "squat_wall_sit", pattern: .squat, isHold: true, value: 45))
        let vm = makeViewModel(user: onboardedUser(), logs: logs)

        await vm.load()

        XCTAssertEqual(vm.phase, .discipline)
        let progress = vm.phaseProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.weeksSustained, 5)
        XCTAssertEqual(progress?.clearedFoundationCount, 2)
        XCTAssertEqual(progress?.foundations.map(\.isCleared), [true, true, false, false])
        XCTAssertEqual(progress?.hasEarnedStrength, false, "the surface must agree with the gate: not earned")

        // And the gate itself, over the same history, resolves to Discipline - no disagreement.
        let gate = try? await PhaseEvaluatorService(
            exerciseService: try! MockExerciseService(), now: { self.asOf }, calendar: calendar
        ).phase(for: onboardedUser(), recentLogs: logs)
        XCTAssertEqual(gate, .discipline)
    }
}

// MARK: - US-M02 rendered-UI evidence

/// Hosts the actual `ProgressTabView` surface and gates it two ways.
///
/// It **renders** the US-M02 cards to PNGs so they can be reviewed as an end user would see them: the
/// free legibility layer (pillar balance, chain position, personal bests) with the non-nagging premium
/// upsell in place of the deep layer, the premium variant with the deep analytics section unlocked, and
/// the fresh-user empty state. The mock container ships empty history (US-M01), so these states cannot
/// be reached by tapping the running app - the snapshots stand in for that live capture.
///
/// It also **reads the hosted surface's live accessibility tree**, in two tests that write no PNG at
/// all: they are the regression gate for the calendar resolving "today" against the injected clock
/// rather than the wall clock, and for the weekday header being hidden from VoiceOver rather than read
/// as seven loose letters. Both need the same hosted, settled production view the renders need, which is
/// why they live here rather than beside the view-model tests above.
///
/// The renders land where `EvidenceOutput` decides - a per-run temporary directory by default, so a
/// plain `test` leaves the worktree clean, and the committed `artifacts/reports/us-m02/` only when asked
/// for explicitly. That destination used to be an absolute path baked in from one machine's tooling run,
/// which meant every run of the default scheme wrote into a directory belonging to a session that no
/// longer exists - on any other machine, into a path that had never existed at all.
@MainActor
final class ProgressTabSnapshotTests: XCTestCase {

    /// The window a hosted surface lives in while it is captured or read.
    private var renderWindow: UIWindow?

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A varied, realistic six-week history: all three pillars, the four foundational patterns, a
    /// rep best and a hold best, and a spread of perceived-difficulty ratings so every US-M02 card
    /// (including the premium difficulty mix) has real content to render.
    private func sampleLogs() -> [WorkoutLog] {
        struct Spec {
            let exerciseId: String, pillar: Pillar, pattern: MovementPattern
            let reps: Int?, seconds: Int?, difficulty: PerceivedDifficulty
        }
        let specs: [Spec] = [
            Spec(exerciseId: "push_knee", pillar: .strength, pattern: .push, reps: 14, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "squat_bodyweight", pillar: .strength, pattern: .squat, reps: 22, seconds: nil, difficulty: .tooEasy),
            Spec(exerciseId: "hinge_glute_bridge", pillar: .strength, pattern: .hinge, reps: 18, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "core_forearm_plank", pillar: .strength, pattern: .core, reps: nil, seconds: 55, difficulty: .tooHard),
            Spec(exerciseId: "mobility_cat_cow", pillar: .mobility, pattern: .mobility, reps: 12, seconds: nil, difficulty: .justRight),
            Spec(exerciseId: "primal_bear_crawl", pillar: .primal, pattern: .locomotion, reps: 10, seconds: nil, difficulty: .justRight),
        ]
        return (0..<18).map { offset in
            let spec = specs[offset % specs.count]
            let set = CompletedSet(reps: spec.reps, durationSeconds: spec.seconds)
            let logged = LoggedExercise(
                id: UUID(), exerciseId: spec.exerciseId, pillar: spec.pillar,
                movementPattern: spec.pattern,
                completedSets: [set, set], skipped: false
            )
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: date(daysAgo: offset * 2),
                requestedMinutes: 20, durationMinutes: 15 + offset % 6, wasReturn: false,
                shape: .blend, focusPillar: spec.pillar, perceivedDifficulty: spec.difficulty,
                exercises: [logged]
            )
        }
    }

    private func makeViewModel(logs: [WorkoutLog], premium: Bool) -> ProgressViewModel {
        let subscription = Subscription(
            tier: premium ? .premium : .free, provider: .apple, expiresAt: nil, trialEndsAt: nil
        )
        return ProgressViewModel(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try! MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: subscription),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: self.calendar),
            now: { self.asOf },
            calendar: self.calendar
        )
    }

    private func snapshot(viewModel: ProgressViewModel, tall: Bool, fileName: String) async throws {
        // Pre-load so the populated content path renders when the view is hosted.
        await viewModel.load()
        try render(viewModel: viewModel, tall: tall, fileName: fileName)
    }

    /// The scratch height a hosted `ProgressTabView` is given so the whole of its `ScrollView` lays out
    /// at once rather than a screenful at a time. Comfortably taller than the content on purpose: the
    /// pixel capture is cropped back to what the content measures (`capturedHeight`), so headroom costs
    /// nothing while running out of it would clip the bottom of the surface - which is why the measure
    /// throws rather than silently returning a truncated height.
    private enum HostHeight {
        static let populated: CGFloat = 3200
        static let empty: CGFloat = 900
    }

    /// Hosts the production `ProgressTabView` tall enough for the whole scrolling surface to lay out and
    /// confirms the content fit inside that height. It is the one hosting policy both the pixel captures
    /// and the accessibility reads run through, so neither can drift onto its own magic height or lose
    /// the outgrew-host guard the other has: a surface grown past its host height fails loudly on both
    /// paths rather than being captured cropped or read clipped.
    private func hostedProgressTab(
        _ viewModel: ProgressViewModel, tall: Bool
    ) throws -> (host: UIHostingController<ProgressTabView>, contentSize: CGSize) {
        let layoutSize = CGSize(width: 393, height: tall ? HostHeight.populated : HostHeight.empty)
        let (host, window) = HostedSurface.host(ProgressTabView(viewModel: viewModel), size: layoutSize)
        renderWindow = window
        let contentHeight = try capturedHeight(of: host.view, laidOutIn: layoutSize)
        return (host, CGSize(width: layoutSize.width, height: contentHeight))
    }

    /// Hosting, measurement and capture stay in one synchronous body so that the height and the render
    /// read the very same laid-out hierarchy: an intervening suspension would let the surface change
    /// between the height being taken and the pixels being composited against it. Everything that has
    /// to be awaited (`viewModel.load()`) has already happened by the time this is called.
    private func render(viewModel: ProgressViewModel, tall: Bool, fileName: String) throws {
        let (host, size) = try hostedProgressTab(viewModel, tall: tall)

        // Capturing (which pins the render scale) is `HostedSurface`'s, and encoding, the did-it-draw
        // check and the write are all `EvidenceOutput`'s, so a capture that failed any precondition
        // never reaches disk to overwrite a committed baseline.
        let image = HostedSurface.capture(host.view, size: size)
        try EvidenceOutput.write(image, named: fileName, for: EvidenceOutput.Story.progressAnalytics)
    }

    /// The height the capture is cropped to: what the content actually laid out to, rather than the
    /// taller scratch height it had to be hosted in.
    ///
    /// A baseline is committed so a human can eyeball it and a layout change shows up as a diff, and a
    /// long blank tail undermines both - it costs bytes and reads as a layout bug rather than as a
    /// capture artifact. `layer.render(in:)` composites from the layer tree's origin, so a shorter
    /// canvas simply drops that empty tail: nothing is re-laid out, and nothing above it moves.
    ///
    /// Measured off the scroll view's own content rather than `systemLayoutSizeFitting`, because the
    /// hosted view is a `ScrollView` whose fitting size is the viewport it was given, not the content
    /// inside it. Falls back to the full hosted height if the surface is not scrolling (or measures to
    /// nothing), so the capture can only ever lose empty space, never content.
    ///
    /// Throws rather than asserting when the content outgrew its host: an assertion that let the caller
    /// carry on would fail the run *and* write the truncated PNG, so under `REPTODAY_WRITE_EVIDENCE=1`
    /// it would overwrite the committed baseline with a known-bad image and leave a staged diff
    /// indistinguishable from a legitimate regeneration. Throwing keeps the failure loud and the
    /// baseline the run was about to corrupt untouched.
    private func capturedHeight(of root: UIView, laidOutIn layoutSize: CGSize) throws -> CGFloat {
        guard let scrollView = firstScrollView(in: root) else { return layoutSize.height }
        // Converted out of the scroll view's content coordinates, so the scroll view's own offset in
        // the hierarchy (the safe-area inset it sits below) is carried into the answer.
        let contentBottom = scrollView.convert(CGPoint(x: 0, y: scrollView.contentSize.height), to: root).y
        let bottom = contentBottom + scrollView.adjustedContentInset.bottom
        guard bottom > 0 else { return layoutSize.height }

        // Cropping may only ever remove empty space. If the content outgrew the height it was hosted
        // in, the capture would be a silently truncated baseline - the one outcome worse than the
        // dead space this crop exists to remove.
        guard ceil(bottom) <= layoutSize.height else {
            throw CaptureOutgrewHost(contentHeight: ceil(bottom), hostedHeight: layoutSize.height)
        }
        return ceil(bottom)
    }

    /// Raised instead of writing a PNG whose bottom would be cut off mid-content.
    private struct CaptureOutgrewHost: Error, CustomStringConvertible {
        let contentHeight: CGFloat
        let hostedHeight: CGFloat

        var description: String {
            "The surface laid out to \(Int(contentHeight))pt, taller than the \(Int(hostedHeight))pt it "
            + "was hosted in, so the capture would be cropped mid-content. Nothing was written - host it "
            + "taller rather than committing a truncated baseline."
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// Free tier: the three free cards render for everyone and the quiet premium upsell stands in for
    /// the deep layer.
    func testRenderFreeProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: sampleLogs(), premium: false),
                           tall: true, fileName: "progress-m02-free.png")
    }

    /// Premium tier: the same free cards plus the unlocked deep analytics section (pattern balance,
    /// weekly volume chart, difficulty mix).
    func testRenderPremiumProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: sampleLogs(), premium: true),
                           tall: true, fileName: "progress-m02-premium.png")
    }

    /// Fresh user: the encouraging empty state (no cards, never gated, never loss-framed).
    func testRenderEmptyProgressTab() async throws {
        try await snapshot(viewModel: makeViewModel(logs: [], premium: false),
                           tall: false, fileName: "progress-m02-empty.png")
    }

    // MARK: - The calendar reads the view model's clock, not the wall clock

    /// The calendar is the one surface that names a date, so it has to resolve "today" and normalize
    /// a completed day with the *same* clock and calendar the view model derived `completedDays`
    /// against. Read off the live accessibility tree of the hosted production view: the injected
    /// clock's today (Jul 8, 2026) is marked as a completed session, and a day the fixture never
    /// worked is marked as no session.
    ///
    /// Both halves fail if the view reaches for `Date()` / `Calendar.current` itself - the marker
    /// lands on whatever day the suite happens to run, and every dot silently disappears because a
    /// day normalized in one calendar is never found in a set normalized in another.
    func testCalendarMarksTheInjectedClocksTodayRatherThanTheWallClock() async throws {
        let labels = try await hostedAccessibilityLabels(for: makeViewModel(logs: sampleLogs(), premium: false))

        let today = expectedDayLabel(day: 8, suffix: ", today, session completed")
        let untouched = expectedDayLabel(day: 7, suffix: ", no session")

        XCTAssertTrue(labels.contains(today),
                      "The calendar should mark the injected clock's today as worked with \"\(today)\". Saw: \(labels.filter { $0.contains("2026") })")
        XCTAssertTrue(labels.contains(untouched),
                      "A day the fixture never worked should read as \"\(untouched)\"")
    }

    /// The weekday header is visual scaffolding for the grid below, whose cells each speak their own
    /// full date and state - so the bare initials are seven disconnected single letters in the swipe
    /// path, saying nothing the day cells do not.
    func testWeekdayHeaderIsNotSpokenAsSevenLooseLetters() async throws {
        let labels = try await hostedAccessibilityLabels(for: makeViewModel(logs: sampleLogs(), premium: false))

        // Positive anchor first: the negative assertion below is only meaningful once the calendar grid
        // is proven on screen and being read. Without this, the test passes vacuously if the card fails
        // to render, is clipped out of the hosted viewport, or the day cells stop speaking at all.
        let renderedDayCell = expectedDayLabel(day: 7, suffix: ", no session")
        XCTAssertTrue(labels.contains(renderedDayCell),
                      "The calendar grid should have rendered a day cell reading \"\(renderedDayCell)\"; without it the header assertion below is vacuous")

        let initials = Set(calendar.veryShortStandaloneWeekdaySymbols)
        XCTAssertTrue(labels.allSatisfy { !initials.contains($0) },
                      "The weekday initials should be hidden from VoiceOver. Saw: \(labels.filter { initials.contains($0) })")
    }

    /// Hosts the production `ProgressTabView` in a real key window and returns every accessibility
    /// label in traversal order - the strings VoiceOver reads as the user swipes down the screen.
    ///
    /// Hosting and reading both go through the shared seam: `hostedProgressTab` hosts at the one height
    /// the pixel captures use and fails loudly if the content outgrows it (so this path can never read a
    /// clipped screen), and `HostedSurface.host` inside it is what lets the surface settle before it is
    /// read - without that settling these assertions would report an empty or half-built screen on a
    /// loaded machine. The guard below is the backstop - an empty tree would otherwise let both tests
    /// pass on a screen that speaks nothing at all.
    private func hostedAccessibilityLabels(for viewModel: ProgressViewModel) async throws -> [String] {
        await viewModel.load()

        let (host, _) = try hostedProgressTab(viewModel, tall: true)
        let labels = AccessibilityTree.labels(in: host.view)

        renderWindow?.isHidden = true
        XCTAssertFalse(labels.isEmpty, "The hosted Progress tab exposed no accessibility tree at all")
        return labels
    }

    /// The label a day cell is expected to speak, built the way the production view builds it: the
    /// same `EEEEdMMMy` template in the injected calendar and time zone, left at `Locale.current`
    /// because the spoken date should be localized for the user. Deriving it here rather than
    /// hard-coding the en_US rendering is what keeps these tests about the *clock* the view reads
    /// rather than about the language the simulator happens to run in.
    private func expectedDayLabel(day: Int, suffix: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMy")
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: day))!
        return formatter.string(from: date) + suffix
    }
}
