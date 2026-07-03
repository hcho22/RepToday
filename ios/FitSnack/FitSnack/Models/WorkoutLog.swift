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
}

// MARK: - CompletedSet

/// What the user actually did in one set: `reps` for rep-based movements, or
/// `durationSeconds` for holds.
struct CompletedSet: Codable, Equatable {
    var reps: Int?
    var durationSeconds: Int?
}
