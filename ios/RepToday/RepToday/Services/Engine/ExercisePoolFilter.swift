import Foundation

/// Pipeline Step 4 of the deterministic engine (US-C04): narrow the full library down to the
/// pool of exercises that are *safe and appropriate* for this user, so later steps never even
/// see something above the user's level, gated behind the Strength Phase, hard on an injury, or
/// repeatedly skipped.
///
/// Steps 1-3 chose the session's shape, pillar(s), and lead pattern; Step 4 decides *which
/// exercises are eligible* to fill them. It removes, from the full library:
/// - **phase-gated** movements - `phase == .strength` while the user is still in `.discipline`;
/// - **injury-contraindicated** movements - whose `movementPattern` is hard on one of the user's
///   declared injuries (see `InjuryContraindication`);
/// - **too-hard** movements - `difficulty` above the user's *effective* cap: the fitness-level band
///   (beginner 1-2, intermediate 1-3, advanced 1-5) lifted to the full `1...5` range once the user
///   has earned the `.strength` phase, so demonstrated competence overrides a conservative
///   onboarding estimate (US-SP01, `effectiveDifficultyCap(for:phase:)`);
/// - **repeatedly-skipped** movements - skipped more than `recentSkipThreshold` times across
///   `recentLogs`;
/// and enforces the Zero-Equipment Floor (`equipment == []`) as a final guarantee even though the
/// library is already validated bodyweight-only at load (US-B02).
///
/// Like the earlier steps this is a pure function of its inputs - the library, the `User`, and
/// `recentLogs` - with no hidden clock or library lookup, so it stays deterministic and
/// unit-testable, mirroring `MovementPatternFocus`.
///
/// `pool(forPattern:)` answers the per-pattern question the assembly step asks ("give me the
/// eligible exercises for this needed pattern"), and handles the case where filtering empties a
/// needed pattern: it relaxes the *soft* filters (difficulty cap, recent-skip) - never the *hard*
/// safety filters (phase, injury, equipment) - to offer the single safest available bodyweight
/// option, and records that a fallback happened (`FallbackReason`). If even the hard-safety pool
/// is empty, the pattern simply cannot be trained safely and is reported as such rather than the
/// engine reaching for an unsafe pick.

// MARK: - InjuryContraindication

/// Maps a free-text onboarding injury tag (`UserProfile.injuries`, e.g. `"knees"`,
/// `"lower_back"`) to the movement patterns it makes unsafe.
///
/// The mapping is deliberately at *pattern* granularity: the exercise model carries no
/// per-movement contraindication data (US-A03), so the engine reasons about the pattern a
/// movement belongs to. A knee injury rules out the `squat` pattern (deep knee flexion), a
/// lower-back injury rules out `hinge` (loaded spinal flexion), and so on. This is coarse by
/// design - a finer per-exercise contraindication tag is a future refinement; the structured
/// pattern map is the honest signal available today.
///
/// Tags are normalized (lower-cased, stripped to letters, de-pluralized) before lookup, so
/// `"Knees"`, `"knee"`, and `"knees "` all resolve the same. An unrecognized tag contributes no
/// contraindication - a safe default that never silently empties the pool on an unknown string.
///
/// - Important: That fail-open default is intentional but a latent safety gap. There is **no
///   compile-time binding** between the canonical keys here (`knee` / `back` / `lowerback` /
///   `shoulder` / `wrist` / `ankle` / `hip`) and the onboarding injury-tag vocabulary, which is
///   defined later in US-E01. If onboarding emits a tag that does not normalize onto a key (e.g.
///   `"neck"`, or a full phrase like `"lower back pain"` -> `"lowerbackpain"`), injury protection
///   for that tag silently disappears with no error. When US-E01 lands it **must** reconcile the
///   tags it emits with these keys - ideally by sharing a single closed vocabulary - so a mismatch
///   cannot quietly disable the filter.
enum InjuryContraindication {

