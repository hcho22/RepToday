import Foundation

/// The forgiving, Return-protected Consistency Score (US-H01): the deterministic, on-device
/// measure of **showing up**. It replaces the fragile streak entirely - there is no XP, no
/// levels, no badges, and no single miss that zeroes the number. A user is "someone who moves,"
/// and a bad week dents the score modestly; it never punishes them for being human.
///
/// The model is a weighted rolling average of weekly adherence:
///
/// - `weeklyAdherence(week) = min(1, workoutsCompleted / weeklyGoal)` - a 5-minute session is a
///   full show-up (any completed log counts as one workout, regardless of its duration), so the
///   ceiling is met by *showing up*, not by training hard or long.
/// - `score = weightedRollingAverage(weeklyAdherence over recentWeeks) * 100`, with more recent
///   weeks weighted more heavily, so the number tracks who the user is *now* while still
///   remembering the momentum they built.
///
/// Two forgiveness rules keep the score honest without being punitive:
///
/// - **New users aren't penalized for not existing yet.** The window starts at the user's first
///   activity, so the empty weeks before they ever opened the app never drag the average down.
/// - **A Return (US-E06) protects the Score - it is celebrated, never penalized.** The empty
///   "gap weeks" that a Return closed are excused from the average (the away time the Return
///   forgives), and the week the user came back counts as a full show-up. A comeback therefore
///   *cannot* reduce the score; it can only preserve or rebuild it.
///
/// `longestChain` is tracked and surfaced as an earned point of pride - the longest run of
/// consecutive on-goal weeks the user has *ever* achieved. Because it is a historical maximum, a
/// broken chain lowers only the (unsurfaced) current run; the celebrated number never falls, so
/// the chain is a source of pride and never a threat.
///
/// Like the engine's steps, this is a pure function of its inputs - `asOf` is injected, never a
/// wall-clock read - so it is fully deterministic and unit-testable. The concrete
/// `ConsistencyServiceProtocol` implementation (`ConsistencyScoreService`) reads the real clock
/// once at the boundary and delegates every computation here.
enum ConsistencyScore {

    // MARK: - Tuning constants

    /// Target sessions per week when the caller does not override it (matches `Consistency.weeklyGoal`).
    static let defaultWeeklyGoal = 3

    /// The number of recent weeks the rolling average spans. Weeks older than this fall out of the
    /// window entirely, so the score reflects recent behavior; the window still starts no earlier
    /// than the user's first activity.
    static let recentWeeksWindow = 8

    // MARK: - Evaluation

