import Foundation

/// Deterministic in-session exercise swap (US-C08): given a workout and one of its prescribed
/// slots, hand back an equivalent substitute the user can do instead - same pillar, same movement
/// pattern, comparable difficulty, fitting the same time slot - so the user stays in control of a
/// movement they dislike or cannot do without breaking the session the engine built.
///
/// This is the engine's one *interactive* step (Steps 1-7 build the session up front; this reshapes
/// a single slot on request), but it obeys the same contract as the rest of the pipeline:
/// - **Equivalence** - a substitute must match the swapped exercise's `pillar` and `movementPattern`
///   and sit within `difficultyBandWidth` of its `difficulty`, so the session keeps the same shape
///   and the slot stays "the same kind of work" rather than turning a push slot into a stretch.
/// - **Safety** - candidates are drawn from `ExercisePoolFilter.eligiblePool`, so every substitute
///   already respects the user's phase, injuries, fitness-level difficulty cap, recent-skip history,
///   and the Zero-Equipment Floor. The swap step never re-derives those rules and never relaxes
///   them: if the only same-pattern options are gated, over-cap, or hard on an injury, there is no
///   safe substitute and the step says so rather than reaching for an unsafe pick.
/// - **Timing fidelity** - a substitute's slot must land within the slot's tolerance (see
///   `slotTolerance`) of the slot it replaces, both sides priced through
///   `SessionAssembly.workSecondsPerSet` at the target each movement actually carries - the same
///   arithmetic the session was sized with. The per-set target itself (reps or hold seconds) is
///   recomputed capacity-relative for the substitute via `AdaptiveOverload`, exactly as assembly would
///   have. Because that target is *not* transferable - a movement the user has never logged opens at
///   its own default while the slot it replaces may carry a long-grown one - the substitute's **set
///   count** is the lever that absorbs the difference, within the same
///   `minTrainingSets...maxTrainingSets` rails and on the same set-adjustable blocks the assembler's
///   own timing fit uses. That lever is a strict *fallback*: a substitute that fits the slot as built
///   outranks every substitute that needs a re-pick, so a swap restructures a slot only when no in-band
///   peer fits it as built, and only when no permitted set count fits at all is a candidate
///   out-of-budget.
///
/// Like every other engine step this is a pure function of its inputs - the slot, the `Workout`, the
/// `User`, the full `library`, `recentLogs`, and the `sessionPolicy` the session was generated against
/// - with no hidden clock or library lookup, so a given
/// request always yields the same outcome and is unit-testable, mirroring `ExercisePoolFilter`,
/// `ProgressionChainSelection`, and `AdaptiveOverload`. Only the substitute's fresh `UUID` varies run
/// to run; the chosen movement and its targets are fully determined by the inputs.

// MARK: - SwapOutcome

/// The result of a swap request: either an equivalent substitute, or an honest "no alternative" when
/// no safe, in-band, in-budget movement exists for the slot.
///
/// "No alternative" is a legitimate, expected outcome (a pattern whose only peers are Strength-Phase
/// skills, ruled out by an injury, or all outside the time budget), not an error - so the UI (US-G03)
/// can show a friendly message and keep the original slot rather than the engine substituting
/// something unsafe or off-pattern.
enum SwapOutcome: Equatable {
    /// A valid substitute, ready to drop into the slot in place of the original.
    case substituted(PrescribedExercise)
    /// No safe, equivalent, in-budget substitute exists; the caller keeps the original slot.
    case noAlternative
}

// MARK: - ExerciseSwap

/// Resolves a deterministic, constraint-respecting substitute for one prescribed slot (US-C08).
enum ExerciseSwap {

    // MARK: Tuning constants

    /// How far a substitute's `difficulty` may sit from the swapped exercise's and still count as
    /// "similar" - the difficulty *band* the substitute must fall within. A band of 1 lets a
    /// difficulty-2 movement swap for a 1, 2, or 3 (still subject to the user's fitness-level cap,
    /// which the eligible pool enforces), so the substitute is comparable, never a leap in either
    /// direction. Tunable.
    static let difficultyBandWidth = 1

