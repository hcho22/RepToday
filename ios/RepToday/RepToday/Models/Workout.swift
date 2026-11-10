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
    /// Set for single-focus sessions; nil for blends that span multiple pillars.
    var focusPillar: Pillar?
    /// The minutes the user asked for; the assembled session lands within ±1 of this.
    var requestedMinutes: Int
    /// True when the engine served this session as a Return after a gap (US-E06): the gap since
    /// the last logged session crossed the Return threshold, so the session was made easy and
    /// winnable regardless of staleness. The Return decision is made once, here at generation; the
    /// post-session flow (US-L01) copies it onto `WorkoutLog.wasReturn` (US-D02) rather than
    /// re-deriving detection at a different `asOf`. Defaults to `false` (a normal session).
    var wasReturn: Bool = false
    /// Ordered blocks; the first is always a warm-up, and a cooldown closes sessions over 10 min.
    var blocks: [WorkoutBlock]
    /// The Training Day this session trains (ADR-0012), or `nil` for a Recovery flow and for every
    /// session generated before Training Days existed. Today labels the session with it; the log
    /// derives its own Training Day from its station roles (`WorkoutLog.trainingDay`), so nothing
    /// reads this back. Optional so older snapshots decode unchanged.
    var trainingDay: TrainingDay? = nil
}

// MARK: - WorkoutBlock

/// A titled, ordered group of prescribed exercises within a session (e.g. "Warm-up",
/// "Strength", "Primal", "Cooldown").
struct WorkoutBlock: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    /// The role this block plays in the session structure.
    var category: ExerciseCategory
    var exercises: [PrescribedExercise]
    /// Seconds of the pause between two stations of this circuit block (ADR-0013): 15 seconds, grown
    /// toward 60 on a 45 or 60 minute session the reps alone cannot fill. `nil` - a bookend, and every
    /// session saved before the pause could grow - means `SessionAssembly.transitionSeconds`.
    var transitionSeconds: Int? = nil
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
    /// Seconds the timing fit added to each set's work window past its generous pace (ADR-0010): on a
    /// rep-based training set the countdown runs this much longer, and the user rests through the
    /// spare time at the end of the set. `nil` (no stretch, and every session saved before stretching
    /// existed) leaves the window at the generous pace. Optional so older snapshots decode unchanged.
    var stretchSeconds: Int? = nil
    /// What this station does in a Training Day (US-TD02): a `main` rung, a `practice` preview of the
    /// next rung, the `core` Core Sprinkle, or a `recovery` stretch. `nil` for a warm-up or cooldown
    /// stretch and for every session generated before Training Days. Copied onto the log, where it
    /// decides what counts toward progression (`LoggedExercise.countsForProgression`).
    var role: StationRole? = nil
    /// The user's Earned Reps for this movement when it was prescribed (US-TD02), so a prescription
    /// padded above them (or cut below them on a short session) still records what was earned.
    /// Rep-based movements only; `nil` off the main and core stations.
    var earnedReps: Int? = nil
    /// The hold-seconds counterpart of `earnedReps`, for a timed hold.
    var earnedDurationSeconds: Int? = nil
}
