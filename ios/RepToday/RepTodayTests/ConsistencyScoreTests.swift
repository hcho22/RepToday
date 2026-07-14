import XCTest
@testable import RepToday

/// Tests the forgiving, Return-protected Consistency Score (US-H01): the pure `ConsistencyScore`
/// evaluator that replaces `MockConsistencyService`.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: an empty history is zero; a
/// perfect run is 100; a single miss dents the score modestly and never zeroes it; a 5-minute
/// session is a full show-up; recent weeks weigh more than older ones; a Return protects the score
/// (the gap it closed is excused and the comeback week is celebrated); and `longestChain` surfaces
/// the best run ever achieved, never lowered by a later break.
final class ConsistencyScoreTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed Gregorian/UTC calendar with a Sunday week start, so week bucketing is deterministic.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }()

    /// A Wednesday, comfortably mid-week: shifting by whole weeks stays inside the intended week,
    /// and small day offsets for multiple same-week sessions never cross a week boundary.
    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    private func log(weeksAgo: Int, dayOffset: Int, wasReturn: Bool, durationMinutes: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: durationMinutes,
            durationMinutes: durationMinutes,
            wasReturn: wasReturn,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    /// `count` completed sessions inside the week `weeksAgo` (spread across distinct earlier days so
    /// they stay in the same week), with an optional Return flag on the first and a per-session
    /// duration.
    private func week(weeksAgo: Int, count: Int, wasReturn: Bool = false, durationMinutes: Int = 15) -> [WorkoutLog] {
        (0..<count).map { i in
            log(weeksAgo: weeksAgo, dayOffset: i, wasReturn: wasReturn && i == 0, durationMinutes: durationMinutes)
        }
    }

    private func evaluate(_ logs: [WorkoutLog], weeklyGoal: Int = 3) -> Consistency {
        ConsistencyScore.evaluate(logs: logs, weeklyGoal: weeklyGoal, asOf: asOf, calendar: calendar)
    }

    // MARK: - Empty history

    func testEmptyHistoryIsZero() {
        let c = evaluate([])
        XCTAssertEqual(c.score, 0)
        XCTAssertEqual(c.longestChain, 0)
        XCTAssertEqual(c.workoutsThisWeek, 0)
        XCTAssertEqual(c.totalWorkoutsCompleted, 0)
        XCTAssertEqual(c.totalMinutesExercised, 0)
        XCTAssertEqual(c.weeklyGoal, 3)
    }

    // MARK: - Perfect run

    func testPerfectRunIsHundred() {
        // Eight consecutive on-goal weeks (3 sessions each).
        let logs = (0..<8).flatMap { week(weeksAgo: $0, count: 3) }
        let c = evaluate(logs)
        XCTAssertEqual(c.score, 100, accuracy: 0.0001, "a fully on-goal history scores 100")
        XCTAssertEqual(c.longestChain, 8, "eight consecutive on-goal weeks")
        XCTAssertEqual(c.workoutsThisWeek, 3)
        XCTAssertEqual(c.totalWorkoutsCompleted, 24)
    }

    // MARK: - Single-miss dent (not zero)

    /// PRD validation: a user at ~100 who misses one day this week dents modestly, never to zero.
    func testSingleMissDentsModestlyNotZero() {
        // Seven prior on-goal weeks; this week only 2 of the 3 sessions (one missed day).
        var logs = (1...7).flatMap { week(weeksAgo: $0, count: 3) }
        logs += week(weeksAgo: 0, count: 2)

        let c = evaluate(logs)
        XCTAssertLessThan(c.score, 100, "a missed day dents the score")
        XCTAssertGreaterThan(c.score, 80, "the dent is modest, not catastrophic")
        XCTAssertGreaterThan(c.score, 0, "a single miss never zeroes the score")
        XCTAssertEqual(c.workoutsThisWeek, 2)
    }

    // MARK: - 5-minute show-up

    func testFiveMinuteSessionIsFullShowUp() {
        // Three 5-minute sessions a week for the whole window: duration is irrelevant to adherence.
        let logs = (0..<8).flatMap { week(weeksAgo: $0, count: 3, durationMinutes: 5) }
        let c = evaluate(logs)
        XCTAssertEqual(c.score, 100, accuracy: 0.0001, "a 5-minute session counts as a full show-up")
        XCTAssertEqual(c.totalMinutesExercised, 24 * 5)
    }

    // MARK: - Rolling weighting (recent weeks weigh more)

    func testRecentWeeksWeighMoreThanOlder() {
        // Same total work over six contiguous weeks (no gaps), placed differently: on-goal recently
        // and weak long ago, vs. the mirror image.
        let strongRecently = (0...2).flatMap { week(weeksAgo: $0, count: 3) }
            + (3...5).flatMap { week(weeksAgo: $0, count: 1) }
        let strongLongAgo = (0...2).flatMap { week(weeksAgo: $0, count: 1) }
            + (3...5).flatMap { week(weeksAgo: $0, count: 3) }

        let recent = evaluate(strongRecently).score
        let old = evaluate(strongLongAgo).score
        XCTAssertGreaterThan(recent, old, "the same work weighs more when it is recent")
    }

    // MARK: - Return protection (celebrated, never penalized)

    /// PRD validation: a Return after a longer gap does not reduce the score. The empty gap weeks
    /// the Return closed are excused, and the comeback week is credited as a full show-up.
    func testReturnDoesNotReduceScore() {
        // On-goal weeks 4/5/6, then a three-week gap (weeks 1/2/3 empty), then a Return this week.
        let history = (4...6).flatMap { week(weeksAgo: $0, count: 3) }
        let withReturn = history + week(weeksAgo: 0, count: 1, wasReturn: true)
        let withoutReturn = history + week(weeksAgo: 0, count: 1, wasReturn: false)

        let protected = evaluate(withReturn).score
        let unprotected = evaluate(withoutReturn).score

        // With the gap weeks excused and the comeback week celebrated as a full show-up, the score
        // reflects only the on-goal weeks - exactly as if the user had never left.
        XCTAssertEqual(protected, 100, accuracy: 0.0001, "a Return does not reduce the score")
        XCTAssertGreaterThan(protected, unprotected, "the same comeback without a Return flag is penalized")
        XCTAssertLessThan(unprotected, 50, "an un-protected multi-week gap drags the score down")
    }

    /// An interior empty week that no Return closed still counts as a miss - only a Return excuses
    /// the away time it forgave.
    func testUnexcusedEmptyWeekStillDentsScore() {
        let filled = (0...2).flatMap { week(weeksAgo: $0, count: 3) }
        // The same on-goal weeks either side of an empty, non-Return week 1.
        let gapped = week(weeksAgo: 0, count: 3) + week(weeksAgo: 2, count: 3)

        let gappedScore = evaluate(gapped).score
        XCTAssertLessThan(gappedScore, evaluate(filled).score, "an unexcused empty week dents the score")
        XCTAssertGreaterThan(gappedScore, 0, "one missed week never zeroes the score")
    }

    // MARK: - Longest chain (earned pride, never a threat)

    func testLongestChainIsHistoricalMaxNotCurrentRun() {
        // Five on-goal weeks (7..3), a broken week (2), then two on-goal weeks (1..0).
        let logs = (3...7).flatMap { week(weeksAgo: $0, count: 3) }
            + (0...1).flatMap { week(weeksAgo: $0, count: 3) }
        // Week 2 has no sessions -> the chain breaks there.
        let c = evaluate(logs)
        XCTAssertEqual(c.longestChain, 5, "the surfaced chain is the best run ever, not the current one")
    }

    func testReturnWeekCountsTowardChain() {
        // Two on-goal weeks, then a Return week after a gap: the comeback week is on-goal for the chain.
        let logs = (5...6).flatMap { week(weeksAgo: $0, count: 3) }
            + week(weeksAgo: 0, count: 1, wasReturn: true)
        let c = evaluate(logs)
        XCTAssertGreaterThanOrEqual(c.longestChain, 2, "the pre-gap run is preserved")
    }

    // MARK: - Weekly goal

    func testWeeklyGoalIsRespectedAndClamped() {
        // A goal of 5: three sessions a week is 3/5 adherence, not a full week.
        let logs = (0..<4).flatMap { week(weeksAgo: $0, count: 3) }
        XCTAssertLessThan(evaluate(logs, weeklyGoal: 5).score, 100, "a higher goal is harder to fully meet")
        // A nonsensical goal is clamped to at least 1 rather than dividing by zero.
        XCTAssertEqual(evaluate(logs, weeklyGoal: 0).score, 100, accuracy: 0.0001)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let logs = (0..<6).flatMap { week(weeksAgo: $0, count: 2) }
        XCTAssertEqual(evaluate(logs), evaluate(logs))
    }
}
