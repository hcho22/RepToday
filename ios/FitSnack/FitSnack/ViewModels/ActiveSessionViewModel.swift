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
/// it is scheduled against a wall-clock `restDeadline`, and backgrounding the app pauses it (capturing
/// the remaining seconds) so the countdown never blows past while the user is away. All rest logic is
/// pure over the injected clock, so the tests drive the countdown, skip, extend, pause, and resume
/// without real time passing.
///
/// The in-session swap (US-K03) lets the user replace the current exercise with a deterministic
/// same-pillar/pattern peer so one movement they can't or won't do never derails the session. It
/// calls the engine's swap step (US-C08, `ExerciseSwap.swap` behind `WorkoutEngineProtocol`), which
/// substitutes within the same pillar, pattern, difficulty band, and time budget and never duplicates
/// a movement already in the session; when no safe in-budget peer exists it returns `.noAlternative`
/// and the original slot stays. The swap dependencies are injected and optional, so the player still
/// constructs (e.g. in previews) without an engine - swap simply stays unavailable then.
///
/// Elapsed time is derived from an injected clock rather than an internal ticking counter: the view
/// re-reads `elapsed(asOf:)` once a second via a `TimelineView`, so the value is accurate, resilient
/// to backgrounding, and a pure function the tests can drive without real time passing.
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
    /// and freezes the elapsed clock; the rich post-session summary and log write are US-L01.
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

    /// True while a rest period is in force between sets - running or paused. The player shows the
    /// rest overlay while this holds and hides it (revealing the already-advanced next set) once the
    /// rest ends by countdown, skip, or the final set.
    private(set) var isResting = false

    /// The full length of the current rest in seconds, including any extensions - the denominator for
    /// the rest progress ring.
    private(set) var restTotalSeconds = 0

    /// The wall-clock instant the running rest is scheduled to finish. `nil` while paused (the app is
    /// backgrounded) or when no rest is active.
    private var restDeadline: Date?

    /// The remaining seconds captured when the rest was paused (backgrounding). `nil` while running.
    private var restRemainingWhenPaused: Int?

    private let now: () -> Date
    private let feedback: RestTimerFeedback

    /// The engine seam the swap runs through (US-C08). `nil` when the player is built without an
    /// engine (previews), which simply leaves swap unavailable.
    private let swapEngine: (any WorkoutEngineProtocol)?
    /// The user and recent logs the swap step needs to filter and size a substitute. Captured at
    /// construction from the Ready Screen's already-loaded state, so a swap adds no fetch.
    private let user: User?
    private let recentLogs: [WorkoutLog]

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

    /// The fire-and-forget completion write launched at `finish()`, exposed only so tests can await
    /// the recording settling. The UI never awaits it: like persistence, the write is best-effort and
    /// the player never stalls on it.
    private(set) var completionTask: Task<Void, Never>?

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
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        feedback: RestTimerFeedback = SystemRestTimerFeedback()
    ) {
        self.workout = state.workout
        self.swapEngine = swapEngine
        self.user = user
        self.recentLogs = recentLogs
        self.store = store
        self.userId = userId
        self.completionService = completionService
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
        if let rest = state.rest {
            self.isResting = true
            self.restTotalSeconds = rest.totalSeconds
            self.restDeadline = rest.deadline
            self.restRemainingWhenPaused = rest.remainingWhenPaused
        }
    }

    /// Fresh-start convenience: play `workout` from its first set, with no completed work yet.
    convenience init(
        workout: Workout,
        swapEngine: (any WorkoutEngineProtocol)? = nil,
        user: User? = nil,
        recentLogs: [WorkoutLog] = [],
        store: (any ActiveSessionStore)? = nil,
        userId: String? = nil,
        completionService: (any SessionCompletionServiceProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        feedback: RestTimerFeedback = SystemRestTimerFeedback()
    ) {
        self.init(
            state: ActiveSessionState(fresh: workout),
            swapEngine: swapEngine,
            user: user,
            recentLogs: recentLogs,
            store: store,
            userId: userId,
            completionService: completionService,
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
        // Skipping moves on immediately, so any rest in force is dropped without firing its cue.
        endRest(fireFeedback: false)
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

    /// The `WorkoutLog` to write for the finished session (US-L01): what was requested vs. actually
    /// completed, the shape/focus/return flags copied straight off the played `Workout` (never
    /// re-derived), and the per-exercise completed/skipped rows. `nil` unless the session is complete.
    /// The perceived-difficulty rating is `nil` here; US-L02 collects it on the completion screen.
    func completionLog() -> WorkoutLog? {
        guard isComplete else { return nil }
        return WorkoutLog(
            id: UUID(),
            workoutId: workout.id,
            completedAt: finishedAt ?? now(),
            requestedMinutes: workout.requestedMinutes,
            durationMinutes: completedDurationMinutes(),
            wasReturn: workout.wasReturn,
            shape: workout.shape,
            focusPillar: workout.focusPillar,
            perceivedDifficulty: nil,
            exercises: loggedExercises()
        )
    }

    /// Whole minutes actually exercised, wall-clock from start to finish, floored at 1 so a genuinely
    /// completed session always records a positive duration. This is the completed - not requested -
    /// duration Default Duration learning (US-F04) and the Consistency Score (US-H01) read.
    private func completedDurationMinutes() -> Int {
        let end = finishedAt ?? now()
        return max(1, Int((Double(elapsed(asOf: end)) / 60.0).rounded()))
    }

    /// Fire the completion recording once, at the `finish()` transition (US-L01). Fire-and-forget and
    /// best-effort: the UI renders the celebration immediately and never awaits the write; a nil
    /// service/user (previews) records nothing. Chained behind any prior write so it lands in order.
    private func recordCompletion() {
        guard let completionService, let user, let log = completionLog() else { return }
        let previous = completionTask
        completionTask = Task {
            _ = await previous?.value
            try? await completionService.recordCompletedSession(log, user: user, recentLogs: recentLogs)
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
    /// capacity-relative target with the original slot's set count and rest preserved, the set counter
    /// resets to 1, and any sets already recorded for the replaced movement are discarded (the
    /// exercise is being abandoned, mirroring a skip). On `.noAlternative` the original slot stays and
    /// `noSwapAlternative` flips so the UI shows an honest "no alternative" state. A no-op once the
    /// session is complete, while a swap is already in flight, or when swap is unavailable.
    func swapCurrentExercise() async {
        guard canSwap, !isSwapping, let engine = swapEngine, let user, let step = currentStep else { return }
        isSwapping = true
        noSwapAlternative = false
        defer { isSwapping = false }

        // A swap reshapes the slot, so any lingering rest ends without firing its completion cue.
        endRest(fireFeedback: false)

        let outcome: SwapOutcome
        do {
            outcome = try await engine.swapExercise(
                step.prescription,
                in: snapshotForSwap(),
                user: user,
                recentLogs: recentLogs
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
            // The lineup changed - persist so a resume after a swap restores the substitute, not the
            // movement the user replaced.
            persist()
        case .noAlternative:
            noSwapAlternative = true
        }
    }

    /// A snapshot of the session as it stands now - every current step's prescription in one block -
    /// so the swap step's duplicate check sees the exercises actually in play (including earlier
    /// swaps), not the original lineup. Only the flat exercise set matters to `ExerciseSwap`; the
    /// block grouping is collapsed and the shape metadata carried through unchanged.
    private func snapshotForSwap() -> Workout {
        let block = WorkoutBlock(
            id: workout.id,
            title: "Session",
            category: .strength,
            exercises: steps.map(\.prescription)
        )
        return Workout(
            id: workout.id,
            createdAt: workout.createdAt,
            shape: workout.shape,
            focusPillar: workout.focusPillar,
            requestedMinutes: workout.requestedMinutes,
            wasReturn: workout.wasReturn,
            blocks: [block]
        )
    }

    // MARK: - Rest timer (US-K02)

    /// Whether the active rest is paused (the app is backgrounded). Distinct from `isResting`, which
    /// stays true across a pause so the overlay remains up.
    var isRestPaused: Bool { restRemainingWhenPaused != nil }

    /// Seconds left on the running rest, counted down from `restTotalSeconds` to zero, as of `date`.
    /// Zero when no rest is active; while paused it holds the captured remaining value. Pure over the
    /// clock so the view's per-second timeline reads it cheaply and tests advance time deterministically.
    func restRemaining(asOf date: Date) -> Int {
        guard isResting else { return 0 }
        if let paused = restRemainingWhenPaused { return paused }
        guard let deadline = restDeadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(date))))
    }

    /// Begin a rest period of `seconds`, scheduled against the injected clock. A non-positive rest
    /// (a prescription with no configured rest) opens no overlay, so the next set shows immediately.
    func startRest(seconds: Int) {
        guard seconds > 0 else { return }
        restTotalSeconds = seconds
        restDeadline = now().addingTimeInterval(TimeInterval(seconds))
        restRemainingWhenPaused = nil
        isResting = true
    }

    /// End the rest and fire the completion cue exactly once, but only if the running rest has reached
    /// zero. Idempotent and safe to call every tick from the view's timeline (a paused or unfinished
    /// rest is left untouched), so the auto-advance and haptic fire once at the right instant.
    func completeRestIfElapsed(asOf date: Date) {
        guard isResting, restRemainingWhenPaused == nil, restRemaining(asOf: date) == 0 else { return }
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
        restTotalSeconds += seconds
        if let paused = restRemainingWhenPaused {
            restRemainingWhenPaused = paused + seconds
        } else if let deadline = restDeadline {
            restDeadline = deadline.addingTimeInterval(TimeInterval(seconds))
        }
        persist()
    }

    /// Pause the running rest (the app is backgrounding), capturing the remaining seconds so the
    /// countdown freezes instead of blowing past while the user is away. A no-op if not running.
    /// The paused remainder is persisted, so a rest that was mid-countdown when the app was killed
    /// resumes from exactly where it stopped after a relaunch (US-K04).
    func pauseRest(asOf date: Date) {
        guard isResting, restRemainingWhenPaused == nil else { return }
        restRemainingWhenPaused = restRemaining(asOf: date)
        restDeadline = nil
        persist()
    }

    /// Resume a paused rest (the app is foregrounding again), rescheduling the deadline from the
    /// captured remainder. A no-op if not currently paused.
    func resumeRest(asOf date: Date) {
        guard isResting, let remaining = restRemainingWhenPaused else { return }
        restDeadline = date.addingTimeInterval(TimeInterval(remaining))
        restRemainingWhenPaused = nil
        persist()
    }

    private func endRest(fireFeedback: Bool) {
        guard isResting else { return }
        isResting = false
        restDeadline = nil
        restRemainingWhenPaused = nil
        restTotalSeconds = 0
        if fireFeedback { feedback.restDidComplete() }
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
        // Record the completed session (US-L01) at the completion transition - the single point every
        // finishing path (last set, final skip, a swap that finishes mid-flight) routes through - so
        // the win is durable even if the user quits on the completion screen.
        recordCompletion()
    }

    // MARK: - Snapshot & persistence (US-K04)

    /// A snapshot of the current play state for persistence - the current lineup (reflecting any
    /// swap), the position, what has been done, the session-clock origin, and the rest timer. Pure
    /// over the view model's state; timing is captured as absolute instants (`startedAt`, the rest
    /// `deadline`), so restoring at an unknown-later moment recomputes elapsed time and a running
    /// rest countdown correctly.
    func snapshot() -> ActiveSessionState {
        let slots = steps.map {
            ActiveSessionState.Slot(blockTitle: $0.blockTitle, blockCategory: $0.blockCategory, prescription: $0.prescription)
        }
        let rest: ActiveSessionState.Rest? = isResting
            ? ActiveSessionState.Rest(totalSeconds: restTotalSeconds, deadline: restDeadline, remainingWhenPaused: restRemainingWhenPaused)
            : nil
        return ActiveSessionState(
            workout: workout,
            slots: slots,
            currentStepIndex: currentStepIndex,
            currentSet: currentSet,
            completedSets: completedSets,
            skippedStepIDs: skippedStepIDs,
            startedAt: startedAt,
            rest: rest
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
