import Foundation
import Observation

/// Backs the active-session player (US-K01) - the focused screen that walks the user through a
/// generated `Workout` one exercise at a time so they never lose their place mid-session.
///
/// The view model flattens the session's blocks into a single ordered list of `Step`s (warm-up ->
/// training -> cooldown, in the engine's order) and tracks exactly where the user is: the current
/// step, the set they are on, and the elapsed wall-clock time. Completing a set advances the
/// session and records what was done toward the `WorkoutLog`. After each set a rest timer (US-K02)
/// counts down the prescription's `restSeconds` and, when it elapses, fires an accessible
/// haptic/audio cue.
///
/// When the session completes (US-L01) the view model writes the `WorkoutLog` through the injected
/// `SessionCompletionServiceProtocol` - fire-and-forget at the `finish()` transition, so the record is
/// durable even if the user quits on the completion screen - and exposes a template-based `summary`
/// (duration + muscle/mobility coverage) for the celebration screen. The perceived-difficulty rating
/// is collected on that screen by US-L02.
///
/// Background/resume (US-K04) is delivered by a persistence seam: after every meaningful change - and
/// just before backgrounding - the view model writes a full `ActiveSessionState` snapshot to an
/// injected `ActiveSessionStore` (keyed by the user's id) and clears it the instant the session
/// completes. Because the snapshot captures the current lineup, position, completed work, the
/// session-clock origin, and the rest timer as absolute instants, the player restores the *exact*
/// position after a relaunch, and the Ready Screen can offer an abandoned session as Resume or
/// Discard. The `init(state:)` designated initializer is the resume entry point; the fresh-start
/// `init(workout:)` is a convenience over it.
///
/// The rest timer is derived from the same injected clock as elapsed time, but with pause semantics:
/// it runs on a `Countdown` (a wall-clock deadline, with the remainder frozen while paused), so
/// backgrounding the app pauses it and the countdown never blows past while the user is away. The Hold
/// Timer below runs on the same type rather than a copy of it, so a fix to the mechanism lands on both.
/// All rest logic is pure over the injected clock, so the tests drive the countdown, skip, extend,
/// pause, and resume without real time passing.
///
/// The in-session swap (US-K03) lets the user replace the current exercise with a deterministic
/// same-pillar/pattern peer so one movement they can't or won't do never derails the session. It
/// calls the engine's swap step (US-C08, `ExerciseSwap.swap` behind `WorkoutEngineProtocol`), which
/// substitutes within the same pillar, pattern, difficulty band, and time budget and never duplicates
/// a movement already in the session; when no safe in-budget peer exists it returns `.noAlternative`
/// and the original slot stays. The swap dependencies are injected and optional, so the player still
/// constructs (e.g. in previews) without an engine - swap simply stays unavailable then.
///
/// Elapsed time is derived from an injected clock rather than an internal ticking counter, and is
/// deliberately *not* shown while the session runs (US-O03): a visible ticking total turns the session
/// into something to get through, so the clock only surfaces as the completion summary's duration.
/// `elapsed(asOf:)` stays a pure function of the clock, so `completedDurationMinutes()` - and the log,
/// Default Duration learning, and Consistency Score behind it - are unchanged.
///
/// A timed (`isHold`) exercise gets a Hold Timer instead (US-O03): the user taps "Start hold", a
/// countdown runs, and at zero it fires the same `RestTimerFeedback` cue exactly once and records the
/// set automatically. It is counted one *side* at a time, because the engine charges a per-side
/// movement for both sides - a set of side plank is two legs, and a single countdown that recorded
/// the set at the end of one would quietly halve the work the session was built around. The countdown
/// itself is in-memory only and is never persisted or restored: backgrounding *within* the session
/// freezes and resumes the leg through `scenePhase`, while tearing the player down ends it outright,
/// and only the side the user still owes is carried into the snapshot - so a resumed session always
/// comes back idle. (`init(state:)` records why a hold is not a rest.) The timer is the offer, not the
/// only way through: a timed exercise keeps a manual completion in the secondary row - offered while a
/// leg runs too - so a user who held it off-timer or was interrupted part-way through banks the work
/// rather than losing it to a skip. Rep-based exercises are untouched: set tracker plus a manual
/// "Complete set".
@Observable
final class ActiveSessionViewModel {

    /// Seconds added each time the user taps "extend" during a rest.
    static let restExtension = 15

    /// One playable position in the session: a single prescribed exercise, tagged with the block it
    /// belongs to and its 1-based position across the whole session (for "3 of 8" progress copy).
    struct Step: Identifiable {
        /// Mirrors the prescription's id, so the step is stable across regenerations.
        let id: UUID
        let blockTitle: String
        let blockCategory: ExerciseCategory
        let prescription: PrescribedExercise
        /// 1-based position of this exercise across every block in the session.
        let position: Int
        /// Total exercises across every block, so the player can show "position of total".
        let total: Int
    }

    /// The session being played, kept whole so US-K03 (swap) and US-K04 (resume) can reach it.
    let workout: Workout

    /// The flattened, ordered exercises the player walks through.
    private(set) var steps: [Step]

    /// Index into `steps` of the exercise on screen now.
    private(set) var currentStepIndex = 0

    /// The 1-based set the user is currently working on within the current exercise.
    private(set) var currentSet = 1

    /// True once every exercise has been completed or skipped. The player shows its completion state
    /// and freezes the elapsed clock; the post-session `summary` and the fire-and-forget log write
    /// (US-L01) hang off this transition.
    private(set) var isComplete: Bool

    /// What the user actually did, accumulated toward the eventual `WorkoutLog` (US-L01), keyed by
    /// prescription id. Each completed set records the prescribed target as performed - US-L02 adds
    /// the perceived-difficulty rating; a later story can collect actual reps if the design calls for
    /// it. A skipped exercise records no sets and is flagged in `skippedStepIDs`.
    private(set) var completedSets: [UUID: [CompletedSet]] = [:]

