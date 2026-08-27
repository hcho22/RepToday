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
/// - **Timing fit (even-round circuit model, US-CC03/US-CC04)** - a training block is played as
///   circuit *rounds* (one set of each exercise per round, "Round N of M"), so every exercise in a
///   training block carries the **same** set count = the block's round count; the block is internally
///   uniform (see ADR-0003). Its planned wall-clock is
///   `rounds × Σ(exercise workPerSet) + rounds × between-station transitions + (rounds - 1) × round-rest`
///   (`blockSeconds`), where `workPerSet` re-prices the movement's estimate as a fixed per-set setup
///   cost plus the per-unit work of the target Step 6 actually prescribed (see `workSecondsPerSet`).
///   The old per-exercise set-adjust lever (which produced *uneven* blocks) is retired for training
///   blocks; the timing fit instead tunes the bounded **between-round rest** within its band as the
///   primary lever, falling back to adding/dropping a whole round (uniformly) or a whole exercise -
///   never an uneven per-exercise count, and never touching the capacity-relative *per-set* target
///   from Step 6. The warm-up/cooldown bookends stay one set each and flow linearly. A deterministic
///   best-fit pass trims or extends the session until it lands within `toleranceSeconds` of the request.
///
/// Identity and the reference clock enter here (the earlier steps are clock-free and id-free): the
/// `Workout`/`WorkoutBlock`/`PrescribedExercise` ids are fresh `UUID`s and `createdAt`/staleness are
/// measured against the caller-supplied `asOf`. The *content* of the assembled session (which
/// exercises, in which order, at what sets/reps) is a pure, deterministic function of the inputs;
/// only the ids vary run to run, so tests assert structure and timing rather than whole-`Workout`
/// equality.
enum SessionAssembly {

    // MARK: - Tuning constants

    /// Seconds of the fixed **between-station transition** inside a circuit round (US-CC04): the short
    /// "Next: <exercise>, get ready" reposition beat between two consecutive exercises (e.g. Pike ->
    /// Split Squat). It is not zero and not recovery - the recovery gap is the between-round rest below.
    /// Counted once per gap *between* the stations of a round, and once between two adjacent blocks (the
    /// move from the warm-up into the first station, etc.) - see `blockSeconds`/`totalSeconds`.
    static let transitionSeconds = 15

    /// The default **between-round rest** a training block is seeded at, before the timing fit tunes it
    /// within `[minRoundRestSeconds, maxRoundRestSeconds]` (US-CC04). In-band by construction (40 sits
    /// between 30 and 75), so a session that never needs tuning still ships a sensible recovery rest.
    static let strengthRestSeconds = 40
    /// Rest between the (single) sets of a mobility bookend movement. A bookend is one set, so this is
    /// never actually charged (there is no between-set gap on a one-set item); kept only as the value a
    /// materialized bookend prescription carries.
    static let mobilityRestSeconds = 15
    /// The ±window the assembled session must land within around the requested time (1 minute).
    static let toleranceSeconds = 60

    /// The bounded band the **between-round rest** may take (US-CC04, ADR-0003). This is the primary
    /// timing-fit lever that replaces the retired per-exercise set-adjust move: within a training block
    /// each second of round-rest moves `(rounds - 1)` seconds of planned wall-clock, giving fine-grained
    /// control without touching set counts or the capacity-relative per-set target from Step 6. The fit
    /// never leaves this band - a value outside it would be either no recovery at all or a rest so long it
    /// stalls the circuit - so when the band alone cannot close the gap the coarser whole-round /
    /// whole-exercise levers take over (still uniformly, never an uneven block). The chosen value is a
    /// deterministic function of the inputs (the fit's greedy best-fit jump toward closing the gap,
    /// clamped to the band).
    static let minRoundRestSeconds = 30
    static let maxRoundRestSeconds = 75

    /// Round-count rails a *training* block's uniform set count (= its round count) may move between
    /// (US-CC03, capped by US-RC01). Every exercise in the block shares this count, so a round is
    /// well-defined and "Round N of M" is structurally even. The per-set target (reps/seconds) from
    /// Step 6 is never touched; only how many rounds are run is a timing lever, and only within these
    /// rails so a fit never produces an absurd round count.
    ///
    /// **US-RC01 (Round Cap and Wide Circuits, ADR-0004) capped the upper rail at `4`** (down from a
    /// prior `8`): no exercise is ever prescribed more than four times in a session, however long. A
    /// long session is no longer filled by cranking rounds past that cap - it is filled **wider**,
    /// with more distinct movements (`Builder.strengthBlock`'s second-chain accessories, generated by
    /// `ProgressionChainSelection.selectAll`). The timing fit (`candidates()`) is depth-first: every
    /// active station is taken to this cap before an accessory is ever promoted from the reserve, so
    /// short and medium sessions stay clean one-movement-per-pattern circuits and only a long session
    /// goes wide. The lower rail floors a circuit at a real round (never a one-off single set); a Step
    /// 6 seed below it (`AdaptiveOverload`'s own `1...4` set clamp can return `1`) is raised to the
    /// floor at construction (`clampTrainingSets`) rather than left for the fit to discover, since the
    /// fit's round move only ever steps by one within these rails and an out-of-band seed would never
    /// self-correct.
    static let minTrainingSets = 2
    static let maxTrainingSets = 4

