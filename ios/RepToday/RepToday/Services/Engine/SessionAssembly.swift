import Foundation

/// Pipeline Step 7 of the deterministic engine (US-C07): take everything Steps 1-6 decided and
/// assemble a complete, playable `Workout` that opens with a warm-up, closes with a cooldown when
/// it runs long, and lands within ±1 minute of the minutes the user asked for.
///
/// This is the step that turns the pipeline's per-decision outputs into the structured session the
/// active-session player renders:
/// - **Shape** (Step 1, `SessionShapeTemplate`) decides single-focus vs. blend.
/// - **Pillars** (Step 2, `PillarPlan`) decide which pillar a single-focus trains, or - for a blend -
///   how the training time splits: the staleness `PillarWeights` size the blocks, so the staler pillar
///   both leads and gets the larger share. A short/full blend sizes strength (primal folded in) and
///   mobility; an extended blend (US-E02) promotes primal to a third, `locomotion`-driven block.
/// - **Pattern, exercise, and target** (Steps 3-6, `PatternFocus` / `ProgressionChainSelection` /
///   `AdaptiveOverload`) fill each training block: the stalest patterns first, the ability-matched
///   exercise in each, and that exercise's capacity-relative reps/sets/hold. During cold start Step
///   0's Start Seed (US-O02) is resolved once here and threaded into all three - it bands the
///   strength/primal pool, tells Step 5 which chains it withheld, and sizes Step 6's no-history
///   target - so a self-reported level reaches every part of the block that depends on it.
///
/// On top of those it owns two things the earlier steps deliberately left to assembly:
/// - **Structure** - every session opens with a `.warmup` block (mobility); a `.cooldown` block of
///   static stretches closes any session longer than `cooldownThresholdMinutes`. In a short
///   mobility-led session the opening warm-up and the Movement Practice block are both mobility, so
///   the opening flow doubles as warm-up + training, exactly as the PRD describes.
/// - **Timing fit** - the planned wall-clock is `Σ(sets × workPerSet) + rests + transitions`, where
///   `workPerSet` re-prices the movement's estimate as a fixed per-set setup cost plus the per-unit
///   work of the target Step 6 actually prescribed (see `workSecondsPerSet`); a
///   deterministic best-fit pass trims or extends the session (adding/removing whole exercises or
///   individual sets, never touching the capacity-relative *per-set* target from Step 6) until it
///   lands within `toleranceSeconds` of the request.
///
/// Identity and the reference clock enter here (the earlier steps are clock-free and id-free): the
/// `Workout`/`WorkoutBlock`/`PrescribedExercise` ids are fresh `UUID`s and `createdAt`/staleness are
/// measured against the caller-supplied `asOf`. The *content* of the assembled session (which
/// exercises, in which order, at what sets/reps) is a pure, deterministic function of the inputs;
/// only the ids vary run to run, so tests assert structure and timing rather than whole-`Workout`
/// equality.
enum SessionAssembly {

    // MARK: - Tuning constants

    /// Seconds of transition between two consecutive exercises (move to the next spot, reset). Counted
    /// once per gap across the whole session, matching `Σ ... + transitions`.
    static let transitionSeconds = 15
    /// Rest between sets of a strength/primal movement.
    static let strengthRestSeconds = 40
    /// Rest between sets of a mobility movement (a stretch needs little reset).
    static let mobilityRestSeconds = 15
    /// The ±window the assembled session must land within around the requested time (1 minute).
    static let toleranceSeconds = 60

    /// Set-count rails the timing-fit pass may move a *training* block's exercises between. The
    /// per-set target (reps/seconds) from Step 6 is never touched; only how many sets are done is a
    /// timing lever, and only within these rails so a fit never produces an absurd set count.
    static let minTrainingSets = 1
    static let maxTrainingSets = 4

    /// Per-block ceilings on how many distinct movements each mobility-sourced block may draw from the
    /// shared 12-movement pool. The warm-up and the cooldown reserve their movements first (the
    /// cooldown before any Movement Practice block - see `buildBlocks`); the elastic Movement Practice
    /// block then takes whatever remains and makes up any shortfall with its set-count lever, so no
    /// block ever starves the cooldown of its static holds.
    static let maxWarmupExercises = 3
    static let maxMobilityTrainingExercises = 8
    static let maxCooldownExercises = 4

    /// Sessions longer than this many minutes close with a cooldown stretch (so 15/20/30 get one,
    /// 5/10 do not).
    static let cooldownThresholdMinutes = 10

    /// Hard backstop on the timing-fit loop; each accepted step strictly shrinks the timing error, so
    /// the loop converges well within this in practice.
    static let maxFitIterations = 200

    /// Seconds of work in one second of a prescribed hold, *per side* - the per-unit half of the work
    /// model in `workSecondsPerSet`, and the one half that needs no calibration at all: a 40-second
    /// hold is 40 seconds of work by definition, and a 40-second hold prescribed `isPerSide` is 80.
    static let secondsPerHoldSecond = 1.0

    /// The fixed per-set cost of getting into position, bracing, and getting out again - the *setup*
    /// half of the work model in `workSecondsPerSet` for a rep-based movement.
    ///
    /// A hold needs no such constant: its per-unit cost is known a priori (see `secondsPerHoldSecond`),
    /// so its setup is simply the authored remainder `estimate - sides × defaultDurationSeconds`. A rep
    /// carries no authored duration, so exactly one of the two halves has to be assumed and the other
    /// read off the movement's own authored cadence. Assuming the setup - and deriving the cadence - is
    /// the right way round: cadence genuinely varies per movement (the catalog authors anything from
    /// `hinge_glute_bridge` at 15 reps in 40s to `push_one_arm` at 3 in 50s), while getting down onto
    /// the floor and back up is much the same work whatever the movement is.
    ///
    /// The value is calibrated from the *holds*, where setup is observed rather than fitted: across the
    /// catalog's 17 holds the authored remainder is 5-25 seconds with a median of exactly 10. Taking
    /// the constant from a different family of movements than the ones it is then applied to is what
    /// keeps it from being circular - the previous per-rep constant was calibrated from the four
    /// rep-based entries it subsequently assigned zero setup to, which is no calibration at all.
    static let setupSecondsPerSet = 10.0