    /// Prescription ids the user skipped, so the eventual log can mark them `skipped`.
    private(set) var skippedStepIDs: Set<UUID> = []

    /// When the player started, captured once. Elapsed time is measured from here.
    private(set) var startedAt: Date?

    /// When the session completed, so elapsed time freezes instead of ticking past the finish.
    private(set) var finishedAt: Date?

    // MARK: - Swap (US-K03)

    /// True while a swap request is in flight, so the UI can disable the swap control and never fire
    /// two overlapping swaps of the same slot.
    private(set) var isSwapping = false

    /// True when the most recent swap request found no safe, in-budget peer (`.noAlternative`): the
    /// original slot stays and the UI shows an honest "no alternative" state rather than an unsafe
    /// substitution. Cleared when the user advances off the exercise or requests another swap.
    private(set) var noSwapAlternative = false

    // MARK: - Rest timer (US-K02)

    /// The rest in force between sets, or `nil` when none is. Both timers run on the same `Countdown`
    /// (absolute deadline, pause/resume), so a fix to the mechanism lands on both rather than on
    /// whichever copy it was written against; what differs is what each one *does* at zero.
    private var rest: Countdown?

    /// True while a rest period is in force between sets - running or paused. The player shows the
    /// rest overlay while this holds and hides it (revealing the already-advanced next set) once the
    /// rest ends by countdown, skip, or the final set.
    var isResting: Bool { rest != nil }

    /// The full length of the current rest in seconds, including any extensions - the denominator for
    /// the rest progress ring.
    var restTotalSeconds: Int { rest?.total ?? 0 }

    // MARK: - Hold timer (US-O03)

    /// The hold leg counting down for the current exercise, or `nil` between legs. Deliberately *not*
    /// persisted: unlike a rest, a hold does not survive the player being torn down (see `init(state:)`).
    private var hold: Countdown?

    /// True while a hold leg is counting down for the current exercise - running or paused. The player
    /// shows the countdown in place of the demo while this holds.
    var isHolding: Bool { hold != nil }

    /// The full length of the running hold leg in seconds - one side's prescribed hold, and the
    /// denominator for the countdown ring. Zero between legs.
    var holdTotalSeconds: Int { hold?.total ?? 0 }

    /// The 1-based side of the current set the hold is on. Always 1 for a bilateral movement; a
    /// per-side movement runs the prescribed hold once per side, so its set is two legs and side 2 is
    /// the second of them. This is the one piece of hold state that *is* persisted, so a user who
    /// finished the first side never silently repeats it.
    private(set) var holdSide = 1

    private let now: () -> Date
    private let feedback: RestTimerFeedback

    /// The engine seam the swap runs through (US-C08). `nil` when the player is built without an
    /// engine (previews), which simply leaves swap unavailable.
    private let swapEngine: (any WorkoutEngineProtocol)?
    /// The user and recent logs the swap step needs to filter and size a substitute. Captured at
    /// construction from the Ready Screen's already-loaded state, so a swap adds no fetch.
    private let user: User?
    private let recentLogs: [WorkoutLog]
    /// The policy this session was generated against, carried so a mid-session swap sizes its
    /// substitute with the same Step 6 levers - including the cold-start Start Seed (US-O02) - rather
    /// than reverting to the neutral defaults. `.default` in previews / when none was supplied.
    private let sessionPolicy: SessionPolicy

    // MARK: - Persistence (US-K04)

    /// The store the in-progress session is written to after every meaningful change and cleared on
    /// completion, so backgrounding or a relaunch never costs the user their place. `nil` (with a nil
    /// `userId`) in previews, where the player simply persists nothing.
    private let store: (any ActiveSessionStore)?
    /// The id the session is persisted under - the owning user's id.
    private let userId: String?

    /// The most recently launched persistence write, exposed only so tests can await the store
    /// settling. The UI never awaits it: persistence is fire-and-forget and best-effort, so the
    /// player never stalls on a disk write.
    private(set) var persistenceTask: Task<Void, Never>?

    // MARK: - Completion recording (US-L01)

    /// The seam that writes the `WorkoutLog` and does the post-session bookkeeping (Consistency Score
    /// refresh, cold-start handoff) the instant the session completes. `nil` in previews / when no
    /// user is wired, where completion simply records nothing.
    private let completionService: (any SessionCompletionServiceProtocol)?

    // MARK: - Analytics (US-T10)

    /// Anonymous product-telemetry sink (US-T10). Optional exactly like `ReadyViewModel.analytics`,
    /// so previews and tests that do not exercise the funnel construct the player unchanged; when
    /// absent the lifecycle emissions are simply skipped. Every emission goes through it
    /// **unconditionally** - consent (US-T06) is enforced inside the sink, so this view model never
    /// re-checks the opt-out flag (a second gate could disagree with the first).
    private let analytics: (any AnalyticsServiceProtocol)?

    /// The most recently launched telemetry emission, chained so the events land in call order and
    /// exposed only so tests can await the sink settling. The UI never awaits it: emission is strictly
    /// fire-and-forget, so the player never stalls on the network.
    private(set) var analyticsTask: Task<Void, Never>?

    /// Ensures `session_completed` is emitted at most once per player (US-T10). It fires from the
    /// single dismiss choke point `recordSessionEnd()`, so this one-shot makes a repeated dismiss a
    /// no-op and the completion never double-fires. (The abandonment terminal event is not emitted by
    /// the player at all - a resumable pause is not an abandonment; see `recordSessionEnd()`.) Not
    /// persisted: the funnel counts distinct installs and the backend dedups by `installId`.
    private var hasEmittedTerminalEvent = false

