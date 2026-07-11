import Foundation
import Observation

/// Backs the active-session player (US-K01) - the focused screen that walks the user through a
/// generated `Workout` one exercise at a time so they never lose their place mid-session.
///
/// The view model flattens the session's blocks into a single ordered list of `Step`s (warm-up ->
/// training -> cooldown, in the engine's order) and tracks exactly where the user is: the current
/// step, the set they are on, and the elapsed wall-clock time. Completing a set advances the
/// session and records what was done toward the eventual `WorkoutLog` (US-L01 writes it; US-L02
/// collects the perceived-difficulty rating). After each set a rest timer (US-K02) counts down the
/// prescription's `restSeconds` and, when it elapses, fires an accessible haptic/audio cue - the
/// in-session swap (US-K03) and background/resume (US-K04) build on this same view model.
///
/// The rest timer is derived from the same injected clock as elapsed time, but with pause semantics:
/// it is scheduled against a wall-clock `restDeadline`, and backgrounding the app pauses it (capturing
/// the remaining seconds) so the countdown never blows past while the user is away. All rest logic is
/// pure over the injected clock, so the tests drive the countdown, skip, extend, pause, and resume
/// without real time passing.
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

    init(
        workout: Workout,
        now: @escaping () -> Date = { Date() },
        feedback: RestTimerFeedback = SystemRestTimerFeedback()
    ) {
        self.workout = workout
        self.now = now
        self.feedback = feedback
        let flattened = Self.flatten(workout)
        self.steps = flattened
        self.isComplete = flattened.isEmpty
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
    /// original start, so elapsed time never resets. US-K04 will persist `startedAt` across relaunch.
    func start() {
        guard startedAt == nil else { return }
        startedAt = now()
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
    }

    /// Skip the remaining rest and reveal the next set immediately, without firing the completion cue
    /// (the user chose to move on). A no-op when no rest is active.
    func skipRest() {
        endRest(fireFeedback: false)
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
    }

    /// Pause the running rest (the app is backgrounding), capturing the remaining seconds so the
    /// countdown freezes instead of blowing past while the user is away. A no-op if not running.
    func pauseRest(asOf date: Date) {
        guard isResting, restRemainingWhenPaused == nil else { return }
        restRemainingWhenPaused = restRemaining(asOf: date)
        restDeadline = nil
    }

    /// Resume a paused rest (the app is foregrounding again), rescheduling the deadline from the
    /// captured remainder. A no-op if not currently paused.
    func resumeRest(asOf date: Date) {
        guard isResting, let remaining = restRemainingWhenPaused else { return }
        restDeadline = date.addingTimeInterval(TimeInterval(remaining))
        restRemainingWhenPaused = nil
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
    }

    /// Flatten the session's blocks into a single ordered list, tagging each exercise with its block
    /// and its overall position so the player can render block context and "N of M" progress.
    private static func flatten(_ workout: Workout) -> [Step] {
        let pairs = workout.blocks.flatMap { block in
            block.exercises.map { (block, $0) }
        }
        let total = pairs.count
        return pairs.enumerated().map { index, pair in
            let (block, prescription) = pair
            return Step(
                id: prescription.id,
                blockTitle: block.title,
                blockCategory: block.category,
                prescription: prescription,
                position: index + 1,
                total: total
            )
        }
    }
}