    /// The most of a **rep-based** movement's authored per-set estimate that `workSecondsPerSet` will
    /// treat as fixed setup. A movement whose estimate is mostly setup carries almost no cadence signal,
    /// so its own default would stop saying anything useful about a target moved off it; capping the
    /// setup share at half keeps `setupSecondsPerSet` from swallowing a short authored estimate. Inert
    /// across the shipped catalog (every estimate is at least 35s), it bounds a future entry rather than
    /// today's.
    ///
    /// It deliberately does *not* apply to holds. A hold's setup is not assumed but observed - the
    /// authored remainder left once its known per-unit cost is subtracted - so there is no constant to
    /// bound, and capping it would corrupt a figure the catalog states outright. Several shipped holds
    /// are legitimately over this share (`core_l_sit` implies 25s of setup on a 35s estimate, 71%;
    /// `core_tuck_l_sit` 23s on 35s, 66%), which is the catalog describing a movement that takes longer
    /// to get into than to hold, not an authoring error.
    static let maxSetupShareOfEstimate = 0.5

    // MARK: - Entry point

    /// Assembles the complete session for `requestedMinutes` (pipeline Step 7).
    ///
    /// Runs the full pipeline over `library`, `user`, and `recentLogs`, structures the result into
    /// warm-up / training / cooldown blocks per the Step 1 shape, and timing-fits it to within
    /// `toleranceSeconds` of the request. `asOf` is the reference "now" (used for `createdAt` and all
    /// staleness math) so the function stays a pure function of its inputs.
    ///
    /// `sessionPolicy` is the per-user program the engine runs on (US-E03): its `pillarWeighting`
    /// scales Step 2's staleness split, its `varietyWindow` sets Step 5's no-repeat window, and its
    /// `progressionRate` paces Step 6's overload bump. It also carries the situational overrides the
    /// engine reads: the `coldStartContract` for a brand-new user (US-E04) and the `reentry` ramp for a
    /// returning one (US-E06). It defaults to `SessionPolicy.default` (every lever neutral, no
    /// overrides), which reproduces pre-policy behavior exactly, so an unpolicied caller is unchanged.
    static func assemble(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Workout {
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)

        var blocks = planBlocks(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: asOf,
            calendar: calendar
        )
        // Shape the blend's two training blocks toward their staleness-weighted shares first, then let
        // the global timing fit land the overall total within tolerance.
        shapeTowardTargets(&blocks)
        fit(&blocks, targetSeconds: requestedMinutes * 60)

        return Workout(
            id: UUID(),
            createdAt: asOf,
            shape: template.shape,
            focusPillar: focusPillar(of: blocks),
            requestedMinutes: requestedMinutes,
            wasReturn: isReturnSession(
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                asOf: asOf,
                calendar: calendar
            ),
            blocks: blocks.compactMap { $0.materialize() }
        )
    }

    /// Whether this generation is a Return (US-E06): a real gap since the last logged session, but
    /// only in the steady state - a Return is suppressed while cold-start still owns the first
    /// sessions (the two overrides are mutually exclusive). Computed here as the single source of
    /// truth so the pillar/pool/volume overrides in `planBlocks` and the `Workout.wasReturn` flag the
    /// assembler stamps always agree, and the post-session log-writer (US-L01) records the same
    /// decision the engine acted on rather than re-deriving it at a different `asOf`.
    static func isReturnSession(
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !ColdStartOverride.isActive(user: user, sessionPolicy: sessionPolicy)
            && ReturnOverride.isReturn(recentLogs: recentLogs, asOf: asOf, calendar: calendar)
    }

    /// Builds the seeded block skeleton (warm-up, the pillar plan's training block(s) with their
    /// weight targets, and an optional cooldown) before the timing fit - the structural output of
    /// Steps 1-6. Exposed internally so tests can inspect block reserves and per-block weight targets
    /// prior to the global fit consuming them. `sessionPolicy` threads the US-E03 levers into
    /// Steps 2/5/6 (see `assemble`) and the situational Step 0 cold-start (US-E04) and Step 0.5 Return
    /// (US-E06) overrides; it defaults to `SessionPolicy.default` (neutral, no regression).
    static func planBlocks(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        asOf: Date,
        calendar: Calendar = .current
    ) -> [PlannedBlock] {
        let template = SessionShapeTemplate.select(requestedMinutes: requestedMinutes)

        // Step 0 (US-E04): the cold-start override runs before Steps 1-6 while a brand-new user is
        // still finding their footing. Step 0.5 (US-E06): the Return override serves a returning user
        // an easy, winnable session. The two are mutually exclusive - a Return is suppressed while
        // cold-start is active, since cold-start already serves gentle, capped, contrast sessions - so
        // the pillar-plan and pool overrides never fight over the same inputs. Both are no-ops in the
        // steady state, so a warmed-up, present user runs exactly the US-E03 pipeline.
        let isReturn = isReturnSession(
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: asOf,
            calendar: calendar
        )

        let coldStartPlan = ColdStartOverride.overridePlan(
            PillarPlan.select(
                template: template,
                recentLogs: recentLogs,
                profile: user.profile,
                pillarWeighting: sessionPolicy.pillarWeighting,
                asOf: asOf,
                calendar: calendar
            ),
            template: template,
            user: user,
            sessionPolicy: sessionPolicy
        )
        // On a Return, discipline overrides optimization: mobility leads regardless of staleness.
        let pillarPlan = ReturnOverride.overridePlan(coldStartPlan, isReturn: isReturn)

        // The Start Seed (US-O02), resolved exactly once for the whole generation. Its two halves - the
        // difficulty floor the training pool is banded to and the volume a no-history prescription
        // opens at - have to move together, so all three consumers below read this one resolution
        // rather than each re-deriving it from `recentLogs`.
        let startSeed = ColdStartOverride.startSeed(
            user: user,
            sessionPolicy: sessionPolicy,
            recentLogs: recentLogs
        )

        // On a Return, cap the eligible difficulty so a strong pre-gap history can't serve a punishing
        // tier (layered after the cold-start band; only one is ever active). The cold-start band is the
        // Start Seed's floor (US-O02) applied under the cap (US-G01): together they restrict the
        // strength/primal training pool to `[startingDifficultyFloor, cappedMaxDifficulty]` so an
        // active user's first sessions open at the band entry rather than the absolute entry tier.
        let pool = ReturnOverride.returnPool(
            ColdStartOverride.startBandedPool(
                ColdStartOverride.cappedPool(
                    ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs),
                    user: user,
                    sessionPolicy: sessionPolicy
                ),
                seed: startSeed
            ),
            isReturn: isReturn
        )

