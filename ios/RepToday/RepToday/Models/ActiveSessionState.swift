import Foundation

/// A persistable snapshot of an in-progress session (US-K04) - everything the active-session player
/// needs to restore the *exact* position after backgrounding or an app relaunch, so a text message
/// never costs the user their workout.
///
/// The snapshot captures the play state, not just the generated `Workout`: the current lineup
/// (`slots`, which reflects any in-session swap, US-K03), where the user is (`currentStepIndex` /
/// `currentSet`), what they have done so far (`completedSets` / `skippedStepIDs`), the session clock
/// origin (`startedAt`), the rest timer (`rest`), and the side a part-done per-side hold left them on
/// (`hold`, US-O03). It is a plain
/// `Codable` value type persisted whole as JSON by the `ActiveSessionStore`, keyed by the owning
/// user's id and cleared the moment the session completes or is discarded - so at most one resumable
/// session exists per user.
///
/// Timing is stored as absolute instants (`startedAt`, `rest.deadline`) rather than remaining
/// durations, so elapsed time and a running rest restore correctly across a relaunch that happened at
/// an unknown later moment. A rest that was paused on backgrounding (US-K02) instead carries its
/// frozen remainder, so it resumes from where it stopped. No running hold countdown is stored at all -
/// only the side it left the user on (see `Hold`).
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

    /// How far through a per-side hold's set the user is (US-O03), or `nil` when there is nothing to
    /// carry - a rep-based exercise, a bilateral hold, or a per-side set not yet half done.
    ///
    /// A hold is counted one *side* at a time, because the engine charges a per-side movement for both
    /// sides: a set of `core_side_plank` is two 20-second legs, not one. The side is the only part of
    /// the Hold Timer that is persisted at all. The running countdown deliberately is **not**: unlike a
    /// rest, which genuinely continues while the app is away, a hold does not survive the player being
    /// torn down - the user stopped holding when they left the screen - so a resumed session restarts
    /// the leg on a deliberate tap. Carrying the side is what stops them repeating one they already did.
    struct Hold: Codable, Equatable {
        /// The 1-based side of the current set; greater than 1 only for a per-side movement mid-set.
        var side: Int
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
    /// How far through a per-side set the user is (US-O03), or `nil` when there is none. Never a
    /// running countdown - that is in-memory only.
    /// Optional and defaulted, so a snapshot written before US-O03 decodes unchanged.
    var hold: Hold?
    /// The whole minutes exercised as of the last active moment (US-T10), captured in the snapshot so
    /// a give-up emission (Discard or overwrite) can report `session_abandoned`'s `completed_minutes`
    /// off the persisted state rather than recomputing wall-clock elapsed at the give-up instant -
    /// which, for a session paused and then discarded much later, would fold the idle gap into the
    /// exercised total. Carries the player's `completedDurationMinutes` value (floored at 1, capped at
    /// `requestedMinutes`), so "completed minutes" means the same thing on both terminal events.
    /// Optional and defaulted, so a snapshot written before US-T10 decodes unchanged.
    var exercisedMinutes: Int?

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
        self.hold = nil
        self.exercisedMinutes = nil
    }

    init(
        workout: Workout,
        slots: [Slot],
        currentStepIndex: Int,
        currentSet: Int,
        completedSets: [UUID: [CompletedSet]],
        skippedStepIDs: Set<UUID>,
        startedAt: Date?,
        rest: Rest?,
        hold: Hold? = nil,
        exercisedMinutes: Int? = nil
    ) {
        self.workout = workout
        self.slots = slots
        self.currentStepIndex = currentStepIndex
        self.currentSet = currentSet
        self.completedSets = completedSets
        self.skippedStepIDs = skippedStepIDs
        self.startedAt = startedAt
        self.rest = rest
        self.hold = hold
        self.exercisedMinutes = exercisedMinutes
    }
}