    /// Clamps a Step 6 per-set-target `sets` value into `minTrainingSets...maxTrainingSets` before it
    /// seeds a training block's initial round count (US-RC01). `AdaptiveOverload`'s own set clamp
    /// (`1...4`) can still return `1` (a single demonstrated set), which sits below this block's floor;
    /// applying it here at construction, rather than relying on the timing fit to raise it later, is
    /// what keeps every training-block exercise inside the rails from the moment it is seeded.
    static func clampTrainingSets(_ sets: Int) -> Int {
        min(max(sets, minTrainingSets), maxTrainingSets)
    }

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

    /// The one constant that turns `workSecondsPerSet` from a planning-only proxy into a **generous
    /// runtime pace** (US-CC08): the multiplier applied to the *estimated* half of a set's cost so the
    /// number the fit budgets - and therefore the auto-advancing on-screen work window that reads the
    /// very same function - is a slower-end pace a typical user comfortably finishes within, rather than
    /// the typical-case time the catalog authored.
    ///
    /// **Why a factor rather than new authored data.** The honest sourcing for a runtime window is
    /// observed per-movement completion times (the PRD's open question), which do not exist. What does
    /// exist is `Exercise.estimatedTimePerSetSeconds`, a *typical*-case number: across the catalog's
    /// fundamentals the derived cadence is 2.0-2.5 seconds per rep (`hinge_glute_bridge` 2.00,
    /// `push_wall` 2.08, `squat_bodyweight`/`squat_sumo` 2.33, `push_incline`/`hinge_good_morning` 2.50),
    /// which is a brisk metronome tempo with no pause - below the ~2.5-3.0 s/rep a controlled bodyweight
    /// rep actually takes. Scaling that typical case by a single deterministic factor keeps the model's
    /// per-movement shape (cadence still read off each movement's own authored fields) while moving the
    /// whole thing to the slower end, and keeps the value a pure function of the exercise and target.
    ///
    /// **Why 1.25.** It lands the fundamentals at 2.5-2.9 s/rep of work and lifts the assumed per-set
    /// setup from 10s to 12.5s - the slower end of the controlled-tempo band, with room for the reaction
    /// lag at the window's start cue. Read as a distribution: if the authored estimate is a median
    /// completion time and self-paced cadence varies with a ~20% coefficient of variation, ×1.25 sits
    /// near the 85th percentile, so the large majority of users finish inside the window unhurried and
    /// the rest are within a rep of it (the set still logs as prescribed, US-CC09). The round-count cost
    /// is flat across 1.20-1.30, so the choice inside that band is a pure pacing decision that buys no
    /// extra session-shape change.
    ///
    /// **What it does not touch.** The split is *estimated* versus *definitional*, not windowed versus
    /// un-windowed. A hold's per-unit cost is not an estimate at all - a 40-second hold is 40 seconds by
    /// definition (`secondsPerHoldSecond`, doubled per side), so prescribed equals elapsed and there is
    /// nothing to be generous about; holds pass through at 1.0. The factor multiplies only the
    /// assumed/derived rep half, where the authored number really is a guess at how long a user takes -
    /// the same assumed-vs-observed split `maxSetupShareOfEstimate` already draws. That is why a
    /// *rep-based* movement is paced wherever it sits, warm-up and cooldown stretches included: those
    /// bookend reps are estimated too, and the plan must budget the slower user's real time whether or
    /// not that set happens to run under an on-screen countdown, or the session overruns for exactly the
    /// users the generosity exists to protect. It is a *pacing* multiplier on the work-seconds model
    /// only: Step 6's capacity-relative per-set target (reps/hold seconds) is untouched.
    ///
    /// **Accepted trade-off (US-CC08).** The same inflated number drives the planning fit, so a session
    /// fits fewer rounds in the middle of the range and station/round counts shift at the ends. The
    /// coupling itself is the point: it is what forbids a screen window roomier than the plan. A fast
    /// user simply finishes early and taps **Done**.
    ///
    /// - Note: The specific round/station counts this paragraph originally measured (e.g. "45 min: 8
    ///   rounds x 4 stations") predate US-RC01, which capped `maxTrainingSets` at `4` and replaced
    ///   "add more rounds" with "add more stations" as the lever for a long session - see that
    ///   constant. This factor's own pacing math and calibration are unaffected.
    static let workPaceGenerosityFactor = 1.25

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
            // US-AC05: the pattern-emphasis lever biases Step 3's stalest-first ordering as a pure
            // preference. Clamped to the policy rails here so the engine only ever sees an
            // order-preserving positive multiplier - an out-of-range coach write can never act as a
            // filter or invert the ordering.
            patternEmphasis: sessionPolicy.patternEmphasis.mapValues(SessionPolicy.clampedEmphasis),
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
    /// On top of that split, the rep half is scaled by `workPaceGenerosityFactor` (US-CC08), which is
    /// what makes this a **runtime** pace rather than a planning proxy: the authored estimate is a
    /// typical-case time, and the factor moves it to the slower-end pace a user comfortably finishes
    /// within - so a default-sized *rep* set is priced above what the catalog authored, while a
    /// default-sized *hold* still costs exactly it. The hold is left alone because its per-unit cost is
    /// definitional rather than estimated (prescribed seconds are elapsed seconds), not because of where
    /// the set is played: every rep-based set is paced, warm-up and cooldown stretches included, since
    /// their reps are estimated the same way and the plan owes them the same slower-user budget. See that
    /// constant for the calibration and the accepted trade-off.
    ///
    /// - Note: This is per-set *work* only; the between-round rest and the between-station transition are
    ///   counted separately by `blockSeconds`/`plannedSeconds`.
    /// - Note: This is now a **single source of truth** shared by planning and runtime (US-CC08). Since
    ///   US-CC01 the player's auto-advancing work window for a rep-based training set counts down exactly
    ///   this number (`ActiveSessionViewModel.workWindowSecondsPerSet`), so the seconds the fit budgeted
    ///   for a set are the seconds the user is given to perform it - the screen window can never be
    ///   roomier than the plan (which would make every set overrun the requested minutes) nor tighter
    ///   (which would rush the user). It is still not *measured*: a completed set logs the target it was
    ///   prescribed, never anything timed (US-CC09), and there is no per-rep input. So per-second accuracy
    ///   remains false precision on a self-paced activity; what matters is that the model carries no
    ///   *systematic* bias about which sets are longer than which, because a consistent per-slot error
    ///   accumulates across a session where random error averages out - and, since US-CC08, that its
    ///   overall level is deliberately set at the generous end rather than the typical one.
    static func workSecondsPerSet(for exercise: Exercise, reps: Int?, durationSeconds: Int?) -> Int {
        let estimate = exercise.estimatedTimePerSetSeconds
        // A hold's per-unit cost is definitional rather than estimated - prescribed seconds are elapsed
        // seconds - so there is nothing for the generosity factor to be generous about and it does not
        // apply (see `workPaceGenerosityFactor`). Every rep-based set is paced, whatever block it lands
        // in, including the no-baseline fallback below, which is the same estimate by another route.
        let generosity = exercise.isHold ? 1.0 : workPaceGenerosityFactor
        let baseline = exercise.isHold ? exercise.defaultDurationSeconds : exercise.defaultReps
        let prescribed = exercise.isHold ? durationSeconds : reps
        guard let baseline, baseline > 0, let prescribed, prescribed > 0 else {
            return max(1, Int((Double(estimate) * generosity).rounded()))
        }

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
        let paced = setup + perUnit * Double(prescribed)
        return max(1, Int((paced * generosity).rounded()))
    }