    /// Normalized injury tag -> the patterns it contraindicates. Keys must be stored in
    /// de-pluralized (singular) form because `normalize` strips a trailing `s` (see its note).
    private static let patternsByInjury: [String: Set<MovementPattern>] = [
        "knee": [.squat],
        "back": [.hinge],
        "lowerback": [.hinge],
        "shoulder": [.push, .pull],
        "wrist": [.push],
        "ankle": [.locomotion],
        "hip": [.squat, .hinge],
    ]

    /// The patterns a single injury tag contraindicates (empty for an unrecognized tag).
    static func patterns(forInjury injury: String) -> Set<MovementPattern> {
        patternsByInjury[normalize(injury)] ?? []
    }

    /// The union of patterns contraindicated by all of the user's injury tags.
    static func contraindicatedPatterns(for injuries: [String]) -> Set<MovementPattern> {
        injuries.reduce(into: Set<MovementPattern>()) { result, injury in
            result.formUnion(patterns(forInjury: injury))
        }
    }

    /// Lower-cases, drops everything but letters (so `"lower_back"` / `"lower back"` collapse to
    /// `"lowerback"`), and removes a trailing plural `s` so `"knees"` matches the `"knee"` key.
    ///
    /// - Note: Because the trailing `s` is stripped unconditionally, `patternsByInjury` keys must be
    ///   stored de-pluralized; a legitimately-singular future key ending in `s` (e.g. `"abs"`) would
    ///   normalize to `"ab"` and be unreachable.
    private static func normalize(_ injury: String) -> String {
        var key = injury.lowercased().filter { $0.isLetter }
        if key.count > 1, key.hasSuffix("s") { key.removeLast() }
        return key
    }
}

// MARK: - ExercisePoolFilter

/// Filters the library to the eligible pool for a user (pipeline Step 4).
enum ExercisePoolFilter {

    // MARK: Tuning constants

    /// An exercise skipped *more* than this many times across `recentLogs` is dropped from the
    /// pool (so 4+ skips removes it). Tunable.
    static let recentSkipThreshold = 3

    // MARK: Difficulty cap

    /// The difficulty band a fitness level may draw from: beginner 1-2, intermediate 1-3,
    /// advanced 1-5. Anything above the cap is filtered out.
    ///
    /// This is the band derived from the self-reported onboarding `FitnessLevel` *alone*. The
    /// eligible-pool check does not consume it directly - it goes through `effectiveDifficultyCap`,
    /// which layers the earned phase on top (US-SP01).
    static func difficultyCap(for level: FitnessLevel) -> ClosedRange<Int> {
        switch level {
        case .beginner: return 1...2
        case .intermediate: return 1...3
        case .advanced: return 1...5
        }
    }

    /// The full catalog difficulty range an *earned* Strength-Phase user may draw from, lifting the
    /// conservative onboarding-`FitnessLevel` band so the hardest phase-gated skills become
    /// reachable. `1...5` is the whole shipped difficulty spectrum (the same ceiling `.advanced`
    /// already sees), so competence-earned access never depends on how the user self-reported.
    static let strengthPhaseDifficultyCap: ClosedRange<Int> = 1...5

    /// The **effective** difficulty band - the single source of truth for the eligible-pool cap
    /// check (US-SP01). For a `.discipline` user it is exactly `difficultyCap(for:)`, the
    /// conservative band from the onboarding `FitnessLevel`. For a user who has *earned* the
    /// `.strength` phase, demonstrated competence overrides that estimate: the cap is lifted to the
    /// full catalog range so a phase-gated difficulty-5 skill is reachable regardless of the
    /// onboarding level.
    ///
    /// This resolves the "double-gate trap": a phase-gated skill must clear *both* `isPhaseAllowed`
    /// and the difficulty cap, yet the two gates were derived from independent signals (earned phase
    /// vs. self-reported level), so a beginner/intermediate user who earned Strength still saw
    /// nothing. Keying the cap lift off `user.phase` - the `PhaseEvaluator`'s own output - means the
    /// difficulty gate can never disagree with the phase gate about who has graduated.
    ///
    /// A `.discipline` user's band is byte-identical to `difficultyCap(for:)`, so their eligible
    /// pool is entirely unchanged.
    static func effectiveDifficultyCap(for level: FitnessLevel, phase: Phase) -> ClosedRange<Int> {
        switch phase {
        case .discipline: return difficultyCap(for: level)
        case .strength: return strengthPhaseDifficultyCap
        }
    }