    /// The fire-and-forget completion write launched at `finish()`, exposed only so tests can await
    /// the recording settling. The UI never awaits it: like persistence, the write is best-effort and
    /// the player never stalls on it. A rating given on the completion screen (US-L02) chains behind it
    /// so the rating's re-save always lands after the initial write of the same log.
    private(set) var completionTask: Task<Void, Never>?

    // MARK: - Rating (US-L02)

    /// The perceived-difficulty rating the user gave on the completion screen, or `nil` if they haven't
    /// rated (skipping the control is treated as unrated). Feeds the Asymmetric Ramp (US-E05) on the
    /// next session: `tooHard` eases the next target, `tooEasy` intensifies it.
    ///
    /// During cold start a `tooHard` reaches further than the next session. Through
    /// `SessionCompletionServiceProtocol.recordPerceivedDifficulty` it also steps the Start Seed
    /// difficulty floor down a tier (US-O02), and on the session that retires the band that becomes a
    /// durable account-level fact (`User.ColdStart.bandFloorAtHandoff`) rather than one session's ease.
    private(set) var perceivedDifficulty: PerceivedDifficulty?

    /// The durable `WorkoutLog` built once at the `finish()` transition and kept so a later rating
    /// updates the *same* record (stable id) rather than writing a second, un-linked log. `nil` until
    /// the session completes.
    private var completedLog: WorkoutLog?

    /// Restore-capable designated initializer (US-K04): builds the player from a persisted - or
    /// freshly-seeded - `ActiveSessionState`, so a fresh start, a resume-after-relaunch, and a resume
    /// from the Ready Screen all funnel through one representation of the play state. When `store` and
    /// `userId` are supplied the player persists a fresh snapshot after every meaningful change and
    /// clears it on completion; without them (previews) it persists nothing.
    init(
        state: ActiveSessionState,
        swapEngine: (any WorkoutEngineProtocol)? = nil,
        user: User? = nil,
        recentLogs: [WorkoutLog] = [],
        sessionPolicy: SessionPolicy = .default,
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        feedback: RestTimerFeedback = SystemRestTimerFeedback()
    ) {
        self.workout = state.workout
        self.swapEngine = swapEngine
        self.user = user
        self.recentLogs = recentLogs
        self.sessionPolicy = sessionPolicy
        self.store = store
        self.userId = userId
        self.completionService = completionService
        self.analytics = analytics
        self.now = now
        self.feedback = feedback

        let steps = Self.steps(from: state.slots)
        self.steps = steps
        self.isComplete = steps.isEmpty
        // Clamp the restored position into range so a corrupt or truncated snapshot resumes safely
        // rather than trapping on an out-of-bounds index.
        self.currentStepIndex = steps.isEmpty ? 0 : min(max(state.currentStepIndex, 0), steps.count - 1)
        self.currentSet = max(1, state.currentSet)
        self.completedSets = state.completedSets
        self.skippedStepIDs = state.skippedStepIDs
        self.startedAt = state.startedAt
        // A rest genuinely continues while the app is away - the user *is* resting - so it restores and
        // keeps counting. One that already ran out while the app was gone is simply over: restoring it
        // would have the overlay's first tick fire a completion cue for a rest nobody is in. Covers all
        // four shapes at once, since a frozen remainder of zero is as expired as a deadline in the past.
        if let rest = state.rest {
            let restored = Countdown(
                total: rest.totalSeconds, deadline: rest.deadline, remainingWhenPaused: rest.remainingWhenPaused
            )
            if restored.remaining(asOf: now()) > 0 { self.rest = restored }
        }
        // A hold is different, and this is the rule that keeps it safe: a leg **never** survives the
        // player being torn down. Only the side the user still owes is restored, so a resumed session
        // always comes back idle showing "Start hold" and the leg begins again on a deliberate tap.
        //
        // The alternative - restoring the countdown, however carefully guarded - kept regenerating the
        // same defect through different doors: a past deadline, a frozen remainder of zero, and a frozen
        // remainder that `onAppear` obligingly un-froze all ended with the cue firing and a `CompletedSet`
        // banked for work nobody did. They shared a cause: the Hold Timer was modelled on the rest timer,
        // and the two are not alike here. Resting continues while you are away from the screen; planking
        // does not. Carrying the *side* and nothing else is both the honest model and the one with no
        // door left to guard.
        if let hold = state.hold {
            self.holdSide = max(1, hold.side)
        }
    }

    /// Fresh-start convenience: play `workout` from its first set, with no completed work yet.
    convenience init(
        workout: Workout,
        swapEngine: (any WorkoutEngineProtocol)? = nil,
        user: User? = nil,
        recentLogs: [WorkoutLog] = [],
        sessionPolicy: SessionPolicy = .default,
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        feedback: RestTimerFeedback = SystemRestTimerFeedback()
    ) {
        self.init(
            state: ActiveSessionState(fresh: workout),
            swapEngine: swapEngine,
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            store: store,
            userId: userId,
            completionService: completionService,
            analytics: analytics,
            now: now,
            feedback: feedback
        )
    }

    // MARK: - Derived state