    /// The planned seconds one set of a prescribed slot takes, at the target it actually carries.
    static func workSecondsPerSet(of prescription: PrescribedExercise) -> Int {
        workSecondsPerSet(
            for: prescription.exercise,
            reps: prescription.reps,
            durationSeconds: prescription.durationSeconds
        )
    }

    /// Whether a block of `category` is played as a circuit of even rounds (US-CC03): the strength and
    /// dedicated-primal training blocks are; the warm-up/cooldown bookends flow linearly. Kept as the one
    /// place the circuit/linear distinction is drawn so `blockSeconds` (over `PlannedBlock`) and
    /// `plannedSeconds` (over a materialized `Workout`) can never disagree about how a block is priced.
    /// The `.mobility` case is defensive only - US-M01 retired the mobility training block, so none is
    /// emitted - and is treated as linear.
    static func isCircuit(_ category: ExerciseCategory) -> Bool {
        switch category {
        case .strength, .primal: return true
        case .warmup, .cooldown, .mobility: return false
        }
    }

    /// The planned wall-clock of an assembled `Workout` under the even-round model (US-CC03/US-CC04):
    /// the sum of each block's `blockSeconds` plus one between-station transition between adjacent
    /// blocks. A training block is priced as a circuit
    /// (`rounds × Σ workPerSet + rounds × between-station transitions + (rounds - 1) × round-rest`), a
    /// bookend as a linear one-set-each block. The same quantity the timing-fit pass minimizes against
    /// (`totalSeconds`), exposed so callers and tests measure the session exactly as the engine sized it.
    static func plannedSeconds(of workout: Workout) -> Int {
        let nonEmpty = workout.blocks.filter { !$0.exercises.isEmpty }
        let blockWork = nonEmpty.reduce(0) { $0 + blockSeconds(of: $1) }
        return blockWork + max(0, nonEmpty.count - 1) * transitionSeconds
    }

