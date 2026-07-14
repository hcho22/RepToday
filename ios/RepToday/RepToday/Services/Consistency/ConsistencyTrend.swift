import Foundation

/// One point on the Consistency Score trend the Progress tab charts (US-M01): the forgiving score
/// as it stood at the end of one past week.
struct ConsistencyTrendPoint: Equatable, Identifiable {
    /// The start-of-week date this point represents (the chart's x value).
    let weekStart: Date
    /// The forgiving Consistency Score (0-100) as of that week's vantage.
    let score: Double

    var id: Date { weekStart }
}

/// The Consistency Score *over time* the Progress tab renders as a line chart (US-M01).
///
/// There is deliberately no separate trend algorithm here. A trend point is simply the real
/// forgiving score (`ConsistencyScore.evaluate`, US-H01) computed as it *would have stood* at the
/// end of each past week - evaluate the same logs with `asOf` walked back one week at a time. This
/// keeps a single source of truth for what "the score" means: the trajectory is the very same number
/// the headline shows, sampled at earlier vantages, so the chart can never drift from the headline.
///
/// Because it reuses the pure evaluator, every forgiveness rule is honored automatically at each
/// vantage: the window starts at first activity, Returns are excused, recency is weighted. Logs after
/// a given week are future-dated relative to that week's `asOf` and the evaluator discards them, so
/// each point reflects only the history the user had accumulated by then.
///
/// Like the evaluator, this is a pure function of its inputs (`asOf` injected, never a wall-clock
/// read), so it is fully deterministic and unit-testable.
enum ConsistencyTrend {

    /// The Consistency Score trajectory as of `asOf`, one point per week from the user's first active
    /// week (capped at `maxWeeks`) through the current week, oldest first.
    ///
    /// `maxWeeks` defaults to `ConsistencyScore.recentWeeksWindow` so the trend spans exactly the
    /// rolling window the score itself averages over - older weeks have already fallen out of the
    /// number, so charting them would be misleading. An empty history yields no points (a fresh user
    /// has no trajectory yet, which the view surfaces as an encouraging empty state rather than a flat
    /// line at zero).
    static func trend(
        logs: [WorkoutLog],
        weeklyGoal: Int = ConsistencyScore.defaultWeeklyGoal,
        maxWeeks: Int = ConsistencyScore.recentWeeksWindow,
        asOf: Date,
        calendar: Calendar = .current
    ) -> [ConsistencyTrendPoint] {
        guard !logs.isEmpty, maxWeeks >= 1 else { return [] }
        let goal = max(1, weeklyGoal)

        // How many whole weeks back the oldest (non-future) session lands. Future-dated logs are
        // ignored so a clock skew can't invent an earlier start, mirroring the evaluator.
        let oldestWeeksAgo = logs
            .map { ConsistencyScore.weeksAgo($0.completedAt, from: asOf, calendar) }
            .filter { $0 >= 0 }
            .max() ?? 0
        let span = min(oldestWeeksAgo, maxWeeks - 1)

        // Walk oldest -> newest (largest weeks-ago down to this week) so the points read left-to-right.
        return stride(from: span, through: 0, by: -1).compactMap { weeksAgo in
            let vantage = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: asOf) ?? asOf
            let consistency = ConsistencyScore.evaluate(
                logs: logs,
                weeklyGoal: goal,
                asOf: vantage,
                calendar: calendar
            )
            return ConsistencyTrendPoint(
                weekStart: ConsistencyScore.startOfWeek(vantage, calendar),
                score: consistency.score
            )
        }
    }
}