    /// The most a swap may move the session's wall-clock, measured over the whole slot -
    /// `sets × workPerSet + (sets - 1) × rest`, each side priced at the target it actually carries - so
    /// the rest periods a set-count change adds or removes are counted, since rest is the one part of
    /// the budget that is exactly known. A candidate no permitted set count brings inside this is
    /// rejected, so a swap never meaningfully alters the session length. Tunable.
    static let slotToleranceSeconds = 30

    /// Extra tolerance a slot the assembler would *not* re-fit gets, as a share of its estimated work.
    ///
    /// A training slot is part exact and part estimate: its rests are a known quantity, and if a
    /// substitute's own target lands it outside the flat gate the set lever moves it back in. A
    /// structural bookend is neither - it is one set, so it has no rest at all and 100% of its cost is
    /// the soft work estimate, and `allowSetAdjust: false` means there is no lever to reach for. Holding
    /// that to the same flat gate is maximum false precision on the one slot with no recourse: it does
    /// not make the session more accurate, it just refuses the swap.
    ///
    /// The share was read off the shipped catalog rather than picked: when it was set, across all 57
    /// movements the widest gap between a movement's own per-set work at its default and its *nearest*
    /// in-band peer's was 30% (`mobility_pigeon` at 100s against `mobility_9090_hip` at 70s; the 95th
    /// percentile 14%). So a 30% band was exactly wide enough to admit every pair the catalog then
    /// authored as equivalent work, and no wider. The later one-set Movement Practice mobility expansion
    /// only narrowed those gaps - `mobility_lizard_lunge` at 90s now sits between pigeon and 90/90 - so
    /// 0.3 is now a safe, slightly conservative upper bound rather than a tight fit, and the whole-library
    /// coverage sweep confirms it still admits every authored-equivalent pair. It is additive over the
    /// flat gate rather than replacing it, so a very small slot keeps the flat allowance instead of being
    /// handed a tighter one.
    static let softSlotToleranceShare = 0.3

    /// How far this slot's planned seconds may move, given the estimated work it carries and whether
    /// the assembler would re-fit it. `workSeconds` is the slot's own `sets × workPerSet`.
    static func slotTolerance(workSeconds: Int, setsAreAdjustable: Bool) -> Int {
        guard !setsAreAdjustable else { return slotToleranceSeconds }
        return slotToleranceSeconds + Int((softSlotToleranceShare * Double(max(0, workSeconds))).rounded())
    }

    // MARK: Entry point

    /// The substitute for `prescription` within `workout`, or `.noAlternative` when none qualifies.
    ///
    /// `prescription` is the slot the user asked to replace; `library` is the full catalog (the
    /// substitute pool is the eligible subset of it). The returned `PrescribedExercise`, when present,
    /// is a different movement in the same pillar and pattern, within the difficulty band and the time
    /// budget, with its own capacity-relative per-set target, the original slot's rest, and the set count
    /// that keeps the slot inside that budget (the original's whenever it already does).
    ///
    /// `sessionPolicy` is the same per-user program the session was assembled against, so a substitute
    /// is sized by the *same* Step 6 levers, at the same scope, the rest of the lineup was: the policy's
    /// `progressionRate`, during cold-start the Start Seed (US-O02, strength and primal only), and on a
    /// Return or its Re-entry Ramp the eased
    /// `reentryScale` (US-E06, read off the session's own `wasReturn` stamp plus the policy's ramp
    /// state, so the swap never re-derives the decision at a different clock). Without them a
    /// mid-session swap would silently re-derive the substitute's target at the neutral levers, handing
    /// an advanced cold-start user a x1.00 slot in a session built at x1.30, or a returning user one
    /// full-volume slot in a session whose whole point is to be uniformly gentle. `sessionPolicy`
    /// defaults to `SessionPolicy.default` (every lever neutral), which reproduces the pre-policy swap
    /// exactly.
    static func swap(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default
    ) -> SwapOutcome {
        let target = prescription.exercise

        // Draw substitutes from the eligible pool: that single filter already guarantees phase,
        // injury, difficulty-cap, recent-skip, and Zero-Equipment-Floor safety, so the swap step
        // never has to (and never gets to) relax any of them.
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs)