    /// Planned wall-clock of one materialized `WorkoutBlock` in isolation, the mirror of
    /// `blockSeconds(_ block: PlannedBlock)` over a finished session. A circuit training block reads its
    /// uniform round count and round-rest off any exercise (they are all equal by construction, US-CC03);
    /// a linear bookend is `Σ workPerSet` (one set each) plus the transitions between its stations.
    static func blockSeconds(of block: WorkoutBlock) -> Int {
        let exercises = block.exercises
        guard !exercises.isEmpty else { return 0 }
        let perRoundWork = exercises.reduce(0) { $0 + workSecondsPerSet(of: $1) }
        let stationGaps = max(0, exercises.count - 1)
        if isCircuit(block.category) {
            let rounds = exercises[0].sets
            let roundRest = exercises[0].restSeconds
            return rounds * perRoundWork
                + rounds * stationGaps * transitionSeconds
                + max(0, rounds - 1) * roundRest
        }
        // Linear bookend: one set each (any multi-set is priced honestly, but bookends are single-set).
        let work = exercises.reduce(0) { sum, item in
            sum + item.sets * workSecondsPerSet(of: item) + max(0, item.sets - 1) * item.restSeconds
        }
        return work + stationGaps * transitionSeconds
    }

    // MARK: - Timing fit

    /// Trims or extends `blocks` until the planned wall-clock is as close to `targetSeconds` as the
    /// available adjustments allow (comfortably inside `toleranceSeconds` in practice, not merely at
    /// its edge).
    ///
    /// A deterministic best-fit loop: each pass measures the signed error, then picks the single
    /// adjustment - tune the between-round rest, add/drop a whole round, or promote/drop a whole exercise
    /// (US-CC04's levers) - that brings the planned time closest to target, applying it only if it
    /// strictly reduces the absolute error. No move ever makes a training block uneven: the round-rest
    /// and whole-round levers touch every station equally, and a promoted station joins at the block's
    /// current round count. The loop runs to the local minimum (it stops only when no adjustment can
    /// shrink the gap further). Because every accepted step strictly shrinks a non-negative integer
    /// error, the loop converges.
    static func fit(_ blocks: inout [PlannedBlock], targetSeconds: Int) {
        for _ in 0..<maxFitIterations {
            let error = totalSeconds(blocks) - targetSeconds
            if error == 0 { return }
            guard let chosen = bestAdjustment(in: blocks, towardError: error) else { return }
            apply(chosen, to: &blocks)
        }
    }

    /// The single best strictly-improving adjustment for the given signed `error` (planned - target), or
    /// `nil` at the local minimum. Shared by the global `fit` and the per-block `shapeTowardTargets` so
    /// the two passes use identical levers and tie-breaks. `restrictedTo` limits enumeration to one block.
    private static func bestAdjustment(
        in blocks: [PlannedBlock],
        towardError error: Int,
        restrictedTo only: Int? = nil
    ) -> Adjustment? {
        var best: (adjustment: Adjustment, resultError: Int)?
        for (adjustment, delta) in candidates(in: blocks, towardError: error, restrictedTo: only) {
            let resultError = abs(error + delta)
            guard resultError < abs(error) else { continue }
            if best == nil || resultError < best!.resultError {
                best = (adjustment, resultError)
            }
        }
        return best?.adjustment
    }

    /// Planned wall-clock of a set of blocks mid-assembly under the even-round model (same formula as
    /// `plannedSeconds(of:)`): each block's `blockSeconds` plus one between-station transition between
    /// adjacent non-empty blocks.
    static func totalSeconds(_ blocks: [PlannedBlock]) -> Int {
        let nonEmpty = blocks.filter { !$0.items.isEmpty }
        let blockWork = nonEmpty.reduce(0) { $0 + blockSeconds($1) }
        return blockWork + max(0, nonEmpty.count - 1) * transitionSeconds
    }

    /// Planned wall-clock of a single block in isolation. A **circuit** training block
    /// (`allowSetAdjust`) is `rounds × Σ workPerSet + rounds × between-station transitions +
    /// (rounds - 1) × round-rest`, reading its uniform round count and round-rest off its (equal) items.
    /// A **linear** bookend is `Σ workPerSet` (one set each) plus the transitions between its stations.
    /// Because every timing-fit adjustment touches exactly one block and never changes whether a block is
    /// non-empty, the between-block transition count is invariant during the fit, so this per-block
    /// measure and the global `totalSeconds` stay consistent and the weight-shaping pass is exact.
    static func blockSeconds(_ block: PlannedBlock) -> Int {
        guard !block.items.isEmpty else { return 0 }
        let perRoundWork = block.items.reduce(0) { $0 + $1.workSecondsPerSet }
        let stationGaps = max(0, block.items.count - 1)
        if block.allowSetAdjust {
            let rounds = block.items[0].sets
            let roundRest = block.items[0].restSeconds
            return rounds * perRoundWork
                + rounds * stationGaps * transitionSeconds
                + max(0, rounds - 1) * roundRest
        }
        let work = block.items.reduce(0) { $0 + $1.sets * $1.workSecondsPerSet + max(0, $1.sets - 1) * $1.restSeconds }
        return work + stationGaps * transitionSeconds
    }

