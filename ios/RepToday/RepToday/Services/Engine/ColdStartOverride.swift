import Foundation

/// Pipeline Step 0 of the deterministic engine (US-E04): the cold-start override that runs *before*
/// Steps 1-6 while a brand-new user is still finding their footing, so their first sessions are kept
/// gentle and vivid and a mis-reported fitness level never produces a badly over-hard day.
///
/// Step 0 is deliberately a thin override, not a second engine. It touches exactly two of the inputs
/// the rest of the pipeline already consumes, and leaves everything else to Steps 1-6:
///
/// - **Capped Starting Difficulty** (`cappedPool`) - the eligible pool is restricted to movements at
///   or below the policy's `coldStartContract.cappedMaxDifficulty`, so someone who over-rated their
///   fitness level still gets a winnable first day. The "served at the gentle end of the band"
///   promise then falls out of Step 5, which already starts a no-history user at the gentlest tier.
/// - **First-Week Contrast** (`overridePlan`) - when the contract sets `forceContrastSpread`, the
///   day's lead pillar is forced onto a deterministic rotation keyed by `coldStart.sessionsLogged`,
///   overriding the single-theme bias `why`/`sitsLong` alone would produce (a desk worker's
///   all-mobility week) so the first week visibly spans strength, mobility, and primal.
///
/// Step 0 is gated on two conditions and is otherwise a no-op: the user is still in the cold-start
/// window (`user.coldStart.active`) *and* the live policy carries a `coldStartContract`. Once the
/// engine retires cold-start (US-G04 clears the contract and flips `active` off), both overrides
/// return their input untouched and the engine behaves exactly as US-E03. Like every other step it
/// is a pure function of its inputs (no hidden clock; the "day" is read from `sessionsLogged`), so it
/// stays deterministic and unit-testable.
enum ColdStartOverride {

    /// The canonical First-Week Contrast rotation order. Cycling through all three first-class
    /// pillars is what guarantees the vivid day-to-day spread (US-G02) instead of a single-theme
    /// week; the rotation is restricted per shape to the pillars a session can actually train.
    static let rotation: [Pillar] = [.strength, .mobility, .primal]

    // MARK: - Gate

    /// Whether Step 0 applies at all: the user is still in the cold-start window and the live policy
    /// carries a cold-start contract. When this is false both overrides below are no-ops.
    static func isActive(user: User, sessionPolicy: SessionPolicy) -> Bool {
        user.coldStart.active && sessionPolicy.coldStartContract != nil
    }

    // MARK: - Capped Starting Difficulty

