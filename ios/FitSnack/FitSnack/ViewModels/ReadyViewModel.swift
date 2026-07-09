import Foundation
import Observation

/// Backs the minimal Ready Screen the app opens to (US-I01).
///
/// The Ready Screen's promise is that today's session is *already there* - no browsing, no picker
/// to clear. On appear this view model loads the current user and their in-force `SessionPolicy`,
/// then asks the deterministic engine for a complete session at the learned Default Duration. The
/// engine is on-device and sub-100ms, so the session is present the moment the screen renders.
///
/// This is the seam US-I01 lands on. The richer Ready Screen behavior - the non-blocking duration
/// chip with instant regeneration (US-J01) and the Variety Language line, Consistency Score, policy
/// note, and re-program-on-open (US-J02) - layers onto this same view model in Epic J.
@Observable
final class ReadyViewModel {

    /// The loaded user, once available.
    private(set) var user: User?
    /// Today's generated session; `nil` until `load()` completes.
    private(set) var workout: Workout?
    /// True while the first load is in flight.
    private(set) var isLoading = false
    /// Set only when loading fails (no user, or the engine threw); `nil` in the happy path.
    private(set) var errorMessage: String?

    private let userService: any UserServiceProtocol
    private let sessionPolicyService: any SessionPolicyServiceProtocol
    private let workoutEngine: any WorkoutEngineProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    /// Injected clock so the recent-log lookback window is testable.
    private let now: () -> Date

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.workoutEngine = workoutEngine
        self.workoutLogService = workoutLogService
        self.now = now
    }

    /// The duration the session is generated at - the user's learned Default Duration, or a neutral
    /// fallback before a user has loaded.
    var requestedMinutes: Int {
        user?.duration.defaultMinutes ?? 15
    }

    /// Load the user, policy, and today's session. Idempotent enough to call on every appear; a
    /// second call refreshes rather than duplicating work.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let user = try await userService.currentUser() else {
                errorMessage = "No profile found yet."
                return
            }
            self.user = user

            // Recent logs feed the engine's staleness and Adaptive Overload steps; a freshly
            // onboarded user simply has none. The lookback is generous so the engine sees the full
            // relevant history without loading everything.
            let lookback = Calendar.current.date(byAdding: .day, value: -recentLogLookbackDays, to: now())
            let recentLogs = try await workoutLogService.workoutLogs(from: lookback, to: nil)

            let policy = try await sessionPolicyService.currentPolicy(for: user)
            let workout = try await workoutEngine.generateWorkout(
                requestedMinutes: user.duration.defaultMinutes,
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: policy
            )
            self.workout = workout
        } catch {
            errorMessage = "We couldn't load today's session."
        }
    }

    /// How far back the Ready Screen reads logs for engine context. Covers the Consistency Score
    /// window (8 weeks) with headroom.
    private let recentLogLookbackDays = 70
}