    // MARK: Individual rules (each independently testable)

    /// Strength-Phase skills stay hidden until the user has earned the Strength Phase; discipline
    /// movements are always allowed.
    static func isPhaseAllowed(_ exercise: Exercise, for user: User) -> Bool {
        isPhaseAllowed(exercise, phase: user.phase)
    }

    /// The phase-only core of the gate above, taking the earned `phase` directly. The `for user:`
    /// overload delegates here, so a read-only surface that must mark a rung "locked until the
    /// Strength Phase is earned" (the progression map, US-SP05) reads the *same* rule the engine
    /// filters on rather than a parallel re-derivation - `!isPhaseAllowed(_:phase:)` is exactly
    /// "this rung is a Strength-Phase skill and the user has not earned it."
    static func isPhaseAllowed(_ exercise: Exercise, phase: Phase) -> Bool {
        exercise.phase == .discipline || phase == .strength
    }

    /// Whether the exercise's difficulty sits within the user's level cap (the onboarding
    /// `FitnessLevel` band alone, ignoring earned phase). The eligible-pool check uses
    /// `isWithinEffectiveDifficultyCap` instead; this stays the level-only rule for callers that
    /// reason about the conservative band directly.
    static func isWithinDifficultyCap(_ exercise: Exercise, for level: FitnessLevel) -> Bool {
        difficultyCap(for: level).contains(exercise.difficulty)
    }

    /// Whether the exercise's difficulty sits within the user's **effective** cap - the onboarding
    /// `FitnessLevel` band lifted by the earned phase (US-SP01). This is what the eligible pool
    /// gates on, so an earned Strength-Phase user reaches the harder catalog their competence unlocked.
    static func isWithinEffectiveDifficultyCap(_ exercise: Exercise, for user: User) -> Bool {
        effectiveDifficultyCap(for: user.profile.fitnessLevel, phase: user.phase)
            .contains(exercise.difficulty)
    }

    /// Whether the exercise's pattern is clear of every injury the user declared.
    static func isInjurySafe(_ exercise: Exercise, injuries: [String]) -> Bool {
        !InjuryContraindication.contraindicatedPatterns(for: injuries)
            .contains(exercise.movementPattern)
    }

    /// How many times this exercise id was skipped across `recentLogs` (completed reps don't
    /// count - only entries flagged `skipped`).
    static func recentSkipCount(forExerciseId id: String, in recentLogs: [WorkoutLog]) -> Int {
        recentLogs.reduce(0) { count, log in
            count + log.exercises.filter { $0.exerciseId == id && $0.skipped }.count
        }
    }

    /// Whether the exercise has been skipped few enough times to stay in the pool.
    static func isWithinSkipLimit(_ exercise: Exercise, recentLogs: [WorkoutLog]) -> Bool {
        recentSkipCount(forExerciseId: exercise.id, in: recentLogs) <= recentSkipThreshold
    }

    /// The Zero-Equipment Floor: every offered movement is pure bodyweight.
    static func isBodyweight(_ exercise: Exercise) -> Bool {
        exercise.equipment.isEmpty
    }

    // MARK: Full eligible pool