    /// The exercise on screen now, or `nil` once the session is complete. The index stays parked on
    /// the final exercise when the session finishes, so completion is what clears the current step.
    var currentStep: Step? {
        guard !isComplete, steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    /// The number of sets prescribed for the current exercise.
    var setsInCurrentStep: Int { currentStep?.prescription.sets ?? 0 }

    /// Total prescribed sets across the whole session - the denominator for the progress bar.
    var totalSets: Int { steps.reduce(0) { $0 + $1.prescription.sets } }

    /// How many sets the user has completed so far across the session.
    var completedSetCount: Int { completedSets.values.reduce(0) { $0 + $1.count } }

    /// Session progress in `0...1` by completed sets, so a longer exercise weighs more than a shorter
    /// one. Skipped exercises simply never contribute their sets.
    var progress: Double {
        totalSets == 0 ? 1 : Double(completedSetCount) / Double(totalSets)
    }

    // MARK: - Timing

    /// Begin the session clock. Idempotent: a second call (e.g. the view re-appearing) keeps the
    /// original start, so elapsed time never resets. `startedAt` is persisted (US-K04) so elapsed
    /// time survives a relaunch - a resumed session keeps its already-set origin rather than restarting.
    func start() {
        guard startedAt == nil else { return }
        startedAt = now()
        // US-T10: `session_started` fires once per session, inside the same `startedAt == nil`
        // idempotency that gates the clock start, carrying the requested minutes. Fire-and-forget
        // through the sink, so telemetry never delays the first render.
        emit(.sessionStarted, properties: ["requested_minutes": .int(workout.requestedMinutes)])
        // Persist immediately so even an untouched-but-started session is resumable after a relaunch.
        persist()
    }

    /// Elapsed whole seconds from the start to `date`, frozen at `finishedAt` once complete. A pure
    /// function of the injected clock so the view's per-second `TimelineView` reads it cheaply and the
    /// tests can advance time deterministically.
    func elapsed(asOf date: Date) -> Int {
        guard let startedAt else { return 0 }
        let end = finishedAt ?? date
        return max(0, Int(min(date, end).timeIntervalSince(startedAt)))
    }

    // MARK: - Advancing the session

    /// Record the current set as done and advance: to the next set of the same exercise, or to the
    /// next exercise once the last set is finished, or to the completion state at the end. A no-op
    /// once the session is complete. Unless the session just finished, this opens a rest period
    /// (US-K02) using the just-completed prescription's `restSeconds`, so the next effort is paced.
    func completeSet() {
        guard !isComplete, let step = currentStep else { return }
        // Any prior rest is over the moment the next set is logged (a no-op in the overlay-gated UI,
        // where the complete-set control is hidden during rest).
        endRest(fireFeedback: false)
        // The set is done, so the hold that timed it is too - and the next set starts back on side 1.
        // Already ended (without a second cue) when the hold itself is what completed the set; when the
        // user banked it by hand mid-leg instead, this is what takes the running countdown down, and it
        // fires no cue because coming out early is the user's choice rather than the timer's verdict.
        resetHold()
        recordSet(for: step.prescription)
        let restSeconds = step.prescription.restSeconds
        if currentSet < step.prescription.sets {
            currentSet += 1
        } else {
            advanceExercise()
        }
        // No rest after the final set of the session - the session is over, not paced.
        if !isComplete {
            startRest(seconds: restSeconds)
        }
        persist()
    }

    /// Skip the current exercise, marking it skipped for the eventual log, and advance to the next
    /// exercise. A skip means the user is abandoning the exercise entirely, so any sets already
    /// recorded for it are discarded - a skipped exercise never carries completed sets in
    /// `loggedExercises()`. A no-op once complete. (Swapping to a peer instead is US-K03; this is
    /// the plain "move past it" path.)
    func skipExercise() {
        guard !isComplete, let step = currentStep else { return }
        // Skipping moves on immediately, so any rest or hold in force is dropped without firing a cue.
        endRest(fireFeedback: false)
        resetHold()
        completedSets.removeValue(forKey: step.id)
        skippedStepIDs.insert(step.id)
        advanceExercise()
        persist()
    }

    /// Build the per-exercise log rows for the eventual `WorkoutLog` (US-L01) from what was actually
    /// tracked - the completed sets and skip flags - carrying pillar/pattern inline so staleness can
    /// be computed without re-resolving the exercise.
    func loggedExercises() -> [LoggedExercise] {
        steps.map { step in
            let exercise = step.prescription.exercise
            return LoggedExercise(
                id: UUID(),
                exerciseId: exercise.id,
                pillar: exercise.pillar,
                movementPattern: exercise.movementPattern,
                completedSets: completedSets[step.id] ?? [],
                skipped: skippedStepIDs.contains(step.id)
            )
        }
    }

    // MARK: - Completion (US-L01)

    /// The template-based post-session summary shown on the completion screen: what the user did and
    /// the muscle/mobility coverage the session produced. `nil` until the session is complete. Pure
    /// over the completed state (elapsed time freezes at `finishedAt`), so it is stable across renders.
    var summary: SessionSummary? {
        guard isComplete else { return nil }
        return SessionSummary.from(loggedExercises: loggedExercises(), durationMinutes: completedDurationMinutes())
    }

    /// The durable `WorkoutLog` for the finished session (US-L01): what was requested vs. actually
    /// completed, the shape/focus/return flags copied straight off the played `Workout` (never
    /// re-derived), the per-exercise completed/skipped rows, and any perceived-difficulty rating
    /// (US-L02). `nil` unless the session is complete. This is the same record - stable id - that both
    /// the initial completion write and a later rating update target.
    func completionLog() -> WorkoutLog? { completedLog }

    /// Build the durable log once, at the `finish()` transition. The id is generated here (not per
    /// call) so a rating given afterward re-saves this exact record rather than a second, un-linked log.
    private func buildCompletionLog() -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: workout.id,
            completedAt: finishedAt ?? now(),
            requestedMinutes: workout.requestedMinutes,
            durationMinutes: completedDurationMinutes(),
            wasReturn: workout.wasReturn,
            shape: workout.shape,
            focusPillar: workout.focusPillar,
            perceivedDifficulty: perceivedDifficulty,
            exercises: loggedExercises()
        )
    }

    /// Whole minutes actually exercised, wall-clock from start to finish, floored at 1 so a genuinely
    /// completed session always records a positive duration and capped at the session's
    /// `requestedMinutes`. This is the completed - not requested - duration Default Duration learning
    /// (US-F04) and the Consistency Score (US-H01) read.
    ///
    /// The session clock intentionally keeps running as wall-clock time while backgrounded (US-K01/K04),
    /// and mid-session backgrounding is a supported flow, so an unbounded value would let a long
    /// background stretch inflate the logged duration - which would drift Default Duration learning's
    /// EWMA (US-F04) and `totalMinutesExercised` upward. The session was fit to ±1 min of
    /// `requestedMinutes`, so a completed session cannot meaningfully have taken longer than that; the
    /// cap bounds backgrounding inflation while a bail-early stays under the cap.
    private func completedDurationMinutes() -> Int {
        let end = finishedAt ?? now()
        let raw = Int((Double(elapsed(asOf: end)) / 60.0).rounded())
        return max(1, min(raw, workout.requestedMinutes))
    }

    /// Fire the completion recording once, at the `finish()` transition (US-L01). Fire-and-forget and
    /// best-effort: the UI renders the celebration immediately and never awaits the write; a nil
    /// service/user (previews) records nothing. Chained behind any prior write so it lands in order.
    private func recordCompletion() {
        guard let completionService, let user, let log = completedLog else { return }
        let previous = completionTask
        completionTask = Task {
            _ = await previous?.value
            try? await completionService.recordCompletedSession(log, user: user, recentLogs: recentLogs)
        }
    }

    /// Record the user's perceived-difficulty rating for the finished session (US-L02) and persist it
    /// onto the already-written log so tomorrow's session adjusts to it via the Asymmetric Ramp
    /// (US-E05). Optional and non-blocking: it only applies once the session is complete, re-tapping a
    /// different rating simply overwrites the last, and skipping it entirely leaves the session unrated.
    /// The persist is fire-and-forget and chained *behind* the initial completion write (they target the
    /// same log id), so the rating's re-save can never be clobbered by an initial write still in flight.
    func rate(_ difficulty: PerceivedDifficulty) {
        guard isComplete else { return }
        perceivedDifficulty = difficulty
        completedLog?.perceivedDifficulty = difficulty
        recordRating(difficulty)
    }

    private func recordRating(_ difficulty: PerceivedDifficulty) {
        // Only meaningful when the completion was actually recorded (a log was written). Without a
        // service/user (previews), the rating is kept in memory for the UI but persists nothing.
        guard let completionService, user != nil, let log = completedLog else { return }
        let previous = completionTask
        completionTask = Task {
            _ = await previous?.value
            try? await completionService.recordPerceivedDifficulty(difficulty, forLog: log)
        }
    }

    // MARK: - Swap (US-K03)

    /// Whether the current exercise can be swapped: an engine and user are wired and there is an
    /// exercise on screen. The UI hides the swap control when this is false (e.g. in previews with no
    /// engine, or on the completion state).
    var canSwap: Bool {
        swapEngine != nil && user != nil && currentStep != nil
    }

    /// Swap the current exercise for a deterministic same-pillar/pattern peer (US-K03), so one
    /// movement the user can't or won't do never derails the session. Runs the engine's swap step
    /// (US-C08), which substitutes within the same pillar, pattern, difficulty band, and time budget
    /// and never duplicates a movement already in the session (including one already swapped in this
    /// session - the request is built from the *current* lineup, not the original).
    ///
    /// On `.substituted` the current slot is replaced in place: the substitute carries a fresh
    /// capacity-relative target, the original slot's rest, and the set count the engine sized it at (the
    /// slot's own unless that would push the session out of its time budget). The set counter resets to
    /// 1 - which is also what keeps a substitute with *fewer* sets than the slot the user is part-way
    /// through from stranding them past its end - and any sets already recorded for the replaced movement
    /// are discarded (the exercise is being abandoned, mirroring a skip). On `.noAlternative` the original slot stays and
    /// `noSwapAlternative` flips so the UI shows an honest "no alternative" state. A no-op once the
    /// session is complete, while a swap is already in flight, or when swap is unavailable.
    func swapCurrentExercise() async {
        guard canSwap, !isSwapping, let engine = swapEngine, let user, let step = currentStep else { return }
        isSwapping = true
        noSwapAlternative = false
        defer { isSwapping = false }

        // A swap reshapes the slot, so any lingering rest or running hold ends without firing a
        // completion cue. The *side* is deliberately not cleared here: a swap that comes back
        // `.noAlternative` leaves the original movement in place, and sending a user who has already
        // held one side back to side 1 of the movement they kept would cost them that side for nothing.
        // It is cleared below, on the substitution that actually makes it meaningless.
        endRest(fireFeedback: false)
        endHold(fireFeedback: false)

        let outcome: SwapOutcome
        do {
            outcome = try await engine.swapExercise(
                step.prescription,
                in: snapshotForSwap(),
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy
            )
        } catch {
            // An unexpected engine failure leaves the original slot untouched; the user can retry.
            return
        }

        // If the user advanced off this exercise or finished the session during the await (Complete set
        // / Skip stay tappable, and finishing the final exercise leaves currentStepIndex unchanged), the
        // swap result is stale - discard it entirely rather than relocating it, so it can never reset
        // another exercise's set counter, resurrect an already-passed slot, or overwrite the completed
        // final exercise after the session ended.
        guard !isComplete, steps.indices.contains(currentStepIndex), steps[currentStepIndex].id == step.id else { return }

        switch outcome {
        case .substituted(let substitute):
            let previous = steps[currentStepIndex]
            completedSets.removeValue(forKey: previous.id)
            skippedStepIDs.remove(previous.id)
            steps[currentStepIndex] = Step(
                id: substitute.id,
                blockTitle: previous.blockTitle,
                blockCategory: previous.blockCategory,
                prescription: substitute,
                position: previous.position,
                total: previous.total
            )
            currentSet = 1
            // A different movement means a different set of legs: the side the user was owed on the
            // movement they just replaced does not carry over to the one that replaced it - and
            // neither does any leg started while the swap was in flight, which would otherwise run
            // its countdown out against the substitute and record a set that was never performed.
            resetHold()
            // The lineup changed - persist so a resume after a swap restores the substitute, not the
            // movement the user replaced.
            persist()
        case .noAlternative:
            noSwapAlternative = true
        }
    }

    /// A snapshot of the session as it stands now - every current step's prescription, regrouped into
    /// the blocks the steps came from - so the swap step's duplicate check sees the exercises actually
    /// in play (including earlier swaps) rather than the original lineup, and still sees which *block*
    /// the slot being replaced belongs to. The block matters: `ExerciseSwap` may move a set count to
    /// keep a substitute inside the slot's time budget, and only on the blocks the assembler itself
    /// would adjust - never the warm-up or the cooldown. Steps are already in block order, so
    /// consecutive steps sharing a block fold back into one; the shape metadata is carried through
    /// unchanged.
    private func snapshotForSwap() -> Workout {
        var blocks: [WorkoutBlock] = []
        for step in steps {
            if let last = blocks.last, last.title == step.blockTitle, last.category == step.blockCategory {
                blocks[blocks.count - 1] = WorkoutBlock(
                    id: last.id,
                    title: last.title,
                    category: last.category,
                    exercises: last.exercises + [step.prescription]
                )
            } else {
                blocks.append(
                    WorkoutBlock(
                        id: UUID(),
                        title: step.blockTitle,
                        category: step.blockCategory,
                        exercises: [step.prescription]
                    )
                )
            }
        }
        return Workout(
            id: workout.id,
            createdAt: workout.createdAt,
            shape: workout.shape,
            focusPillar: workout.focusPillar,
            requestedMinutes: workout.requestedMinutes,
            wasReturn: workout.wasReturn,
            blocks: blocks
        )
    }

    // MARK: - Rest timer (US-K02)

    /// Whether the active rest is paused (the app is backgrounded). Distinct from `isResting`, which
    /// stays true across a pause so the overlay remains up.
    var isRestPaused: Bool { rest?.isPaused ?? false }

    /// Seconds left on the running rest, counted down from `restTotalSeconds` to zero, as of `date`.
    /// Zero when no rest is active; while paused it holds the captured remaining value. Pure over the
    /// clock so the view's per-second timeline reads it cheaply and tests advance time deterministically.
    func restRemaining(asOf date: Date) -> Int { rest?.remaining(asOf: date) ?? 0 }

    /// Begin a rest period of `seconds`, scheduled against the injected clock. A non-positive rest
    /// (a prescription with no configured rest) opens no overlay, so the next set shows immediately.
    func startRest(seconds: Int) {
        guard seconds > 0 else { return }
        rest = Countdown(seconds: seconds, from: now())
    }

    /// End the rest and fire the completion cue exactly once, but only if the running rest has reached
    /// zero. Idempotent and safe to call every tick from the view's timeline (a paused or unfinished
    /// rest is left untouched), so the auto-advance and haptic fire once at the right instant.
    func completeRestIfElapsed(asOf date: Date) {
        guard rest?.hasElapsed(asOf: date) == true else { return }
        endRest(fireFeedback: true)
        persist()
    }

    /// Skip the remaining rest and reveal the next set immediately, without firing the completion cue
    /// (the user chose to move on). A no-op when no rest is active.
    func skipRest() {
        guard isResting else { return }
        endRest(fireFeedback: false)
        persist()
    }

    /// Add `seconds` to the running rest, extending both the deadline (or the paused remainder) and
    /// the total the progress ring measures against. A no-op when no rest is active.
    func extendRest(by seconds: Int = ActiveSessionViewModel.restExtension) {
        guard isResting, seconds > 0 else { return }
        rest?.extend(by: seconds)
        persist()
    }

    /// Pause the running rest (the app is backgrounding), capturing the remaining seconds so the
    /// countdown freezes instead of blowing past while the user is away. A no-op if not running.
    /// The paused remainder is persisted, so a rest that was mid-countdown when the app was killed
    /// resumes from exactly where it stopped after a relaunch (US-K04).
    func pauseRest(asOf date: Date) {
        guard isResting, !isRestPaused else { return }
        rest?.pause(asOf: date)
        persist()
    }

    /// Resume a paused rest (the app is foregrounding again), rescheduling the deadline from the
    /// captured remainder. A no-op if not currently paused.
    func resumeRest(asOf date: Date) {
        guard isRestPaused else { return }
        rest?.resume(asOf: date)
        persist()
    }

    private func endRest(fireFeedback: Bool) {
        guard isResting else { return }
        rest = nil
        if fireFeedback { feedback.restDidComplete() }
    }

    // MARK: - Hold timer (US-O03)

    /// The hold prescribed for one side of the current exercise, or `nil` when the current step is not
    /// a timed movement (rep-based, complete, or a hold carrying no usable duration). This is what
    /// gates the whole Hold Timer: a `nil` here means the player shows the unchanged manual set tracker.
    var holdSecondsPerSide: Int? {
        guard let step = currentStep,
              step.prescription.exercise.isHold,
              let seconds = step.prescription.durationSeconds,
              seconds > 0
        else { return nil }
        return seconds
    }

    /// How many legs one set of the current exercise is - one per side, so two for a per-side movement.
    /// Read through `Exercise.sidesPerSet`, the same field the engine's timing model charges against,
    /// so the timer cannot ask for less work than the session was planned around.
    var holdSidesPerSet: Int { currentStep?.prescription.exercise.sidesPerSet ?? 1 }

    /// Whether the user can start a hold leg right now: there is a timed exercise on screen and no
    /// rest, hold, swap, or completion in the way. A swap in flight is what the movement on screen is
    /// about to stop being, so a leg started against it would be timing a prescription the user is
    /// already replacing.
    var canStartHold: Bool {
        !isComplete && !isResting && !isHolding && !isSwapping && holdSecondsPerSide != nil
    }

    /// Whether the running hold is paused (the app is backgrounded). Distinct from `isHolding`, which
    /// stays true across a pause so the countdown stays on screen.
    var isHoldPaused: Bool { hold?.isPaused ?? false }

    /// Seconds left on the running hold leg, counted down from `holdTotalSeconds` to zero, as of
    /// `date`. Zero when no leg is running; while paused it holds the captured remainder. Pure over
    /// the injected clock, so the view's ticker reads it cheaply and tests drive it without real time.
    func holdRemaining(asOf date: Date) -> Int { hold?.remaining(asOf: date) ?? 0 }

    /// Begin the current side's hold, scheduled against the injected clock. A no-op when a hold cannot
    /// start (rep-based exercise, rest in force, one already running).
    func startHold() {
        guard canStartHold, let seconds = holdSecondsPerSide else { return }
        hold = Countdown(seconds: seconds, from: now())
    }

    /// End the hold leg at zero, firing the completion cue exactly once. On the last side that also
    /// records the set and opens the rest (US-K02), so a timed exercise advances without the user
    /// touching the screen; on an earlier side it parks on the next side, where the tap to start it is
    /// the user's own time to change position. Idempotent and safe to call every tick from the view's
    /// ticker (a paused or unfinished leg is left untouched), so the cue fires once at the right instant
    /// and never per-tick.
    func completeHoldIfElapsed(asOf date: Date) {
        guard hold?.hasElapsed(asOf: date) == true else { return }
        let sides = holdSidesPerSet
        let finishedSide = holdSide
        endHold(fireFeedback: true)
        if finishedSide < sides {
            holdSide = finishedSide + 1
            persist()
        } else {
            // Records the set and starts the rest; `completeSet` resets the side back to 1 for the next.
            completeSet()
        }
    }

    /// Abandon the running hold leg without recording anything and without firing the cue - the user
    /// stopped early. The side is kept, so they can re-start the same leg. A no-op when none is running.
    func cancelHold() {
        guard isHolding else { return }
        endHold(fireFeedback: false)
    }

    /// Pause the running hold while the app is away, so the countdown freezes rather than blowing past
    /// and its cue cannot fire at a screen nobody is looking at. A no-op if not running.
    ///
    /// This is an in-session pause only: a leg is never written to disk, so it does not survive the
    /// player being torn down (see `init(state:)`). What it covers is the interruption the user is still
    /// present for - a notification banner, Control Centre, a glance at another app - after which they
    /// come back to the same leg with the same time left.
    func pauseHold(asOf date: Date) {
        guard isHolding, !isHoldPaused else { return }
        hold?.pause(asOf: date)
    }

    /// Resume a paused hold (the app is foregrounding again), rescheduling from the captured remainder.
    /// A no-op if not currently paused.
    func resumeHold(asOf date: Date) {
        guard isHoldPaused else { return }
        hold?.resume(asOf: date)
    }

    private func endHold(fireFeedback: Bool) {
        guard isHolding else { return }
        hold = nil
        if fireFeedback { feedback.restDidComplete() }
    }

    /// Clear the hold entirely - the running leg *and* the side the user is part-way through. This is
    /// what every move off the current set does (completing it, skipping the exercise, swapping it),
    /// so a fresh set always opens on side 1.
    private func resetHold() {
        endHold(fireFeedback: false)
        holdSide = 1
    }

    // MARK: - Private

    private func recordSet(for prescription: PrescribedExercise) {
        let performed = CompletedSet(reps: prescription.reps, durationSeconds: prescription.durationSeconds)
        completedSets[prescription.id, default: []].append(performed)
    }

    private func advanceExercise() {
        currentSet = 1
        // A fresh exercise starts with no "no alternative" notice - that verdict was about the slot
        // the user just left.
        noSwapAlternative = false
        if currentStepIndex + 1 < steps.count {
            currentStepIndex += 1
        } else {
            finish()
        }
    }

    private func finish() {
        guard !isComplete else { return }
        isComplete = true
        finishedAt = now()
        // Build the durable log once here (stable id) so a rating given on the completion screen (US-L02)
        // updates this same record. Then record the completed session (US-L01) at the completion
        // transition - the single point every finishing path (last set, final skip, a swap that finishes
        // mid-flight) routes through - so the win is durable even if the user quits on the completion screen.
        completedLog = buildCompletionLog()
        recordCompletion()
    }

    // MARK: - Lifecycle telemetry (US-T10)

    /// Emit the `session_completed` terminal event as the player is dismissed, when - and only when -
    /// the session actually completed. `ActiveSessionView.close()` routes every exit through here
    /// (US-K04), and the one-shot guard makes a repeated dismiss a no-op, so `session_completed` never
    /// double-fires.
    ///
    /// A dismiss that leaves the session *resumable* is a PAUSE, not an abandonment (US-T10 refinement
    /// of the AC's literal "emit at dismiss-with-completed==false"): the physical session lives on in
    /// the store and can still be resumed and completed, so emitting `session_abandoned` here would let
    /// one physical session emit *both* an abandon (on the pause) and a completion (after the resume),
    /// double-counting the >=80% completion metric. Abandonment therefore fires on **true give-up** of
    /// a resumable session instead - an explicit Discard, or an overwrite by a fresh Start - both owned
    /// by `ReadyViewModel`, which still holds the persisted snapshot after this player is gone. The net
    /// invariant across the full resume path is one terminal event per physical session (completed xor
    /// abandoned), never both and never neither-when-an-outcome-occurred.
    ///
    /// `session_completed` is emitted *here*, at dismissal, rather than at the `finish()` transition,
    /// so it carries the perceived-difficulty rating the user gives on the completion screen - which
    /// `finish()` cannot have, because `rate()` only runs after the session is already complete
    /// (US-T10 decision, Option B). It reads all four properties off the completion log built at
    /// `finish()` (`perceived_difficulty` omitted when the user left the session unrated, since the
    /// bag carries no null).
    ///
    /// Accepted tradeoff (US-T10 decision): a session the user finishes but force-quits from the
    /// celebration screen *before* tapping Done emits no `session_completed`, even though its
    /// `WorkoutLog` still persists - a known, rare blind spot in the >=80% session-completion-rate
    /// metric, recorded here and in `docs/test-coverage.md` rather than left silent.
    func recordSessionEnd() {
        guard !hasEmittedTerminalEvent else { return }
        // Only a completed session emits a terminal event from the player; a resumable pause emits
        // nothing (its abandonment, if it ever comes, fires from the give-up path in ReadyViewModel).
        guard isComplete, let log = completedLog else { return }
        hasEmittedTerminalEvent = true
        var properties: [String: AnalyticsValue] = [
            "requested_minutes": .int(log.requestedMinutes),
            "completed_minutes": .int(log.durationMinutes),
            "was_return": .bool(log.wasReturn)
        ]
        if let difficulty = log.perceivedDifficulty {
            properties["perceived_difficulty"] = .string(difficulty.rawValue)
        }
        emit(.sessionCompleted, properties: properties)
    }

    /// The current millisecond client timestamp off the injected clock - the same encoding
    /// `AnalyticsEvent` carries everywhere, with no raw `Date()` read, so emissions stay deterministic
    /// under a test clock.
    private func timestampMs() -> Int {
        Int(now().timeIntervalSince1970 * 1000)
    }

    /// Hand one telemetry event to the sink, fire-and-forget. A `nil` sink (previews / tests that do
    /// not exercise the funnel) simply skips it. Emissions are chained behind the previous one so they
    /// land in call order - `session_started` before either terminal event - even though each is
    /// launched off the calling path and never awaited by the UI.
    private func emit(_ name: AnalyticsEventName, properties: [String: AnalyticsValue] = [:]) {
        guard let analytics else { return }
        let event = AnalyticsEvent(name: name, timestampMs: timestampMs(), properties: properties)
        let previous = analyticsTask
        analyticsTask = Task { _ = await previous?.value; await analytics.record(event) }
    }

    // MARK: - Snapshot & persistence (US-K04)

    /// A snapshot of the current play state for persistence - the current lineup (reflecting any
    /// swap), the position, what has been done, the session-clock origin, the rest timer, and the side
    /// a part-done per-side hold left the user on. Pure over the view model's state; timing is captured
    /// as absolute instants (`startedAt`, the rest `deadline`), so restoring at an unknown-later moment
    /// recomputes elapsed time and a running rest countdown correctly. The hold is the exception, and
    /// deliberately so: only its side is carried, never a running leg (US-O03).
    func snapshot() -> ActiveSessionState {
        let slots = steps.map {
            ActiveSessionState.Slot(blockTitle: $0.blockTitle, blockCategory: $0.blockCategory, prescription: $0.prescription)
        }
        let rest: ActiveSessionState.Rest? = self.rest.map {
            ActiveSessionState.Rest(totalSeconds: $0.total, deadline: $0.deadline, remainingWhenPaused: $0.remainingWhenPaused)
        }
        // Only the side is captured, never the running leg (US-O03): a hold does not survive the player
        // being torn down, so there is nothing else about it worth carrying. What a resume must not lose
        // is that a per-side set is half done - otherwise the user repeats a side and works three legs
        // of a two-leg set.
        let hold: ActiveSessionState.Hold? = holdSide > 1 ? ActiveSessionState.Hold(side: holdSide) : nil
        return ActiveSessionState(
            workout: workout,
            slots: slots,
            currentStepIndex: currentStepIndex,
            currentSet: currentSet,
            completedSets: completedSets,
            skippedStepIDs: skippedStepIDs,
            startedAt: startedAt,
            rest: rest,
            hold: hold,
            // Captured here, at each meaningful change while the session is active, so a later
            // give-up (Discard / overwrite) reports the minutes actually exercised as of the last
            // active moment (US-T10) rather than wall-clock elapsed measured at the give-up instant.
            exercisedMinutes: completedDurationMinutes()
        )
    }

    /// Persist the current play state, or clear it once the session is complete (US-K04). Writes are
    /// chained behind the previous one so they land in call order even though each is fire-and-forget,
    /// and the whole thing is a no-op when no store/userId is wired (previews). Best-effort: a failed
    /// write never disrupts the session, and the UI never awaits it.
    private func persist() {
        guard let store, let userId else { return }
        let previous = persistenceTask
        if isComplete {
            // A completed session is no longer resumable, so it is cleared rather than saved.
            persistenceTask = Task { _ = await previous?.value; try? await store.clear(for: userId) }
        } else {
            let snapshot = snapshot()
            persistenceTask = Task { _ = await previous?.value; try? await store.save(snapshot, for: userId) }
        }
    }

    /// Rebuild the ordered step list from a lineup snapshot, tagging each slot with its 1-based
    /// overall position so the player can render block context and "N of M" progress. Position and
    /// total are rederived from the slot order rather than stored, so they always agree with the list.
    private static func steps(from slots: [ActiveSessionState.Slot]) -> [Step] {
        let total = slots.count
        return slots.enumerated().map { index, slot in
            Step(
                id: slot.prescription.id,
                blockTitle: slot.blockTitle,
                blockCategory: slot.blockCategory,
                prescription: slot.prescription,
                position: index + 1,
                total: total
            )
        }
    }
}