        // Movements already in the session, so a swap never hands back a duplicate of something the
        // user is already doing. The original slot is excluded explicitly below, so its presence here
        // is harmless.
        let inSessionIds = Set(workout.blocks.flatMap(\.exercises).map(\.exercise.id))

        // The Start Seed in force for this session (US-O02), so a substitute for a cold-start user
        // opens at the same volume the rest of their lineup did.
        let startVolume = ColdStartOverride.volumeSeed(
            user: user,
            sessionPolicy: sessionPolicy,
            recentLogs: recentLogs
        )

        // The Return / Re-entry Ramp ease in force for this session (US-E06), read off the stamp the
        // assembler already made rather than re-derived against a fresh clock, so a substitute is held
        // back exactly as much as the slot it replaces.
        let reentryScale = ReturnOverride.reentryScale(
            isReturn: workout.wasReturn,
            reentry: sessionPolicy.reentry
        )

        let originalWorkPerSet = SessionAssembly.workSecondsPerSet(of: prescription)
        let originalSlotSeconds = slotSeconds(
            workPerSet: originalWorkPerSet,
            sets: prescription.sets,
            rest: prescription.restSeconds
        )

        // Whether the slot the user is replacing is one the assembler's own timing fit may move set
        // counts on. The one-set blocks are not (`allowSetAdjust: false` on the warm-up, the cooldown,
        // and the mobility Movement Practice block), so a swapped stretch stays the one set it was built
        // as - a stretch is one set at every length, and a swap never reintroduces a multi-set stretch.
        let setsAreAdjustable = blockIsSetAdjustable(containing: prescription, in: workout)

        // How far this slot may move, measured against the slot the user actually has: the flat gate on
        // a slot the set lever can re-fit, widened by the soft-estimate share on a bookend that cannot.
        let tolerance = slotTolerance(
            workSeconds: prescription.sets * originalWorkPerSet,
            setsAreAdjustable: setsAreAdjustable
        )

        // Same pillar + pattern, within the difficulty band, not the original, not already in the
        // session, and reachable inside the slot's budget at some permitted set count. Both sides of
        // that budget check are priced at the target they actually carry - the original at the reps or
        // hold seconds it was prescribed, the candidate at the target Step 6 would give it here - so
        // the tolerance bounds the session's real wall-clock rather than two movements' default-sized
        // estimates.
        let candidates = pool.compactMap { candidate -> Candidate? in
            guard
                candidate.id != target.id,
                candidate.pillar == target.pillar,
                candidate.movementPattern == target.movementPattern,
                abs(candidate.difficulty - target.difficulty) <= difficultyBandWidth,
                !inSessionIds.contains(candidate.id)
            else { return nil }

            let overload = overloadTarget(
                for: candidate,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                reentryScale: reentryScale,
                startVolume: startVolume
            )
            let workPerSet = SessionAssembly.workSecondsPerSet(
                for: candidate,
                reps: overload.reps,
                durationSeconds: overload.durationSeconds
            )
            guard let fit = bestFitSets(
                workPerSet: workPerSet,
                rest: prescription.restSeconds,
                originalSets: prescription.sets,
                originalSlotSeconds: originalSlotSeconds,
                setsAreAdjustable: setsAreAdjustable,
                tolerance: tolerance
            ) else { return nil }
            return Candidate(exercise: candidate, overload: overload, sets: fit.sets, drift: fit.drift)
        }
        guard !candidates.isEmpty else { return .noAlternative }