    // MARK: - Target shaping

    /// Grows each block that carries a `targetSeconds` toward that share (a best-fit greedy scoped to
    /// the single block), so an extended session's strength/primal blocks are split toward the fixed
    /// strength-leads-primal division (`extendedTrainingBlocks`) *before* `fit` lands the overall total.
    /// A single-block training middle carries no target and is left entirely to the global fit. It uses
    /// the same levers as the global fit - the round-rest, whole rounds within the rails, and reserve
    /// promotion - and never touches the capacity-relative per-set target from Step 6, nor makes the
    /// block uneven.
    static func shapeTowardTargets(_ blocks: inout [PlannedBlock]) {
        for index in blocks.indices {
            guard let target = blocks[index].targetSeconds else { continue }
            for _ in 0..<maxFitIterations {
                let error = blockSeconds(blocks[index]) - target
                if error == 0 { break }
                guard let chosen = bestAdjustment(in: blocks, towardError: error, restrictedTo: index) else { break }
                apply(chosen, to: &blocks)
            }
        }
    }

    /// Every available timing-fit move with the signed seconds it would add or remove, under the
    /// even-round model (US-CC04, widened by US-RC01). For a **circuit** training block the round count
    /// and the between-round rest are tuned *together* as one atomic move: for each round count within
    /// one step of the current one (`{-1, 0, +1}`, clamped to the rails), the in-band round-rest that
    /// best cancels `error` is solved directly and offered as a single `setRoundsAndRest`. Coupling them
    /// is what lets the fit trade a whole round for more (or less) rest in one step - e.g. drop a round
    /// *and* stretch the rest to the top of its band - rather than getting trapped at a round count whose
    /// only reachable rest is pinned to a band edge. The round-rest alone is the fine lever (the `0`-step
    /// case); a whole round is the coarse one.
    ///
    /// Promoting a whole exercise (from the reserve, possibly a US-RC01 accessory) is coupled the same
    /// way, but searches the *entire* `minTrainingSets...maxTrainingSets` range rather than one step: a
    /// new station's cost scales with the round count it joins at, so pricing it only at the block's
    /// *current* round count (which the round-only lever may have already walked toward the cap chasing
    /// a gap it alone cannot close) can make the only available widening move an oversized, overshooting
    /// jump. Searching the whole range for the round count that best fits the block *with the station
    /// already added* is what lets the fit actually find "add a station and run it at 2-3 rounds instead
    /// of 4" in one step (`addReserveWithRounds`) - dropping the last station is the mirror coarse lever,
    /// still at the block's current round count. A **linear** bookend grows/shrinks purely by one-set
    /// movement count (`addReserve` there always joins at one set). Enumerated in a fixed block order (and,
    /// per block, in `{-1, 0, +1}` round order for the fine lever) so ties resolve deterministically.
    /// `restrictedTo`, when set, limits enumeration to a single block. `error` is the current signed gap
    /// (planned - target).
    private static func candidates(
        in blocks: [PlannedBlock],
        towardError error: Int,
        restrictedTo only: Int? = nil
    ) -> [(Adjustment, Int)] {
        var result: [(Adjustment, Int)] = []
        for (blockIndex, block) in blocks.enumerated() {
            if let only, only != blockIndex { continue }
            guard let lead = block.items.first else { continue }
            let perRoundWork = block.items.reduce(0) { $0 + $1.workSecondsPerSet }
            let stationGaps = max(0, block.items.count - 1)

            if block.allowSetAdjust {
                let rounds = lead.sets
                let roundRest = lead.restSeconds
                // Per-round fixed cost (work + within-round transitions), independent of the round count
                // and the rest, so a block's seconds are `rounds × perRoundCost + (rounds - 1) × rest`.
                let perRoundCost = perRoundWork + stationGaps * transitionSeconds
                let currentBlockSeconds = rounds * perRoundCost + max(0, rounds - 1) * roundRest

                // Combined round-count + round-rest lever. For each candidate round count one step from
                // the current one, solve the in-band rest that best drives the total to target, and offer
                // the pair as a single move. The `0`-step case is the pure fine round-rest jump.
                for delta in [-1, 0, 1] {
                    let newRounds = rounds + delta
                    guard newRounds >= minTrainingSets, newRounds <= maxTrainingSets else { continue }
                    // The block seconds that would cancel `error`: current minus the gap (since a change
                    // in this block's seconds moves the total one-for-one).
                    let desiredBlockSeconds = currentBlockSeconds - error
                    let newRest: Int
                    if newRounds >= 2 {
                        let ideal = Double(desiredBlockSeconds - newRounds * perRoundCost) / Double(newRounds - 1)
                        newRest = min(maxRoundRestSeconds, max(minRoundRestSeconds, Int(ideal.rounded())))
                    } else {
                        // A single round has no between-round gap, so the rest is uncharged; keep it in
                        // band for when a later step grows the block back past one round.
                        newRest = min(maxRoundRestSeconds, max(minRoundRestSeconds, roundRest))
                    }
                    let newBlockSeconds = newRounds * perRoundCost + max(0, newRounds - 1) * newRest
                    let moveDelta = newBlockSeconds - currentBlockSeconds
                    guard moveDelta != 0 else { continue }
                    result.append((.setRoundsAndRest(block: blockIndex, rounds: newRounds, rest: newRest), moveDelta))
                }

                // Whole-exercise lever (US-RC01): promote the next reserve station - possibly a
                // second-chain accessory - **jointly** with the round count it would run at, exactly
                // like the round+rest move above searches its own small range rather than only
                // stepping ±1. Pricing a new station at whatever round count the round-only lever
                // happened to leave the block at (i.e. always "the block's *current* round count")
                // was tried and rejected: once the round lever alone has already walked the block up
                // near the cap chasing a gap it cannot fully close, a station's cost (`rounds × ...`)
                // is priced at that same near-cap count, so the one available widening move becomes an
                // oversized, overshooting jump with no way back to a smaller round count that would
                // have paired with it far better. Searching the whole `minTrainingSets...maxTrainingSets`
                // range for the round count that best fits the block *with the station already added*
                // is what actually finds "add a station and run it at 2-3 rounds instead of 4" in one
                // step, which is the shape a long session widening for real should take - the emergent
                // depth-first behavior (short sessions never take this over the cheaper round+rest
                // moves; only a session four rounds of its current stations still falls short of does).
                if let next = block.reserve.first {
                    let wps = workSecondsPerSet(for: next.exercise, reps: next.reps, durationSeconds: next.durationSeconds)
                    let widenedStationGaps = stationGaps + 1
                    let widenedPerRoundCost = perRoundWork + wps + widenedStationGaps * transitionSeconds
                    let desiredBlockSeconds = currentBlockSeconds - error
                    var best: (rounds: Int, rest: Int, seconds: Int)?
                    for candidateRounds in minTrainingSets...maxTrainingSets {
                        let candidateRest: Int
                        if candidateRounds >= 2 {
                            let ideal = Double(desiredBlockSeconds - candidateRounds * widenedPerRoundCost)
                                / Double(candidateRounds - 1)
                            candidateRest = min(maxRoundRestSeconds, max(minRoundRestSeconds, Int(ideal.rounded())))
                        } else {
                            candidateRest = min(maxRoundRestSeconds, max(minRoundRestSeconds, roundRest))
                        }
                        let candidateSeconds = candidateRounds * widenedPerRoundCost
                            + max(0, candidateRounds - 1) * candidateRest
                        if best == nil || abs(candidateSeconds - desiredBlockSeconds) < abs(best!.seconds - desiredBlockSeconds) {
                            best = (candidateRounds, candidateRest, candidateSeconds)
                        }
                    }
                    if let best {
                        result.append((
                            .addReserveWithRounds(block: blockIndex, rounds: best.rounds, rest: best.rest),
                            best.seconds - currentBlockSeconds
                        ))
                    }
                }
                // Drop the last station (returns it to the reserve), removing `rounds` sets of its work
                // plus one between-station gap per round.
                if block.items.count > block.minItems, let last = block.items.last {
                    result.append((.dropItem(block: blockIndex), -(rounds * (last.workSecondsPerSet + transitionSeconds))))
                }
            } else {
                // Linear bookend: it grows/shrinks purely by one-set movement count.
                if let next = block.reserve.first {
                    let wps = workSecondsPerSet(for: next.exercise, reps: next.reps, durationSeconds: next.durationSeconds)
                    result.append((.addReserve(block: blockIndex), wps + transitionSeconds))
                }
                if block.items.count > block.minItems, let last = block.items.last {
                    result.append((.dropItem(block: blockIndex), -(last.workSecondsPerSet + transitionSeconds)))
                }
            }
        }
        return result
    }

