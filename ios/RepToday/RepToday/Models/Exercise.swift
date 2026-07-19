import Foundation

/// A single movement in the bundled library (US-A03), mirroring v5 section 2.3.
///
/// Every exercise is bodyweight (`equipment == []`, the Zero-Equipment Floor). Each
/// strength/primal movement sits in a progression chain (`progressionChainId` +
/// `progressionOrder`) linked by `regressionId`/`progressionId`, so the engine can walk
/// a user up or down the chain. Movements are either holds (`isHold == true`, timed via
/// `defaultDurationSeconds`) or rep-based (`isHold == false`, via `defaultReps`).
struct Exercise: Codable, Equatable, Identifiable {
    /// Stable string id, e.g. `"push_standard"`. Matches the keys in `Exercises.json`.
    var id: String
    var displayName: String
    var pillar: Pillar
    var movementPattern: MovementPattern
    var category: ExerciseCategory
    /// Difficulty band 1...5; the engine caps by fitness level (beginner 1-2,
    /// intermediate 1-3, advanced 1-5).
    var difficulty: Int
    /// `.discipline` for launch movements; `.strength` for gated skills (L-sit, pistol
    /// squat, one-arm push-up) that only appear once the user has earned the Strength Phase.
    var phase: Phase
    /// Always `[]` in the MVP (Zero-Equipment Floor).
    var equipment: [Equipment]
    /// Holds are timed; everything else is rep-based.
    var isHold: Bool
    /// Starting reps when there is no logged capacity (rep-based movements).
    var defaultReps: Int?
    /// Starting hold duration when there is no logged capacity (holds).
    var defaultDurationSeconds: Int?
    /// Used by the timing-fit step to size the session.
    var estimatedTimePerSetSeconds: Int
    /// Metabolic equivalent, used to estimate active energy for HealthKit.
    var metValue: Double
    /// Groups a regression -> standard -> progression sequence.
    var progressionChainId: String
    /// Position within the chain; entry tier is 0.
    var progressionOrder: Int
    /// The easier movement one step down the chain, if any.
    var regressionId: String?
    /// The harder movement one step up the chain, if any.
    var progressionId: String?
    /// Human-readable rule for advancing, e.g. `"3x15 clean reps"`.
    var advancementCriteria: String
    /// True when the movement is doable in a small space with only a floor and wall.
    var apartmentFriendly: Bool
    /// The bundled Lottie animation file (without extension) demonstrating this movement (US-O01).
    /// `nil` when no animation ships for the movement, in which case the player's `ExerciseDemoView`
    /// falls back to the movement-appropriate SF Symbol so a demo is never blank. Optional with a
    /// `nil` default so the existing `Exercises.json` and pre-O01 persisted records decode unchanged.
    var animationName: String? = nil
}
