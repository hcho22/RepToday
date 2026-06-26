import Foundation

/// The generated session the user plays (US-A03).
///
/// A `Workout` is what the deterministic engine assembles: an ordered list of
/// `WorkoutBlock`s (warm-up, training blocks, optional cooldown), each holding ordered
/// `PrescribedExercise`s with concrete sets/reps/duration/rest. It is self-contained -
/// each prescription embeds its full `Exercise` - so the active-session player can render
/// it without re-resolving ids.

// MARK: - Workout

struct Workout: Codable, Equatable, Identifiable {
    var id: UUID
    var createdAt: Date
    /// The shape selected from requested minutes (single-focus vs blend).
    var shape: SessionShape
    /// Set for single-focus sessions; nil for blends that span both pillars.
    var focusPillar: Pillar?
    /// The minutes the user asked for; the assembled session lands within ±1 of this.
    var requestedMinutes: Int
    /// Ordered blocks; the first is always a warm-up, and a cooldown closes sessions over 10 min.
    var blocks: [WorkoutBlock]
}

// MARK: - WorkoutBlock

/// A titled, ordered group of prescribed exercises within a session (e.g. "Warm-up",
/// "Strength", "Movement Practice", "Cooldown").
struct WorkoutBlock: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    /// The role this block plays in the session structure.
    var category: ExerciseCategory
    var exercises: [PrescribedExercise]
}

// MARK: - PrescribedExercise

/// One exercise as prescribed for this session: the movement plus the capacity-relative
/// targets the engine computed (Adaptive Overload). Rep-based movements use `reps`; holds
/// use `durationSeconds`.
struct PrescribedExercise: Codable, Equatable, Identifiable {
    var id: UUID
    /// The full movement, embedded so the player needs no lookup.
    var exercise: Exercise
    var sets: Int
    /// Target reps per set (rep-based movements).
    var reps: Int?
    /// Target hold duration per set in seconds (holds).
    var durationSeconds: Int?
    /// Rest between sets in seconds.
    var restSeconds: Int
}
