import Foundation

/// Pipeline Step 7 of the deterministic engine (US-C07): take everything Steps 1-6 decided and
/// assemble a complete, playable `Workout` that opens with a warm-up, closes with a cooldown when
/// it runs long, and lands within ±1 minute of the minutes the user asked for.
///
/// This is the step that turns the pipeline's per-decision outputs into the structured session the
/// active-session player renders:
/// - **Shape** (Step 1, `SessionShapeTemplate`) decides single-focus vs. blend, which here is only a
///   distinction of length band and whether primal earns its own block - **every** session is
///   strength-led (US-001/US-002/US-M01), so there is no pillar-lead decision and no strength-vs-mobility
///   split to size. Mobility appears only as the warm-up and cooldown bookends, never as a training
///   block. A single-focus or shorter blend builds one strength block (primal folded in) that fills the
///   whole training budget; an extended blend (US-E02) carves primal into its own `locomotion`-driven
///   block, a bounded minority of the budget (`extendedTrainingBlocks`), with strength keeping the lead.
/// - **Pattern, exercise, and target** (Steps 3-6, `PatternFocus` / `ProgressionChainSelection` /
///   `AdaptiveOverload`) fill each training block: the stalest patterns first, the ability-matched
///   exercise in each, and that exercise's capacity-relative reps/sets/hold. During cold start Step
///   0's Start Seed (US-O02) is resolved once here and threaded into all three - it bands the
///   strength/primal pool, tells Step 5 which chains it withheld, and sizes Step 6's no-history
///   target - so a self-reported level reaches every part of the block that depends on it.
///
/// On top of those it owns two things the earlier steps deliberately left to assembly:
/// - **Structure** - every session opens with a `.warmup` block (mobility) and, past
///   `cooldownThresholdMinutes`, closes with a `.cooldown` block of static stretches. These bookends
///   are the only mobility in the session (US-M01): there is no mobility middle block at any length.
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
    ///
    /// The upper rail is deliberately the lever that carries a **long** session. Multiple sets are
    /// redundant for a stretch but legitimate training for strength, so the mobility bookends are pinned
    /// at one set (`allowSetAdjust: false`) and the strength/primal blocks instead take all the extra time
    /// up to this ceiling. Since US-M01 removed the Movement Practice mobility block, the strength/primal
    /// blocks are now the *only* training lever, so this ceiling was raised (from the previous `5`, which
    /// was calibrated when a many-stretch mobility block still carried part of a long session's minutes) to
    /// the smallest value that lets a 45- and 60-minute strength session still land within
    /// `toleranceSeconds`: a 60-minute session opens its handful of strength/primal movements to more sets
    /// rather than a mobility block. It applies across the board, but only ever binds on a session long
    /// enough for the fit to need the time - a short session never reaches it, because adding a set there
    /// would overshoot the request.
    static let minTrainingSets = 1
    static let maxTrainingSets = 8

    /// Primal's fixed share of the training budget in an extended (41-60 min) session, where it earns its
    /// own dedicated block (`extendedTrainingBlocks`). Since US-M01 removed the Movement Practice block
    /// and its `PillarWeights` split, the strength-vs-primal division is no longer staleness-weighted:
    /// primal is shaped toward this fixed minority share and strength takes the rest, so strength always
    /// leads and the minutes freed by removing mobility accrue to strength (decision 3). Kept a genuine
    /// minority block (~4-6 sets of one locomotion movement at 45-60 min) while strength keeps a clear
    /// majority - above the archived ~0.75-0.80 accessory-model strength share (US-M01 validation).
    static let extendedPrimalTrainingShare = 0.15

    /// Per-block ceilings on how many distinct movements each mobility-sourced bookend may draw from the
    /// shared mobility pool. Since US-M01 the only mobility-sourced blocks are the warm-up and the
    /// cooldown; the warm-up draws first and the cooldown before any training block is built (see
    /// `buildBlocks`), and the strength/primal blocks draw a disjoint pool, so the cooldown is never
    /// starved of its static holds.
    ///
    /// `maxWarmupExercises` is the *ceiling* the length-scaled warm-up (`warmupExerciseCount`) tops out
    /// at, chosen so the two mobility bookends never over-drain the shared pool even in their worst case
    /// (a long session where the warm-up hits this ceiling *and* the cooldown hits `maxCooldownExercises`):
    /// `4 + 4 = 8` of the 26 mobility movements, leaving generous day-to-day variety headroom.
    static let maxWarmupExercises = 4
    static let maxCooldownExercises = 4

    /// How many distinct movements the opening warm-up seeds (all active, one set each), scaled by
    /// session length so a longer session opens with a fuller warm-up while a tiny session keeps the
    /// warm-up lean so it does not crowd out strength: **≤10 min: 1, 11-20: 2, 21-40: 3, 41-60: 4**,
    /// clamped to `maxWarmupExercises`.
    ///
    /// The warm-up is seeded at this count directly (`warmupBlock`) rather than started at one movement
    /// and left to the global timing fit to grow, so the "more fully loosened up before the Strength
    /// block" behavior is a deterministic property of the session shape, not an accident of whether the
    /// fit happened to promote a reserve. The warm-up's seconds count toward the budget like any other
    /// block, and the timing fit trims the strength/mobility training to keep the whole session inside
    /// `toleranceSeconds` (verified across 5/10/15/20/30/45/60 in `SessionAssemblyTests`).
    static func warmupExerciseCount(forRequestedMinutes minutes: Int) -> Int {
        let scaled: Int
        switch minutes {
        case ..<11: scaled = 1
        case ..<21: scaled = 2
        case ..<41: scaled = 3
        default: scaled = 4
        }
        return min(scaled, maxWarmupExercises)
    }

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
    /// catalog's 26 holds the authored remainder is 5-25 seconds with a median of exactly 10. Taking
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
    /// `sessionPolicy` is the per-user program the engine runs on (US-E03): its `varietyWindow` sets
    /// Step 5's no-repeat window and its `progressionRate` paces Step 6's overload bump (its
    /// `pillarWeighting` is inert since US-M01 - see `SessionPolicy`). It also carries the situational
    /// overrides the
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

    /// Builds the seeded block skeleton (warm-up, the leading strength training block, an optional
    /// dedicated primal block at the extended lengths, and an optional cooldown) before the timing fit -
    /// the structural output of Steps 1-6. Exposed internally so tests can inspect block reserves and the
    /// extended session's per-block time targets prior to the global fit consuming them. `sessionPolicy`
    /// threads the US-E03 levers into Steps 5/6 (see `assemble`) and the situational Step 0 cold-start
    /// (US-E04) and Step 0.5 Return (US-E06) gentleness rails; it defaults to `SessionPolicy.default`
    /// (neutral, no regression).
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
        // cold-start is active, since cold-start already serves gentle, capped sessions - so the pool
        // and volume overrides never fight over the same inputs. Both are no-ops in the steady state, so
        // a warmed-up, present user runs exactly the US-E03 pipeline.
        //
        // Neither override touches pillar *selection* anymore: since US-M01 the session lead is
        // structural - `buildBlocks` always builds a leading strength block from `template` (US-001/
        // US-002), with the shape alone deciding whether primal is folded in or gets its own block. So
        // cold-start and Return contribute only their gentleness rails below (the capped pool and the
        // eased volume), never a lead override, and there is no strength-vs-mobility split to compute.
        let isReturn = isReturnSession(
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: asOf,
            calendar: calendar
        )

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
            // US-M03: the desk-worker `sitsLong` signal is a pure *bias* input to bookend selection -
            // never a direct sizing lever. It reorders the mobility bookend pool toward posture/hip
            // openers and changes no block's count and no bookend stretch count, so it cannot re-inflate a
            // short session or reintroduce a mobility middle block (see `orderedMobility`/`postureHipLean`).
            sitsLong: user.profile.sitsLong,
            asOf: asOf,
            calendar: calendar
        )
        return builder.buildBlocks(
            template: template,
            requestedMinutes: requestedMinutes
        )
    }

    // MARK: - Posture / hip bias (US-M03)

    /// The hip-dominant strength patterns that define a "posture / hip opener" for the US-M03 `sitsLong`
    /// bias. A desk worker sits in sustained hip flexion with a slumped posterior chain, so the stretches
    /// that counter that are exactly the ones already tagged (US-M02) as complementing the squat and hinge
    /// patterns - the hip- and posterior-chain-dominant movements. Deriving the set from the existing
    /// `complements` metadata rather than a new per-exercise tag keeps one taxonomy: a stretch is a hip
    /// opener iff it already earns its place beside a squat/hinge day.
    static let postureHipPatterns: Set<MovementPattern> = [.squat, .hinge]

    /// Whether `exercise` is a posture/hip opener under the US-M03 bias: a mobility movement whose US-M02
    /// `complements` tag names at least one hip-dominant pattern (`postureHipPatterns`). An untagged
    /// movement (never true for the load-validated mobility catalog) is not an opener. Pure - the whole
    /// `sitsLong` bias reduces to this predicate over existing metadata.
    static func isPostureHipOpener(_ exercise: Exercise) -> Bool {
        guard let complements = exercise.complements else { return false }
        return complements.contains { postureHipPatterns.contains($0) }
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
    /// produced. A session with a single training block (single-focus, or a shorter blend whose one
    /// strength block folds primal in) reports that block's pillar - always `.strength` since US-M01; an
    /// extended blend leaves two training blocks (strength + a dedicated primal, no single focus, so
    /// `nil`), and a degenerate warmup-only session leaves none. Reading it from the built blocks keeps
    /// the label truthful when an extended session degrades to a lone strength block because the capped
    /// pool left no eligible locomotion movement (US-E04).
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

    // MARK: - Target shaping

    /// Grows each block that carries a `targetSeconds` toward that share (a best-fit greedy scoped to
    /// the single block), so an extended session's strength/primal blocks are split toward the fixed
    /// strength-leads-primal division (`extendedTrainingBlocks`) *before* `fit` lands the overall total.
    /// A single-block training middle carries no target and is left entirely to the global fit. It uses
    /// the same levers as the global fit - set counts within the rails and reserve promotion - and never
    /// touches the capacity-relative per-set target from Step 6.
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
                // Step 6 prescribed. Without that, a set-adjustable block whose items already sit at
                // `maxTrainingSets` (a capacity-grown or cold-start-seeded strength block can) has no
                // fine-grained lever left at all: its only move is a whole extra exercise at full volume,
                // which a short session cannot absorb, and the greedy fit parks minutes away from the
                // request. A non-set-adjustable block (the warm-up and cooldown bookends) promotes its
                // reserve only at the item's own one set - so a bookend grows purely by movement count.
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
    /// Whether timing fit may add/drop sets on this block's exercises. The strength and primal training
    /// blocks set it; the warm-up and cooldown bookends do not, staying at one set each and growing only
    /// by promoting more distinct movements from their reserve.
    let allowSetAdjust: Bool
    /// The minimum exercises this block must retain (timing fit never trims below it).
    let minItems: Int
    /// The planned-seconds share this block should be shaped toward before the global timing fit, set for
    /// an extended session's strength/primal blocks from the fixed strength-leads-primal split
    /// (`extendedTrainingBlocks`). `nil` leaves the block to the global fit alone (the warm-up, the
    /// cooldown, and a single-block strength training middle).
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
    /// blocks - the mobility bookends are one set of a stretch at every level, so the warm-up and
    /// cooldown are identical for a beginner and an advanced user. Neutral outside the cold-start window.
    let startVolume: ColdStartOverride.VolumeSeed
    /// The movements Step 0's Start Seed band held out of reach (US-O02): Step 5 treats them as
    /// never-on-offer rather than fresh, which is what keeps the session after the cold-start handoff
    /// from regressing to an untouched entry tier (see `ProgressionChainSelection`).
    let withheldByStartSeed: Set<String>
    /// The desk-worker `sitsLong` signal (US-M03), threaded in as a **bias**, never a direct sizing lever.
    /// When set, the warm-up and cooldown pools are reordered to lead with posture/hip openers (see
    /// `orderedMobility`/`postureHipLean`); it changes no block's count and no bookend stretch count, so
    /// it can never re-inflate a short session or bring back a mobility middle block. It does change which
    /// stretches *fill* the fixed-count bookends, though, and stretches differ in `workSecondsPerSet`, so
    /// a desk worker's bookend duration can differ from the general profile's - and since that duration
    /// feeds `trainingBudget` (extended path) and the global timing fit (short/full), a strength set count
    /// can be *incidentally* coupled to bookend composition. The training middle staying byte-identical
    /// across profiles is therefore test-guarded at the shipped catalog and lengths
    /// (`testSitsLongDoesNotSizeAnyTrainingBlock`), not an absolute invariant. Since US-M01 removed the
    /// Movement Practice accessory (the block `sitsLong` used to *size*), this is the only thing `sitsLong`
    /// does in the engine.
    let sitsLong: Bool
    let asOf: Date
    let calendar: Calendar
    /// Movements already claimed by an earlier block (active or reserve), so blocks never collide.
    var usedIds: Set<String> = []

    /// Builds the ordered block skeleton for the session: a warm-up first, the leading **strength**
    /// training block, a dedicated **primal** block on the extended lengths, and a cooldown when the
    /// session runs past `cooldownThresholdMinutes`.
    ///
    /// Every session is strength-led by construction (US-001/US-002/US-M01): the training middle is
    /// always a strength block, never a mobility one. Mobility survives only as the warm-up and cooldown
    /// bookends - there is no Movement Practice middle block at any length (US-M01). Primal keeps its own
    /// treatment (US-M01 decision 1): folded into the strength block on the shorter shapes, and its own
    /// block at 41-60 min.
    ///
    /// The cooldown's static holds are *reserved* here, before the training middle is built (it is
    /// constructed up front and appended last only at output time), so a blend's cooldown keeps real
    /// holds plus reserves rather than the single leftover stretch it would get if a block claimed the
    /// mobility pool first. The strength/primal blocks draw a disjoint pool, so the bookends' mobility
    /// reservation is never contended by the training middle.
    ///
    /// `template` distinguishes an extended blend (US-E02), which promotes primal to its own block,
    /// from the shorter shapes that keep folding primal into strength.
    mutating func buildBlocks(
        template: SessionShapeTemplate,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        // The day's lead strength pattern (Step 3), resolved once so both bookends bias toward the
        // same complementary stretch (US-M02). Strength-only - never primal - so the complement
        // target is always a mapped strength pattern even on the shorter shapes that fold primal
        // into the strength block; `nil` (a degenerate primal-only pool) simply leaves the bookends
        // on their general variety ordering.
        let lead = leadStrengthPattern()
        let warmup = warmupBlock(requestedMinutes: requestedMinutes, complementing: lead)
        let cooldown = requestedMinutes > SessionAssembly.cooldownThresholdMinutes ? cooldownBlock(complementing: lead) : nil

        let middle: [PlannedBlock]
        if template == .blendExtended {
            middle = extendedTrainingBlocks(
                warmup: warmup,
                cooldown: cooldown,
                requestedMinutes: requestedMinutes
            )
        } else {
            // Single-focus and the shorter blends: one strength block (primal folded in) is the whole
            // training middle. It carries no `targetSeconds`, so the global timing fit grows it to fill
            // the entire training budget - which is how the minutes the retired Movement Practice block
            // used to hold are reallocated to strength (US-M01 decision 3).
            middle = strengthBlock(includePrimal: true).map { [$0] } ?? []
        }

        return [warmup] + middle + (cooldown.map { [$0] } ?? [])
    }

    /// The training blocks of an extended (41-60 min) session: a leading **strength** block and a
    /// dedicated **primal** block (US-E02). The Movement Practice mobility block is gone (US-M01), so the
    /// only split here is strength-vs-primal, and it is a **fixed** minority split rather than the
    /// staleness-weighted one the retired `PillarWeights` drove: primal is shaped toward
    /// `extendedPrimalTrainingShare` of the training budget and strength takes the rest. Strength always
    /// leads and, because the freed mobility minutes now go to it, runs heavier than under the archived
    /// accessory model (US-M01 decision 3); primal keeps the same one-movement block it had before.
    ///
    /// Both blocks are shaped toward their `targetSeconds` before the global timing fit lands the total.
    /// If the capped pool leaves no eligible locomotion movement, `primalBlock()` is `nil` and the
    /// session degrades to a single strength block (which then absorbs the whole budget) rather than
    /// emitting an empty primal block.
    private mutating func extendedTrainingBlocks(
        warmup: PlannedBlock,
        cooldown: PlannedBlock?,
        requestedMinutes: Int
    ) -> [PlannedBlock] {
        // In an extended blend primal earns its own block, so the strength block must not also fold
        // primal in (that would double-book the same locomotion movement).
        var strength = strengthBlock(includePrimal: false)
        var primal = primalBlock()

        let bookendSeconds = SessionAssembly.blockSeconds(warmup)
            + (cooldown.map(SessionAssembly.blockSeconds) ?? 0)
        let trainingBudget = max(0, requestedMinutes * 60 - bookendSeconds)
        if primal != nil {
            let primalTarget = Int((Double(trainingBudget) * SessionAssembly.extendedPrimalTrainingShare).rounded())
            primal?.targetSeconds = primalTarget
            strength?.targetSeconds = max(0, trainingBudget - primalTarget)
        } else {
            strength?.targetSeconds = trainingBudget
        }

        // Strength leads (US-002), so it comes first; the bounded-minority primal block follows.
        return [strength, primal].compactMap { $0 }
    }

    // MARK: Blocks

    /// The opening warm-up: the freshest mobility movements, one set each. Always first, and - since
    /// US-M01 - one of only two mobility blocks in the session (the other being the cooldown), never a
    /// lead-in to a mobility training block.
    ///
    /// The number of movements scales with session length (`warmupExerciseCount`), and all of them are
    /// seeded as **active** items (not reserves) with `minItems` pinned to that count, so a longer
    /// session deterministically opens with a fuller warm-up rather than relying on the global timing
    /// fit to promote reserves. Like the cooldown bookend it is one set each and never set-adjustable;
    /// the timing fit still trims the strength/primal training around it to keep the session inside
    /// `toleranceSeconds`.
    private mutating func warmupBlock(
        requestedMinutes: Int,
        complementing lead: MovementPattern? = nil
    ) -> PlannedBlock {
        let items = mobilityItems(
            from: orderedMobility(holdsOnly: false, complementing: lead),
            cap: SessionAssembly.warmupExerciseCount(forRequestedMinutes: requestedMinutes)
        )
        return PlannedBlock(
            title: "Warm-Up",
            category: .warmup,
            items: items,
            reserve: [],
            allowSetAdjust: false,
            minItems: max(1, items.count)
        )
    }

    /// The closing cooldown: static mobility holds (falling back to any mobility if no holds remain),
    /// one set each. `nil` when no mobility movement is left.
    private mutating func cooldownBlock(complementing lead: MovementPattern? = nil) -> PlannedBlock? {
        var candidates = orderedMobility(holdsOnly: true, complementing: lead)
        if candidates.isEmpty { candidates = orderedMobility(holdsOnly: false, complementing: lead) }
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
    ///
    /// `complementing` biases the result prefer-then-fill (US-M02): when the day's lead strength
    /// pattern is supplied, the single best-variety stretch that complements it is promoted to the
    /// front so the bookend *leads* with a matched stretch, with every remaining slot left in this
    /// same staleness / no-repeat order. The bias is a pure, stable reorder that never drops a
    /// stretch, so a bookend is never starved: when no ordered stretch complements the lead (or the
    /// lead is `nil`) the general variety ordering stands unchanged as the fallback.
    ///
    /// `sitsLong` layers the US-M03 posture/hip bias underneath that: a desk worker's bookend pool is
    /// first reordered to lead with posture/hip openers (`postureHipLean`), then the US-M02
    /// lead-complement promotion runs on top of the reordered pool. Composing the two this way keeps
    /// US-M02's slot-0 authority intact (the pattern-matched lead stretch still wins the first slot)
    /// while every *following* bookend slot fills with hip relief first. Both steps are pure, stable
    /// reorders of a deterministically-sorted array, so the assembled session stays an `asOf`-pure
    /// function of its inputs, and neither changes the bookend's count - though the posture/hip reorder
    /// does change which stretches fill it, so bookend duration (and, through the timing fit, a strength
    /// set count) can differ between profiles (see `sitsLong`/`postureHipLean`).
    private func orderedMobility(holdsOnly: Bool, complementing lead: MovementPattern? = nil) -> [Exercise] {
        let lastWorked = mobilityLastWorked()
        let recent = recentlyUsedIds()
        let ordered = pool
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
        let leaned = Self.postureHipLean(ordered, apply: sitsLong)
        return Self.leadingComplement(leaned, complementing: lead)
    }

    /// Prefer-then-fill (US-M02): promote the first (best-variety) stretch in `ordered` whose
    /// `complements` contains `lead` to the front, leaving every other stretch in its existing
    /// relative order. A no-op when `lead` is `nil` or no stretch complements it, so the general
    /// mobility ordering is the fallback and the bookend is never starved or emptied. Pure and
    /// deterministic: it reorders a deterministically-sorted array by an array `contains`, with no
    /// set-iteration order dependence and no clock, so the assembled session stays an `asOf`-pure
    /// function of its inputs. When several complementary stretches tie on freshness the tie is
    /// already resolved by `ordered`'s existing staleness / no-repeat ordering, so no new
    /// nondeterminism enters here.
    private static func leadingComplement(
        _ ordered: [Exercise],
        complementing lead: MovementPattern?
    ) -> [Exercise] {
        guard
            let lead,
            let leadIndex = ordered.firstIndex(where: { $0.complements?.contains(lead) == true })
        else { return ordered }
        var reordered = ordered
        let complement = reordered.remove(at: leadIndex)
        reordered.insert(complement, at: 0)
        return reordered
    }

    /// The US-M03 desk-worker bias: when `apply` (the user's `sitsLong`), stable-partition `ordered` so
    /// posture/hip openers lead, every other stretch trailing, each group keeping its incoming relative
    /// order. A no-op when `apply` is false, so a non-desk-bound user's bookends are byte-identical to
    /// today's.
    ///
    /// This is a *preference layered on the existing ordering*, never a filter and never a direct sizing
    /// lever: it drops no stretch and adds none, so the fallback pool is undiminished (a bookend is never
    /// starved), every block's count and the bookend stretch count are untouched (a short session cannot
    /// be re-inflated with stretching), and no path here can create a mobility middle block - the reorder
    /// only ever feeds the warm-up and cooldown pools. It does change bookend *composition*, so a desk
    /// worker's bookend duration - and, through the timing fit, a strength set count - can differ from the
    /// general profile's; the training middle holding byte-identical is test-guarded at the shipped
    /// catalog and lengths (`testSitsLongDoesNotSizeAnyTrainingBlock`), not structural. It runs *before*
    /// `leadingComplement`, which retains final authority over the lead
    /// slot (US-M02). Pure and deterministic: a stable partition of an already deterministically-sorted
    /// array (`filter` preserves order), with no set-iteration dependence and no clock, so the assembled
    /// session stays an `asOf`-pure function of its inputs.
    private static func postureHipLean(_ ordered: [Exercise], apply: Bool) -> [Exercise] {
        guard apply else { return ordered }
        return ordered.filter(SessionAssembly.isPostureHipOpener)
            + ordered.filter { !SessionAssembly.isPostureHipOpener($0) }
    }

    /// The day's lead strength pattern (Step 3) the bookends bias toward (US-M02): the stalest
    /// strength pattern with the no-repeat rule applied, taken over strength patterns only so the
    /// complement target is always a mapped strength pattern - never primal `locomotion`, which the
    /// `complements` mapping does not cover - even on the shorter shapes that fold primal into the
    /// strength block. `nil` when the pool holds no strength movement, leaving the bookends on the
    /// general variety ordering.
    private func leadStrengthPattern() -> MovementPattern? {
        orderedStrengthPatterns(includePrimal: false).first
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