    private static func apply(_ adjustment: Adjustment, to blocks: inout [PlannedBlock]) {
        switch adjustment {
        case let .setRoundsAndRest(block, rounds, rest):
            for index in blocks[block].items.indices {
                blocks[block].items[index].sets = rounds
                blocks[block].items[index].restSeconds = rest
            }
        case let .addReserve(block):
            // Linear bookend only (see `.addReserveWithRounds` for a circuit training block): join at
            // one set, since a bookend is never set-adjustable.
            var promoted = blocks[block].reserve.removeFirst()
            promoted.sets = 1
            blocks[block].items.append(promoted)
        case let .addReserveWithRounds(block, rounds, rest):
            // Circuit training block (US-RC01): the promoted station and every existing station move to
            // the jointly-solved round count/rest together, so the block stays uniform the moment the
            // new station lands rather than joining at a stale round count a later move must reconcile.
            var promoted = blocks[block].reserve.removeFirst()
            promoted.sets = rounds
            promoted.restSeconds = rest
            blocks[block].items.append(promoted)
            for index in blocks[block].items.indices {
                blocks[block].items[index].sets = rounds
                blocks[block].items[index].restSeconds = rest
            }
        case let .dropItem(block):
            let removed = blocks[block].items.removeLast()
            blocks[block].reserve.insert(removed, at: 0)
        }
    }