        let recentlyUsed = recentlyUsedIds(recentLogs: recentLogs, window: sessionPolicy.varietyWindow)
        let chosen = candidates.min { lhs, rhs in
            // 1. Leave the slot's shape alone. The set lever is a *fallback* for when no in-band peer
            //    fits the slot as built, not a way to shave seconds off an otherwise fine swap, so a
            //    candidate that fits at the original count outranks every candidate that needs a
            //    re-pick. Only when none does are the re-picked ones considered at all.
            let lhsKeeps = lhs.sets == prescription.sets
            let rhsKeeps = rhs.sets == prescription.sets
            if lhsKeeps != rhsKeeps { return lhsKeeps }
            // 2. Closest difficulty to the original (a true peer beats a band-edge option).
            let lhsGap = abs(lhs.exercise.difficulty - target.difficulty)
            let rhsGap = abs(rhs.exercise.difficulty - target.difficulty)
            if lhsGap != rhsGap { return lhsGap < rhsGap }
            // 3. Smallest change to the session's wall-clock.
            if lhs.drift != rhs.drift { return lhs.drift < rhs.drift }
            // 4. Among re-picked candidates, the smallest move off the original count.
            let lhsSetMove = abs(lhs.sets - prescription.sets)
            let rhsSetMove = abs(rhs.sets - prescription.sets)
            if lhsSetMove != rhsSetMove { return lhsSetMove < rhsSetMove }
            // 5. Variety: prefer a movement the user has not done in the last few sessions.
            let lhsRecent = recentlyUsed.contains(lhs.exercise.id)
            let rhsRecent = recentlyUsed.contains(rhs.exercise.id)
            if lhsRecent != rhsRecent { return !lhsRecent }
            // 6. Deterministic final tie-break.
            return lhs.exercise.id < rhs.exercise.id
        }!