    /// The forgiving Consistency Score as of `asOf`, computed purely from completed `logs`.
    ///
    /// `logs` are the user's completed sessions (any log is a show-up - logs are only written on
    /// completion). `weeklyGoal` defaults to `defaultWeeklyGoal` and is clamped to at least 1 so
    /// adherence is always well-defined. An empty history yields a zeroed `Consistency` (score 0,
    /// chain 0) - a fresh user has simply not started yet, which is neither punished nor celebrated.
    static func evaluate(
        logs: [WorkoutLog],
        weeklyGoal: Int = defaultWeeklyGoal,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Consistency {
        let goal = max(1, weeklyGoal)
        let totalWorkouts = logs.count
        let totalMinutes = logs.reduce(0) { $0 + $1.durationMinutes }

        guard !logs.isEmpty else {
            return Consistency(
                weeklyGoal: goal,
                score: 0,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        }

        // Bucket every log by how many whole weeks ago it landed (0 = this week). Future-dated logs
        // (weeksAgo < 0) are ignored so a clock skew can't invent activity.
        var workoutsByWeek: [Int: Int] = [:]
        var returnWeeks: Set<Int> = []
        for log in logs {
            let weeksAgo = weeksAgo(log.completedAt, from: asOf, calendar)
            guard weeksAgo >= 0 else { continue }
            workoutsByWeek[weeksAgo, default: 0] += 1
            if log.wasReturn { returnWeeks.insert(weeksAgo) }
        }

        let workoutsThisWeek = workoutsByWeek[0] ?? 0
        let longestChain = longestChain(workoutsByWeek: workoutsByWeek, returnWeeks: returnWeeks, goal: goal)

        return Consistency(
            weeklyGoal: goal,
            score: score(workoutsByWeek: workoutsByWeek, returnWeeks: returnWeeks, goal: goal),
            workoutsThisWeek: workoutsThisWeek,
            longestChain: longestChain,
            totalWorkoutsCompleted: totalWorkouts,
            totalMinutesExercised: totalMinutes
        )
    }

    // MARK: - Score (weighted rolling average of weekly adherence)

    private static func score(
        workoutsByWeek: [Int: Int],
        returnWeeks: Set<Int>,
        goal: Int
    ) -> Double {
        guard let oldestActivity = workoutsByWeek.keys.max() else { return 0 }
        // The window runs from this week (0) back to the oldest activity, capped at the rolling
        // window - never into the emptiness before the user's first session.
        let oldestIncluded = min(oldestActivity, recentWeeksWindow - 1)

        var weightedSum = 0.0
        var weightTotal = 0.0
        for weeksAgo in 0...oldestIncluded {
            let count = workoutsByWeek[weeksAgo] ?? 0

            let adherence: Double
            if count == 0 {
                // An empty week the user was away for. Excused (dropped from the average) only when
                // the gap it belongs to was closed by a Return - the away time a comeback forgives.
                if isExcusedGapWeek(weeksAgo, workoutsByWeek: workoutsByWeek, returnWeeks: returnWeeks) {
                    continue
                }
                adherence = 0
            } else if returnWeeks.contains(weeksAgo) {
                // The comeback week itself: a Return is celebrated as a full show-up, never penalized
                // for carrying only the single (deliberately gentle) session it was served.
                adherence = 1
            } else {
                adherence = min(1, Double(count) / Double(goal))
            }

            let weight = weight(forWeeksAgo: weeksAgo)
            weightedSum += weight * adherence
            weightTotal += weight
        }

        guard weightTotal > 0 else { return 0 }
        return (weightedSum / weightTotal) * 100
    }

    /// Whether an empty week is part of a gap that a Return closed, and so is excused from the
    /// average. It is excused when the first active week *after* it (chronologically forward, i.e.
    /// the most recent week that is still older-or-equal in time... expressed in weeks-ago terms,
    /// the largest `weeksAgo` below this one that has activity) contains a Return. That ties each
    /// excused gap to exactly the comeback that ended it: a later non-Return week stops the excusal,
    /// so only the away time a Return actually forgave is dropped.
    private static func isExcusedGapWeek(
        _ weeksAgo: Int,
        workoutsByWeek: [Int: Int],
        returnWeeks: Set<Int>
    ) -> Bool {
        // Forward in time = fewer weeks ago. Find the nearest active week more recent than this one.
        let nextActive = (0..<weeksAgo)
            .reversed()
            .first { (workoutsByWeek[$0] ?? 0) > 0 }
        guard let nextActive else { return false }
        return returnWeeks.contains(nextActive)
    }

    /// Recency weight for a week: more recent weeks weigh more. Linear from `recentWeeksWindow`
    /// (this week) down to `1` (the oldest week in the window), so the score leans toward who the
    /// user is now without discarding earned momentum.
    private static func weight(forWeeksAgo weeksAgo: Int) -> Double {
        Double(max(1, recentWeeksWindow - weeksAgo))
    }

    // MARK: - Longest chain (earned pride, never a threat)

    /// The longest run of consecutive on-goal weeks the user has *ever* achieved, scanned across all
    /// history (not just the rolling window). A week is on-goal when it met the weekly goal, or when
    /// it is a celebrated Return week. An empty non-Return week breaks the current run - but because
    /// this returns the historical maximum, a break never lowers the surfaced number.
    private static func longestChain(
        workoutsByWeek: [Int: Int],
        returnWeeks: Set<Int>,
        goal: Int
    ) -> Int {
        guard let oldestActivity = workoutsByWeek.keys.max() else { return 0 }
        var longest = 0
        var current = 0
        // Walk oldest -> newest so consecutive weeks are adjacent in the scan.
        for weeksAgo in stride(from: oldestActivity, through: 0, by: -1) {
            let count = workoutsByWeek[weeksAgo] ?? 0
            let onGoal = count >= goal || returnWeeks.contains(weeksAgo)
            if onGoal {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    // MARK: - Week math

    /// Whole weeks between `date` and `asOf` (0 = same week). Negative when `date` is in a week after
    /// `asOf` (a future-dated log), which callers discard.
    private static func weeksAgo(_ date: Date, from asOf: Date, _ calendar: Calendar) -> Int {
        let from = startOfWeek(date, calendar)
        let to = startOfWeek(asOf, calendar)
        return calendar.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0
    }

    private static func startOfWeek(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Service

/// The real `ConsistencyServiceProtocol` implementation backing the app, replacing
/// `MockConsistencyService` (US-H01). It reads the wall clock exactly once per call (the only
/// impurity) and delegates the entire computation to the pure, deterministic `ConsistencyScore`.
final class ConsistencyScoreService: ConsistencyServiceProtocol {

    /// A clock seam so the service stays deterministic under test; production uses `Date.init`.
    private let now: () -> Date
    private let calendar: Calendar

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    func consistency(for logs: [WorkoutLog], weeklyGoal: Int) async throws -> Consistency {
        ConsistencyScore.evaluate(logs: logs, weeklyGoal: weeklyGoal, asOf: now(), calendar: calendar)
    }

    func updatedConsistency(after log: WorkoutLog, user: User, recentLogs: [WorkoutLog]) async throws -> Consistency {
        ConsistencyScore.evaluate(
            logs: recentLogs + [log],
            weeklyGoal: user.consistency.weeklyGoal,
            asOf: now(),
            calendar: calendar
        )
    }
}
