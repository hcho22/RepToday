import Foundation

/// The canonical domain vocabulary shared by every model, the engine, persistence,
/// and the views (US-A02).
///
/// Every enum here is backed by a stable `String` raw value. Those raw values are a
/// persistence contract: they are written into CoreData (as JSON-encoded `Data`) and
/// synced to CloudKit, so **renaming a case's raw value silently breaks already-stored
/// data**. The case *names* may be refactored freely; the raw *values* must not change.
/// `EnumsTests` pins every raw value for exactly this reason.
///
/// Conformances are uniform across the file:
/// - `Codable` so models round-trip through JSON / CoreData.
/// - `CaseIterable` so the UI and the engine can enumerate the full set.
/// - `Identifiable` (id == raw value) so SwiftUI `ForEach` can iterate cases directly.
/// - `Equatable`/`Hashable` come for free from a raw-value enum and the engine leans on
///   both (staleness maps keyed by `Pillar`/`MovementPattern`, set membership, etc.).

// MARK: - Pillar

/// The training pillars a session can draw from.
///
/// `strength` and `mobility` are co-primary (Movement Practice is not a warm-up).
/// `primal` (bear crawl, crab walk, ground-to-standing) is a small movement-quality
/// category folded in alongside them.
enum Pillar: String, Codable, CaseIterable, Identifiable, Hashable {
    case strength
    case mobility
    case primal

    var id: String { rawValue }
}

// MARK: - Phase

/// The two-phase journey. Computed by the `PhaseEvaluator`, never user-selectable.
///
/// Every user starts in `discipline` (consistency is the only goal) and earns
/// `strength` over time. At MVP launch all users resolve to `discipline`.
enum Phase: String, Codable, CaseIterable, Identifiable, Hashable {
    case discipline
    case strength

    var id: String { rawValue }
}

// MARK: - MovementPattern

/// The fundamental movement patterns the engine balances by staleness so the user
/// gets variety and never repeats yesterday's primary pattern.
enum MovementPattern: String, Codable, CaseIterable, Identifiable, Hashable {
    case push
    case squat
    case hinge
    case core
    case pull
    case mobility
    case locomotion

    var id: String { rawValue }
}

// MARK: - ExerciseCategory

/// The role an exercise plays inside an assembled session.
///
/// Distinct from `Pillar`: `warmup`/`cooldown` are session-structure roles, while
/// `strength`/`mobility`/`primal` mirror the training pillars.
enum ExerciseCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case strength
    case mobility
    case warmup
    case cooldown
    case primal

    var id: String { rawValue }
}

// MARK: - Equipment

/// Equipment an exercise requires beyond the body itself.
///
/// In the MVP every exercise carries `equipment == []` - the Zero-Equipment Floor
/// guarantees each session is completable with only a floor and a wall. These cases
/// exist for the Phase 2 equipment variants (Strength Phase) so the model and stored
/// data are forward-compatible; the engine still filters everything to bodyweight today.
enum Equipment: String, Codable, CaseIterable, Identifiable, Hashable {
    case pullUpBar = "pull_up_bar"
    case resistanceBand = "resistance_band"
    case dumbbells
    case kettlebell
    case bench

    var id: String { rawValue }
}

// MARK: - FitnessLevel

/// Self-reported fitness level from onboarding. Caps the difficulty band the engine
/// will draw from (beginner 1-2, intermediate 1-3, advanced 1-5).
enum FitnessLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }
}

// MARK: - PrimaryGoal

/// The user's primary motivation, captured in onboarding. Informs tone and template
/// insights; it never overrides the deterministic engine.
enum PrimaryGoal: String, Codable, CaseIterable, Identifiable, Hashable {
    case stayActive = "stay_active"
    case buildStrength = "build_strength"
    case increaseEnergy = "increase_energy"
    case reduceStress = "reduce_stress"
    case loseWeight = "lose_weight"

    var id: String { rawValue }
}

// MARK: - SessionShape

/// The structural shape the engine selects from requested minutes:
/// `singleFocus` for 5-10 min (one pillar, done well) and `blend` for 11-60 min
/// (both pillars, warm-up always, cooldown over 10 min).
enum SessionShape: String, Codable, CaseIterable, Identifiable, Hashable {
    case singleFocus = "single_focus"
    case blend

    var id: String { rawValue }
}

// MARK: - PerceivedDifficulty

/// Post-session feedback that feeds Adaptive Overload within one cycle:
/// `tooHard` eases the next target, `tooEasy` intensifies it.
enum PerceivedDifficulty: String, Codable, CaseIterable, Identifiable, Hashable {
    case tooEasy = "too_easy"
    case justRight = "just_right"
    case tooHard = "too_hard"

    var id: String { rawValue }
}

// MARK: - Sex

/// Biological sex captured in onboarding, used only to refine energy-expenditure
/// estimates (e.g. the HealthKit active-energy calculation). Never gates content.
enum Sex: String, Codable, CaseIterable, Identifiable, Hashable {
    case male
    case female
    case other

    var id: String { rawValue }
}

// MARK: - SubscriptionTier

/// Entitlement level. `free` is unlimited core workouts forever; `premium` unlocks
/// the depth layer (full analytics, later Strength Phase / AI). The core loop is
/// never gated behind `premium`.
enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Hashable {
    case free
    case premium

    var id: String { rawValue }
}

// MARK: - SubscriptionProvider

/// Who manages the subscription. The MVP bills exclusively through StoreKit 2, so
/// `apple` is the only provider; the enum exists so stored data stays forward-
/// compatible if another billing path is ever added.
enum SubscriptionProvider: String, Codable, CaseIterable, Identifiable, Hashable {
    case apple

    var id: String { rawValue }
}
