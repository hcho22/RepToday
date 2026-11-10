import XCTest
@testable import RepToday

/// Tests the deterministic `PhaseEvaluator` (US-H02): the rule that decides whether a user has
/// *earned* the Strength Phase from two independent signals - sustained consistency and cleared
/// foundational competence - and is never user-selectable. The foundations are Push, Pull, Legs and
/// Core (ADR-0006): Legs needs both its Squat and Hinge sides, and Pull counts only its horizontal chain.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: consistency-only stays
/// Discipline, competence-only stays Discipline, both-met promotes to Strength, and a fresh user is
/// Discipline. An entry rung clears the way the rep grammar clears any rung (US-TD03): four sets at the
/// top of the user's range, at earned reps, in a session that counts toward advancement. The library
/// is a small self-contained fixture so the evaluator is exercised as pure logic with no bundle
/// dependency.
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

    /// A minimal library covering the foundation lines. Each has a chain with an entry tier (order 0)
    /// plus a next tier, so the entry can be cleared from a logged performance of it. A rep entry and a
    /// hold entry are both represented so the `isHold` branch is exercised.
    /// Squat and hinge each carry a second chain (lunge, hip) that also counts for Legs; pull carries
    /// its counting horizontal chain and the postural chain that never counts. Mobility is present but
    /// irrelevant to competence.
    private func exercise(
        id: String,
        pattern: MovementPattern,
        pillar: Pillar,
        order: Int,
        chainId: String,
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
            advancementCriteria: isHold ? "4 clean holds at the top of your hold range" : "4 clean sets at the top of your rep range",
            apartmentFriendly: true
        )
    }

    private lazy var library: [Exercise] = [
        // push: a rep entry, plus a next tier.
        exercise(id: "push_wall", pattern: .push, pillar: .strength, order: 0, chainId: "push_h", isHold: false, progressionId: "push_std"),
        exercise(id: "push_std", pattern: .push, pillar: .strength, order: 1, chainId: "push_h", isHold: false),
        // squat: a hold entry, plus a next tier.
        exercise(id: "squat_wall", pattern: .squat, pillar: .strength, order: 0, chainId: "squat", isHold: true, progressionId: "squat_sumo"),
        exercise(id: "squat_sumo", pattern: .squat, pillar: .strength, order: 1, chainId: "squat", isHold: false),
        // squat's second chain: a lunge entry also clears the squat side of Legs.
        exercise(id: "lunge_reverse", pattern: .squat, pillar: .strength, order: 0, chainId: "lunge", isHold: false, progressionId: "lunge_split"),
        exercise(id: "lunge_split", pattern: .squat, pillar: .strength, order: 1, chainId: "lunge", isHold: false),
        // hinge: a rep entry.
        exercise(id: "hinge_bridge", pattern: .hinge, pillar: .strength, order: 0, chainId: "hinge_b", isHold: false, progressionId: "hinge_slb"),
        exercise(id: "hinge_slb", pattern: .hinge, pillar: .strength, order: 1, chainId: "hinge_b", isHold: false),
        // hinge's second chain: a good-morning entry also clears the hinge side of Legs.
        exercise(id: "hinge_good_morning", pattern: .hinge, pillar: .strength, order: 0, chainId: "hinge_hip", isHold: false, progressionId: "hinge_sl_rdl"),
        exercise(id: "hinge_sl_rdl", pattern: .hinge, pillar: .strength, order: 1, chainId: "hinge_hip", isHold: false),
        // pull: the horizontal chain counts; the postural chain never does.
        exercise(id: "pull_scap", pattern: .pull, pillar: .strength, order: 0, chainId: "pull_horizontal", isHold: false, progressionId: "pull_row"),
        exercise(id: "pull_row", pattern: .pull, pillar: .strength, order: 1, chainId: "pull_horizontal", isHold: false),
        exercise(id: "pull_superman", pattern: .pull, pillar: .strength, order: 0, chainId: "pull_postural", isHold: true, progressionId: "pull_ytw"),
        exercise(id: "pull_ytw", pattern: .pull, pillar: .strength, order: 1, chainId: "pull_postural", isHold: false),
        // core: a hold entry.
        exercise(id: "core_plank", pattern: .core, pillar: .strength, order: 0, chainId: "core_p", isHold: true, progressionId: "core_side"),
        exercise(id: "core_side", pattern: .core, pillar: .strength, order: 1, chainId: "core_p", isHold: true),
        // mobility: not a foundational pattern; never gates competence.
        exercise(id: "mob_cat_cow", pattern: .mobility, pillar: .mobility, order: 0, chainId: "mob", isHold: false),
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

    /// A log this week with a single main station of `exerciseId`: `sets` sets of `value` (reps, or
    /// seconds for a hold), prescribed at `earned` (the value itself when not given).
    private func workedLog(_ exerciseId: String, value: Int, earned: Int? = nil, sets: Int = 4, role: StationRole? = .main) -> WorkoutLog {
        let exercise = library.first { $0.id == exerciseId }!
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
                    movementPattern: exercise.movementPattern,
                    completedSets: Array(
                        repeating: exercise.isHold ? CompletedSet(reps: nil, durationSeconds: value) : CompletedSet(reps: value, durationSeconds: nil),
                        count: sets
                    ),
                    skipped: false,
                    role: role,
                    earnedReps: exercise.isHold || role == nil ? nil : (earned ?? value),
                    earnedDurationSeconds: exercise.isHold && role != nil ? (earned ?? value) : nil
                )
            ]
        )
    }

    /// The top of `exerciseId`'s earned range for a user at `level`.
    private func top(_ exerciseId: String, level: FitnessLevel = .beginner) -> Int {
        RepGrammar.earnedRange(for: library.first { $0.id == exerciseId }!, level: level).upperBound
    }

    /// A log this week that *clears* the entry tier `exerciseId` for a user at `level`: four sets at the
    /// top of the range, at earned reps that had reached it.
    private func clearingLog(_ exerciseId: String, level: FitnessLevel = .beginner) -> WorkoutLog {
        workedLog(exerciseId, value: top(exerciseId, level: level))
    }

    /// Logs clearing every foundation: push, pull (horizontal), both sides of legs, and core.
    private func competenceLogs() -> [WorkoutLog] {
        [
            clearingLog("push_wall"),
            clearingLog("pull_scap"),
            clearingLog("squat_wall"),
            clearingLog("hinge_bridge"),
            clearingLog("core_plank"),
        ]
    }

    private func evaluate(_ logs: [WorkoutLog], weeklyGoal: Int = 3, level: FitnessLevel = .beginner) -> Phase {
        PhaseEvaluator.evaluate(logs: logs, weeklyGoal: weeklyGoal, library: library, level: level, asOf: asOf, calendar: calendar)
    }

    private func progress(_ logs: [WorkoutLog], weeklyGoal: Int = 3, level: FitnessLevel = .beginner) -> PhaseProgress {
        PhaseEvaluator.progress(logs: logs, weeklyGoal: weeklyGoal, library: library, level: level, asOf: asOf, calendar: calendar)
    }

    private func isPushCleared(_ logs: [WorkoutLog], level: FitnessLevel = .beginner) -> Bool? {
        progress(logs, level: level).foundations.first { $0.foundation == .push }?.isCleared
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
        // Clear push/pull/legs but not core: competence requires all four.
        let partial = [
            clearingLog("push_wall"),
            clearingLog("pull_scap"),
            clearingLog("squat_wall"),
            clearingLog("hinge_bridge"),
        ]
        let logs = sustainedHistory(weeks: 8) + partial
        XCTAssertEqual(evaluate(logs), .discipline, "missing one foundation keeps the user in Discipline")
    }

    // MARK: - Legs needs both sides (ADR-0006)

    /// Every foundation cleared *except* one line of Legs stays Discipline: quads alone (or hinge
    /// alone) cannot stand in for the whole foundation.
    func testLegsNeedsBothItsSquatAndHingeSides() throws {
        let everythingElse = [
            clearingLog("push_wall"),
            clearingLog("pull_scap"),
            clearingLog("core_plank"),
        ]
        let squatOnly = sustainedHistory(weeks: 8) + everythingElse
            + [clearingLog("squat_wall")]
        let hingeOnly = sustainedHistory(weeks: 8) + everythingElse
            + [clearingLog("hinge_bridge")]
        let both = squatOnly + [clearingLog("hinge_bridge")]

        XCTAssertEqual(evaluate(squatOnly), .discipline, "the squat side alone does not clear Legs")
        XCTAssertEqual(evaluate(hingeOnly), .discipline, "the hinge side alone does not clear Legs")
        XCTAssertEqual(evaluate(both), .strength, "both sides clear Legs and, with the rest, earn Strength")

        let legs = try XCTUnwrap(progress(squatOnly).foundations.first { $0.foundation == .legs })
        XCTAssertEqual(legs.lines.map(\.isCleared), [true, false])
        XCTAssertEqual(legs.clearedLineCount, 1)
        XCTAssertEqual(legs.lineCount, 2)
        XCTAssertFalse(legs.isCleared, "Legs reads cleared only when both sides are")
    }

    /// Either chain of a side counts: a lunge entry clears the squat side and a hip-hinge entry clears
    /// the hinge side, exactly as one chain of push always sufficed.
    func testEitherChainOfALegsSideClearsIt() {
        let logs = sustainedHistory(weeks: 8) + [
            clearingLog("push_wall"),
            clearingLog("pull_scap"),
            clearingLog("lunge_reverse"),
            clearingLog("hinge_good_morning"),
            clearingLog("core_plank"),
        ]
        XCTAssertEqual(evaluate(logs), .strength)
    }

    // MARK: - Pull counts only the horizontal chain (ADR-0006)

    /// The postural chain stays in sessions but never clears Pull, however well it is performed.
    func testPosturalPullNeverClearsPull() {
        let logs = sustainedHistory(weeks: 8) + competenceLogs().filter { $0.exercises.first?.exerciseId != "pull_scap" }
            + [clearingLog("pull_superman")]

        XCTAssertEqual(evaluate(logs), .discipline, "a cleared postural entry does not clear Pull")
        let pull = progress(logs).foundations.first { $0.foundation == .pull }
        XCTAssertEqual(pull?.isCleared, false)
    }

    func testHorizontalPullClearsPull() {
        let logs = sustainedHistory(weeks: 8) + competenceLogs()
        let pull = progress(logs).foundations.first { $0.foundation == .pull }
        XCTAssertEqual(pull?.isCleared, true, "the horizontal chain's entry rung clears Pull")
        XCTAssertEqual(evaluate(logs), .strength)
    }

    /// A horizontal entry logged a step short of the top of the range is not cleared, and the postural
    /// entry cannot make up for it.
    func testShortHorizontalPullWithClearedPosturalStaysUncleared() {
        let logs = [
            workedLog("pull_scap", value: top("pull_scap") - RepGrammar.step),
            clearingLog("pull_superman"),
        ]
        XCTAssertEqual(progress(logs).foundations.first { $0.foundation == .pull }?.isCleared, false)
    }

    /// An entry logged but not *cleared* (short of the top of the range) does not count as competence.
    func testUnclearedEntryDoesNotCountAsCompetence() {
        // Push at 25 reps, a step short of a beginner's 30; every other foundation line fully cleared.
        let short = workedLog("push_wall", value: 25)
        let logs = sustainedHistory(weeks: 8) + [short]
            + [
                clearingLog("pull_scap"),
                clearingLog("squat_wall"),
                clearingLog("hinge_bridge"),
                clearingLog("core_plank"),
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

    /// A session rated "too hard" clears no Foundation line, whatever its sets logged and whether or not
    /// the "couldn't finish" follow-up reached it (decision 15).
    func testATooHardSessionNeverClearsAFoundation() {
        var logs = sustainedHistory(weeks: 8) + competenceLogs()
        XCTAssertEqual(evaluate(logs), .strength)
        let pushIndex = logs.firstIndex { $0.exercises.contains { $0.exerciseId == "push_wall" } }!
        logs[pushIndex].perceivedDifficulty = .tooHard
        for mark in [nil, false, true] as [Bool?] {
            logs[pushIndex].exercises[0].couldNotFinish = mark
            XCTAssertEqual(isPushCleared(logs), false, "too hard, couldNotFinish \(String(describing: mark))")
            XCTAssertEqual(evaluate(logs), .discipline)
        }
    }

    // MARK: - The rep grammar's bar (US-TD03)

    /// The bar is four sets at the top of the range: three sets at the top, or four a step short, do not
    /// clear an entry rung.
    func testAnEntryClearsOnlyWithFourSetsAtTheTopOfTheRange() {
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 30, sets: 3)]), false, "three sets at the top")
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 25)]), false, "four sets a step short")
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 30)]), true, "four sets at the top")
        XCTAssertEqual(progress([workedLog("core_plank", value: 55)]).foundations.first { $0.foundation == .core }?.isCleared, false,
                       "a hold a step short of 60 seconds")
        XCTAssertEqual(progress([clearingLog("core_plank")]).foundations.first { $0.foundation == .core }?.isCleared, true)
    }

    /// A log written before Training Days carries no Earned Reps and reads earned = its smallest set, so
    /// three sets of 15, which once cleared an entry rung, no longer do, while four sets at the top still do.
    func testALegacyThreeByFifteenLogNoLongerClearsAFoundation() {
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 15, sets: 3, role: nil)]), false)
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 30, role: nil)]), true)
    }

    /// Padding fills a long session up to the top of the range, but only Earned Reps at the top clear a
    /// rung: four padded sets of 30 at earned 25 clear nothing.
    func testPaddedSetsAtTheTopDoNotClearAFoundation() {
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 30, earned: 25)]), false)
    }

    /// A Practice station never moves a foundation, whatever it logged.
    func testAPracticeStationNeverClearsAFoundation() {
        XCTAssertEqual(isPushCleared([workedLog("push_wall", value: 30, role: .practice)]), false)
    }

    /// The top of the range is the user's level's: four sets of 30 clear a beginner's or an
    /// intermediate's entry rung, while an advanced user's reps range runs to 50.
    func testTheBarIsTheTopOfTheUsersLevelRange() {
        let atThirty = [workedLog("push_wall", value: 30)]
        XCTAssertEqual(isPushCleared(atThirty, level: .beginner), true)
        XCTAssertEqual(isPushCleared(atThirty, level: .intermediate), true)
        XCTAssertEqual(isPushCleared(atThirty, level: .advanced), false)
        XCTAssertEqual(isPushCleared([clearingLog("push_wall", level: .advanced)], level: .advanced), true)

        let advancedCompetence = ["push_wall", "pull_scap", "squat_wall", "hinge_bridge", "core_plank"]
            .map { clearingLog($0, level: .advanced) }
        XCTAssertEqual(evaluate(sustainedHistory(weeks: 8) + advancedCompetence, level: .advanced), .strength)
        XCTAssertEqual(evaluate(sustainedHistory(weeks: 8) + competenceLogs(), level: .advanced), .discipline,
                       "a beginner's clears are not an advanced user's")
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
                clearingLog("push_wall"),
                clearingLog("pull_scap"),
                clearingLog("squat_wall"),
                clearingLog("hinge_bridge"),
            ]),
            ("legs half", sustainedHistory(weeks: 8) + competenceLogs().filter { $0.exercises.first?.exerciseId != "hinge_bridge" }),
        ]
        for scenario in scenarios {
            let earned = progress(scenario.logs).hasEarnedStrength
            let gated = evaluate(scenario.logs) == .strength
            XCTAssertEqual(earned, gated, "progress.hasEarnedStrength must equal the gate for: \(scenario.name)")
        }
    }

    /// The PRD validation shape: 5 sustained weeks with push+pull cleared (legs/core not) surfaces
    /// exactly "5 of 8 weeks" and exactly 2 of 4 foundations cleared - and is *not* earned, matching
    /// what the gate would decide. The squat half of Legs is also cleared, and does not make Legs read
    /// as cleared.
    func testProgressReportsFiveOfEightWeeksAndTwoOfFourFoundations() {
        let logs = sustainedHistory(weeks: 5) + [
            clearingLog("push_wall"),
            clearingLog("pull_scap"),
            clearingLog("squat_wall"),
        ]
        let p = progress(logs)

        XCTAssertEqual(p.weeksSustained, 5, "five active weeks")
        XCTAssertEqual(p.requiredWeeks, 8, "the window is eight weeks")
        XCTAssertEqual(p.clearedFoundationCount, 2, "push and pull cleared, legs (one side) and core not")
        XCTAssertEqual(p.foundationCount, 4)

        // Per-foundation flags, in display order (Push / Pull / Legs / Core).
        XCTAssertEqual(p.foundations.map(\.foundation), [.push, .pull, .legs, .core])
        XCTAssertEqual(p.foundations.map(\.isCleared), [true, true, false, false])
        XCTAssertEqual(p.foundations.map(\.lineCount), [1, 1, 2, 1])
        XCTAssertEqual(p.foundations[2].clearedLineCount, 1, "Legs reads 1 of 2")

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