        // The Return / Re-entry Ramp holds Step 6's volume below normal: the gentle floor on the Return
        // itself, climbing back over the following ramp sessions (`sessionPolicy.reentry`). Neutral in
        // the steady state, so it is a no-op.
        let reentryScale = ReturnOverride.reentryScale(isReturn: isReturn, reentry: sessionPolicy.reentry)

        // The Start Seed's volume half: the reps/sets a no-history prescription opens at, matched to
        // the self-reported fitness level and eased by any cold-start down-signal already logged, so it
        // stays in step with the banded pool above. Neutral outside the cold-start window.
        let startVolume = startSeed.volume

        // The other half of the Start Seed band: the movements it withholds accrue no history, so
        // Step 5 is told they were never on offer rather than outgrown. Without it their untouched
        // entry tiers win the freshness preference outright the moment the band lifts.
        let withheldByStartSeed = ColdStartOverride.withheldByStartSeed(
            library: library,
            user: user,
            sessionPolicy: sessionPolicy,
            seed: startSeed
        )

        var builder = Builder(
            library: library,
            pool: pool,
            recentLogs: recentLogs,
            progressionRate: sessionPolicy.progressionRate,
            varietyWindow: sessionPolicy.varietyWindow,
            reentryScale: reentryScale,
            startVolume: startVolume,
            withheldByStartSeed: withheldByStartSeed,
            asOf: asOf,
            calendar: calendar
        )
        return builder.buildBlocks(
            pillarPlan: pillarPlan,
            template: template,
            requestedMinutes: requestedMinutes
        )
    }

    // MARK: - Focus pillar

    /// The pillar a training block trains, or `nil` for the structural bookends (`warmup`/`cooldown`).
    static func pillar(of category: ExerciseCategory) -> Pillar? {
        switch category {
        case .strength: return .strength
        case .mobility: return .mobility
        case .primal: return .primal
        case .warmup, .cooldown: return nil
        }
    }

    /// The session's reported `focusPillar`, read from the training blocks the assembly *actually*
    /// produced rather than the pre-assembly pillar plan. A single-focus session leaves exactly one
    /// non-empty training block, and its pillar is the focus; a blend leaves two or three (no single
    /// focus, so `nil`), and a degenerate warmup-only session leaves none. Reading it from the built
    /// blocks keeps the label truthful when a cold-start primal day degrades to a strength/mobility
    /// block because the capped pool left no eligible locomotion movement (US-E04).
    static func focusPillar(of blocks: [PlannedBlock]) -> Pillar? {
        let training = blocks.filter { !$0.items.isEmpty && pillar(of: $0.category) != nil }
        guard training.count == 1 else { return nil }
        return pillar(of: training[0].category)
    }

    // MARK: - Planned wall-clock

    /// The planned seconds one set of `exercise` takes at the per-set target Step 6 actually
    /// prescribed: a fixed per-set `setup` cost plus `perUnit × prescribed` of work.
    ///
    /// `Exercise.estimatedTimePerSetSeconds` is a single constant calibrated against the movement's
    /// *own* default per-set value (`defaultReps` / `defaultDurationSeconds`), so reading it directly
    /// silently assumes every set is prescribed at that default. It is not: Step 6 is
    /// capacity-relative, and the cold-start Start Seed (US-O02) opens an active user at up to x1.30 of
    /// the default on their very first session.
    ///
    /// Nor is that estimate pure per-unit work: getting into position, bracing and getting out again is
    /// paid once per set whether the set is 8 reps or 20. Scaling the whole constant by
    /// `prescribed / default` therefore overstates a capacity-grown set and understates a shrunk one,
    /// so the estimate is split into its two components instead - one assumed, the other read off the
    /// movement's own authored fields:
    /// - a **hold**'s per-unit cost is known a priori: `secondsPerHoldSecond` per prescribed second,
    ///   *doubled* when the movement is `isPerSide`, because a "20 second" side plank is 20 seconds
    ///   left plus 20 seconds right. Its setup is then the authored remainder,
    ///   `estimate - sides × defaultDurationSeconds` - 5s for `core_side_plank`, 10s for
    ///   `mobility_pigeon` - so a grown 40s side plank costs 85s, not the 65s a per-side-blind split
    ///   charged or the 90s strict proportionality charged.
    /// - a **rep** carries no authored duration to anchor the per-unit half, so the other half is the
    ///   assumed one: setup is `setupSecondsPerSet` (capped by `maxSetupShareOfEstimate`), and the
    ///   cadence is the authored remainder `(estimate - setup) / defaultReps`. Reading cadence per
    ///   movement is what keeps per-side and slow-tempo reps honest - `push_archer` ("3x8 clean reps per
    ///   side", 5 reps in 50s) prices 8 reps at 74s rather than the 59s a fixed 3s-per-rep cadence gave.
    ///
    /// Both halves reproduce `estimatedTimePerSetSeconds` exactly at the movement's own default, so a
    /// default-sized set is priced exactly as the catalog authored it and only a target Step 6 moved
    /// off the default is re-priced. That keeps the planned wall-clock - and therefore the ±1 minute
    /// promise the timing fit is measured against - honest about the session the user is actually going
    /// to do. A movement with no default to scale against falls back to the flat estimate.
    ///
    /// - Note: This is per-set *work* only; the between-set rest and the inter-exercise transition are
    ///   counted separately by `plannedSeconds`.
    /// - Note: The work half of a session is never *timed*. Nothing counts a rep or a hold down; the
    ///   only countdown in the player is the rest timer, and a completed set logs the target it was
    ///   prescribed rather than anything measured. So this is a planning-only quantity that never
    ///   reaches the UI and is never compared against reality - its single job is fitting a session to
    ///   the minutes the user asked for. Chasing per-second accuracy on a self-paced activity would be
    ///   false precision; what matters, and what the split above buys, is that the model carries no
    ///   *systematic* bias, because a consistent per-slot error accumulates across a session where
    ///   random error averages out. Set count is the better-founded lever for the same reason: each set
    ///   added or removed moves a real, deterministic rest period.
    static func workSecondsPerSet(for exercise: Exercise, reps: Int?, durationSeconds: Int?) -> Int {
        let estimate = exercise.estimatedTimePerSetSeconds
        let baseline = exercise.isHold ? exercise.defaultDurationSeconds : exercise.defaultReps
        let prescribed = exercise.isHold ? durationSeconds : reps
        guard let baseline, baseline > 0, let prescribed, prescribed > 0 else { return estimate }

        let authoredPerUnit = Double(estimate) / Double(baseline)
        let perUnit: Double
        if exercise.isHold {
            // Known per-unit cost; the `min` keeps a hold whose authored estimate does not even cover
            // its own sides (bad authoring) from yielding a negative setup.
            perUnit = min(Double(exercise.sidesPerSet) * secondsPerHoldSecond, authoredPerUnit)
        } else {
            // Assumed setup, derived cadence; the `max` enforces `maxSetupShareOfEstimate`.
            perUnit = max(
                (Double(estimate) - setupSecondsPerSet) / Double(baseline),
                authoredPerUnit * (1 - maxSetupShareOfEstimate)
            )
        }
        let setup = max(0, Double(estimate) - perUnit * Double(baseline))
        return max(1, Int((setup + perUnit * Double(prescribed)).rounded()))
    }

    /// The planned seconds one set of a prescribed slot takes, at the target it actually carries.
    static func workSecondsPerSet(of prescription: PrescribedExercise) -> Int {
        workSecondsPerSet(
            for: prescription.exercise,
            reps: prescription.reps,
            durationSeconds: prescription.durationSeconds
        )
    }

    /// The planned wall-clock of an assembled `Workout`: `Σ(sets × workPerSet) + rests +
    /// transitions`. The same formula the timing-fit pass minimizes against, exposed so callers and
    /// tests measure the session exactly as the engine sized it.
    static func plannedSeconds(of workout: Workout) -> Int {
        let items = workout.blocks.flatMap(\.exercises)
        let work = items.reduce(0) { sum, item in
            sum + item.sets * workSecondsPerSet(of: item)
                + max(0, item.sets - 1) * item.restSeconds
        }
        return work + max(0, items.count - 1) * transitionSeconds
    }

    // MARK: - Timing fit

    /// Trims or extends `blocks` until the planned wall-clock is as close to `targetSeconds` as the
    /// available adjustments allow (comfortably inside `toleranceSeconds` in practice, not merely at
    /// its edge).
    ///
    /// A deterministic best-fit loop: each pass measures the signed error, then - adding when short,
    /// removing when long - picks the single adjustment (extra/fewer set, extra/dropped exercise) that
    /// brings the planned time closest to target, applying it only if it strictly reduces the absolute
    /// error. The loop runs to the local minimum (it stops only when no adjustment can shrink the gap
    /// further), so it does not park on the first value that happens to fall just inside tolerance.
    /// Because every accepted step strictly shrinks a non-negative integer error, the loop converges.
    static func fit(_ blocks: inout [PlannedBlock], targetSeconds: Int) {
        for _ in 0..<maxFitIterations {
            let error = totalSeconds(blocks) - targetSeconds
            if error == 0 { return }

            let candidates = error < 0 ? additions(in: blocks) : removals(in: blocks)
            var best: (adjustment: Adjustment, resultError: Int)?
            for (adjustment, delta) in candidates {
                let resultError = abs(error + delta)
                guard resultError < abs(error) else { continue }
                if best == nil || resultError < best!.resultError {
                    best = (adjustment, resultError)
                }
            }
            guard let chosen = best?.adjustment else { return }
            apply(chosen, to: &blocks)
        }
    }

    /// Planned wall-clock of a set of blocks mid-assembly (same formula as `plannedSeconds(of:)`).
    static func totalSeconds(_ blocks: [PlannedBlock]) -> Int {
        let items = blocks.flatMap(\.items)
        let work = items.reduce(0) { $0 + $1.seconds }
        return work + max(0, items.count - 1) * transitionSeconds
    }

    /// Planned wall-clock of a single block in isolation: its items' work + rests + the transitions
    /// *between* those items. Because every timing-fit adjustment touches exactly one block, the same
    /// add/drop deltas the global fit uses also describe this per-block measure exactly, so the
    /// weight-shaping pass and the global fit stay consistent.
    static func blockSeconds(_ block: PlannedBlock) -> Int {
        let work = block.items.reduce(0) { $0 + $1.seconds }
        return work + max(0, block.items.count - 1) * transitionSeconds
    }

    // MARK: - Weighted shaping

    /// Grows each block that carries a `targetSeconds` toward that share (a best-fit greedy scoped to
    /// the single block), so a blend's training time is split by the Step 2 pillar weights *before*
    /// `fit` lands the overall total. It uses the same levers as the global fit - set counts within the
    /// rails and reserve promotion - and never touches the capacity-relative per-set target from Step 6.
    static func shapeTowardTargets(_ blocks: inout [PlannedBlock]) {
        for index in blocks.indices {
            guard let target = blocks[index].targetSeconds else { continue }
            for _ in 0..<maxFitIterations {
                let error = blockSeconds(blocks[index]) - target
                if error == 0 { break }

                let candidates = error < 0
                    ? additions(in: blocks, restrictedTo: index)
                    : removals(in: blocks, restrictedTo: index)
                var best: (adjustment: Adjustment, resultError: Int)?
                for (adjustment, delta) in candidates {
                    let resultError = abs(error + delta)
                    guard resultError < abs(error) else { continue }
                    if best == nil || resultError < best!.resultError {
                        best = (adjustment, resultError)
                    }
                }
                guard let chosen = best?.adjustment else { break }
                apply(chosen, to: &blocks)
            }
        }
    }

    /// Every time-increasing adjustment available, with the seconds it would add: one per
    /// set-adjustable item below the set cap (add a set), and one per block holding a reserve exercise
    /// (promote the next reserve exercise). Enumerated in a fixed block/item order so ties resolve
    /// deterministically. `restrictedTo`, when set, limits the enumeration to a single block (used by
    /// the weight-shaping pass to grow one training block toward its own share).
    private static func additions(in blocks: [PlannedBlock], restrictedTo only: Int? = nil) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if let only, only != blockIndex { continue }
            if block.allowSetAdjust {
                for (itemIndex, item) in block.items.enumerated() where item.sets < maxTrainingSets {
                    let delta = item.workSecondsPerSet + item.restSeconds
                    result.append((.addSet(block: blockIndex, item: itemIndex), delta))
                }
            }
            if let next = block.reserve.first {
                // A reserve may be promoted at any set count within the rails, not only at the count
                // Step 6 prescribed. Without that, a block whose items already sit at `maxTrainingSets`
                // (an advanced cold-start Start Seed opens at 4) has no fine-grained lever left at all:
                // its only move is a whole extra exercise at full volume, which a short session cannot
                // absorb, and the greedy fit parks minutes away from the request.
                let counts = block.allowSetAdjust
                    ? Array(minTrainingSets...max(minTrainingSets, next.sets))
                    : [next.sets]
                for sets in counts {
                    var probe = next
                    probe.sets = sets
                    result.append((
                        .addReserve(block: blockIndex, sets: sets),
                        probe.seconds + transitionSeconds
                    ))
                }
            }
        }
        return result
    }

    /// Every time-decreasing adjustment available, with the (negative) seconds it would remove: one
    /// per set-adjustable item above the set floor (drop a set), and one per block holding more than
    /// its required minimum exercises (drop the last exercise). `restrictedTo`, when set, limits the
    /// enumeration to a single block (used by the weight-shaping pass).
    private static func removals(in blocks: [PlannedBlock], restrictedTo only: Int? = nil) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if let only, only != blockIndex { continue }
            if block.allowSetAdjust {
                for (itemIndex, item) in block.items.enumerated() where item.sets > minTrainingSets {
                    let delta = -(item.workSecondsPerSet + item.restSeconds)
                    result.append((.removeSet(block: blockIndex, item: itemIndex), delta))
                }
            }
            if block.items.count > block.minItems, let last = block.items.last {
                result.append((.dropItem(block: blockIndex), -(last.seconds + transitionSeconds)))
            }
        }
        return result
    }

    private static func apply(_ adjustment: Adjustment, to blocks: inout [PlannedBlock]) {
        switch adjustment {
        case let .addSet(block, item):
            blocks[block].items[item].sets += 1
        case let .removeSet(block, item):
            blocks[block].items[item].sets -= 1
        case let .addReserve(block, sets):
            var promoted = blocks[block].reserve.removeFirst()
            promoted.sets = sets
            blocks[block].items.append(promoted)
        case let .dropItem(block):
            let removed = blocks[block].items.removeLast()
            blocks[block].reserve.insert(removed, at: 0)
        }
    }

    /// One timing-fit move, addressed by block/item index into the in-progress `[PlannedBlock]`.
    private enum Adjustment {
        case addSet(block: Int, item: Int)
        case removeSet(block: Int, item: Int)
        case addReserve(block: Int, sets: Int)
        case dropItem(block: Int)
    }
}

