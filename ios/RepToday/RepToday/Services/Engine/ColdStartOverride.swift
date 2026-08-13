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
///   promise then falls out of Step 5, which starts a no-history user at the gentlest eligible tier
///   the Start Seed band did not withhold - for a beginner (neutral floor) that is the chain entry,
///   and for an active level it is the band floor.
/// - **Start Seed** (`startSeed` / `startBandedPool` / `volumeSeed`, US-O02) - the floor beneath that
///   cap and the volume a no-history prescription opens at, so an *active* user's first sessions are
///   not served the absolute beginner tier at beginner volume.
/// - **Cold-Start Strength Lead** (`overridePlan`, US-004) - when the contract sets
///   `forceContrastSpread`, every cold-start day is forced to lead **strength** (a single-focus day
///   trains strength; a blend leads strength), overriding the mobility/primal bias `why`/`sitsLong`
///   alone would produce (a desk worker's all-mobility week). Strength is what the first week builds;
///   the gentleness rails above (the difficulty cap and the Start Seed) are what keep it winnable.
///   This reverses the retired First-Week Contrast rotation, which deliberately *spread* the lead
///   across all three pillars - the flag's meaning is now "lead strength on cold-start days".
///
/// Step 0 is gated on two conditions and is otherwise a no-op: the user is still in the cold-start
/// window (`user.coldStart.active`) *and* the live policy carries a `coldStartContract`. Once the
/// engine retires cold-start (US-G04 clears the contract and flips `active` off), every override
/// above returns its input untouched and Steps 1-6 run exactly as US-E03 wrote them.
///
/// `withheldByStartSeed` is the one deliberate exception, and it outlives the gate by design. It is
/// not an override but a *factual* record of which movements the band never put on offer, so past the
/// handoff it reads the floor `ColdStartHandoff` recorded (`User.ColdStart.bandFloorAtHandoff`) and
/// keeps Step 5 from mistaking a chain the band hid for a fresh one. It withholds nothing for a user
/// who never ran a band. See `withheldByStartSeed` for why that has to survive the retirement.
///
/// Like every other step it is a pure function of its inputs (no hidden clock; the "day" is read from
/// `sessionsLogged`), so it stays deterministic and unit-testable.
enum ColdStartOverride {

    // MARK: - Gate

    /// Whether Step 0 applies at all: the user is still in the cold-start window and the live policy
    /// carries a cold-start contract. When this is false every override below (`cappedPool`,
    /// `startBandedPool`, `volumeSeed`, `overridePlan`) is a no-op. `withheldByStartSeed` is the sole
    /// exception - it falls through to the floor recorded at the handoff, which is the whole point of
    /// recording it.
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
    /// Resolving both halves together is what makes the self-correction coherent: a `tooHard` rating has
    /// to step the *tier* and the *volume* back at the same time, or de-escalating to an easier movement
    /// would simply re-apply the full volume seed to a movement the user has never logged. The two read
    /// different evidence beyond that - see `startSeed` - which is exactly why they are resolved once,
    /// as a pair, rather than derived independently wherever each is needed.
    struct StartSeed: Equatable {
        /// The gentlest difficulty the strength/primal training pool is banded to. Clamped down per
        /// movement pattern to what that pattern actually offers, so a band never empties one.
        var difficultyFloor: Int
        /// What a no-history prescription inside that band opens at.
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
    /// The contract's seeded values are the *aim*; what is actually served is that aim **eased by the
    /// down-signals the cold-start window has already produced**, so a dishonest self-report corrects
    /// itself within one cycle rather than holding the user at an unwinnable tier for the whole first
    /// week. Easing stops at neutral: a down-signal can never push the seed *below* the un-seeded
    /// default, and a seed already at or under neutral is left exactly as it is.
    ///
    /// The two halves read deliberately *different* evidence:
    ///
    /// - The **tier** floor eases only on an explicit `tooHard` rating (`isTierDownSignal`). That
    ///   rating is the one signal that actually says "this tier is beyond me". A skip is the product's
    ///   escape hatch and means "not this movement" - one the user dislikes, has no room for, or does
    ///   not want today - which is not evidence about the tier at all. The tier floor is also the half
    ///   that outlives the window (`ColdStartHandoff` records it at the handoff), so reading a
    ///   preference skip as over-reach would bake that mis-reading into the account permanently.
    /// - The **volume** eases on either signal (`isVolumeDownSignal`), mirroring the Asymmetric Ramp
    ///   (US-E05), which treats a bailed-on set and a `tooHard` rating identically. Backing the reps
    ///   off when a set went unfinished is the right read whatever the reason, and being wrong costs
    ///   nothing: the volume seed is re-resolved from the window on every generation, applies only to
    ///   no-history prescriptions, and is gone the moment cold start retires. `AdaptiveOverload`
    ///   therefore stays exactly as it is - it moves volume only, never a tier.
    static func startSeed(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> StartSeed {
        typealias Contract = SessionPolicy.ColdStartContract
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return .neutral
        }
        let volumeSignals = volumeDownSignalCount(recentLogs: recentLogs)
        return StartSeed(
            difficultyFloor: easedDifficultyFloor(
                aim: contract.startingDifficultyFloor,
                tierDownSignals: tierDownSignalCount(recentLogs: recentLogs)
            ),
            volume: VolumeSeed(
                repMultiplier: eased(
                    contract.startingRepMultiplier,
                    toward: Contract.neutralStartingRepMultiplier,
                    to: contract.startingRepMultiplier * pow(AdaptiveOverload.hardStep, Double(volumeSignals))
                ),
                sets: eased(
                    contract.startingSets,
                    toward: Contract.neutralStartingSets,
                    to: contract.startingSets - volumeSignals
                )
            )
        )
    }

