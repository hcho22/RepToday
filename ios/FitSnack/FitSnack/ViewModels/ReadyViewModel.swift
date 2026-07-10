import Foundation
import Observation

/// Backs the minimal Ready Screen the app opens to (US-I01).
///
/// The Ready Screen's promise is that today's session is *already there* - no browsing, no picker
/// to clear. On appear this view model loads the current user and their in-force `SessionPolicy`,
/// then asks the deterministic engine for a complete session at the learned Default Duration. The
/// engine is on-device and sub-100ms, so the session is present the moment the screen renders.
///
/// This is the seam US-I01 lands on. US-J01 layers on the non-blocking duration chip with instant
/// on-device regeneration; the Variety Language line, Consistency Score, policy note, and
/// re-program-on-open (US-J02) build on this same view model next.
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

    /// The duration today's session is currently generated at. Starts at the user's learned Default
    /// Duration on `load()`, then follows whichever duration chip the user taps (US-J01). Distinct
    /// from `user.duration.defaultMinutes` (the persisted learned default): tapping a chip changes
    /// the session in the moment without rewriting the learned default.
    private(set) var selectedMinutes = ReadyViewModel.fallbackMinutes

    /// The duration chips the Ready Screen offers (5/10/15/20/30/45/60), reusing the canonical,
    /// ascending chip vocabulary the learned Default Duration always snaps to.
    let durationChips = DefaultDurationLearning.chipValues

    private let userService: any UserServiceProtocol
    private let sessionPolicyService: any SessionPolicyServiceProtocol
    private let workoutEngine: any WorkoutEngineProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    /// Injected clock so the recent-log lookback window is testable.
    private let now: () -> Date

    /// Engine inputs cached from `load()` so a chip tap regenerates the session on-device without
    /// re-fetching the user, logs, or policy - keeping regeneration well inside the sub-100ms budget
    /// so Start is never left waiting on an answer.
    private var recentLogs: [WorkoutLog] = []
    private var policy: SessionPolicy = .default

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

    /// The duration the session is generated at - the currently selected chip. Retained as
    /// `requestedMinutes` because it is exactly what the engine and log record as requested minutes.
    var requestedMinutes: Int { selectedMinutes }

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
            selectedMinutes = user.duration.defaultMinutes

            // Recent logs feed the engine's staleness and Adaptive Overload steps; a freshly
            // onboarded user simply has none. The lookback is generous so the engine sees the full
            // relevant history without loading everything.
            let lookback = Calendar.current.date(byAdding: .day, value: -recentLogLookbackDays, to: now())
            recentLogs = try await workoutLogService.workoutLogs(from: lookback, to: nil)
            policy = try await sessionPolicyService.currentPolicy(for: user)

            try await generate()
        } catch {
            errorMessage = "We couldn't load today's session."
        }
    }

    /// Adjust the session length to a tapped duration chip and regenerate in place. Non-blocking:
    /// the existing session stays on screen (Start never disabled) while the on-device engine
    /// produces the new one, which lands well under 100ms. A tap on the already-selected chip, or
    /// before a user has loaded, is a no-op.
    func selectDuration(_ minutes: Int) async {
        guard user != nil, minutes != selectedMinutes else { return }
        selectedMinutes = minutes
        errorMessage = nil
        do {
            try await generate()
        } catch {
            errorMessage = "We couldn't update today's session."
        }
    }

    /// Generate today's session at `selectedMinutes` from the cached engine inputs. Shared by the
    /// initial load and every chip regeneration so both take the identical path.
    private func generate() async throws {
        guard let user else { return }
        workout = try await workoutEngine.generateWorkout(
            requestedMinutes: selectedMinutes,
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: policy
        )
    }

    /// How far back the Ready Screen reads logs for engine context. Covers the Consistency Score
    /// window (8 weeks) with headroom.
    private let recentLogLookbackDays = 70

    /// The duration shown before a user has loaded - a neutral mid-range default.
    private static let fallbackMinutes = 15
}
