import Foundation

/// The record written when a session finishes (US-A03), mirroring v5 section 2.3.
///
/// `WorkoutLog` is the signal the engine reads back: Adaptive Overload uses
/// `completedSets` + `perceivedDifficulty` to set the next targets, pillar/pattern
/// staleness comes from `completedAt`, and the Consistency Score counts it as a show-up.
/// Persisted to CoreData as `CDWorkoutLog` (US-A04).

// MARK: - WorkoutLog

struct WorkoutLog: Codable, Equatable, Identifiable {
    /// This log's own identity.
    var id: UUID
    /// The `Workout` this log records.
    var workoutId: UUID
    var completedAt: Date
    /// The minutes the Ready Screen offered or the user set for this session (US-D02).
    /// Paired with `durationMinutes` (requested vs. actually completed): the gap between the
    /// two is how Default Duration learning and the Disengagement signal see shrinking sessions.
    var requestedMinutes: Int
    /// The actually-completed minutes exercised; a 5-minute session still counts as a full
    /// show-up. This - not `requestedMinutes` - is what feeds `duration.completedDurationEWMA`
    /// so the learned Default Duration tracks what the user finishes, never what they asked for.
    var durationMinutes: Int
    /// True when this session was served as a Return after a gap (US-D02/US-E06). A Return is
    /// celebrated and never penalizes the Consistency Score; the readjustment for lost time
    /// lives in the following Re-entry Ramp, never in the Return itself. Defaults to `false`.
    var wasReturn: Bool = false
    var shape: SessionShape
    /// Set for single-focus sessions.
    var focusPillar: Pillar?
    /// How the session felt; feeds Adaptive Overload within one cycle.
    var perceivedDifficulty: PerceivedDifficulty?
    var exercises: [LoggedExercise]
}

// MARK: - LoggedExercise

/// Per-exercise outcome within a logged session. Carries `pillar`/`movementPattern`
/// inline so staleness can be computed without re-resolving the exercise.
struct LoggedExercise: Codable, Equatable, Identifiable {
    var id: UUID
    var exerciseId: String
    var pillar: Pillar
    var movementPattern: MovementPattern
    var completedSets: [CompletedSet]
    /// True when the user skipped this exercise; repeated skips drop it from the pool.
    var skipped: Bool
    /// The completion screen's post-session "couldn't finish" mark (ADR-0011): after rating a session
    /// "too hard" the user taps the moves they could not finish. `true` steps this move back and keeps
    /// this session from counting toward its advancement; `nil` (unmarked, and every log written before
    /// the mark existed) leaves the session's rating to decide (`WorkoutLog.stepsBack(_:)`).
    /// One flag per move, never per set: a set still records prescribed = performed (US-CC09).
    /// Optional so older logs decode unchanged and older app versions ignore it.
    var couldNotFinish: Bool? = nil
}

extension LoggedExercise {
    /// Whether the user actually performed this exercise: not skipped, and at least one set
    /// carrying real work (`reps > 0` or `durationSeconds > 0`). The one shared definition of
    /// "performed" behind the Progress tab's worked instances and the Coach context's recent
    /// patterns, so a skipped or set-less step never reads as done work on either surface.
    var wasPerformed: Bool {
        !skipped && completedSets.contains { ($0.reps ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0 }
    }
}

extension WorkoutLog {
    /// Whether this session steps `logged` back (ADR-0011): a skip, or "too hard" on a move the user
    /// marked "couldn't finish" - or on every move when they marked none, which is what the completion
    /// screen promises ("everything eases off a little"). A "too hard" session that marked some moves
    /// leaves the others alone. The one definition behind Adaptive Overload's step back
    /// (`AdaptiveOverload.signal(for:in:)`) and `countsTowardAdvancement(_:)`.
    func stepsBack(_ logged: LoggedExercise) -> Bool {
        if logged.skipped { return true }
        guard perceivedDifficulty == .tooHard else { return false }
        return logged.couldNotFinish == true || !exercises.contains { $0.couldNotFinish == true }
    }

    /// Whether `logged` may count toward clearing a tier's advancement criteria (and a Foundation line,
    /// and so the earned Strength Phase): only when this session does not step it back. A move stepped
    /// back still recorded the target it asked for (prescribed = performed), so its sets would
    /// otherwise read as met.
    func countsTowardAdvancement(_ logged: LoggedExercise) -> Bool {
        !stepsBack(logged)
    }
}

// MARK: - CompletedSet

/// What the user actually did in one set: `reps` for rep-based movements, or
/// `durationSeconds` for holds.
struct CompletedSet: Codable, Equatable {
    var reps: Int?
    var durationSeconds: Int?
}
