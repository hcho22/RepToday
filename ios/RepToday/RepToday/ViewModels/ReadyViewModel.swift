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

    /// An abandoned in-progress session the user can resume or discard (US-K04), or `nil` when none
    /// is saved. Read from the `ActiveSessionStore` on open and after the player closes, so a session
    /// the user backgrounded out of - or that a relaunch interrupted - is offered back rather than
    /// silently lost.
    private(set) var resumableSession: ActiveSessionState?

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
    /// Where an in-progress session is read from (US-K04) so an abandoned session can be resumed or
    /// discarded from the Ready Screen. The player writes to this same store while a session is live.
    private let activeSessionStore: any ActiveSessionStore
    /// Anonymous product telemetry sink (US-T09). Optional exactly like `OnboardingViewModel.analytics`,
    /// so previews and tests that do not exercise the funnel construct the view model unchanged; when
    /// absent the `ready_screen_shown` emission is simply skipped. The emission goes through it
    /// **unconditionally** - consent (US-T06) is enforced inside the sink, so this view model never
    /// re-checks the opt-out flag (a second gate could disagree with the first).
    private let analytics: (any AnalyticsServiceProtocol)?
    /// Injected clock so the recent-log lookback window is testable. It also anchors the
    /// `generation_ms` measurement (US-T09), captured immediately before and after the engine call,
    /// so that measurement is deterministic under a test clock rather than a raw `Date()` read.
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
    /// re-fetching the logs or policy - keeping regeneration well inside the sub-100ms budget so Start
    /// is never left waiting on an answer. (The *profile* is deliberately not cached across a
    /// regeneration: it carries the injury safety filters, which are editable while this screen is
    /// alive, so `generate()` re-reads it.) Also handed to the active-session player so an in-session
    /// swap (US-K03) filters and sizes a substitute without a fresh fetch.
    private(set) var recentLogs: [WorkoutLog] = []
    /// The policy today's session was generated against. Handed to the active-session player so an
    /// in-session swap (US-K03) sizes its substitute with the same Step 6 levers the session was built
    /// on - including the cold-start Start Seed (US-O02) - rather than reverting to the neutral defaults.
    private(set) var policy: SessionPolicy = .default

    /// True once the first successful load has seeded `selectedMinutes` from the learned default.
    /// A re-appear (the Today tab's `.task` re-fires on every return) refreshes the engine inputs
    /// but preserves the user's in-session chip choice rather than snapping back to the default.
    private var hasSeededSelection = false

    /// Ensures `ready_screen_shown` is emitted exactly once per Ready Screen appearance (US-T09),
    /// scoped to the first successful load. Emission lives in `load()`, not the shared `generate()`,
    /// so a duration-chip regeneration (which reaches the engine only through `selectDuration()`)
    /// structurally cannot trip it and inflate the funnel count. Not persisted across launches: the
    /// funnel counts distinct installs and the backend dedups by `installId`.
    private var hasEmittedReadyScreenShown = false

    /// The wall-time the most recent session generation took, in whole milliseconds, measured off the
    /// injected clock around the engine call specifically (US-T09). Measured on every `generate()` -
    /// including chip-tap regenerations, useful for internal debugging - but only the first-load value
    /// is emitted as `ready_screen_shown`'s `generation_ms`.
    private(set) var lastGenerationMs: Int = 0

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        workoutEngine: any WorkoutEngineProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        consistencyService: any ConsistencyServiceProtocol = ConsistencyScoreService(),
        varietyLanguageResolver: VarietyLanguageResolver = VarietyLanguageResolver(),
        activeSessionStore: any ActiveSessionStore = InMemoryActiveSessionStore(),
        analytics: (any AnalyticsServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.workoutEngine = workoutEngine
        self.workoutLogService = workoutLogService
        self.consistencyService = consistencyService
        self.varietyLanguageResolver = varietyLanguageResolver
        self.activeSessionStore = activeSessionStore
        self.analytics = analytics
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

            // Surface any abandoned in-progress session so the screen can offer Resume or Discard
            // (US-K04). Best-effort and independent of today's generated session: a read failure
            // just leaves nothing to resume. Refreshed on every appear so a session the user
            // backgrounded out of - and the player persisted - is offered back on return.
            resumableSession = try? await activeSessionStore.load(for: user.id)

            // Recent logs feed the engine's staleness and Adaptive Overload steps; a freshly
            // onboarded user simply has none. The lookback is generous so the engine sees the full
            // relevant history without loading everything.
            let lookback = Calendar.current.date(byAdding: .day, value: -recentLogLookbackDays, to: now())
            recentLogs = try await workoutLogService.workoutLogs(from: lookback, to: nil)
            policy = try await sessionPolicyService.currentPolicy(for: user)

            // The profile just read is the freshest there is, so the load path needs no second fetch.
            try await generate(user: user)

            // US-T09: `ready_screen_shown` fires once per Ready Screen appearance, scoped to the first
            // successful load, carrying the `generation_ms` just measured in `generate()`. Guarded like
            // the `hasComputedConsistency` / `hasCheckedReprogramOnOpen` one-shots below, and emitted
            // here rather than inside `generate()` so a chip-tap regeneration (which never runs `load()`)
            // cannot re-emit and inflate the count. Fire-and-forget through the sink: it returns
            // immediately and swallows any failure, so telemetry never gates the session render or Start.
            if !hasEmittedReadyScreenShown {
                hasEmittedReadyScreenShown = true
                await analytics?.record(
                    AnalyticsEvent(
                        name: .readyScreenShown,
                        timestampMs: timestampMs(),
                        properties: ["generation_ms": .int(lastGenerationMs)]
                    )
                )
            }

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
        guard let cached = user, minutes != selectedMinutes else { return }
        let previous = selectedMinutes
        selectedMinutes = minutes
        errorMessage = nil
        do {
            // Unlike the load path, this tap can arrive long after the profile was read - and the
            // injury safety filters on it are editable from Settings and the coach's route while this
            // screen is alive (US-AC08). So re-read, best-effort: an unreadable profile falls back to
            // the snapshot rather than failing the regeneration.
            let user = (try? await userService.currentUser()) ?? cached
            try await generate(user: user)
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

    /// The store the active-session player persists to and resumes from (US-K04), handed to the
    /// player so a fresh session it starts writes to the same place the Ready Screen reads.
    var sessionStore: any ActiveSessionStore { activeSessionStore }

    /// Reconcile the resumable session after the player dismisses (US-K04), driven by whether the
    /// session *completed*. A completed session is dropped directly: the player already enqueued the
    /// store clear, so re-reading the store here would race that clear and could momentarily resurrect
    /// the just-finished snapshot as resumable. An abandoned session is re-read so the player's saved
    /// snapshot is surfaced back. This replaces the earlier store-load-on-dismiss, removing the race.
    func handlePlayerDismiss(completed: Bool) async {
        if completed {
            resumableSession = nil
            // A completed session writes a log and refreshes the user aggregate (US-L01), so the
            // Consistency Score the Ready Screen shows is now stale. Re-read the user and full history
            // and recompute the score, so returning from the player reflects the win without waiting
            // for the next genuine open. Best-effort: a failure just leaves the prior surfaces up.
            await refreshAfterCompletion()
        } else {
            await refreshResumableSession()
        }
    }

    /// Refresh the insight surfaces after a completed session (US-L01). Re-fetches the user (whose
    /// cold-start state and consistency the completion recorder advanced) and recomputes the displayed
    /// Consistency Score from the full, now-longer history. Deliberately does not regenerate today's
    /// session or re-fire the on-open re-program - those belong to a genuine open.
    private func refreshAfterCompletion() async {
        guard let existing = user else { return }
        let refreshed = (try? await userService.currentUser()) ?? existing
        user = refreshed
        let allLogs = (try? await workoutLogService.workoutLogs(from: nil, to: nil)) ?? recentLogs
        await refreshInsights(for: refreshed, logs: allLogs)
    }

    /// Re-read whether an abandoned session is resumable (US-K04). Called after the player closes, so
    /// a session the user just finished (the player cleared it) or abandoned (the player saved it) is
    /// reflected without a full reload. A no-op before a user has loaded.
    func refreshResumableSession() async {
        guard let user else { return }
        resumableSession = try? await activeSessionStore.load(for: user.id)
    }

    /// Discard the abandoned session so it is no longer offered (US-K04) - the user chose to let it
    /// go. Clears the store and the surfaced state. A no-op before a user has loaded.
    ///
    /// This is a **true give-up** of a resumable session, so it is where `session_abandoned` fires
    /// (US-T10) - not the player's mid-session dismiss, which is a pause the physical session can still
    /// be resumed and completed from. Emitting off the persisted snapshot (rather than in the player)
    /// is what keeps one physical session to a single terminal event across the resume path.
    func discardResumableSession() async {
        guard let user else { return }
        let abandoned = resumableSession
        try? await activeSessionStore.clear(for: user.id)
        resumableSession = nil
        if let abandoned { await emitSessionAbandoned(for: abandoned) }
    }

    /// The user tapped Start with a paused session still resumable: starting fresh overwrites that
    /// session in the store (keyed by the user's id, single slot), so the paused one is being given up
    /// (US-T10). Emit its `session_abandoned` off the persisted snapshot before the fresh player's
    /// first persist overwrites it, and drop it from the surfaced state so the Resume card clears. A
    /// no-op when nothing is resumable (the ordinary fresh start). Together with Discard this covers
    /// both true give-up paths, so a resumable session that never completes still emits exactly one
    /// terminal event rather than none.
    func abandonResumableSessionForOverwrite() async {
        guard let abandoned = resumableSession else { return }
        resumableSession = nil
        await emitSessionAbandoned(for: abandoned)
    }

    /// Emit `session_abandoned` for a resumable session the user has given up (US-T10). Both true
    /// give-up paths - Discard and overwrite - route through here, so the abandonment fires exactly
    /// once per given-up physical session and reads its coarse `abandon_point` and exercised-minutes
    /// straight off the persisted snapshot (the player that produced them is already gone). The
    /// emission goes through the sink **unconditionally** - consent (US-T06) is enforced inside the
    /// sink - and is fire-and-forget, so the give-up UI never waits on it. A `nil` sink (previews /
    /// tests not exercising the funnel) simply skips it.
    private func emitSessionAbandoned(for state: ActiveSessionState) async {
        guard let analytics else { return }
        // The block the current step sits in maps to a coarse, non-identifying bucket. The index is
        // clamped exactly as the player clamps a restored position, so a truncated snapshot resolves
        // to a real slot rather than trapping; `.strength` (-> mainWork) is a purely defensive fallback.
        let category: ExerciseCategory
        if state.slots.isEmpty {
            category = .strength
        } else {
            let index = min(max(state.currentStepIndex, 0), state.slots.count - 1)
            category = state.slots[index].blockCategory
        }
        await analytics.record(
            AnalyticsEvent(
                name: .sessionAbandoned,
                timestampMs: timestampMs(),
                properties: [
                    "completed_minutes": .int(state.exercisedMinutes ?? 0),
                    "abandon_point": .string(AbandonPoint(blockCategory: category).rawValue)
                ]
            )
        )
    }

    /// The current millisecond client timestamp off the injected clock (US-T09) - the same encoding
    /// `AnalyticsEvent` carries everywhere, with no raw `Date()` read.
    private func timestampMs() -> Int {
        Int(now().timeIntervalSince1970 * 1000)
    }

    /// Generate today's session at `selectedMinutes` from the cached engine inputs and the profile the
    /// caller hands in. Shared by the initial load and every chip regeneration so both take the
    /// identical path, and each supplies a profile it has just read - `load()` the one it fetched, a
    /// chip tap a fresh one, because the safety filters on it (the injury flags, US-AC08) are editable
    /// from Settings and from the coach's route while this screen is alive and a session built against
    /// a stale profile would still offer movements the user has just asked to work around. The
    /// requested minutes are captured before the engine await so a superseded, slower generation (an
    /// older chip tap still in flight) can never overwrite the session the latest selection produced.
    private func generate(user: User) async throws {
        self.user = user
        let requested = selectedMinutes
        // Measure the generation call specifically (US-T09) - the injected clock read straddles only
        // the engine await, not the surrounding view work, so `generation_ms` stays planning-honest.
        // Clamped at 0 defensively, mirroring US-T08's `elapsed_seconds`, so a non-monotonic clock read
        // can never produce a negative latency.
        let generationStart = now()
        let generated = try await workoutEngine.generateWorkout(
            requestedMinutes: requested,
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: policy
        )
        let generationMs = max(0, Int(now().timeIntervalSince(generationStart) * 1000))
        guard requested == selectedMinutes else { return }
        workout = generated
        lastGenerationMs = generationMs

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
