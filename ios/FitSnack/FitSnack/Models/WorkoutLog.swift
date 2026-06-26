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
    /// Actual minutes exercised; a 5-minute session still counts as a full show-up.
    var durationMinutes: Int
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