    /// One timing-fit move, addressed by block index into the in-progress `[PlannedBlock]`. Every move
    /// preserves a training block's uniform round count (US-CC03): `setRoundsAndRest` writes the same
    /// round count and rest to every station, and `addReserve` joins at the block's current round count.
    private enum Adjustment {
        /// Set every station of a circuit block to the same round count and (in-band) between-round rest.
        case setRoundsAndRest(block: Int, rounds: Int, rest: Int)
        /// Promote the next reserve movement into a **linear bookend** block, at one set.
        case addReserve(block: Int)
        /// Promote the next reserve movement into a **circuit training** block (US-RC01), and set every
        /// station - the new one included - to the jointly-solved round count and (in-band) rest.
        case addReserveWithRounds(block: Int, rounds: Int, rest: Int)
        /// Drop the last movement from the block back to the reserve.
        case dropItem(block: Int)
    }
}

// MARK: - PlannedItem

/// One exercise as it is being sized during assembly: the movement, its capacity-relative per-set
/// target (reps or hold seconds from Step 6), the current set count (= the block's round count on a
/// circuit training block, a timing lever), and the rest that follows (the between-round rest on a
/// circuit block, likewise a lever). Materializes into a playable `PrescribedExercise` once assembly is
/// done. On a circuit training block every item shares one `sets` and one `restSeconds` (US-CC03);
/// per-item seconds are therefore not meaningful in isolation - `SessionAssembly.blockSeconds` owns the
/// round-aware wall-clock formula.
struct PlannedItem: Equatable {
    let exercise: Exercise
    let reps: Int?
    let durationSeconds: Int?
    /// The set count. On a circuit training block this is the block's uniform round count; the timing
    /// fit moves it only via the block-level `setRoundsAndRest` move, so it stays equal across the block.
    var sets: Int
    /// On a circuit training block this is the between-round rest (a tunable lever within
    /// `[minRoundRestSeconds, maxRoundRestSeconds]`, kept equal across the block); on a bookend it is
    /// the (uncharged) one-set rest.
    var restSeconds: Int