// MARK: - PlannedItem

/// One exercise as it is being sized during assembly: the movement, its capacity-relative per-set
/// target (reps or hold seconds from Step 6), the current set count (a timing lever), and the rest
/// between sets. Materializes into a playable `PrescribedExercise` once assembly is done.
struct PlannedItem: Equatable {
    let exercise: Exercise
    let reps: Int?
    let durationSeconds: Int?
    var sets: Int
    let restSeconds: Int

    /// Planned seconds for one set at this item's actual per-set target (see
    /// `SessionAssembly.workSecondsPerSet(for:reps:durationSeconds:)`), so a seeded or
    /// capacity-grown prescription is sized as the work it really is.
    var workSecondsPerSet: Int {
        SessionAssembly.workSecondsPerSet(for: exercise, reps: reps, durationSeconds: durationSeconds)
    }

    /// Planned seconds for this item alone: `sets × workPerSet + (sets - 1) × rest`.
    var seconds: Int {
        sets * workSecondsPerSet + max(0, sets - 1) * restSeconds
    }

    func materialize() -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: reps,
            durationSeconds: durationSeconds,
            restSeconds: restSeconds
        )
    }
}

// MARK: - PlannedBlock

/// A session block being assembled: its title and structural `category` (warm-up / strength /
/// mobility / cooldown), the exercises currently in it, a `reserve` of further candidates the timing
/// fit may promote, whether its exercises' set counts are a timing lever, and the floor on how many
/// exercises it must keep.
struct PlannedBlock {
    let title: String
    let category: ExerciseCategory
    var items: [PlannedItem]
    var reserve: [PlannedItem]
    /// Training blocks let timing fit add/drop sets; warm-up and cooldown stay at one set each.
    let allowSetAdjust: Bool
    /// The minimum exercises this block must retain (timing fit never trims below it).
    let minItems: Int
    /// The planned-seconds share this block should be shaped toward before the global timing fit, set
    /// for a blend's two training blocks from the Step 2 pillar weights. `nil` leaves the block to the
    /// global fit alone (warm-up, cooldown, and single-focus training).
    var targetSeconds: Int? = nil

