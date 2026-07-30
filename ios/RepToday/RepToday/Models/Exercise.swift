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
    /// Set when the prescribed per-set value is *per side* - a 20-second side plank is 20 seconds left
    /// plus 20 seconds right, and `advancementCriteria` says so in words ("3x30s hold per side").
    /// The timing model needs it explicitly for holds, whose per-second work cost is fixed at one second
    /// per prescribed second *per side*, so a per-side hold's set costs twice its prescribed duration.
    /// Read through `sidesPerSet` rather than directly; optional (absent means not per side) so an
    /// `Exercises.json` copy or an already-persisted active session written before it existed decodes
    /// unchanged.
    var isPerSide: Bool?
    /// The authored cost of one set *at this movement's own default* per-set value, and the anchor the
    /// timing-fit step calibrates against. It is not read directly: `SessionAssembly.workSecondsPerSet`
    /// splits it into a fixed per-set setup cost plus a per-unit rate and re-prices the set against the
    /// target Step 6 actually prescribed, so a grown or cold-start-seeded target is sized as the longer
    /// set it really is while a default-sized one still costs exactly what is authored here.
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

    /// How many times a set's prescribed per-set value is actually performed: twice for an `isPerSide`
    /// movement, once otherwise (including when the flag is absent). Read by the timing model, which has
    /// to charge a "20 second" side plank for both sides.
    ///
    /// - Important: The timing model reads this for **holds only**, and deliberately so. A hold's
    ///   per-unit cost is known a priori (one second of work per prescribed second, per side), so the
    ///   sides have to be applied explicitly. A rep-based movement's cadence is instead *derived* from
    ///   its own authored `estimatedTimePerSetSeconds` against `defaultReps`, and that authored estimate
    ///   already covers every side the set is performed on - `push_archer` ("3x8 clean reps per side")
    ///   is authored at 5 reps in 50s with both sides included. Applying `sidesPerSet` in the rep branch
    ///   as well would therefore double-count the 17 per-side rep movements outright. The flag is not
    ///   inert there by oversight; it is already accounted for.
    ///   The other consumers are `AdaptiveOverload.clampPerSet`, where it divides the hold ceiling so
    ///   `maxHoldSeconds` means what it says on a per-side hold, and the player's own copy
    ///   (`ActiveSessionView.perSideSuffix`, reused by `ReadyView`), which appends " per side" to the
    ///   visual and VoiceOver targets so what the user is asked for cannot drift from what the engine
    ///   charges.
    var sidesPerSet: Int { isPerSide == true ? 2 : 1 }
}