    /// The contract's un-eased difficulty-floor **aim** for this generation, or the neutral floor when
    /// Step 0 is inactive. `ColdStartHandoff` records this alongside the eased floor so a rating that
    /// lands *after* the handoff can re-resolve the floor exactly from the same aim, rather than
    /// guessing at a step size or re-deriving the band from a window the sessions have aged out of.
    static func startSeedFloorAim(user: User, sessionPolicy: SessionPolicy) -> Int {
        guard user.coldStart.active, let contract = sessionPolicy.coldStartContract else {
            return SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        }
        return contract.startingDifficultyFloor
    }

    /// A difficulty-floor `aim` eased by `tierDownSignals` explicit `tooHard` sessions - one tier per
    /// signal, never past neutral. The single definition of the tier easing, shared by the live seed
    /// and by the handoff's recorded floor so the two can never drift.
    static func easedDifficultyFloor(aim: Int, tierDownSignals: Int) -> Int {
        eased(
            aim,
            toward: SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor,
            to: aim - tierDownSignals
        )
    }

    /// How many sessions the user has explicitly rated `tooHard` - the evidence the Start Seed's
    /// difficulty floor eases on (see `startSeed`).
    static func tierDownSignalCount(recentLogs: [WorkoutLog]) -> Int {
        recentLogs.filter(isTierDownSignal).count
    }

    /// Whether one session says the *tier* was beyond the user: they rated it `tooHard`. Deliberately
    /// narrower than `isVolumeDownSignal` - a skip is a preference, not a verdict on difficulty.
    static func isTierDownSignal(_ log: WorkoutLog) -> Bool {
        log.perceivedDifficulty == .tooHard
    }

    /// How many eager down-signals the user has produced for the *volume* half of the seed: sessions
    /// rated `tooHard`, plus sessions where they bailed on a banded (strength/primal) movement.
    static func volumeDownSignalCount(recentLogs: [WorkoutLog]) -> Int {
        recentLogs.filter(isVolumeDownSignal).count
    }

    /// Whether one session is an eager volume down-signal: the user rated it `tooHard`, or bailed on a
    /// banded (strength/primal) movement in it. This mirrors the Asymmetric Ramp's own down-signal
    /// exactly (`AdaptiveOverload` treats a `tooHard` rating and a skip identically), so the seeded
    /// volume and the ramp back off on the same evidence.
    static func isVolumeDownSignal(_ log: WorkoutLog) -> Bool {
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
    /// `seed` is the Start Seed already resolved for this generation (see `startSeed`), so a `tooHard`
    /// first session visibly lowers the *tier* of the next one, not just its reps. It is passed in
    /// rather than re-resolved because the band and the volume have to move together; the convenience
    /// overload below resolves it for callers that only need the pool.
    static func startBandedPool(_ pool: [Exercise], seed: StartSeed) -> [Exercise] {
        let floor = seed.difficultyFloor
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

    /// `startBandedPool` for a caller that has not already resolved the Start Seed.
    static func startBandedPool(
        _ pool: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> [Exercise] {
        startBandedPool(
            pool,
            seed: startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs)
        )
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
    ///   `tooHard` rating, so such a session stops withholding the gentler tier in the same move that
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
        seed: StartSeed
    ) -> Set<String> {
        let floor = bandFloorInForce(user: user, sessionPolicy: sessionPolicy, seed: seed)
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
        seed: StartSeed
    ) -> Int {
        if isActive(user: user, sessionPolicy: sessionPolicy) {
            return seed.difficultyFloor
        }
        return user.coldStart.bandFloorAtHandoff
            ?? SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
    }

    /// `withheldByStartSeed` for a caller that has not already resolved the Start Seed.
    static func withheldByStartSeed(
        library: [Exercise],
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> Set<String> {
        withheldByStartSeed(
            library: library,
            user: user,
            sessionPolicy: sessionPolicy,
            seed: startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs)
        )
    }

    /// The Start Seed volume in force for this generation, or `.neutral` when Step 0 is inactive.
    static func volumeSeed(
        user: User,
        sessionPolicy: SessionPolicy,
        recentLogs: [WorkoutLog]
    ) -> VolumeSeed {
        startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs).volume
    }

    // MARK: - Cold-Start Strength Lead

    /// The pillar plan with the cold-start strength lead applied (US-004): every cold-start day is
    /// forced to lead **strength**, overriding the mobility/primal single-theme bias `why`/`sitsLong`
    /// alone would produce (a desk worker's all-mobility week). A no-op when Step 0 is inactive or the
    /// contract does not set the flag.
    ///
    /// - A single-focus session's one pillar becomes strength outright, so mobility survives only as
    ///   the structural warm-up rather than the day's theme.
    /// - A blend's shares are re-pointed so strength owns the largest block (its block leads and gets
    ///   the most time) via `PillarWeights.favoring(_:)`, which preserves the multiset of shares - the
    ///   emphasis is reordered, never a pillar starved. On an extended blend that already leads
    ///   strength this is a no-op; on a mobility- or primal-led blend it swaps strength to the front.
    ///
    /// This reverses the retired First-Week Contrast rotation (US-G02/US-E04), which forced the lead
    /// onto a `[.strength, .mobility, .primal]` cycle to *spread* the first week across all three
    /// pillars. The `forceContrastSpread` flag survives as the gate; its meaning is now "lead strength
    /// on cold-start days". The gentleness this leaves untouched (the difficulty cap and the Start
    /// Seed's reduced volume) is what keeps a strength-led first week winnable.
    static func overridePlan(
        _ plan: PillarPlan,
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
            return .single(.strength)
        case .blend(let weights):
            return .blend(weights.favoring(.strength))
        }
    }

}
