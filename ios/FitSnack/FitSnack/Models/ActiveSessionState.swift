import Foundation

/// A persistable snapshot of an in-progress session (US-K04) - everything the active-session player
/// needs to restore the *exact* position after backgrounding or an app relaunch, so a text message
/// never costs the user their workout.
///
/// The snapshot captures the play state, not just the generated `Workout`: the current lineup
/// (`slots`, which reflects any in-session swap, US-K03), where the user is (`currentStepIndex` /
/// `currentSet`), what they have done so far (`completedSets` / `skippedStepIDs`), the session clock
/// origin (`startedAt`), and the rest timer (`rest`). It is a plain `Codable` value type persisted
/// whole as JSON by the `ActiveSessionStore`, keyed by the owning user's id and cleared the moment
/// the session completes or is discarded - so at most one resumable session exists per user.
///
/// Timing is stored as absolute instants (`startedAt`, `rest.deadline`) rather than remaining
/// durations, so elapsed time and a running rest countdown restore correctly across a relaunch that
/// happened at an unknown later moment. A rest that was paused on backgrounding (US-K02) instead
/// carries its frozen remainder (`rest.remainingWhenPaused`), so it resumes from where it stopped.
struct ActiveSessionState: Codable, Equatable {

    /// One playable slot in the current lineup: a prescribed exercise plus the block context the
    /// player renders around it. Position ("3 of 8") is not stored - it is the slot's index, rederived
    /// on restore - and the id is the prescription's id, so a swapped-in movement carries its own.
    struct Slot: Codable, Equatable {
        var blockTitle: String
        var blockCategory: ExerciseCategory
        var prescription: PrescribedExercise
    }

    /// The rest timer in force between sets (US-K02), or `nil` when no rest is active. `deadline` is
    /// the wall-clock instant a *running* rest finishes; `remainingWhenPaused` holds the frozen
    /// remainder while the app is backgrounded. Exactly one of the two is set for an active rest.
    struct Rest: Codable, Equatable {
        var totalSeconds: Int
        var deadline: Date?
        var remainingWhenPaused: Int?
    }

    /// The generated session, kept whole as the metadata carrier (id/shape/focusPillar/requestedMinutes/
    /// wasReturn) the eventual `WorkoutLog` and the swap step need. The play lineup is `slots`, which
    /// diverges from `workout.blocks` once the user swaps a movement.
    var workout: Workout
    /// The current, possibly-swapped lineup the player walks through, in order.
    var slots: [Slot]
    /// Index into `slots` of the exercise on screen.
    var currentStepIndex: Int
    /// The 1-based set the user is working on within the current exercise.
    var currentSet: Int
    /// What the user has completed so far, keyed by slot/prescription id (US-K01).
    var completedSets: [UUID: [CompletedSet]]
    /// Slots the user skipped, so a resumed session keeps them flagged for the eventual log.
    var skippedStepIDs: Set<UUID>
    /// When the session clock started; `nil` for a session that was snapshotted before `start()`.
    var startedAt: Date?
    /// The rest timer between sets, or `nil` when not resting.
    var rest: Rest?

    /// A fresh, not-yet-started snapshot for `workout` - the lineup flattened from its blocks with the
    /// player parked at the first set. Used so the player's fresh and resumed construction paths share
    /// one representation of the lineup.
    init(fresh workout: Workout) {
        self.workout = workout
        self.slots = workout.blocks.flatMap { block in
            block.exercises.map { Slot(blockTitle: block.title, blockCategory: block.category, prescription: $0) }
        }
        self.currentStepIndex = 0
        self.currentSet = 1
        self.completedSets = [:]
        self.skippedStepIDs = []
        self.startedAt = nil
        self.rest = nil
    }

    init(
        workout: Workout,
        slots: [Slot],
        currentStepIndex: Int,
        currentSet: Int,
        completedSets: [UUID: [CompletedSet]],
        skippedStepIDs: Set<UUID>,
        startedAt: Date?,
        rest: Rest?
    ) {
        self.workout = workout
        self.slots = slots
        self.currentStepIndex = currentStepIndex
        self.currentSet = currentSet
        self.completedSets = completedSets
        self.skippedStepIDs = skippedStepIDs
        self.startedAt = startedAt
        self.rest = rest
    }
}