    /// The playable block, or `nil` when assembly left it empty (so empties never reach the player).
    func materialize() -> WorkoutBlock? {
        guard !items.isEmpty else { return nil }
        return WorkoutBlock(
            id: UUID(),
            title: title,
            category: category,
            exercises: items.map { $0.materialize() }
        )
    }
}

// MARK: - Builder

/// Generates the per-shape block skeleton (warm-up, training block(s), optional cooldown) seeded with
/// one exercise each plus reserves, running Steps 2-6 to fill the training blocks and the shared
/// mobility pool for the bookends. Kept a small stateful value so a single `usedIds` set stops the
/// same movement appearing in two blocks.
private struct Builder {
    let library: [Exercise]
    let pool: [Exercise]
    let recentLogs: [WorkoutLog]
    /// Session Policy lever (US-E03): paces Step 6's overload bump. `1.0` is neutral.
    let progressionRate: Double
    /// Session Policy lever (US-E03): Step 5's no-repeat variety window, also mirrored by the
    /// mobility variety ordering so both use the same per-user window.
    let varietyWindow: Int
    /// Return / Re-entry Ramp lever (US-E06): holds Step 6's capacity-derived per-set targets below
    /// normal (`< 1.0`) on a Return and its ramp, neutral (`1.0`) otherwise.
    let reentryScale: Double
    /// Cold-start Start Seed volume (US-O02): the reps/sets a *no-history* prescription opens at,
    /// matched to the self-reported fitness level. Applied only to the strength and primal training
    /// blocks - the mobility bookends and Movement Practice are one set of a stretch at every level, so
    /// warm-up/mobility/cooldown are identical for a beginner and an advanced user. Neutral outside
    /// the cold-start window.
    let startVolume: ColdStartOverride.VolumeSeed
    /// The movements Step 0's Start Seed band held out of reach (US-O02): Step 5 treats them as
    /// never-on-offer rather than fresh, which is what keeps the session after the cold-start handoff
    /// from regressing to an untouched entry tier (see `ProgressionChainSelection`).
    let withheldByStartSeed: Set<String>
    let asOf: Date
    let calendar: Calendar
    /// Movements already claimed by an earlier block (active or reserve), so blocks never collide.
    var usedIds: Set<String> = []

