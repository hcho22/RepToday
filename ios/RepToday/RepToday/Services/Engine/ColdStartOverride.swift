import Foundation

/// Pipeline Step 0 of the deterministic engine (US-E04): the cold-start override that runs *before*
/// Steps 1-6 while a brand-new user is still finding their footing, so their first sessions are kept
/// gentle and vivid and a mis-reported fitness level never produces a badly over-hard day.
///
/// Step 0 is deliberately a thin override, not a second engine. It reshapes only inputs the rest of
/// the pipeline already consumes, and leaves everything else to Steps 1-6:
///
/// - **Capped Starting Difficulty** (`cappedPool`) - the eligible pool is restricted to movements at
///   or below the policy's `coldStartContract.cappedMaxDifficulty`, so someone who over-rated their
///   fitness level still gets a winnable first day. The "served at the gentle end of the band"
///   promise then falls out of Step 5, which already starts a no-history user at the gentlest tier.
/// - **Start Seed** (`startSeed` / `startBandedPool` / `volumeSeed`, US-O02) - the floor beneath that
///   cap and the volume a no-history prescription opens at, so an *active* user's first sessions are
///   not served the absolute beginner tier at beginner volume.
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

    // MARK: - Start Seed (US-O02)

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

    /// The whole Start Seed in force for one generation: the difficulty **floor** the strength/primal
    /// training pool is banded to, and the **volume** a no-history prescription opens at.
    ///
    /// Resolving both halves together is what makes the self-correction coherent: a down-signal has to
    /// step the *tier* and the *volume* back at the same time, or de-escalating to an easier movement
    /// would simply re-apply the full volume seed to a movement the user has never logged.
    struct StartSeed: Equatable {
        var difficultyFloor: Int
        var volume: VolumeSeed

        /// The neutral seed: the whole band beneath the cap stays eligible and no-history targets are
        /// exactly the exercise's own defaults - the pre-US-O02 behavior.
        static let neutral = StartSeed(
            difficultyFloor: SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor,
            volume: .neutral
        )
    }

    /// The Start Seed in force for this generation, or `.neutral` when Step 0 is inactive.
    ///
    /// The contract's seeded values are the *aim*; what is actually served is that aim **eased by every
    /// down-signal the cold-start window has already produced**, so a dishonest self-report corrects
    /// itself within one cycle rather than holding the user at an unwinnable tier for the whole first
    /// week. A down-signal is the same eager signal the Asymmetric Ramp (US-E05) reacts to - a session
    /// rated `tooHard`, or one where the user bailed on a strength/primal movement - and each one steps
    /// the floor down a tier, drops a set, and eases the rep multiplier by the ramp's own `hardStep`.
    /// Easing stops at neutral: a down-signal can never push the seed *below* the un-seeded default,
    /// and a seed already at or under neutral is left exactly as it is.
    static func startSeed(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> StartSeed {
        typealias Contract = SessionPolicy.ColdStartContract
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return .neutral
        }
        let signals = downSignalCount(recentLogs: recentLogs)
        return StartSeed(
            difficultyFloor: eased(
                contract.startingDifficultyFloor,
                toward: Contract.neutralStartingDifficultyFloor,
                to: contract.startingDifficultyFloor - signals
            ),
            volume: VolumeSeed(
                repMultiplier: eased(
                    contract.startingRepMultiplier,
                    toward: Contract.neutralStartingRepMultiplier,
                    to: contract.startingRepMultiplier * pow(AdaptiveOverload.hardStep, Double(signals))
                ),
                sets: eased(
                    contract.startingSets,
                    toward: Contract.neutralStartingSets,
                    to: contract.startingSets - signals
                )
            )
        )
    }

    /// How many eager down-signals the user has already produced: sessions they rated `tooHard`, plus
    /// sessions where they bailed on a banded (strength/primal) movement. This mirrors the Asymmetric
    /// Ramp's own down-signal exactly (`AdaptiveOverload` treats a `tooHard` rating and a skip
    /// identically), so the tier and the volume back off on the same evidence.
    static func downSignalCount(recentLogs: [WorkoutLog]) -> Int {
        recentLogs.filter(isDownSignal).count
    }

    /// Whether one session is an eager down-signal: the user rated it `tooHard`, or bailed on a
    /// banded (strength/primal) movement in it. Exposed so anything else reacting to the same
    /// evidence reads it from exactly one definition rather than re-deriving a subtly different one.
    static func isDownSignal(_ log: WorkoutLog) -> Bool {
        log.perceivedDifficulty == .tooHard
            || log.exercises.contains { $0.skipped && ($0.pillar == .strength || $0.pillar == .primal) }
    }

    /// Moves `seeded` toward `neutral` to `backedOff`, never overshooting neutral and never touching a
    /// seed that is already at or below it. Shared by all three seed fields so they can only ever ease,
    /// never harden, in response to a down-signal.
    private static func eased<Value: Comparable>(
        _ seeded: Value,
        toward neutral: Value,
        to backedOff: Value
    ) -> Value {
        guard seeded > neutral else { return seeded }
        return max(neutral, min(seeded, backedOff))
    }

    /// The eligible pool with the Start Seed's difficulty **floor** applied, banding the strength and
    /// primal training movements to `[startingDifficultyFloor, cappedMaxDifficulty]` (the cap having
    /// already been applied by `cappedPool`). Step 5 starts a no-history user at the *lowest eligible*
    /// tier, so raising the floor is exactly what makes an active user's first session open at the band
    /// entry - a standard or diamond push-up rather than a wall push-up - while a beginner (floor `1`)
    /// is untouched. A no-op when Step 0 is inactive or the resolved seed is neutral.
    ///
    /// Two things are deliberately never floored:
    /// - **Mobility** - the warm-up, the Movement Practice block, and the cooldown all draw from the
    ///   mobility pool, and a mobility movement's difficulty is not a measure of training load. Gating
    ///   there is identical for every fitness level.
    /// - **A movement pattern the floor would empty** - the floor is clamped down per pattern to the
    ///   hardest movement that pattern actually offers inside the cap, so banding can never starve a
    ///   pattern (and never break generation) just because the library has no movement that hard yet.
    ///
    /// `recentLogs` is read only to resolve the seed (see `startSeed`), so a `tooHard` first session
    /// visibly lowers the *tier* of the next one, not just its reps.
    static func startBandedPool(
        _ pool: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> [Exercise] {
        let floor = startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs).difficultyFloor
        guard floor > SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor else { return pool }

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
            return exercise.difficulty >= min(floor, hardest)
        }
    }

    /// Whether the Start Seed's difficulty floor applies to a movement: only the strength and primal
    /// training pillars are banded (see `startBandedPool`).
    private static func isBanded(_ exercise: Exercise) -> Bool {
        exercise.pillar == .strength || exercise.pillar == .primal
    }

    // MARK: - Withheld movements

    /// The strength/primal movements the Start Seed band holds - or held during the cold-start week -
    /// out of this user's reach, so Step 5 can tell "the user outgrew this" apart from "the engine
    /// never let them see this".
    ///
    /// This is what closes the post-handoff difficulty cliff. Banding withholds whole progression
    /// chains for five sessions, so they accrue no history; the moment the band lifts their untouched
    /// entry tiers are the only movements the variety window has never seen, and freshness alone
    /// hands an advanced user a wall push-up. `ProgressionChainSelection` skips these when entering a
    /// chain with no history and does not count them as fresh - it never filters them out, so a
    /// narrower pool (a Return, an injury) simply makes the band unreachable and every movement
    /// eligible again.
    ///
    /// The band is the one that actually ran, never one asserted after the fact:
    /// - **While cold start is active** it is the live seed (`startSeed`), already eased by every
    ///   down-signal, so a `tooHard` session stops withholding the gentler tier in the same move that
    ///   lowers the floor.
    /// - **Once cold start retires** it is `user.coldStart.bandFloorAtHandoff` - the floor
    ///   `ColdStartHandoff` recorded, from that same eased seed, on the session that retired the band.
    ///   A user with no recorded floor never ran a banded cold start (they are still inside the window,
    ///   their record predates US-O02, or their contract carried the neutral floor) and withholds
    ///   nothing at all.
    ///
    /// Recording beats re-deriving here, and the reason is the window: the engine's `recentLogs` is
    /// bounded (70 days at the Ready Screen), so the cold-start sessions that produced the band - and
    /// the down-signals that eased it - age out. A derivation would then quietly re-raise the tier a
    /// `tooHard` rating lowered and claim a band the user never lived through. The recorded floor is a
    /// fact about their own week and stays true for the life of the account.
    ///
    /// Pure over its inputs (no wall clock; the band comes from the user's own state and `recentLogs`),
    /// like the rest of Step 0.
    static func withheldByStartSeed(
        library: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> Set<String> {
        let floor = bandFloorInForce(
            user: user,
            sessionPolicy: sessionPolicy,
            recentLogs: recentLogs
        )
        guard floor > SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor else { return [] }

        // Banding never starves a pattern, so a pattern whose hardest movement sits under the floor
        // withholds nothing (mirrors `startBandedPool`'s per-pattern clamp).
        var hardestByPattern: [MovementPattern: Int] = [:]
        for exercise in library where isBanded(exercise) {
            hardestByPattern[exercise.movementPattern] = max(
                hardestByPattern[exercise.movementPattern] ?? 0,
                exercise.difficulty
            )
        }

        return library.reduce(into: Set<String>()) { withheld, exercise in
            guard isBanded(exercise), let hardest = hardestByPattern[exercise.movementPattern] else {
                return
            }
            if exercise.difficulty < min(floor, hardest) { withheld.insert(exercise.id) }
        }
    }

    /// The Start Seed's difficulty floor as it applies to this user right now: the live seed while
    /// cold start is active, otherwise the floor `ColdStartHandoff` recorded when the band retired
    /// (see `withheldByStartSeed`). `neutralStartingDifficultyFloor` when no band ever ran, which is
    /// what a user who never had one - a pre-US-O02 record, a generation against `SessionPolicy
    /// .default` - correctly reports, rather than having a band asserted over them retroactively.
    ///
    /// Note this never reads `profile.fitnessLevel`. That self-report seeds the contract at onboarding
    /// and is never revised; what the band actually ran at is the recorded fact, and it is the only
    /// thing a claim about the user's own past may rest on.
    private static func bandFloorInForce(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> Int {
        if isActive(user: user, sessionPolicy: sessionPolicy) {
            return startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs)
                .difficultyFloor
        }
        return user.coldStart.bandFloorAtHandoff
            ?? SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
    }

    /// The Start Seed volume in force for this generation, or `.neutral` when Step 0 is inactive.
    static func volumeSeed(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> VolumeSeed {
        startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs).volume
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
