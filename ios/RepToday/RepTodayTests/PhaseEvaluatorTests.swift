import XCTest
@testable import RepToday

/// Tests the deterministic `PhaseEvaluator` (US-H02): the rule that decides whether a user has
/// *earned* the Strength Phase from two independent signals - sustained consistency and cleared
/// foundational competence - and is never user-selectable.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: consistency-only stays
/// Discipline, competence-only stays Discipline, both-met promotes to Strength, and a fresh user is
/// Discipline. The library is a small self-contained fixture so the evaluator is exercised as pure
/// logic with no bundle dependency.
final class PhaseEvaluatorTests: XCTestCase {

    // MARK: - Calendar / dates

    /// A fixed Gregorian/UTC calendar with a Sunday week start, so week bucketing is deterministic
    /// (matches `ConsistencyScoreTests`).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }()

    /// A Wednesday, comfortably mid-week, so whole-week shifts stay inside their intended week.
    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    // MARK: - Library fixture

    /// A minimal library covering the four foundational patterns. Each foundational pattern has one
    /// chain with an entry tier (order 0) plus a next tier, so `AdvancementCriteria` can be cleared
    /// from a logged performance of the entry. A rep entry and a hold entry are both represented so
    /// the `isHold` branch is exercised. Mobility is present but irrelevant to competence.
    private func exercise(
        id: String,
        pattern: MovementPattern,
        pillar: Pillar,
        order: Int,
        chainId: String,
        advancementCriteria: String,
        isHold: Bool,
        progressionId: String? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: pattern,
            category: pillar == .mobility ? .mobility : .strength,
            difficulty: order + 1,
            phase: .discipline,
            equipment: [],
            isHold: isHold,
            defaultReps: isHold ? nil : 10,
            defaultDurationSeconds: isHold ? 30 : nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: chainId,
            progressionOrder: order,
            regressionId: nil,
            progressionId: progressionId,
            advancementCriteria: advancementCriteria,
            apartmentFriendly: true
        )
    }

    private lazy var library: [Exercise] = [
        // push: rep entry "3x15", plus a next tier.
        exercise(id: "push_wall", pattern: .push, pillar: .strength, order: 0, chainId: "push_h",
                 advancementCriteria: "3x15 clean reps", isHold: false, progressionId: "push_std"),
        exercise(id: "push_std", pattern: .push, pillar: .strength, order: 1, chainId: "push_h",
                 advancementCriteria: "3x12 clean reps", isHold: false),
        // squat: hold entry "3x45s", plus a next tier.
        exercise(id: "squat_wall", pattern: .squat, pillar: .strength, order: 0, chainId: "squat",
                 advancementCriteria: "3x45s hold", isHold: true, progressionId: "squat_sumo"),
        exercise(id: "squat_sumo", pattern: .squat, pillar: .strength, order: 1, chainId: "squat",
                 advancementCriteria: "3x20 clean reps", isHold: false),
        // hinge: rep entry "3x20".
        exercise(id: "hinge_bridge", pattern: .hinge, pillar: .strength, order: 0, chainId: "hinge_b",
                 advancementCriteria: "3x20 clean reps", isHold: false, progressionId: "hinge_slb"),
        exercise(id: "hinge_slb", pattern: .hinge, pillar: .strength, order: 1, chainId: "hinge_b",
                 advancementCriteria: "3x12 reps per side", isHold: false),
        // core: hold entry "3x30s".
        exercise(id: "core_plank", pattern: .core, pillar: .strength, order: 0, chainId: "core_p",
                 advancementCriteria: "3x30s hold", isHold: true, progressionId: "core_side"),
        exercise(id: "core_side", pattern: .core, pillar: .strength, order: 1, chainId: "core_p",
                 advancementCriteria: "3x30s hold per side", isHold: true),
        // mobility: not a foundational pattern; never gates competence.
        exercise(id: "mob_cat_cow", pattern: .mobility, pillar: .mobility, order: 0, chainId: "mob",
                 advancementCriteria: "3x10 reps", isHold: false),
    ]

    // MARK: - Log builders

    /// A plain show-up log (no exercises), used to build a sustained-consistency history.
    private func showUp(weeksAgo: Int, dayOffset: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 15,
            durationMinutes: 15,
            wasReturn: false,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    /// `weeklyGoal` show-up sessions per week for `weeks` weeks (weeksAgo 0..<weeks), a fully on-goal
    /// history whose Consistency Score is 100 and whose active span is `weeks`.
    private func sustainedHistory(weeks: Int, weeklyGoal: Int = 3) -> [WorkoutLog] {
        (0..<weeks).flatMap { w in
            (0..<weeklyGoal).map { showUp(weeksAgo: w, dayOffset: $0) }
        }
    }

    /// A log this week whose single logged exercise *clears* the entry tier `exerciseId` - three
    /// completed sets each meeting `value` (reps for a rep entry, seconds for a hold).
    private func clearingLog(exerciseId: String, pattern: MovementPattern, isHold: Bool, value: Int) -> WorkoutLog {
        let sets = (0..<3).map { _ in
            CompletedSet(reps: isHold ? nil : value, durationSeconds: isHold ? value : nil)
        }
        return WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(weeksAgo: 0, dayOffset: 0),
            requestedMinutes: 20,
            durationMinutes: 20,
            wasReturn: false,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: exerciseId,
                    pillar: .strength,
                    movementPattern: pattern,
                    completedSets: sets,
                    skipped: false
                )
            ]
        )
    }

    /// Logs clearing the entry tier of every foundational pattern (push/squat/hinge/core).
    private func competenceLogs() -> [WorkoutLog] {
        [
            clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15),
            clearingLog(exerciseId: "squat_wall", pattern: .squat, isHold: true, value: 45),
            clearingLog(exerciseId: "hinge_bridge", pattern: .hinge, isHold: false, value: 20),
            clearingLog(exerciseId: "core_plank", pattern: .core, isHold: true, value: 30),
        ]
    }

    private func evaluate(_ logs: [WorkoutLog], weeklyGoal: Int = 3) -> Phase {
        PhaseEvaluator.evaluate(logs: logs, weeklyGoal: weeklyGoal, library: library, asOf: asOf, calendar: calendar)
    }

    private func progress(_ logs: [WorkoutLog], weeklyGoal: Int = 3) -> PhaseProgress {
        PhaseEvaluator.progress(logs: logs, weeklyGoal: weeklyGoal, library: library, asOf: asOf, calendar: calendar)
    }

    // MARK: - Fresh user

    func testFreshUserIsDiscipline() {
        XCTAssertEqual(evaluate([]), .discipline, "a user with no history has earned nothing yet")
    }

    // MARK: - Consistency-only stays Discipline

    func testConsistencyWithoutCompetenceStaysDiscipline() {
        // Eight fully on-goal weeks (Consistency Score 100, span 8) but no cleared entry tier.
        let logs = sustainedHistory(weeks: 8)
        XCTAssertEqual(evaluate(logs), .discipline, "consistency alone does not earn Strength")
    }

    /// PRD validation: 8 weeks at >= 80% but the entry tiers not cleared -> Discipline.
    func testEightStrongWeeksWithoutCompetenceIsDiscipline() {
        // Eight weeks, mostly on-goal (one week short a session) so adherence is >= 80% but < 100,
        // and no clearing performance anywhere.
        var logs = sustainedHistory(weeks: 8)
        // Drop one session from the oldest week to make it a realistic >= 80% (not a perfect 100).
        if let idx = logs.firstIndex(where: { calendar.dateComponents([.weekOfYear], from: $0.completedAt, to: asOf).weekOfYear == 7 }) {
            logs.remove(at: idx)
        }
        XCTAssertEqual(evaluate(logs), .discipline, "sustained consistency without cleared foundations stays Discipline")
    }

    // MARK: - Competence-only stays Discipline

    func testCompetenceWithoutConsistencyStaysDiscipline() {
        // All four entry tiers cleared this week, but only ~1 week of history: consistency is not
        // sustained over the window.
        let logs = competenceLogs()
        XCTAssertEqual(evaluate(logs), .discipline, "competence alone does not earn Strength")
    }

    /// A single intense week that clears every foundation *and* scores high still fails the
    /// sustained-over-8-weeks requirement, so a hot streak cannot earn Strength.
    func testHotSingleWeekDoesNotEarnStrength() {
        // Three show-ups this week (score 100 because the window starts at first activity) plus all
        // four entries cleared - but the active span is a single week.
        let logs = sustainedHistory(weeks: 1) + competenceLogs()
        XCTAssertEqual(evaluate(logs), .discipline, "one strong week is not sustained consistency")
    }

    // MARK: - Both met promotes

    func testBothSignalsPromoteToStrength() {
        let logs = sustainedHistory(weeks: 8) + competenceLogs()
        XCTAssertEqual(evaluate(logs), .strength, "sustained consistency plus cleared foundations earns Strength")
    }

    // MARK: - Partial competence is not enough

    func testThreeOfFourFoundationsIsStillDiscipline() {
        // Clear push/squat/hinge but not core: competence requires all four.
        let partial = [
            clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15),
            clearingLog(exerciseId: "squat_wall", pattern: .squat, isHold: true, value: 45),
            clearingLog(exerciseId: "hinge_bridge", pattern: .hinge, isHold: false, value: 20),
        ]
        let logs = sustainedHistory(weeks: 8) + partial
        XCTAssertEqual(evaluate(logs), .discipline, "missing one foundational pattern keeps the user in Discipline")
    }

    /// An entry logged but not *cleared* (fell short of the criteria) does not count as competence.
    func testUnclearedEntryDoesNotCountAsCompetence() {
        // Push short of 3x15 (only 10 reps), the other three fully cleared.
        let short = clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 10)
        let logs = sustainedHistory(weeks: 8) + [short]
            + [
                clearingLog(exerciseId: "squat_wall", pattern: .squat, isHold: true, value: 45),
                clearingLog(exerciseId: "hinge_bridge", pattern: .hinge, isHold: false, value: 20),
                clearingLog(exerciseId: "core_plank", pattern: .core, isHold: true, value: 30),
            ]
        XCTAssertEqual(evaluate(logs), .discipline, "a logged-but-not-cleared entry is not competence")
    }

    /// A *skipped* clearing performance never counts, mirroring Step 5's non-skipped rule.
    func testSkippedEntryDoesNotCountAsCompetence() {
        var logs = sustainedHistory(weeks: 8) + competenceLogs()
        // Mark the push clearing exercise skipped.
        if let idx = logs.firstIndex(where: { $0.exercises.contains { $0.exerciseId == "push_wall" } }) {
            logs[idx].exercises[0].skipped = true
        }
        XCTAssertEqual(evaluate(logs), .discipline, "a skipped clearing set does not earn competence")
    }

    // MARK: - Determinism

    func testDeterministic() {
        let logs = sustainedHistory(weeks: 8) + competenceLogs()
        XCTAssertEqual(evaluate(logs), evaluate(logs))
    }

    // MARK: - Component progress (US-SP04)

    /// The gate is *derived from* `progress(...)`: `evaluate == .strength` iff
    /// `progress().hasEarnedStrength`. This is the whole reason the surface can't disagree with the
    /// gate, so it is asserted across every scenario the phase decision is tested on above.
    func testProgressEarnedFlagMatchesGateAcrossScenarios() {
        let scenarios: [(name: String, logs: [WorkoutLog])] = [
            ("fresh", []),
            ("consistency only", sustainedHistory(weeks: 8)),
            ("competence only", competenceLogs()),
            ("hot single week", sustainedHistory(weeks: 1) + competenceLogs()),
            ("both met", sustainedHistory(weeks: 8) + competenceLogs()),
            ("three of four", sustainedHistory(weeks: 8) + [
                clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15),
                clearingLog(exerciseId: "squat_wall", pattern: .squat, isHold: true, value: 45),
                clearingLog(exerciseId: "hinge_bridge", pattern: .hinge, isHold: false, value: 20),
            ]),
        ]
        for scenario in scenarios {
            let earned = progress(scenario.logs).hasEarnedStrength
            let gated = evaluate(scenario.logs) == .strength
            XCTAssertEqual(earned, gated, "progress.hasEarnedStrength must equal the gate for: \(scenario.name)")
        }
    }

    /// The PRD validation shape: 5 sustained weeks with push+squat cleared (hinge/core not) surfaces
    /// exactly "5 of 8 weeks" and exactly 2 of 4 foundations cleared - and is *not* earned, matching
    /// what the gate would decide.
    func testProgressReportsFiveOfEightWeeksAndTwoOfFourFoundations() {
        let logs = sustainedHistory(weeks: 5) + [
            clearingLog(exerciseId: "push_wall", pattern: .push, isHold: false, value: 15),
            clearingLog(exerciseId: "squat_wall", pattern: .squat, isHold: true, value: 45),
        ]
        let p = progress(logs)

        XCTAssertEqual(p.weeksSustained, 5, "five active weeks")
        XCTAssertEqual(p.requiredWeeks, 8, "the window is eight weeks")
        XCTAssertEqual(p.clearedFoundationCount, 2, "push and squat cleared, hinge and core not")
        XCTAssertEqual(p.foundationCount, 4)

        // Per-foundation flags, in evaluator order (push / squat / hinge / core).
        XCTAssertEqual(p.foundations.map(\.pattern), [.push, .squat, .hinge, .core])
        XCTAssertEqual(p.foundations.map(\.isCleared), [true, true, false, false])

        XCTAssertFalse(p.hasFoundationalCompetence, "two of four is not full competence")
        XCTAssertFalse(p.hasEarnedStrength, "not earned - and the gate agrees")
        XCTAssertEqual(evaluate(logs), .discipline)
    }

    /// `weeksSustained` never over-reports past the window even when the user has been active longer.
    func testWeeksSustainedCapsAtRequiredWindow() {
        let logs = sustainedHistory(weeks: 12)
        XCTAssertEqual(progress(logs).weeksSustained, 8, "twelve active weeks still displays as the eight-week window")
    }

    /// Both halves of the consistency signal are exposed and combine exactly as the gate's does:
    /// sustained requires the full span *and* the score at/above the bar.
    func testConsistencyComponentsMatchGate() {
        // Eight on-goal weeks: span 8, score 100 -> both halves hold.
        let strong = progress(sustainedHistory(weeks: 8))
        XCTAssertEqual(strong.weeksSustained, 8)
        XCTAssertTrue(strong.meetsScoreThreshold)
        XCTAssertTrue(strong.hasSustainedConsistency)

        // One week: span short of the window, so not sustained regardless of a perfect score.
        let short = progress(sustainedHistory(weeks: 1))
        XCTAssertFalse(short.hasSustainedConsistency, "a single week is not sustained over the window")
    }
}
