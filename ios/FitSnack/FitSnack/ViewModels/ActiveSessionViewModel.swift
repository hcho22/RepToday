import Foundation
import Observation

/// Backs the active-session player (US-K01) - the focused screen that walks the user through a
/// generated `Workout` one exercise at a time so they never lose their place mid-session.
///
/// The view model flattens the session's blocks into a single ordered list of `Step`s (warm-up ->
/// training -> cooldown, in the engine's order) and tracks exactly where the user is: the current
/// step, the set they are on, and the elapsed wall-clock time. Completing a set advances the
/// session and records what was done toward the eventual `WorkoutLog` (US-L01 writes it; US-L02
/// collects the perceived-difficulty rating). This story owns the walk-through and set tracking
/// only - the rest timer (US-K02), in-session swap (US-K03), and background/resume (US-K04) build
/// on this same view model.
///
/// Elapsed time is derived from an injected clock rather than an internal ticking counter: the view
/// re-reads `elapsed(asOf:)` once a second via a `TimelineView`, so the value is accurate, resilient
/// to backgrounding, and a pure function the tests can drive without real time passing.
@Observable
final class ActiveSessionViewModel {

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

    private let now: () -> Date

    init(workout: Workout, now: @escaping () -> Date = { Date() }) {
        self.workout = workout
        self.now = now
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
    /// once the session is complete.
    func completeSet() {
        guard !isComplete, let step = currentStep else { return }
        recordSet(for: step.prescription)
        if currentSet < step.prescription.sets {
            currentSet += 1
        } else {
            advanceExercise()
        }
    }

    /// Skip the current exercise without recording any sets, marking it skipped for the eventual log,
    /// and advance to the next exercise. A no-op once complete. (Swapping to a peer instead is
    /// US-K03; this is the plain "move past it" path.)
    func skipExercise() {
        guard !isComplete, let step = currentStep else { return }
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