    /// The eligible pool restricted to the cold-start difficulty ceiling: only movements at or below
    /// `coldStartContract.cappedMaxDifficulty` survive, so a mis-reported fitness level never yields a
    /// badly over-hard first day. A no-op when Step 0 is inactive.
    ///
    /// If the cap would empty the pool entirely (no movement that gentle exists for the needed work)
    /// the uncapped pool is returned instead - the safety rail must never break generation by
    /// starving the assembler of every option.
    static func cappedPool(
        _ pool: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy
    ) -> [Exercise] {
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return pool
        }
        let capped = pool.filter { $0.difficulty <= contract.cappedMaxDifficulty }
        return capped.isEmpty ? pool : capped
    }

    // MARK: - Start Seed: difficulty floor (US-O02)

    /// The eligible pool with the Start Seed's difficulty **floor** applied, banding the strength and
    /// primal training movements to `[startingDifficultyFloor, cappedMaxDifficulty]` (the cap having
    /// already been applied by `cappedPool`). Step 5 starts a no-history user at the *lowest eligible*
    /// tier, so raising the floor is exactly what makes an active user's first session open at the band
    /// entry - a standard or diamond push-up rather than a wall push-up - while a beginner (floor `1`)
    /// is untouched. A no-op when Step 0 is inactive or the seed is neutral.
    ///
    /// Two things are deliberately never floored:
    /// - **Mobility** - the warm-up, the Movement Practice block, and the cooldown all draw from the
    ///   mobility pool, and a mobility movement's difficulty is not a measure of training load. Gating
    ///   there is identical for every fitness level.
    /// - **A movement pattern the floor would empty** - the floor is clamped down per pattern to the
    ///   hardest movement that pattern actually offers inside the cap, so banding can never starve a
    ///   pattern (and never break generation) just because the library has no movement that hard yet.
    static func startBandedPool(
        _ pool: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy
    ) -> [Exercise] {
        guard
            user.coldStart.active,
            let contract = sessionPolicy.coldStartContract,
            contract.startingDifficultyFloor > SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        else { return pool }

        // The hardest movement each banded pattern offers within the (already capped) pool.
        var hardestByPattern: [MovementPattern: Int] = [:]
        for exercise in pool where isBanded(exercise) {
            hardestByPattern[exercise.movementPattern] = max(
                hardestByPattern[exercise.movementPattern] ?? 0,
                exercise.difficulty
            )
        }

        return pool.filter { exercise in
            guard isBanded(exercise), let hardest = hardestByPattern[exercise.movementPattern] else {
                return true
            }
            return exercise.difficulty >= min(contract.startingDifficultyFloor, hardest)
        }
    }

    /// Whether the Start Seed's difficulty floor applies to a movement: only the strength and primal
    /// training pillars are banded (see `startBandedPool`).
    private static func isBanded(_ exercise: Exercise) -> Bool {
        exercise.pillar == .strength || exercise.pillar == .primal
    }

    // MARK: - Start Seed: volume (US-O02)

    /// The volume half of the Start Seed: how much of a movement a user at this fitness level should be
    /// prescribed the *first* time they meet it. The engine hands these to Step 6's no-history default
    /// target; a capacity-derived target (session 2+ of that movement) ignores them entirely.
    struct VolumeSeed: Equatable {
        /// Multiplier on the exercise's own default per-set reps / hold seconds.
        var repMultiplier: Double
        /// Set count for a no-history prescription.
        var sets: Int

        /// The neutral seed - unscaled per-set targets over the engine's own default set count, so a
        /// warmed-up user (or a pre-US-O02 policy) is prescribed exactly what they were before.
        static let neutral = VolumeSeed(
            repMultiplier: SessionPolicy.ColdStartContract.neutralStartingRepMultiplier,
            sets: SessionPolicy.ColdStartContract.neutralStartingSets
        )
    }

    /// The Start Seed volume in force for this generation, or `.neutral` when Step 0 is inactive.
    static func volumeSeed(user: User, sessionPolicy: SessionPolicy) -> VolumeSeed {
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return .neutral
        }
        return VolumeSeed(
            repMultiplier: contract.startingRepMultiplier,
            sets: contract.startingSets
        )
    }

    // MARK: - First-Week Contrast

    /// The pillar plan with First-Week Contrast applied: the lead pillar is forced onto the
    /// `sessionsLogged` rotation so consecutive cold-start days never repeat a pillar, overriding the
    /// single-theme bias `why`/`sitsLong` alone would produce. A no-op when Step 0 is inactive or the
    /// contract does not force the spread.
    ///
    /// - A single-focus session's one pillar is set directly to the rotated pillar (the rotation
    ///   spans all three pillars, so a desk worker's mobility lean no longer collapses the week).
    /// - A blend's shares are re-pointed so the rotated pillar owns the largest block (its block leads
    ///   and gets the most time), rotating only over the pillars the shape actually trains
    ///   (strength/mobility for a short or full blend; all three for an extended blend).
    static func overridePlan(
        _ plan: PillarPlan,
        template: SessionShapeTemplate,
        user: User,
        sessionPolicy: SessionPolicy
    ) -> PillarPlan {
        guard
            user.coldStart.active,
            let contract = sessionPolicy.coldStartContract,
            contract.forceContrastSpread
        else { return plan }

        switch plan {
        case .single:
            return .single(contrastPillar(user: user, available: Pillar.allCases))
        case .blend(let weights):
            let available: [Pillar] = template == .blendExtended
                ? [.strength, .mobility, .primal]
                : [.strength, .mobility]
            let lead = contrastPillar(user: user, available: available)
            return .blend(weights.favoring(lead))
        }
    }

    // MARK: - Rotation

    /// The forced lead pillar for the current cold-start day: the onboarding-derived starting pillar
    /// rotated forward by `coldStart.sessionsLogged`, restricted to the pillars a session's shape can
    /// train. Rotating over at least two pillars guarantees consecutive days never repeat.
    static func contrastPillar(user: User, available: [Pillar]) -> Pillar {
        let ordered = rotation.filter { available.contains($0) }
        guard !ordered.isEmpty else { return available.first ?? .strength }
        let start = ordered.firstIndex(of: startingPillar(for: user)) ?? 0
        let day = max(0, user.coldStart.sessionsLogged)
        return ordered[(start + day) % ordered.count]
    }

    /// The day-zero starting pillar derived from onboarding inputs: the user's stated
    /// `why.openingBias` when present (the single allowed programming lever of `why`), otherwise
    /// mobility for a desk worker (`sitsLong`, for same-day relief), otherwise strength. The rotation
    /// then walks forward from here, so onboarding sets where the first week *opens* but never lets it
    /// stall on one theme.
    static func startingPillar(for user: User) -> Pillar {
        if let bias = user.why.openingBias { return bias }
        return user.profile.sitsLong ? .mobility : .strength
    }

}
