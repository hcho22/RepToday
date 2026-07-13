import Foundation
import Observation

/// Backs the Progress tab (US-M01) - the reflection surface where the user *feels* their consistency
/// building. It reads the real `WorkoutLog` history and the real forgiving Consistency Score (US-H01)
/// and derives three read-only surfaces: the headline score with its earned `longestChain`, the score
/// trajectory over time (`ConsistencyTrend`), and the set of days a session was completed (for the
/// calendar). Everything is identity-framed and never loss-framed; there is no XP, no levels, no
/// badges.
///
/// Like the other v6 view models it is `@Observable`, takes its services as protocols, and injects a
/// clock (`now`) so the time-relative trend and calendar are deterministic under test.
@Observable
final class ProgressViewModel {

    /// The forgiving, identity-framed Consistency Score (US-H01) - score, `longestChain`, totals.
    /// `nil` before load or when there is no user.
    private(set) var consistency: Consistency?

    /// The Consistency Score over time (US-M01), oldest week first. Empty for a fresh user (no
    /// trajectory yet) - the view shows an encouraging empty state rather than a flat line at zero.
    private(set) var trend: [ConsistencyTrendPoint] = []

    /// The start-of-day dates on which the user completed at least one session, for the calendar to
    /// mark. Derived straight from `WorkoutLog.completedAt`, so a day is "logged" the moment any
    /// session - even five minutes - finished on it.
    private(set) var completedDays: Set<Date> = []

    /// True while the first load is in flight.
    private(set) var isLoading = false

    /// Set only when there is no profile yet; `nil` in the happy path (an empty history is a valid,
    /// encouraging state, not an error).
    private(set) var errorMessage: String?

    /// Whether the user has any completed history at all. Drives the empty state vs. the populated
    /// calendar/trend/score surfaces.
    var hasHistory: Bool { !completedDays.isEmpty }

    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let consistencyService: any ConsistencyServiceProtocol
    private let now: () -> Date
    private let calendar: Calendar

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol = ConsistencyScoreService(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.consistencyService = consistencyService
        self.now = now
        self.calendar = calendar
    }

    /// Load the full history, score, and derived trend/calendar. Idempotent enough to call on every
    /// appear: a second call simply refreshes, so a session completed on the Today tab is reflected
    /// when the user swings back to Progress.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let user = try? await userService.currentUser() else {
            errorMessage = "No profile found yet."
            return
        }

        // The whole history: `longestChain` is an all-time maximum and the calendar reflects every
        // logged day, so this reads everything rather than the engine's bounded recent window.
        let logs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? []
        let weeklyGoal = user.consistency.weeklyGoal

        completedDays = Set(logs.map { calendar.startOfDay(for: $0.completedAt) })
        consistency = try? await consistencyService.consistency(for: logs, weeklyGoal: weeklyGoal)
        trend = ConsistencyTrend.trend(
            logs: logs,
            weeklyGoal: weeklyGoal,
            asOf: now(),
            calendar: calendar
        )
    }
}
