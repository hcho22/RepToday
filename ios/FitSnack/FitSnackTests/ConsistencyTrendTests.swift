import XCTest
@testable import FitSnack

/// Tests the Consistency Score trend the Progress tab charts (US-M01).
///
/// The trend is not a separate algorithm: each point is the real forgiving score
/// (`ConsistencyScore.evaluate`, US-H01) sampled at an earlier week's vantage. These tests verify the
/// trajectory reflects that - empty history has no trajectory, the newest point matches the headline
/// score, the span is bounded by the rolling window and by first activity, and it is deterministic.
final class ConsistencyTrendTests: XCTestCase {

    /// A fixed Gregorian/UTC calendar with a Sunday week start, matching `ConsistencyScoreTests` so
    /// week bucketing is deterministic.
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

    private func week(weeksAgo: Int, count: Int, wasReturn: Bool = false) -> [WorkoutLog] {
        (0..<count).map { i in
            WorkoutLog(
                id: UUID(), workoutId: UUID(),
                completedAt: date(weeksAgo: weeksAgo, dayOffset: i),
                requestedMinutes: 15, durationMinutes: 15,
                wasReturn: wasReturn && i == 0,
                shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil, exercises: []
            )
        }
    }

    private func trend(_ logs: [WorkoutLog], weeklyGoal: Int = 3, maxWeeks: Int = ConsistencyScore.recentWeeksWindow) -> [ConsistencyTrendPoint] {
        ConsistencyTrend.trend(logs: logs, weeklyGoal: weeklyGoal, maxWeeks: maxWeeks, asOf: asOf, calendar: calendar)
    }

    // MARK: - Empty

    func testEmptyHistoryHasNoTrajectory() {
        XCTAssertTrue(trend([]).isEmpty)
    }

    // MARK: - Span

    /// Three weeks of history yields exactly three points (this week + the two prior active weeks),
    /// oldest first.
    func testSpanCoversFirstActivityThroughNow() {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 2, count: 3)
        let points = trend(logs)

        XCTAssertEqual(points.count, 3)
        // Oldest first: strictly ascending week starts.
        XCTAssertEqual(points.map(\.weekStart), points.map(\.weekStart).sorted())
    }

    /// History older than the rolling window is capped at `maxWeeks` points, so the chart never shows
    /// weeks the score itself has already forgotten.
    func testSpanCappedAtRollingWindow() {
        // Twelve consecutive on-goal weeks, but the window is 8.
        let logs = (0..<12).flatMap { week(weeksAgo: $0, count: 3) }
        let points = trend(logs, maxWeeks: 8)

        XCTAssertEqual(points.count, 8)
    }

    // MARK: - Fidelity to the headline

    /// The newest trend point equals the headline Consistency Score computed at the same `asOf`, so
    /// the chart's right edge always agrees with the big number.
    func testNewestPointMatchesHeadlineScore() {
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 2) + week(weeksAgo: 2, count: 3)
        let headline = ConsistencyScore.evaluate(logs: logs, weeklyGoal: 3, asOf: asOf, calendar: calendar)

        let last = trend(logs).last
        XCTAssertNotNil(last)
        XCTAssertEqual(last!.score, headline.score, accuracy: 0.0001)
    }

    /// Each point reflects only the history the user had by that week: a week with no activity yet
    /// (before their first session) never appears, and an earlier vantage never counts a future
    /// session. A rising history produces a non-trivial trajectory rather than a flat line.
    func testEarlierVantagesReflectOnlyPastActivity() {
        // Perfect recent weeks, empty older ones -> the earliest included point should be lower than
        // the newest as the average fills in. Build a clearly rising history.
        let logs = week(weeksAgo: 0, count: 3) + week(weeksAgo: 1, count: 1) + week(weeksAgo: 2, count: 1)
        let points = trend(logs)
        XCTAssertEqual(points.count, 3)
        // The oldest vantage saw only a single-session week (adherence 1/3); the newest sees the full
        // on-goal week weighted in, so the score should be higher at the end.
        XCTAssertLessThan(points.first!.score, points.last!.score)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let logs = week(weeksAgo: 0, count: 2) + week(weeksAgo: 1, count: 3) + week(weeksAgo: 3, count: 3)
        XCTAssertEqual(trend(logs), trend(logs))
    }
}
