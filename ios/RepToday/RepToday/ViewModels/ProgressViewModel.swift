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

    /// The legibility layer (US-M02): pillar balance, chain position, personal bests, and the
    /// premium-gated deep analytics. `nil` before load or when there is no user. Computed for
    /// everyone; the view renders the free layers always and gates `deep` behind `isPremium`.
    private(set) var analytics: ProgressAnalytics?

    /// Whether the user's entitlement unlocks the deep analytics layer (US-N04). `false` for the free
    /// tier, which sees a clear, non-nagging upsell in its place.
    private(set) var isPremium = false

    /// The phase the user has *earned* (US-H02), read from the persisted profile - drives whether the
    /// free "visible climb" surface (US-SP04) is shown (only while `.discipline`, i.e. still climbing).
    private(set) var phase: Phase = .discipline

    /// The component earn signals behind the Strength-Phase gate (US-SP04): weeks-sustained and
    /// per-foundation cleared flags, computed by the *same* `PhaseEvaluator` logic that gates the
    /// phase, so the surface can never disagree with the actual decision. `nil` before load, when
    /// there is no user, or when the library read fails.
    private(set) var phaseProgress: PhaseProgress?

    /// True while the first load is in flight.
    private(set) var isLoading = false

    /// Set only when there is no profile yet; `nil` in the happy path (an empty history is a valid,
    /// encouraging state, not an error).
    private(set) var errorMessage: String?

    /// Whether the user has any completed history at all. Drives the empty state vs. the populated
    /// calendar/trend/score surfaces.
    var hasHistory: Bool { !completedDays.isEmpty }

    /// The clock and calendar the surfaces above were derived against, for a view to render them
    /// with rather than reaching for the wall clock and `Calendar.current` itself. `completedDays`
    /// is start-of-day normalized by *this* calendar, so a view that normalizes a day with another
    /// one would silently match nothing and draw a full history as an empty month; and "today" has
    /// to be this clock's today, or the injected clock the trend and score already honour stops
    /// reaching the one surface that names a date.
    var displayNow: Date { now() }
    var displayCalendar: Calendar { calendar }

    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let consistencyService: any ConsistencyServiceProtocol
    private let exerciseService: any ExerciseServiceProtocol
    private let subscriptionService: any SubscriptionServiceProtocol
    private let phaseService: any PhaseServiceProtocol
    private let now: () -> Date
    private let calendar: Calendar

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        exerciseService: any ExerciseServiceProtocol,
        subscriptionService: any SubscriptionServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol = ConsistencyScoreService(),
        phaseService: (any PhaseServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.exerciseService = exerciseService
        self.subscriptionService = subscriptionService
        self.consistencyService = consistencyService
        // Defaulted so existing call sites (previews, tests) that do not thread a phase service still
        // compile; it reads the same validated library the deterministic gate uses.
        self.phaseService = phaseService ?? PhaseEvaluatorService(exerciseService: exerciseService, now: now, calendar: calendar)
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

        // The legibility layer (US-M02) - pillar balance, chain position, bests, and the deep layer -
        // over the same full history, plus the entitlement that gates the deep layer at render time.
        // Both are best-effort: a library or entitlement read that fails leaves the free surfaces
        // rendering and simply omits or gates the deep layer rather than failing the whole tab.
        if let library = try? await exerciseService.exercises() {
            analytics = ProgressAnalytics.from(
                logs: logs,
                library: library,
                phase: user.phase,
                asOf: now(),
                calendar: calendar
            )
        }
        isPremium = (try? await subscriptionService.currentSubscription().tier) == .premium

        // The free "visible climb" surface (US-SP04): the component earn signals from the same
        // `PhaseEvaluator` logic that gates the phase, over the same full history. Best-effort - a
        // library read that fails simply omits the card rather than failing the tab. `phase` drives
        // whether the card is shown at all (only while still climbing, i.e. `.discipline`).
        phase = user.phase
        phaseProgress = try? await phaseService.progress(for: user, recentLogs: logs)
    }
}