        return .substituted(
            materialize(chosen.exercise, at: chosen.overload, sets: chosen.sets, like: prescription)
        )
    }

    // MARK: Helpers

    /// One in-band, in-budget substitute under consideration: the movement, the Step 6 target already
    /// resolved for it (so the budget check and the materialized slot can never disagree about how big
    /// the substitute is), the set count that brings its slot closest to the original's planned
    /// seconds, and how far the slot still moves the session's wall-clock at that count.
    private struct Candidate {
        let exercise: Exercise
        let overload: OverloadTarget
        let sets: Int
        let drift: Int
    }

    /// The set count a substitute runs at, and the wall-clock drift that leaves - or `nil` when no
    /// permitted count brings the slot inside `tolerance`, which is the one honest reason to reject a
    /// candidate on time.
    ///
    /// Set count is the lever here because the substitute's per-set *target* is not transferable: Step 6
    /// sizes it from the user's demonstrated capacity in that movement, so a peer they have never logged
    /// opens at its own default however grown the slot it replaces is. Sets absorb that difference, and
    /// they are also the best-founded lever available - each set added or removed moves a real,
    /// deterministic rest period alongside its share of the estimated work.
    ///
    /// The original count wins whenever it is already in budget, so a swap leaves the slot's shape alone
    /// unless doing so would push the session out of its stated minutes. Otherwise the closest-fitting
    /// count inside `minTrainingSets...maxTrainingSets` is taken, ties going to the smaller move, so the
    /// re-pick can neither leave the assembler's own rails nor drift far from the slot the user chose to
    /// replace. On a block the assembler would not adjust either, only the original count is considered.
    ///
    /// This settles each candidate's *own* best count; preferring a candidate that needed no re-pick
    /// over one that did is the selection's job (criterion 1), because whether restructuring was
    /// avoidable is only knowable once every candidate has been priced.
    private static func bestFitSets(
        workPerSet: Int,
        rest: Int,
        originalSets: Int,
        originalSlotSeconds: Int,
        setsAreAdjustable: Bool,
        tolerance: Int
    ) -> (sets: Int, drift: Int)? {
        func drift(at sets: Int) -> Int {
            abs(slotSeconds(workPerSet: workPerSet, sets: sets, rest: rest) - originalSlotSeconds)
        }

        let atOriginal = drift(at: originalSets)
        if atOriginal <= tolerance { return (originalSets, atOriginal) }
        guard setsAreAdjustable else { return nil }

        let best = (SessionAssembly.minTrainingSets...SessionAssembly.maxTrainingSets)
            .map { (sets: $0, drift: drift(at: $0)) }
            .min { lhs, rhs in
                lhs.drift != rhs.drift
                    ? lhs.drift < rhs.drift
                    : abs(lhs.sets - originalSets) < abs(rhs.sets - originalSets)
            }
        guard let best, best.drift <= tolerance else { return nil }
        return best
    }

    /// Whether the block holding `prescription` is one the assembler's timing fit may move set counts
    /// on. The warm-up and the cooldown bookends are both built with `allowSetAdjust: false` - a stretch
    /// is one set by construction, at every length (see `SessionAssembly.mobilityBlock`) - so a swap must
    /// not use the set lever on either; a substituted stretch stays the one set it was built as, and only
    /// the strength/primal training blocks are adjustable. The `.mobility` case is kept as defensive
    /// handling only - US-M01 retired the Movement Practice mobility training block, so no `.mobility`
    /// block is emitted today. A slot the workout does not contain is treated as fixed, the conservative
    /// default.
    private static func blockIsSetAdjustable(containing prescription: PrescribedExercise, in workout: Workout) -> Bool {
        guard let block = workout.blocks.first(where: { block in
            block.exercises.contains { $0.id == prescription.id }
        }) else { return false }
        switch block.category {
        case .warmup, .cooldown, .mobility: return false
        case .strength, .primal: return true
        }
    }

    /// The Step 6 target for a substitute, resolved under **every** lever the slot it replaces was
    /// sized with, *at the same scope the assembler applies each one*: the policy's `progressionRate`
    /// (US-E03) and the Return / Re-entry Ramp ease (US-E06) reach every pillar, while the cold-start
    /// Start Seed's volume (US-O02) reaches only strength and primal - `Builder.mobilityItems` sizes a
    /// stretch with the first two levers alone, so the warm-up and cooldown bookends are identical
    /// for a beginner and an advanced user, and a swapped stretch must be too. It is the single place the
    /// swap seam talks to `AdaptiveOverload`, so the budget check and the materialized prescription are
    /// sized identically and a lever cannot go missing - or be scoped differently - in one but not the
    /// other.
    private static func overloadTarget(
        for exercise: Exercise,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        reentryScale: Double,
        startVolume: ColdStartOverride.VolumeSeed
    ) -> OverloadTarget {
        let volume = exercise.pillar == .mobility ? .neutral : startVolume
        return AdaptiveOverload.target(
            for: exercise,
            recentLogs: recentLogs,
            progressionRate: sessionPolicy.progressionRate,
            reentryScale: reentryScale,
            startingRepMultiplier: volume.repMultiplier,
            startingSets: volume.sets
        )
    }

    /// Builds the substitute prescription: the chosen movement at the original slot's rest and the set
    /// count its budget fit settled on (the original's unless that was out of budget), carrying the
    /// Step 6 target resolved for it under the session's own policy. The target is reps for a rep-based
    /// movement and hold seconds for a hold, matched to the substitute's `isHold`, so a rep↔hold swap
    /// within a pattern still yields a well-formed slot.
    private static func materialize(
        _ exercise: Exercise,
        at overload: OverloadTarget,
        sets: Int,
        like prescription: PrescribedExercise
    ) -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: exercise.isHold ? nil : overload.reps,
            durationSeconds: exercise.isHold ? overload.durationSeconds : nil,
            restSeconds: prescription.restSeconds
        )
    }

    /// Planned wall-clock of one slot in isolation: `sets × workPerSet + (sets - 1) × rest`, where
    /// `workPerSet` is `SessionAssembly.workSecondsPerSet` at the target the slot actually carries -
    /// the same formula, over the same work model, that the assembly step's `plannedSeconds` sums over
    /// every slot. Both sides of a swap's budget check go through it, so the check is consistent with
    /// how the session was sized and the rest a set-count change moves is counted.
    private static func slotSeconds(workPerSet: Int, sets: Int, rest: Int) -> Int {
        sets * workPerSet + max(0, sets - 1) * rest
    }

    /// Ids worked (non-skipped) in the most recent few sessions, so a swap can prefer a movement the
    /// user has not just done. The window is the policy's own `varietyWindow`, mirroring Step 5.
    private static func recentlyUsedIds(recentLogs: [WorkoutLog], window: Int) -> Set<String> {
        let recentSessions = recentLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(max(0, window))
        return recentSessions.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }
}