    /// Builds the ordered block skeleton for the session: warm-up first, the training block(s) the
    /// pillar plan calls for, and a cooldown when the session runs past `cooldownThresholdMinutes`.
    ///
    /// The cooldown's static holds are *reserved before* the Movement Practice block draws from the
    /// shared mobility pool (it is constructed here, up front, and appended last only at output time),
    /// so a blend's cooldown keeps real holds plus reserves instead of the single leftover stretch it
    /// would get if the training block claimed the pool first.
    ///
    /// `template` distinguishes an extended blend (US-E02), which promotes primal to its own block,
    /// from the shorter blends that keep folding primal into strength.
    mutating func buildBlocks(
        pillarPlan: PillarPlan,
        template: SessionShapeTemplate,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        let warmup = warmupBlock()
        let cooldown = requestedMinutes > SessionAssembly.cooldownThresholdMinutes ? cooldownBlock() : nil

        var middle: [PlannedBlock] = []
        switch pillarPlan {
        case .single(let pillar):
            switch pillar {
            case .mobility:
                if let block = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises) {
                    middle.append(block)
                }
            case .primal:
                // A single-focus primal day (only reached under the Step 0 First-Week Contrast, US-E04)
                // builds a dedicated locomotion block, degrading gracefully to strength then mobility if
                // the capped pool leaves no eligible primal movement so the day is never empty.
                let block = primalBlock()
                    ?? strengthBlock()
                    ?? mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises)
                if let block { middle.append(block) }
            case .strength:
                if let block = strengthBlock() {
                    middle.append(block)
                }
            }
        case .blend(let weights):
            middle = blendBlocks(
                weights: weights,
                warmup: warmup,
                cooldown: cooldown,
                template: template,
                requestedMinutes: requestedMinutes
            )
        }

        return [warmup] + middle + (cooldown.map { [$0] } ?? [])
    }

    /// The training blocks of a blend, ordered staler-pillar-first and each tagged with the
    /// planned-seconds share it should be shaped toward. The share is the remaining training budget
    /// (request minus the warm-up and cooldown the bookends already cost) split in proportion to the
    /// Step 2 staleness weights, so the staler pillar ends up the *larger* block, not merely the lead.
    ///
    /// A short or full blend produces the two co-primary blocks (strength - which still folds primal
    /// in - and mobility). An extended blend (US-E02) promotes primal to its own `locomotion`-driven
    /// block: the strength block sheds primal, and a dedicated primal block joins the split, ordered
    /// among the three by its weighted share.
    private mutating func blendBlocks(
        weights: PillarWeights,
        warmup: PlannedBlock,
        cooldown: PlannedBlock?,
        template: SessionShapeTemplate,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        let extended = template == .blendExtended

        // In an extended blend primal earns its own block, so the strength block must not also fold
        // primal in (that would double-book the same locomotion movement).
        var strength = strengthBlock(includePrimal: !extended)
        var mobility = mobilityBlock(title: "Movement Practice", cap: SessionAssembly.maxMobilityTrainingExercises)
        var primal = extended ? primalBlock() : nil

        let bookendSeconds = SessionAssembly.blockSeconds(warmup)
            + (cooldown.map(SessionAssembly.blockSeconds) ?? 0)
        let trainingBudget = max(0, requestedMinutes * 60 - bookendSeconds)
        strength?.targetSeconds = Int((Double(trainingBudget) * weights.strength).rounded())
        mobility?.targetSeconds = Int((Double(trainingBudget) * weights.mobility).rounded())
        primal?.targetSeconds = Int((Double(trainingBudget) * weights.primal).rounded())

        // Order the blocks staler-pillar-first (heavier weight leads); a fixed pillar order breaks
        // ties deterministically, matching the prior two-block strength-leads-on-tie behavior.
        let entries: [(weight: Double, tieBreak: Int, block: PlannedBlock?)] = [
            (weights.strength, 0, strength),
            (weights.mobility, 1, mobility),
            (weights.primal, 2, primal),
        ]
        return entries
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.tieBreak < $1.tieBreak }
            .compactMap { $0.block }
    }

    // MARK: Blocks

    /// The opening warm-up: the freshest mobility movements, one set each. Always first; in a
    /// mobility-led session it flows straight into the Movement Practice block so the opening doubles
    /// as warm-up + training.
    private mutating func warmupBlock() -> PlannedBlock {
        let items = mobilityItems(
            from: orderedMobility(holdsOnly: false),
            cap: SessionAssembly.maxWarmupExercises
        )
        return PlannedBlock(
            title: "Warm-Up",
            category: .warmup,
            items: items.isEmpty ? [] : [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: false,
            minItems: 1
        )
    }

    /// A mobility training block (Movement Practice): mobility movements ordered by staleness/variety,
    /// set counts adjustable for timing. `nil` when no mobility movement is left to fill it.
    private mutating func mobilityBlock(title: String, cap: Int) -> PlannedBlock? {
        let items = mobilityItems(from: orderedMobility(holdsOnly: false), cap: cap)
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: title,
            category: .mobility,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: true,
            minItems: 1
        )
    }

    /// The closing cooldown: static mobility holds (falling back to any mobility if no holds remain),
    /// one set each. `nil` when no mobility movement is left.
    private mutating func cooldownBlock() -> PlannedBlock? {
        var candidates = orderedMobility(holdsOnly: true)
        if candidates.isEmpty { candidates = orderedMobility(holdsOnly: false) }
        let items = mobilityItems(from: candidates, cap: SessionAssembly.maxCooldownExercises)
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: "Cooldown",
            category: .cooldown,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: false,
            minItems: 1
        )
    }

    /// The strength training block: one ability-matched exercise per strength pattern, stalest
    /// pattern first (and never repeating the most recent session's lead pattern), each at its Step 6
    /// capacity-relative target. When `includePrimal` is set (every shape but an extended blend), the
    /// primal `locomotion` pattern is folded in here as before; an extended blend passes `false` so
    /// primal instead earns its own dedicated block. `nil` when the pool has no eligible movement.
    private mutating func strengthBlock(includePrimal: Bool = true) -> PlannedBlock? {
        var items: [PlannedItem] = []
        for pattern in orderedStrengthPatterns(includePrimal: includePrimal) {
            guard
                let selection = ProgressionChainSelection.select(
                    pattern: pattern,
                    library: library,
                    pool: pool,
                    recentLogs: recentLogs,
                    varietyWindow: varietyWindow,
                    withheldByStartSeed: withheldByStartSeed
                ),
                !usedIds.contains(selection.exercise.id)
            else { continue }

            let target = AdaptiveOverload.target(
                for: selection.exercise,
                recentLogs: recentLogs,
                progressionRate: progressionRate,
                reentryScale: reentryScale,
                startingRepMultiplier: startVolume.repMultiplier,
                startingSets: startVolume.sets
            )
            usedIds.insert(selection.exercise.id)
            items.append(
                PlannedItem(
                    exercise: selection.exercise,
                    reps: target.reps,
                    durationSeconds: target.durationSeconds,
                    sets: target.sets,
                    restSeconds: SessionAssembly.strengthRestSeconds
                )
            )
        }
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: "Strength",
            category: .strength,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
            allowSetAdjust: true,
            minItems: 1
        )
    }

    /// The dedicated primal block for an extended blend (US-E02): the ability-matched movement from
    /// the primal `locomotion` chain at its Step 6 capacity-relative target, sets adjustable for
    /// timing. Draws only `pillar == .primal` movements from the eligible pool, so the Zero-Equipment
    /// Floor and difficulty gating still hold. `nil` when the pool has no eligible primal movement
    /// (e.g. a difficulty cap or injury filtered them out) - the session then degrades gracefully to
    /// strength + mobility rather than emitting an empty block.
    private mutating func primalBlock() -> PlannedBlock? {
        guard
            let selection = ProgressionChainSelection.select(
                pattern: .locomotion,
                library: library,
                pool: pool,
                recentLogs: recentLogs,
                varietyWindow: varietyWindow,
                withheldByStartSeed: withheldByStartSeed
            ),
            selection.exercise.pillar == .primal,
            !usedIds.contains(selection.exercise.id)
        else { return nil }

        let target = AdaptiveOverload.target(
            for: selection.exercise,
            recentLogs: recentLogs,
            progressionRate: progressionRate,
            reentryScale: reentryScale,
            startingRepMultiplier: startVolume.repMultiplier,
            startingSets: startVolume.sets
        )
        usedIds.insert(selection.exercise.id)
        let item = PlannedItem(
            exercise: selection.exercise,
            reps: target.reps,
            durationSeconds: target.durationSeconds,
            sets: target.sets,
            restSeconds: SessionAssembly.strengthRestSeconds
        )
        return PlannedBlock(
            title: "Primal Movement",
            category: .primal,
            items: [item],
            reserve: [],
            allowSetAdjust: true,
            minItems: 1
        )
    }

    // MARK: Candidate generation

    /// Turns ordered mobility exercises into one-set planned items (per-set value from Step 6),
    /// claiming each id so no later block reuses it.
    private mutating func mobilityItems(from exercises: [Exercise], cap: Int) -> [PlannedItem] {
        exercises.prefix(cap).map { exercise in
            let target = AdaptiveOverload.target(
                for: exercise,
                recentLogs: recentLogs,
                progressionRate: progressionRate,
                reentryScale: reentryScale
            )
            usedIds.insert(exercise.id)
            return PlannedItem(
                exercise: exercise,
                reps: target.reps,
                durationSeconds: target.durationSeconds,
                sets: 1,
                restSeconds: SessionAssembly.mobilityRestSeconds
            )
        }
    }

    /// The strength patterns present in the pool, ordered stalest-first via `PatternFocus`, with the
    /// most recent session's lead pattern held out of the lead slot (Step 3's no-repeat rule). Primal
    /// `locomotion` patterns are included only when `includePrimal` is set (folded into strength for
    /// every shape but an extended blend, which gives primal its own block instead).
    private func orderedStrengthPatterns(includePrimal: Bool) -> [MovementPattern] {
        let patterns = Array(
            Set(
                pool
                    .filter { $0.pillar == .strength || (includePrimal && $0.pillar == .primal) }
                    .map(\.movementPattern)
            )
        )
        guard !patterns.isEmpty else { return [] }

        let ranked = PatternFocus.rank(
            candidatePatterns: patterns,
            recentLogs: recentLogs,
            asOf: asOf,
            calendar: calendar
        )
        guard
            let lead = PatternFocus.select(
                candidatePatterns: patterns,
                recentLogs: recentLogs,
                asOf: asOf,
                calendar: calendar
            )
        else { return ranked }
        return [lead] + ranked.filter { $0 != lead }
    }

    /// Eligible, not-yet-claimed mobility movements ordered for variety: never-worked and longest-ago
    /// first, movements used in the last few sessions pushed back, then shortest (finest timing
    /// granularity) and id as deterministic tie-breaks.
    private func orderedMobility(holdsOnly: Bool) -> [Exercise] {
        let lastWorked = mobilityLastWorked()
        let recent = recentlyUsedIds()
        return pool
            .filter {
                $0.pillar == .mobility
                    && !usedIds.contains($0.id)
                    && (!holdsOnly || $0.isHold)
            }
            .sorted { lhs, rhs in
                let lhsRecent = recent.contains(lhs.id)
                let rhsRecent = recent.contains(rhs.id)
                if lhsRecent != rhsRecent { return !lhsRecent }

                let lhsDate = lastWorked[lhs.id]
                let rhsDate = lastWorked[rhs.id]
                if (lhsDate == nil) != (rhsDate == nil) { return lhsDate == nil }
                if let lhsDate, let rhsDate, lhsDate != rhsDate { return lhsDate < rhsDate }

                if lhs.estimatedTimePerSetSeconds != rhs.estimatedTimePerSetSeconds {
                    return lhs.estimatedTimePerSetSeconds < rhs.estimatedTimePerSetSeconds
                }
                return lhs.id < rhs.id
            }
    }

    /// Most recent completed (non-skipped) date per mobility exercise id, for variety ordering.
    private func mobilityLastWorked() -> [String: Date] {
        var lastWorked: [String: Date] = [:]
        for log in recentLogs {
            for logged in log.exercises where !logged.skipped {
                if let existing = lastWorked[logged.exerciseId], existing >= log.completedAt { continue }
                lastWorked[logged.exerciseId] = log.completedAt
            }
        }
        return lastWorked
    }

    /// Ids worked (non-skipped) in the most recent few sessions, pushed back in variety ordering so
    /// the user is not handed the same stretch two sessions running. The window is the policy's
    /// `varietyWindow`, mirroring Step 5's no-repeat window per user (US-E03).
    private func recentlyUsedIds() -> Set<String> {
        let recentSessions = recentLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(max(0, varietyWindow))
        return recentSessions.reduce(into: Set<String>()) { ids, log in
            for logged in log.exercises where !logged.skipped {
                ids.insert(logged.exerciseId)
            }
        }
    }
}