    /// The full pool of exercises that pass every filter for this user. Order follows the input
    /// library (the filter never reorders), so the result is deterministic.
    static func eligiblePool(
        from library: [Exercise],
        user: User,
        recentLogs: [WorkoutLog]
    ) -> [Exercise] {
        library.filter { exercise in
            passesHardSafety(exercise, for: user)
                && isWithinEffectiveDifficultyCap(exercise, for: user)
                && isWithinSkipLimit(exercise, recentLogs: recentLogs)
        }
    }

    // MARK: Per-pattern pool with fallback

    /// The eligible exercises for one needed `pattern`, with a fallback when the filters leave it
    /// empty.
    ///
    /// Normally this is just `eligiblePool` restricted to `pattern`. When that is empty, the soft
    /// filters (difficulty cap, recent-skip) are relaxed - but never the hard safety filters
    /// (phase, injury, equipment) - and the single safest available bodyweight option is offered,
    /// with `fallback == .relaxedSoftFilters`. If even the hard-safety pool for the pattern is
    /// empty (e.g. an injury rules out the whole pattern), no safe option exists and the pattern
    /// is reported with `fallback == .noSafeOption` and no exercises, so the caller can choose a
    /// different pattern rather than the engine offering something unsafe.
    static func pool(
        forPattern pattern: MovementPattern,
        from library: [Exercise],
        user: User,
        recentLogs: [WorkoutLog]
    ) -> PatternPool {
        let filtered = eligiblePool(from: library, user: user, recentLogs: recentLogs)
            .filter { $0.movementPattern == pattern }
        if !filtered.isEmpty {
            return PatternPool(pattern: pattern, exercises: filtered, fallback: nil)
        }

        let safe = library.filter {
            $0.movementPattern == pattern && passesHardSafety($0, for: user)
        }
        guard let safest = safe.min(by: safestFirst) else {
            return PatternPool(pattern: pattern, exercises: [], fallback: .noSafeOption)
        }
        return PatternPool(pattern: pattern, exercises: [safest], fallback: .relaxedSoftFilters)
    }

    // MARK: Helpers

    /// The hard safety filters that are never relaxed: bodyweight, phase-allowed, injury-safe.
    private static func passesHardSafety(_ exercise: Exercise, for user: User) -> Bool {
        isBodyweight(exercise)
            && isPhaseAllowed(exercise, for: user)
            && isInjurySafe(exercise, injuries: user.profile.injuries)
    }

    /// "Safest first" ordering for the fallback pick: lowest difficulty, then earliest chain
    /// position, then id - so the fallback is the gentlest option and fully deterministic.
    private static func safestFirst(_ a: Exercise, _ b: Exercise) -> Bool {
        if a.difficulty != b.difficulty { return a.difficulty < b.difficulty }
        if a.progressionOrder != b.progressionOrder { return a.progressionOrder < b.progressionOrder }
        return a.id < b.id
    }
}

// MARK: - PatternPool

/// The eligible exercises for one needed movement pattern, plus whether a fallback was required
/// because the filters emptied that pattern.
struct PatternPool: Equatable {
    /// The pattern this pool was resolved for.
    let pattern: MovementPattern
    /// The exercises safe to offer for `pattern`; the single safest option in the
    /// `.relaxedSoftFilters` fallback, or empty when there is `.noSafeOption`.
    let exercises: [Exercise]
    /// `nil` when the normal filtered pool was non-empty; otherwise why a fallback was taken.
    let fallback: FallbackReason?
}

// MARK: - FallbackReason

/// Why `ExercisePoolFilter.pool(forPattern:)` had to fall back, recorded so the assembly step (and
/// later diagnostics) can explain a needed pattern that the filters emptied.
enum FallbackReason: Equatable {
    /// The soft filters (difficulty cap, recent-skip) emptied the pattern, so they were relaxed
    /// and the safest hard-safe bodyweight option was offered instead.
    case relaxedSoftFilters
    /// No bodyweight option for the pattern clears the hard safety filters (phase/injury), so the
    /// pattern cannot be trained safely and must be replaced upstream.
    case noSafeOption
}