    /// Planned seconds for one set at this item's actual per-set target (see
    /// `SessionAssembly.workSecondsPerSet(for:reps:durationSeconds:)`), so a seeded or
    /// capacity-grown prescription is sized as the work it really is.
    var workSecondsPerSet: Int {
        SessionAssembly.workSecondsPerSet(for: exercise, reps: reps, durationSeconds: durationSeconds)
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
    /// can be *incidentally* coupled to bookend composition. Since US-CC08 that coupling actually **binds**
    /// on the shipped catalog: a rep-based stretch carries the generous runtime pace while a hold stretch
    /// does not, so a desk worker's 45-minute warm-up costs ~32s more and the fit pays it out of a whole
    /// strength round. What is guarded is therefore the real invariant - same training movements at the
    /// same per-set targets, with a round count differing only where the bookends really cost different
    /// seconds (`testSitsLongChangesNoTrainingMovementOrTarget`). Since US-M01 removed the
    /// Movement Practice accessory (the block `sitsLong` used to *size*), this is the only thing `sitsLong`
    /// does in the engine.
    let sitsLong: Bool
    /// Session Policy pattern-emphasis lever (US-AC05): a per-`MovementPattern` **multiplier on
    /// staleness** biasing Step 3's stalest-first ordering, already clamped to the policy rails
    /// (`SessionPolicy.clampedEmphasis`) when the builder is constructed. Threaded into
    /// `orderedStrengthPatterns` only, where it reorders the strength/primal pattern list as a pure
    /// preference: it never removes a pattern (a de-emphasized pattern still fills as an accessory when
    /// the block widens), never makes a block uneven or changes its round count (ADR-0003), and never
    /// reintroduces a mobility middle block. Neutral (`1.0` for every pattern) reproduces the pre-US-AC05
    /// ordering exactly. Shaped like `sitsLong`: a reorder layered on the existing ordering, never a filter.
    let patternEmphasis: [MovementPattern: Double]
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
    /// capacity-relative target, plus - since US-RC01 - every further chain each pattern offers as a
    /// **wide-circuit accessory**. When `includePrimal` is set (every shape but an extended blend), the
    /// primal `locomotion` pattern is folded in here as before; an extended blend passes `false` so
    /// primal instead earns its own dedicated block. `nil` when the pool has no eligible movement.
    ///
    /// Built in two breadth-first passes over `ProgressionChainSelection.selectAll`'s per-pattern
    /// ranking, so the reserve widens evenly rather than doubling up on one pattern before another
    /// pattern has even earned its primary: every pattern's primary (rank 0 chain) first, stalest
    /// pattern first, then every pattern's further chains (rank 1+, the accessories), same pattern
    /// order. The very first item becomes the block's sole seeded active station; everything after it -
    /// the other patterns' primaries *and* every pattern's accessories - is reserve the depth-first
    /// timing fit (`candidates()`) may promote once the active stations are already at the round cap.
    private mutating func strengthBlock(includePrimal: Bool = true) -> PlannedBlock? {
        let rankedByPattern = orderedStrengthPatterns(includePrimal: includePrimal).map { pattern in
            ProgressionChainSelection.selectAll(
                pattern: pattern,
                library: library,
                pool: pool,
                recentLogs: recentLogs,
                varietyWindow: varietyWindow,
                withheldByStartSeed: withheldByStartSeed
            )
        }

        var items: [PlannedItem] = []
        for selections in rankedByPattern {
            guard let primary = selections.first else { continue }
            appendTrainingItem(primary, into: &items)
        }
        for selections in rankedByPattern {
            for accessory in selections.dropFirst() {
                appendTrainingItem(accessory, into: &items)
            }
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

    /// Builds one training station's `PlannedItem` for `selection` (its Step 6 capacity-relative
    /// target, round count clamped into the block rails) and appends it to `items`, claiming the
    /// exercise id so no later chain - in this pattern or another - can reuse it. Shared by
    /// `strengthBlock`'s primary and accessory passes and by `primalBlock` (US-RC01) so a station is
    /// sized identically wherever it is drawn from.
    private mutating func appendTrainingItem(_ selection: ChainSelection, into items: inout [PlannedItem]) {
        guard !usedIds.contains(selection.exercise.id) else { return }
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
                sets: SessionAssembly.clampTrainingSets(target.sets),
                restSeconds: SessionAssembly.strengthRestSeconds
            )
        )
    }

    /// The dedicated primal block for an extended blend (US-E02): the ability-matched movement from
    /// the primal `locomotion` chain at its Step 6 capacity-relative target, sets adjustable for
    /// timing - plus, since US-RC01, `locomotion`'s own further chain as a reserve accessory exactly
    /// like a strength pattern's. Draws only `pillar == .primal` movements from the eligible pool, so
    /// the Zero-Equipment Floor and difficulty gating still hold. `nil` when the pool has no eligible
    /// primal movement (e.g. a difficulty cap or injury filtered them out) - the session then degrades
    /// gracefully to strength + mobility rather than emitting an empty block.
    ///
    /// The PRD's default was primal staying single-movement (strength carries all the widening),
    /// revisited only if the primal block itself lands short under the round cap - and it does: a
    /// beginner's 60-min session pins primal at 4 rounds/max rest with only one station and is still
    /// short, because the cap alone cannot make up the shortfall a beginner's lower per-set entry-tier
    /// targets leave. Enabling this one further chain here is that revisit; it changes nothing when the
    /// depth-first fit does not need it (locomotion's second chain never gets promoted at a length the
    /// round cap alone already carries), exactly like a strength pattern's own accessory.
    private mutating func primalBlock() -> PlannedBlock? {
        let selections = ProgressionChainSelection.selectAll(
            pattern: .locomotion,
            library: library,
            pool: pool,
            recentLogs: recentLogs,
            varietyWindow: varietyWindow,
            withheldByStartSeed: withheldByStartSeed
        ).filter { $0.exercise.pillar == .primal }

        var items: [PlannedItem] = []
        for selection in selections {
            appendTrainingItem(selection, into: &items)
        }
        guard !items.isEmpty else { return nil }
        return PlannedBlock(
            title: "Primal Movement",
            category: .primal,
            items: [items[0]],
            reserve: Array(items.dropFirst()),
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
    ///
    /// The US-AC05 `patternEmphasis` lever biases both the rank and the lead selection as a per-pattern
    /// staleness multiplier, but purely as a reorder: the pattern set (and thus the block's structure,
    /// its uniform round count, and every eligible movement) is untouched, so a de-emphasized pattern is
    /// still present and still available to the block's breadth-first widening as an accessory. At
    /// neutral emphasis this is byte-identical to the pre-US-AC05 ordering.
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
            calendar: calendar,
            emphasis: patternEmphasis
        )
        guard
            let lead = PatternFocus.select(
                candidatePatterns: patterns,
                recentLogs: recentLogs,
                asOf: asOf,
                calendar: calendar,
                emphasis: patternEmphasis
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
    /// worker's bookend duration - and, through the timing fit, a training block's round count - can differ
    /// from the general profile's, which since US-CC08's generous pace it actually does at 45/60 min. What
    /// is guarded is the movements and their per-set targets, not the round count
    /// (`testSitsLongChangesNoTrainingMovementOrTarget`). It runs *before*
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
