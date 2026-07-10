import Foundation
import Observation

/// Backs the minimal Ready Screen the app opens to (US-I01).
///
/// The Ready Screen's promise is that today's session is *already there* - no browsing, no picker
/// to clear. On appear this view model loads the current user and their in-force `SessionPolicy`,
/// then asks the deterministic engine for a complete session at the learned Default Duration. The
/// engine is on-device and sub-100ms, so the session is present the moment the screen renders.
///
/// US-I01 lands the seam; US-J01 layers on the non-blocking duration chip with instant on-device
/// regeneration. US-J02 adds the three read-only surfaces the personalization is *felt* through -
/// the session's Variety Language line ("what today is"), the forgiving Consistency Score ("how I'm
/// doing", identity-framed), and the policy note ("what the app changed") - and kicks off the
/// on-open Re-program in the background, so the change lands next open and the user never waits.
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

    /// Today's Variety Language line (US-G03) - the honest, engine-derived contrast between today's
    /// lead pillar and the previous session's ("Today's a mobility day - yesterday was strength").
    /// `nil` for a degenerate warm-up-only session or before load. Template-sourced in the MVP (the
    /// optional LLM upgrade is deferred, US-N05); either way it can only name a contrast the session
    /// actually produced.
    private(set) var varietyNote: SessionPolicy.Note?

    /// The forgiving, identity-framed Consistency Score (US-H01) - the "how I'm doing" surface.
    /// `nil` before load. A best-effort read: a failure leaves it `nil` rather than failing the
    /// already-rendered session.
    private(set) var consistency: Consistency?

    /// The policy's honest note about the last real change (US-F04/US-G03) - the "what the app
    /// changed" surface - or `nil` when there is nothing observable to say. Read straight off the
    /// in-force policy, so it can only claim a change the sessions reflect.
    var policyNote: SessionPolicy.Note? { policy.note }

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
    private let consistencyService: any ConsistencyServiceProtocol
    /// Composes the deterministic Variety Language template with the optional, deferred LLM slice
    /// (US-G03/US-N05). Template-only in the MVP (no provider wired), so it never blocks.
    private let varietyLanguageResolver: VarietyLanguageResolver
    /// Injected clock so the recent-log lookback window is testable.
    private let now: () -> Date

    /// The background re-program kicked off on open (US-J02), exposed only so tests can await it.
    /// The UI never awaits this: the screen is fully interactive while it runs, any newly written
    /// policy applies only on the next open, and a failure is silent.
    private(set) var reprogramTask: Task<Void, Never>?

    /// Ensures the on-open re-program check fires once per app open, not on every tab re-appear.
    private var hasCheckedReprogramOnOpen = false

    /// Ensures the full-history Consistency Score read fires once per app open. The score only
    /// changes when a workout completes, and none completes on the Ready Screen, so re-scanning the
    /// entire log table on every tab re-appear is redundant.
    private var hasComputedConsistency = false

    /// Engine inputs cached from `load()` so a chip tap regenerates the session on-device without
    /// re-fetching the user, logs, or policy - keeping regeneration well inside the sub-100ms budget
    /// so Start is never left waiting on an answer.
    private var recentLogs: [WorkoutLog] = []
    private var policy: SessionPolicy = .default

    /// True once the first successful load has seeded `selectedMinutes` from the learned default.
    /// A re-appear (the Today tab's `.task` re-fires on every return) refreshes the engine inputs
    /// but preserves the user's in-session chip choice rather than snapping back to the default.
    private var hasSeededSelection = false

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol = ConsistencyScoreService(),
        varietyLanguageResolver: VarietyLanguageResolver = VarietyLanguageResolver(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.workoutEngine = workoutEngine
        self.workoutLogService = workoutLogService
        self.consistencyService = consistencyService
        self.varietyLanguageResolver = varietyLanguageResolver
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
            // Seed the selection from the learned default only on the first successful load; a
            // later refresh keeps whatever chip the user has since tapped.
            if !hasSeededSelection {
                selectedMinutes = user.duration.defaultMinutes
                hasSeededSelection = true
            }

            // Recent logs feed the engine's staleness and Adaptive Overload steps; a freshly
            // onboarded user simply has none. The lookback is generous so the engine sees the full
            // relevant history without loading everything.
            let lookback = Calendar.current.date(byAdding: .day, value: -recentLogLookbackDays, to: now())
            recentLogs = try await workoutLogService.workoutLogs(from: lookback, to: nil)
            policy = try await sessionPolicyService.currentPolicy(for: user)

            try await generate()

            // The session is now generated and rendering (the view prioritizes the workout over the
            // loading state), so Start is interactive from here on. The Variety Language line is
            // recomputed inside `generate()` with the session; the Consistency Score and the on-open
            // re-program are best-effort and never gate the session.
            //
            // Consistency reads all history, not the bounded engine window: `longestChain` ("Best
            // run") is a historical maximum, so a run older than the 70-day lookback must still count.
            // The engine inputs keep the bounded `recentLogs` for staleness / Adaptive Overload. The
            // full-history scan runs once per app open: the score only changes when a workout
            // completes, and none completes on the Ready Screen, so a tab re-appear reuses the result.
            if !hasComputedConsistency {
                hasComputedConsistency = true
                let allLogs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? recentLogs
                await refreshInsights(for: user, logs: allLogs)
            }

            // Re-program-on-open fires once per app open (not on every tab re-appear). It runs fully
            // in the background: the app renders from the existing policy now, and any newly written
            // policy applies on the next open (US-F03), never mid-session.
            if !hasCheckedReprogramOnOpen {
                hasCheckedReprogramOnOpen = true
                reprogramTask = reprogramIfDue(user: user, recentLogs: recentLogs, asOf: now())
            }
        } catch {
            errorMessage = "We couldn't load today's session."
        }
    }

    /// Compute the Consistency Score from the full log history. Best-effort and independent of the
    /// session render: a failure leaves it `nil` rather than failing the already-rendered workout,
    /// and it never blocks Start. Duration-independent, so it lives here rather than in `generate()`
    /// (which owns the duration-sensitive Variety Language line). The consistency read is a pure
    /// calculation over the passed-in logs.
    private func refreshInsights(for user: User, logs: [WorkoutLog]) async {
        consistency = try? await consistencyService.consistency(
            for: logs,
            weeklyGoal: user.consistency.weeklyGoal
        )
    }

    /// On open, check whether any re-program trigger is due (US-F01) and, if so, write a fresh policy
    /// in the background against the highest-precedence one (US-F03). Fire-and-forget: the returned
    /// task never blocks the UI, the newly written policy applies only on the next open, and any
    /// failure is silent - the existing policy stays in force.
    private func reprogramIfDue(user: User, recentLogs: [WorkoutLog], asOf: Date) -> Task<Void, Never> {
        Task { [sessionPolicyService] in
            do {
                let triggers = try await sessionPolicyService.dueTriggers(
                    user: user,
                    recentLogs: recentLogs,
                    asOf: asOf
                )
                guard let trigger = triggers.first else { return }
                _ = try await sessionPolicyService.reprogram(
                    user: user,
                    recentLogs: recentLogs,
                    trigger: trigger
                )
            } catch {
                // Best-effort: the existing policy remains in force and the user never waits on this.
            }
        }
    }

    /// Adjust the session length to a tapped duration chip and regenerate in place. Non-blocking:
    /// the existing session stays on screen (Start never disabled) while the on-device engine
    /// produces the new one, which lands well under 100ms. A tap on the already-selected chip, or
    /// before a user has loaded, is a no-op.
    func selectDuration(_ minutes: Int) async {
        guard user != nil, minutes != selectedMinutes else { return }
        let previous = selectedMinutes
        selectedMinutes = minutes
        errorMessage = nil
        do {
            try await generate()
        } catch {
            // Regeneration failed: keep the still-displayed session and roll the selection back so
            // the header and highlighted chip stay consistent with it, rather than surfacing an
            // error the session screen never renders while a workout is present. Only roll back if
            // this tap is still the current selection, so a later tap's choice is never clobbered.
            if selectedMinutes == minutes {
                selectedMinutes = previous
            }
        }
    }

    /// Generate today's session at `selectedMinutes` from the cached engine inputs. Shared by the
    /// initial load and every chip regeneration so both take the identical path. The requested
    /// minutes are captured before the await so a superseded, slower generation (an older chip tap
    /// still in flight) can never overwrite the session the latest selection produced.
    private func generate() async throws {
        guard let user else { return }
        let requested = selectedMinutes
        let generated = try await workoutEngine.generateWorkout(
            requestedMinutes: requested,
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: policy
        )
        guard requested == selectedMinutes else { return }
        workout = generated

        // Recompute the Variety Language line from the freshly generated session, so a duration chip
        // that shifts today's lead pillar never leaves the header describing a contrast this session
        // does not produce. Re-check the guard after the resolver await so a superseded, slower
        // generation cannot overwrite a newer selection's note.
        let note = await varietyLanguageResolver.note(for: generated, recentLogs: recentLogs, user: user)
        guard requested == selectedMinutes else { return }
        varietyNote = note
    }

    /// How far back the Ready Screen reads logs for engine context. Covers the Consistency Score
    /// window (8 weeks) with headroom.
    private let recentLogLookbackDays = 70

    /// The duration shown before a user has loaded - a neutral mid-range default.
    private static let fallbackMinutes = 15
}
