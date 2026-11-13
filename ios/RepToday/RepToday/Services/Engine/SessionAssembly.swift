import Foundation

/// Pipeline Step 7 of the deterministic engine, reshaped into the **Training Day slot plan** (US-TD04,
/// ADR-0012, ADR-0013): turn today's Training Day into a complete, playable `Workout` of a few movements
/// done well, filled to the requested length by reps and rest.
///
/// - **Slots** (decisions 7-11, resized by ADR-0018). Up to two warm-up stretches, then one circuit
///   block: the main slots for the length (5 min 1, 10-15 min 2, 20-30 min 3, 45 min 4, 60 min 5) plus
///   the Core Sprinkles (none at 5-10 min, one at 15-30, two at 45-60), then up to two cooldown
///   stretches. A Push or Pull Day has two ladders, so its third and fourth main slots are Practice
///   Movements of the first and second ladder's next harder rung and its fifth is a **Variation** of a
///   current rung, left empty until one with Trainer art exists; a Legs Day fills its slots from the
///   squat, lunge, bridge and hip ladders, one squat-side and one hinge-side ladder first, and its fifth
///   slot is its first ladder's Practice Movement. Each ladder contributes its current rung, unchanged
///   until earned. A session never mixes groups: only the Core Sprinkle crosses days, and every bookend
///   stretch complements the day's group while the catalog has enough that do.
/// - **Focus Areas** (decision 20, M2). A movement a Focus Area covers (`FocusArea.covers`) is ordered
///   first among its kind of station - so on a short session it takes the slot - is given the Practice
///   slot first, and is padded first (and cut last) by the fit. Abs adds a Core Sprinkle wherever core
///   appears. The Rotation never changes.
/// - **Sets and reps** (decisions 13-16). Every main, Practice and core station runs
///   `RepGrammar.setsPerStation` (4) rounds. Main and core stations start at the user's served Earned
///   Reps (`AdaptiveOverload`); a Practice Movement runs at `RepGrammar.practiceValue`.
/// - **Fit** (decisions 16-17). Reps are the fit lever: a session over its length cuts main and core
///   reps below Earned Reps, never under the short-session floor; a session under it **Pads** them up
///   to the top of the level's range. Padding never moves Earned Reps or a rung - the prescription
///   records the Earned Reps it was built from. Only then does rest grow: the rest after a round up to
///   60 seconds on a session of 30 minutes or less, and on a 45 or 60 minute session the pause between
///   movements up to 60 seconds and the rest after a round up to the level cap (beginner 2:00,
///   intermediate 1:30, advanced 1:00). A session that still cannot fill runs short, honestly
///   (`plannedSeconds`). The tolerance is `toleranceSeconds` (about three minutes).
///
/// Identity and the reference clock enter here: ids are fresh `UUID`s and `createdAt` is the
/// caller-supplied `asOf`. The *content* of the session is a pure, deterministic function of the inputs,
/// so tests assert structure and timing rather than whole-`Workout` equality.
enum SessionAssembly {

    // MARK: - Tuning constants

    /// Seconds of the pause between two stations of a circuit round, and between two blocks: the short
    /// "Next: <exercise>, get ready" beat. On a 45 or 60 minute session the timing fit may grow a
    /// circuit's pause toward `maxTransitionSeconds` (stored on the block, `WorkoutBlock
    /// .transitionSeconds`); everywhere else it is this.
    static let transitionSeconds = 15

    /// The longest a circuit's pause between movements may grow on a 45 or 60 minute session.
    static let maxTransitionSeconds = 60

    /// The rest after a round before the fit grows it, and a bookend's (uncharged) between-set rest.
    static let baseRoundRestSeconds = 15
    static let mobilityRestSeconds = baseRoundRestSeconds

    /// The longest rest after a round on a session of `shortSessionMaxMinutes` or less.
    static let shortSessionMaxRoundRestSeconds = 60

    /// Sessions this long or shorter keep the pause between movements at `transitionSeconds` and the
    /// rest after a round at most `shortSessionMaxRoundRestSeconds`.
    static let shortSessionMaxMinutes = 30

    /// The longest rest after a round on a 45 or 60 minute session, by level (decision 17).
    static func roundRestCap(for level: FitnessLevel, requestedMinutes: Int) -> Int {
        guard requestedMinutes > shortSessionMaxMinutes else { return shortSessionMaxRoundRestSeconds }
        switch level {
        case .beginner: return 120
        case .intermediate: return 90
        case .advanced: return 60
        }
    }

    /// The longest any rest the player opens may run: the beginner round-rest cap. A session saved
    /// before Training Days carries shorter rests and plays them unchanged.
    static let maxRestSeconds = 120

    /// The brief hands-free "Switch sides" beat between the two legs of a per-side hold (US-CC05,
    /// ADR-0010), charged inside the hold's set (`workSecondsPerSet`).
    static let switchSidesSeconds = 5

    /// The window the assembled session should land within around the requested time (about three
    /// minutes, decision 17). A session that cannot fill it runs short and shows its honest time.
    static let toleranceSeconds = 180

    /// The bookends hold at most two stretches each (decision 7).
    static let maxWarmupExercises = 2
    static let maxCooldownExercises = 2

    /// Warm-up stretches by length: one up to 10 minutes, two beyond.
    static func warmupExerciseCount(forRequestedMinutes minutes: Int) -> Int {
        min(minutes <= cooldownThresholdMinutes ? 1 : 2, maxWarmupExercises)
    }

    /// Cooldown stretches by length: none up to 10 minutes, one at 15-20, two from 30.
    static func cooldownExerciseCount(forRequestedMinutes minutes: Int) -> Int {
        switch minutes {
        case ...cooldownThresholdMinutes: return 0
        case ...20: return 1
        default: return maxCooldownExercises
        }
    }

    /// Sessions longer than this many minutes close with a cooldown.
    static let cooldownThresholdMinutes = 10

    /// Main slots by length (ADR-0018): 5 min 1, 10-15 min 2, 20-30 min 3, 45 min 4, 60 min 5.
    static func mainSlotCount(forRequestedMinutes minutes: Int) -> Int {
        switch minutes {
        case ...5: return 1
        case ...15: return 2
        case ...30: return 3
        case ...45: return 4
        default: return 5
        }
    }

    /// Core Sprinkles by length (ADR-0018): none up to 10 minutes, one at 15-30, two at 45-60 - and one
    /// more wherever core appears with an Abs Focus Area (decision 20), which at 45-60 minutes is one from
    /// each core ladder.
    static func coreSprinkleCount(forRequestedMinutes minutes: Int, focusAreas: [FocusArea] = []) -> Int {
        guard minutes > cooldownThresholdMinutes else { return 0 }
        let base = minutes > shortSessionMaxMinutes ? 2 : 1
        return base + (focusAreas.contains(.abs) ? 1 : 0)
    }

    /// The core ladders in canonical order, the Core Sprinkle's tie-break.
    static let coreLadders = ["core_plank", "core_stability", "core_hollow"]

    /// Seconds of work in one second of a prescribed hold, *per side* - the per-unit half of the work
    /// model in `workSecondsPerSet`, and the one half that needs no calibration at all: a 40-second
    /// hold is 40 seconds of work by definition, and a 40-second hold prescribed `isPerSide` is 80.
    static let secondsPerHoldSecond = 1.0

    /// The fixed per-set cost of getting into position, bracing, and getting out again - the *setup*
    /// half of the work model in `workSecondsPerSet` for a rep-based movement.
    ///
    /// A hold needs no such constant: it is charged only the seconds the player runs (see
    /// `workSecondsPerSet`), and gets into position during the get-ready beat before it. A rep
    /// carries no authored duration, so exactly one of the two halves has to be assumed and the other
    /// read off the movement's own authored cadence. Assuming the setup - and deriving the cadence - is
    /// the right way round: cadence genuinely varies per movement (the catalog authors anything from
    /// `hinge_glute_bridge` at 15 reps in 40s to `push_one_arm` at 3 in 50s), while getting down onto
    /// the floor and back up is much the same work whatever the movement is.
    ///
    /// The value is calibrated from the *holds*, where setup is observed rather than fitted: across the
    /// catalog's 26 holds the authored remainder `estimate - sides × defaultDurationSeconds` is 5-25
    /// seconds with a median of exactly 10. Taking the constant from a different family of movements
    /// than the ones it is then applied to is what keeps it from being circular - the previous per-rep
    /// constant was calibrated from the four rep-based entries it subsequently assigned zero setup to,
    /// which is no calibration at all.
    static let setupSecondsPerSet = 10.0

    /// The most of a **rep-based** movement's authored per-set estimate that `workSecondsPerSet` will
    /// treat as fixed setup. A movement whose estimate is mostly setup carries almost no cadence signal,
    /// so its own default would stop saying anything useful about a target moved off it; capping the
    /// setup share at half keeps `setupSecondsPerSet` from swallowing a short authored estimate. Inert
    /// across the shipped catalog (every estimate is at least 35s), it bounds a future entry rather than
    /// today's.
    ///
    /// It does not apply to holds, which are charged no setup at all (`workSecondsPerSet`).
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
    /// - Note: The round and station counts this paragraph originally measured predate Training Days,
    ///   which fix every station at 4 rounds and fill a long session with reps and rest. This factor's
    ///   own pacing math and calibration are unaffected.
    static let workPaceGenerosityFactor = 1.25

    // MARK: - Entry point

    /// Assembles today's session for `requestedMinutes`.
    ///
    /// `trainingDay` is the group to train; `nil` lets the Rotation decide (`TrainingRotation.trainingDay`),
    /// which on a Rest Day is the group "Train anyway" starts - Today decides whether to offer the Rest Day
    /// before it asks for a session.
    ///
    /// `history` is the full log history the Rotation replays (for today's group and the Cycle the Core
    /// Sprinkle rotates on): a Cycle's alignment reaches back to the first Training Day, so a bounded
    /// window would start the replay mid-Cycle. `nil` means `recentLogs` already is the full history.
    /// Every other step reads `recentLogs`.
    ///
    /// `sessionPolicy` carries the levers Step 6 reads (`progressionRate`) and the cold-start contract.
    /// The Return and its Re-entry Ramp are read from `recentLogs` (`ReturnOverride`).
    ///
    /// `variation` is the Ready Screen's **Different workout** request (`SessionVariation`): the moves
    /// earlier presses showed are ranked behind their alternatives wherever the plan has a choice (which
    /// ladders fill a short session, which stretches, which core ladder), while every filter and the fit
    /// still decide each pick. When that leaves nothing new the default session is returned, which is how
    /// a sequence of presses cycles back.
    ///
    /// `activities` are the logged Outside Activities the Rotation reads (decision 21), for today's group
    /// and the Cycle the Core Sprinkle rotates on.
    ///
    /// `hasTrainerArt` answers whether both Trainers have a movement's full pose pair; a Variation is
    /// offered only when it does (ADR-0018). It defaults to the app's own asset catalog.
    static func assemble(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        variation: SessionVariation = .none,
        trainingDay: TrainingDay? = nil,
        history: [WorkoutLog]? = nil,
        activities: [OutsideActivity] = [],
        hasTrainerArt: @escaping (Exercise) -> Bool = SessionAssembly.hasBundledTrainerArt,
        asOf: Date,
        calendar: Calendar = .current
    ) -> Workout {
        let day = trainingDay ?? TrainingRotation.trainingDay(
            logs: history ?? recentLogs,
            activities: activities,
            trainable: trainableDays(user: user, library: library, recentLogs: recentLogs),
            asOf: asOf,
            calendar: calendar
        )
        if !variation.isNone {
            let varied = assemblePass(
                requestedMinutes: requestedMinutes,
                user: user,
                library: library,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                offered: variation.offeredExerciseIds,
                trainingDay: day,
                history: history,
                activities: activities,
                hasTrainerArt: hasTrainerArt,
                asOf: asOf,
                calendar: calendar
            )
            if variation.offersSomethingNew(varied) { return varied }
        }
        return assemblePass(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            offered: [],
            trainingDay: day,
            history: history,
            activities: activities,
            hasTrainerArt: hasTrainerArt,
            asOf: asOf,
            calendar: calendar
        )
    }

    /// Whether both Trainers have the full start/end pose pair for `exercise` in the app's asset catalog,
    /// asked through the same resolver every Trainer surface uses (`TrainerPoseResolver`).
    static func hasBundledTrainerArt(_ exercise: Exercise) -> Bool {
        TrainerPoseResolver.bundled.hasFullArt(exerciseId: exercise.id)
    }

    /// One assembly pass, with `offered` (a `SessionVariation`'s moves) ranked behind their
    /// alternatives; empty for the default session.
    private static func assemblePass(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        offered: Set<String>,
        trainingDay: TrainingDay,
        history: [WorkoutLog]?,
        activities: [OutsideActivity],
        hasTrainerArt: @escaping (Exercise) -> Bool,
        asOf: Date,
        calendar: Calendar
    ) -> Workout {
        var plan = planSession(
            requestedMinutes: requestedMinutes,
            user: user,
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            offered: offered,
            trainingDay: trainingDay,
            history: history,
            activities: activities,
            hasTrainerArt: hasTrainerArt,
            asOf: asOf,
            calendar: calendar
        )
        fit(&plan, targetSeconds: requestedMinutes * 60)
        return Workout(
            id: UUID(),
            createdAt: asOf,
            shape: SessionShapeTemplate.select(requestedMinutes: requestedMinutes).shape,
            focusPillar: plan.stations.isEmpty ? nil : .strength,
            requestedMinutes: requestedMinutes,
            wasReturn: isReturnSession(
                user: user,
                recentLogs: recentLogs,
                sessionPolicy: sessionPolicy,
                asOf: asOf,
                calendar: calendar
            ),
            blocks: plan.materialize(),
            trainingDay: trainingDay
        )
    }

    /// The Rest Day's optional **Recovery** flow (US-TD05): a short, mobility-only session of four
    /// stretches, one set each, matched to the group just finished. Every station is a `recovery`
    /// stretch, so the log neither advances the Rotation nor counts as a session for the Consistency
    /// Score (`WorkoutLog.isRecovery`).
    static func recoveryWorkout(
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        asOf: Date
    ) -> Workout {
        var builder = Builder(
            library: library,
            pool: ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs),
            recentLogs: recentLogs,
            history: recentLogs,
            activities: [],
            trainable: Set(TrainingDay.rotation),
            level: user.profile.fitnessLevel,
            phase: user.phase,
            injuries: user.profile.injuries,
            progressionRate: SessionPolicy.default.progressionRate,
            varietyWindow: SessionPolicy.default.varietyWindow,
            reentryScale: AdaptiveOverload.neutralReentryScale,
            isReturn: false,
            practiceDifficultyCap: nil,
            startingRepMultiplier: AdaptiveOverload.neutralStartingRepMultiplier,
            withheldByStartSeed: [],
            sitsLong: user.profile.sitsLong,
            focusAreas: [],
            offered: [],
            hasTrainerArt: { _ in false },
            asOf: asOf,
            calendar: .current
        )
        let stretches = builder.recoveryStretches(count: recoveryStretchCount)
        let block = WorkoutBlock(
            id: UUID(),
            title: "Recovery",
            category: .cooldown,
            exercises: stretches.map { $0.materialize(restSeconds: mobilityRestSeconds) }
        )
        return Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .singleFocus,
            focusPillar: .mobility,
            requestedMinutes: max(1, (plannedSeconds(of: [block]) + 59) / 60),
            blocks: stretches.isEmpty ? [] : [block]
        )
    }

    /// The Training Days this user can train at all: those with at least one ladder holding a rung the
    /// eligible pool offers. An injury can remove every ladder of a day (a wrist flag empties Push), and
    /// the Rotation passes such a day over rather than serve it as stretches and a Core Sprinkle.
    static func trainableDays(user: User, library: [Exercise], recentLogs: [WorkoutLog]) -> Set<TrainingDay> {
        trainableDays(in: ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs))
    }

    private static func trainableDays(in eligiblePool: [Exercise]) -> Set<TrainingDay> {
        let ladders = Set(eligiblePool.map(\.progressionChainId))
        return Set(TrainingDay.rotation.filter { day in day.ladders.contains(where: ladders.contains) })
    }

    /// Today's plan for this user (ADR-0012): the Rotation over their full log `history` (`nil` when
    /// `recentLogs` already is the full history) and their logged Outside Activities (decision 21),
    /// passing over any day they cannot train.
    static func trainingPlan(
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        history: [WorkoutLog]? = nil,
        activities: [OutsideActivity] = [],
        asOf: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        TrainingRotation.plan(
            logs: history ?? recentLogs,
            activities: activities,
            trainable: trainableDays(user: user, library: library, recentLogs: recentLogs),
            asOf: asOf,
            calendar: calendar
        )
    }

    /// The Cycle strip for this user (decision 19), read exactly as `trainingPlan` reads the Rotation.
    static func cycleSteps(
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        history: [WorkoutLog]? = nil,
        activities: [OutsideActivity] = [],
        asOf: Date,
        calendar: Calendar = .current
    ) -> [CycleStep] {
        TrainingRotation.cycleSteps(
            logs: history ?? recentLogs,
            activities: activities,
            trainable: trainableDays(user: user, library: library, recentLogs: recentLogs),
            asOf: asOf,
            calendar: calendar
        )
    }

    /// Stretches in the Recovery flow: about five minutes of mobility.
    static let recoveryStretchCount = 4

    /// Whether this generation is a Return (US-E06): a real gap since the last logged session, but
    /// only in the steady state - a Return is suppressed while cold-start still owns the first sessions.
    /// The single source of truth for the Return rails in `planSession` and the `Workout.wasReturn` flag.
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

    /// The slot plan before the fit: the bookends, and the circuit's main, Practice and core stations at
    /// their starting numbers. Exposed internally so tests can inspect the plan the fit starts from.
    static func planSession(
        requestedMinutes: Int,
        user: User,
        library: [Exercise],
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy = .default,
        offered: Set<String> = [],
        trainingDay: TrainingDay,
        history: [WorkoutLog]? = nil,
        activities: [OutsideActivity] = [],
        hasTrainerArt: @escaping (Exercise) -> Bool = SessionAssembly.hasBundledTrainerArt,
        asOf: Date,
        calendar: Calendar = .current
    ) -> SessionPlan {
        let isReturn = isReturnSession(
            user: user,
            recentLogs: recentLogs,
            sessionPolicy: sessionPolicy,
            asOf: asOf,
            calendar: calendar
        )
        // Step 0: the cold-start Start Seed, resolved once (its pool band, the chains it withholds, and
        // the opening multiplier move together), and the Return's difficulty cap and Re-entry scale.
        let startSeed = ColdStartOverride.startSeed(user: user, sessionPolicy: sessionPolicy, recentLogs: recentLogs)
        let eligible = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs)
        let pool = ReturnOverride.returnPool(
            ColdStartOverride.startBandedPool(
                ColdStartOverride.cappedPool(
                    eligible,
                    user: user,
                    sessionPolicy: sessionPolicy
                ),
                seed: startSeed
            ),
            isReturn: isReturn
        )
        let withheld = ColdStartOverride.withheldByStartSeed(
            library: MovementAccess.available(in: library, level: user.profile.fitnessLevel, phase: user.phase),
            user: user,
            sessionPolicy: sessionPolicy,
            seed: startSeed
        )
        var builder = Builder(
            library: library,
            pool: pool,
            recentLogs: recentLogs,
            history: history ?? recentLogs,
            activities: activities,
            trainable: trainableDays(in: eligible),
            level: user.profile.fitnessLevel,
            phase: user.phase,
            injuries: user.profile.injuries,
            progressionRate: sessionPolicy.progressionRate,
            varietyWindow: sessionPolicy.varietyWindow,
            reentryScale: ReturnOverride.reentryScale(isReturn: isReturn, recentLogs: recentLogs),
            isReturn: isReturn,
            practiceDifficultyCap: user.coldStart.active ? sessionPolicy.coldStartContract?.cappedMaxDifficulty : nil,
            startingRepMultiplier: startSeed.volume.repMultiplier,
            withheldByStartSeed: withheld,
            sitsLong: user.profile.sitsLong,
            focusAreas: user.profile.focusAreas,
            offered: offered,
            hasTrainerArt: hasTrainerArt,
            asOf: asOf,
            calendar: calendar
        )
        return builder.plan(day: trainingDay, requestedMinutes: requestedMinutes)
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

    /// Whether the stretch `exercise` complements one of `patterns` (its US-M02 `complements` tag) - the
    /// test every day-matched bookend stretch passes while the catalog has enough that do (ADR-0018).
    static func complements(_ exercise: Exercise, anyOf patterns: Set<MovementPattern>) -> Bool {
        exercise.complements?.contains(where: patterns.contains) == true
    }

    /// A warm-up, cooldown or Recovery stretch's per-set number: its catalog length on the grid of
    /// fives, never under 10 (ADR-0011).
    static func bookendValue(for exercise: Exercise) -> Int {
        let base = exercise.isHold ? (exercise.defaultDurationSeconds ?? 30) : (exercise.defaultReps ?? 10)
        return max(10, RepGrammar.floored(base))
    }

    // MARK: - Pillar

    /// The pillar a training block trains, or `nil` for the structural bookends (`warmup`/`cooldown`).
    static func pillar(of category: ExerciseCategory) -> Pillar? {
        switch category {
        case .strength: return .strength
        case .mobility: return .mobility
        case .primal: return .primal
        case .warmup, .cooldown: return nil
        }
    }

    // MARK: - Work per set

    /// The planned seconds one set of `exercise` takes at the per-set target Step 6 actually
    /// prescribed: for a rep movement a fixed per-set `setup` cost plus `perUnit × prescribed` of work,
    /// for a timed hold the seconds the player runs.
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
    /// - a **hold** needs no estimate: it costs exactly what the player runs, `secondsPerHoldSecond` per
    ///   prescribed second, *doubled* when the movement is `isPerSide` (a "20 second" side plank is 20
    ///   seconds left plus 20 seconds right), plus the `switchSidesSeconds` beat between the legs. No
    ///   setup is charged: every hold starts itself straight after its get-ready beat (ADR-0010), so the
    ///   authored setup in its estimate is never played, and charging it ended a hands-free session
    ///   short of the length chosen.
    /// - a **rep** carries no authored duration to anchor the per-unit half, so the other half is the
    ///   assumed one: setup is `setupSecondsPerSet` (capped by `maxSetupShareOfEstimate`), and the
    ///   cadence is the authored remainder `(estimate - setup) / defaultReps`. Reading cadence per
    ///   movement is what keeps per-side and slow-tempo reps honest - `push_archer` ("3x8 clean reps per
    ///   side", 5 reps in 50s) prices 8 reps at 74s rather than the 59s a fixed 3s-per-rep cadence gave.
    ///
    /// The rep split reproduces `estimatedTimePerSetSeconds` exactly at the movement's own default, so a
    /// default-sized set is priced exactly as the catalog authored it and only a target Step 6 moved
    /// off the default is re-priced. That keeps the planned wall-clock - and therefore the ±1 minute
    /// promise the timing fit is measured against - honest about the session the user is actually going
    /// to do. A movement with no default to scale against falls back to the flat estimate.
    ///
    /// On top of that split, the rep half is scaled by `workPaceGenerosityFactor` (US-CC08), which is
    /// what makes this a **runtime** pace rather than a planning proxy: the authored estimate is a
    /// typical-case time, and the factor moves it to the slower-end pace a user comfortably finishes
    /// within - so a default-sized *rep* set is priced above what the catalog authored, while a
    /// *hold* still costs exactly its played seconds. The hold is left alone because its per-unit cost is
    /// definitional rather than estimated (prescribed seconds are elapsed seconds), not because of where
    /// the set is played: every rep-based set is paced, warm-up and cooldown stretches included, since
    /// their reps are estimated the same way and the plan owes them the same slower-user budget. See that
    /// constant for the calibration and the accepted trade-off.
    ///
    /// - Note: This is per-set *work* only; the between-round rest and the between-station transition are
    ///   counted separately by `blockSeconds`/`plannedSeconds`, and any stretch the timing fit adds to a
    ///   rep-based training set's window is added on top (`workSecondsPerSet(of:)`, ADR-0010).
    /// - Note: This is now a **single source of truth** shared by planning and runtime (US-CC08). Since
    ///   US-CC01 the player's auto-advancing work window for a rep-based training set counts down exactly
    ///   this number plus the set's stretch (`ActiveSessionViewModel.workWindowSecondsPerSet`,
    ///   `workSecondsPerSet(of:)`), so the seconds the fit budgeted
    ///   for a set are the seconds the user is given to perform it - the screen window can never be
    ///   roomier than the plan (which would make every set overrun the requested minutes) nor tighter
    ///   (which would rush the user). It is still not *measured*: a completed set logs the target it was
    ///   prescribed, never anything timed (US-CC09), and there is no per-rep input. So per-second accuracy
    ///   remains false precision on a self-paced activity; what matters is that the model carries no
    ///   *systematic* bias about which sets are longer than which, because a consistent per-slot error
    ///   accumulates across a session where random error averages out - and, since US-CC08, that its
    ///   overall level is deliberately set at the generous end rather than the typical one.
    static func workSecondsPerSet(for exercise: Exercise, reps: Int?, durationSeconds: Int?) -> Int {
        if exercise.isHold, let durationSeconds, durationSeconds > 0 {
            // A hold costs exactly what the player runs: one leg per side, with the "Switch sides" beat
            // between legs. No setup is charged, because the player runs none - every hold starts itself
            // straight after its get-ready beat (ADR-0010).
            let sides = exercise.sidesPerSet
            let legs = Int((Double(sides * durationSeconds) * secondsPerHoldSecond).rounded())
            return max(1, legs + (sides - 1) * switchSidesSeconds)
        }
        let estimate = exercise.estimatedTimePerSetSeconds
        // A hold with no prescribed seconds runs on a work window of its flat estimate, and a hold's
        // estimate is not a guess at a user's pace, so the generosity factor does not apply to it (see
        // `workPaceGenerosityFactor`). Every rep-based set is paced, whatever block it lands in,
        // including the no-baseline fallback below, which is the same estimate by another route.
        guard !exercise.isHold, let baseline = exercise.defaultReps, baseline > 0, let reps, reps > 0 else {
            let generosity = exercise.isHold ? 1.0 : workPaceGenerosityFactor
            return max(1, Int((Double(estimate) * generosity).rounded()))
        }

        // Assumed setup, derived cadence; the `max` enforces `maxSetupShareOfEstimate`.
        let perUnit = max(
            (Double(estimate) - setupSecondsPerSet) / Double(baseline),
            Double(estimate) / Double(baseline) * (1 - maxSetupShareOfEstimate)
        )
        let setup = max(0, Double(estimate) - perUnit * Double(baseline))
        let paced = setup + perUnit * Double(reps)
        return max(1, Int((paced * workPaceGenerosityFactor).rounded()))
    }

    /// The planned seconds one set of a prescribed slot takes, at the target it actually carries: its
    /// generous pace (`paceSecondsPerSet(of:)`) plus any stretch the timing fit gave its work window
    /// (ADR-0010). This is the work window the player counts down for a rep-based training set.
    static func workSecondsPerSet(of prescription: PrescribedExercise) -> Int {
        paceSecondsPerSet(of: prescription) + max(0, prescription.stretchSeconds ?? 0)
    }

    /// The generous-pace seconds one set of a prescribed slot takes at the target it carries, before any
    /// stretch (`workSecondsPerSet(for:reps:durationSeconds:)`).
    static func paceSecondsPerSet(of prescription: PrescribedExercise) -> Int {
        workSecondsPerSet(
            for: prescription.exercise,
            reps: prescription.reps,
            durationSeconds: prescription.durationSeconds
        )
    }

    // MARK: - Planned wall-clock

    /// Whether a block of `category` is played as a circuit of even rounds (US-CC03): the training block
    /// is; the warm-up, cooldown and Recovery flow are linear. `.primal` stays a circuit so a session saved
    /// before primal was retired (ADR-0014) still plays as it was planned.
    static func isCircuit(_ category: ExerciseCategory) -> Bool {
        switch category {
        case .strength, .primal: return true
        case .warmup, .cooldown, .mobility: return false
        }
    }

    /// The planned wall-clock of an assembled `Workout`: each block's `blockSeconds` plus one pause
    /// between adjacent blocks - the same quantity the fit lands, so callers measure the session exactly
    /// as the engine sized it, and Today shows it as the honest time.
    static func plannedSeconds(of workout: Workout) -> Int {
        plannedSeconds(of: workout.blocks)
    }

    static func plannedSeconds(of blocks: [WorkoutBlock]) -> Int {
        let nonEmpty = blocks.filter { !$0.exercises.isEmpty }
        return nonEmpty.reduce(0) { $0 + blockSeconds(of: $1) } + max(0, nonEmpty.count - 1) * transitionSeconds
    }

    /// Planned wall-clock of one block. A circuit is `rounds x sum(work per set) + rounds x (stations - 1)
    /// x pause + (rounds - 1) x round rest`, reading its round count and rest off its (equal) stations and
    /// its pause off the block; a linear block is each station's sets plus the pauses between stations.
    static func blockSeconds(of block: WorkoutBlock) -> Int {
        let exercises = block.exercises
        guard !exercises.isEmpty else { return 0 }
        let gap = block.transitionSeconds ?? transitionSeconds
        let stationGaps = max(0, exercises.count - 1)
        if isCircuit(block.category) {
            let rounds = exercises[0].sets
            let perRoundWork = exercises.reduce(0) { $0 + workSecondsPerSet(of: $1) }
            return rounds * perRoundWork + rounds * stationGaps * gap + max(0, rounds - 1) * exercises[0].restSeconds
        }
        let work = exercises.reduce(0) { sum, item in
            sum + item.sets * workSecondsPerSet(of: item) + max(0, item.sets - 1) * item.restSeconds
        }
        return work + stationGaps * gap
    }

    // MARK: - Timing fit

    /// Lands `plan` on `targetSeconds` (decisions 16-17), deterministically and in this order:
    /// 1. **Cut** - while the session runs long, take a step off the main or core station with the most
    ///    room above its short-session floor (the later station on a tie), a station a Focus Area covers
    ///    only once no other station can give.
    /// 2. **Pad** - while it runs short, add a step to the main or core station padded least so far (the
    ///    earlier station on a tie), up to the top of the level's range - the stations a Focus Area covers
    ///    first (decision 20), the others once those are at the top.
    /// 3. **Rest** - then grow the rest after a round, and on a 45 or 60 minute session the pause between
    ///    movements, five seconds at a time up to their caps.
    /// Each step is taken only if it brings the session closer to the target, so the loop ends at the
    /// closest landing its levers allow; whatever gap is left is the session's honest shortfall or
    /// overrun.
    static func fit(_ plan: inout SessionPlan, targetSeconds: Int) {
        func distance(_ candidate: SessionPlan) -> Int { abs(candidate.totalSeconds - targetSeconds) }

        // 1. Cut reps toward the short-session floor.
        while plan.totalSeconds > targetSeconds {
            let cuttable = plan.stations.indices.filter { plan.stations[$0].value - RepGrammar.step >= plan.stations[$0].floor }
            guard let index = cuttable.max(by: { lhs, rhs in
                // An unfocused station gives first; a focused one is cut last.
                let lFocused = plan.stations[lhs].isFocused
                let rFocused = plan.stations[rhs].isFocused
                if lFocused != rFocused { return lFocused }
                let l = plan.stations[lhs].value - plan.stations[lhs].floor
                let r = plan.stations[rhs].value - plan.stations[rhs].floor
                return l != r ? l < r : lhs < rhs
            }) else { break }
            var trial = plan
            trial.stations[index].value -= RepGrammar.step
            guard distance(trial) < distance(plan) else { break }
            plan = trial
        }

        // 2. Pad reps toward the top of the range.
        while plan.totalSeconds < targetSeconds {
            let paddable = plan.stations.indices.filter { plan.stations[$0].value + RepGrammar.step <= plan.stations[$0].ceiling }
            let ordered = paddable.sorted { lhs, rhs in
                // A focused station is padded first (decision 20).
                let lFocused = plan.stations[lhs].isFocused
                let rFocused = plan.stations[rhs].isFocused
                if lFocused != rFocused { return lFocused }
                let l = plan.stations[lhs].padSteps
                let r = plan.stations[rhs].padSteps
                return l != r ? l < r : lhs < rhs
            }
            var improved = false
            for index in ordered {
                var trial = plan
                trial.stations[index].value += RepGrammar.step
                if distance(trial) < distance(plan) {
                    plan = trial
                    improved = true
                    break
                }
            }
            if !improved { break }
        }

        // 3. Grow rest: the pause between movements first (long sessions only), then the rest after a round.
        while plan.totalSeconds < targetSeconds {
            var candidates: [SessionPlan] = []
            if plan.transitionSeconds + RepGrammar.step <= plan.transitionCap, plan.stations.count > 1 {
                var trial = plan
                trial.transitionSeconds += RepGrammar.step
                candidates.append(trial)
            }
            if plan.roundRestSeconds + RepGrammar.step <= plan.roundRestCap {
                var trial = plan
                trial.roundRestSeconds += RepGrammar.step
                candidates.append(trial)
            }
            guard let best = candidates.min(by: { distance($0) < distance($1) }),
                  distance(best) < distance(plan) else { break }
            plan = best
        }
    }

}

// MARK: - PlannedItem

/// One station as it is being sized: the movement, its role, its per-set number (`value`: reps, or hold
/// seconds), the Earned Reps behind it, and the bounds the fit may move the number within - `floor` to
/// `ceiling`, equal to `value` for a station the fit never touches (a Practice Movement, a stretch).
struct PlannedItem: Equatable {
    let exercise: Exercise
    let role: StationRole?
    var value: Int
    /// The served Earned Reps (or hold seconds) this station started from, recorded on the prescription
    /// so Padding and a short session's cut never move progression. `nil` off the main and core stations.
    let earned: Int?
    let sets: Int
    let floor: Int
    let ceiling: Int
    /// The number the station started at, so the fit can pad evenly.
    let start: Int
    /// Whether one of the user's Focus Areas covers the movement (decision 20): the fit pads it first and
    /// cuts it last.
    let isFocused: Bool

    init(
        exercise: Exercise,
        role: StationRole?,
        value: Int,
        earned: Int?,
        sets: Int,
        floor: Int,
        ceiling: Int,
        isFocused: Bool = false
    ) {
        self.exercise = exercise
        self.role = role
        self.value = value
        self.earned = earned
        self.sets = sets
        self.floor = min(floor, value)
        self.ceiling = max(ceiling, value)
        self.start = value
        self.isFocused = isFocused
    }

    /// A station the fit never moves.
    static func fixed(_ exercise: Exercise, role: StationRole?, value: Int, sets: Int, isFocused: Bool = false) -> PlannedItem {
        PlannedItem(
            exercise: exercise,
            role: role,
            value: value,
            earned: nil,
            sets: sets,
            floor: value,
            ceiling: value,
            isFocused: isFocused
        )
    }

    var reps: Int? { exercise.isHold ? nil : value }
    var durationSeconds: Int? { exercise.isHold ? value : nil }
    var padSteps: Int { (value - start) / RepGrammar.step }

    /// Planned seconds for one set at this station's current number (`SessionAssembly.workSecondsPerSet`).
    var workSecondsPerSet: Int {
        SessionAssembly.workSecondsPerSet(for: exercise, reps: reps, durationSeconds: durationSeconds)
    }

    func materialize(restSeconds: Int) -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: reps,
            durationSeconds: durationSeconds,
            restSeconds: restSeconds,
            role: role,
            earnedReps: exercise.isHold ? nil : earned,
            earnedDurationSeconds: exercise.isHold ? earned : nil
        )
    }
}

// MARK: - SessionPlan

/// A Training Day as it is being sized: the warm-up, the circuit's stations with its pause and round
/// rest (and their caps), and the cooldown.
struct SessionPlan: Equatable {
    var trainingDay: TrainingDay
    var warmup: [PlannedItem]
    var stations: [PlannedItem]
    var cooldown: [PlannedItem]
    var transitionSeconds: Int
    var roundRestSeconds: Int
    let transitionCap: Int
    let roundRestCap: Int

    /// The planned wall-clock, priced exactly as `SessionAssembly.plannedSeconds(of:)` prices the
    /// materialized session.
    var totalSeconds: Int {
        let gap = SessionAssembly.transitionSeconds
        func linear(_ items: [PlannedItem]) -> Int {
            items.reduce(0) { $0 + $1.sets * $1.workSecondsPerSet } + max(0, items.count - 1) * gap
        }
        var blocks: [Int] = []
        if !warmup.isEmpty { blocks.append(linear(warmup)) }
        if !stations.isEmpty {
            let rounds = RepGrammar.setsPerStation
            let perRound = stations.reduce(0) { $0 + $1.workSecondsPerSet }
            blocks.append(rounds * perRound + rounds * (stations.count - 1) * transitionSeconds + (rounds - 1) * roundRestSeconds)
        }
        if !cooldown.isEmpty { blocks.append(linear(cooldown)) }
        return blocks.reduce(0, +) + max(0, blocks.count - 1) * gap
    }

    /// Whether the fit has no lever left to lengthen the session: every station at the top of its range
    /// and both rests at their caps. A session short of its length in this state is an honest shortfall.
    var isSaturated: Bool {
        guard !stations.isEmpty else { return true }
        return stations.allSatisfy { $0.value + RepGrammar.step > $0.ceiling }
            && roundRestSeconds + RepGrammar.step > roundRestCap
            && (stations.count <= 1 || transitionSeconds + RepGrammar.step > transitionCap)
    }

    /// The playable blocks; an empty block never reaches the player.
    func materialize() -> [WorkoutBlock] {
        var blocks: [WorkoutBlock] = []
        if !warmup.isEmpty {
            blocks.append(WorkoutBlock(
                id: UUID(),
                title: "Warm-Up",
                category: .warmup,
                exercises: warmup.map { $0.materialize(restSeconds: SessionAssembly.mobilityRestSeconds) }
            ))
        }
        if !stations.isEmpty {
            blocks.append(WorkoutBlock(
                id: UUID(),
                title: trainingDay.displayName,
                category: .strength,
                exercises: stations.map { $0.materialize(restSeconds: roundRestSeconds) },
                transitionSeconds: transitionSeconds
            ))
        }
        if !cooldown.isEmpty {
            blocks.append(WorkoutBlock(
                id: UUID(),
                title: "Cooldown",
                category: .cooldown,
                exercises: cooldown.map { $0.materialize(restSeconds: SessionAssembly.mobilityRestSeconds) }
            ))
        }
        return blocks
    }
}

// MARK: - Builder

/// Fills the slot plan for one Training Day: the bookend stretches, the main stations from the day's
/// ladders, the Practice Movements and the Core Sprinkle. A small stateful value so one `usedIds` set
/// keeps a movement out of two slots.
private struct Builder {
    let library: [Exercise]
    /// The eligible pool (movement access, injuries, recent skips, the Start Seed band, the Return cap).
    let pool: [Exercise]
    let recentLogs: [WorkoutLog]
    /// The full log history the Rotation replays to find the Cycle the Core Sprinkle rotates on.
    let history: [WorkoutLog]
    /// The logged Outside Activities the Rotation reads alongside `history` (decision 21).
    let activities: [OutsideActivity]
    /// The Training Days this user can train (`SessionAssembly.trainableDays`), as the Rotation reads them.
    let trainable: Set<TrainingDay>
    let level: FitnessLevel
    let phase: Phase
    let injuries: [String]
    /// Session Policy pace: how many qualifying sessions a climb of Earned Reps takes.
    let progressionRate: Double
    /// Session Policy variety window: stretches used in this many recent sessions go behind fresher ones.
    let varietyWindow: Int
    /// Return / Re-entry Ramp: holds the prescription under Earned Reps (`< 1`), neutral otherwise.
    let reentryScale: Double
    let isReturn: Bool
    /// The cold-start difficulty cap in force (`SessionPolicy.ColdStartContract.cappedMaxDifficulty`),
    /// `nil` outside the cold-start window. A Practice Movement bypasses the staple gate only, never
    /// this safety cap.
    let practiceDifficultyCap: Int?
    /// Cold-start Start Seed: lifts a no-history opening number (never to the top of the range).
    let startingRepMultiplier: Double
    /// Movements the Start Seed band held out of reach, so a chain's entry is not mistaken for fresh.
    let withheldByStartSeed: Set<String>
    /// The desk-worker `sitsLong` signal (US-M03): a reorder of the bookend pools toward posture and hip
    /// openers, never a sizing lever.
    let sitsLong: Bool
    /// The user's Focus Areas (decision 20): what they cover is ordered first, given the Practice slot
    /// first and padded first; Abs adds a second Core Sprinkle.
    let focusAreas: [FocusArea]
    /// The moves a **Different workout** press asks the session to avoid: ranked behind their
    /// alternatives wherever the plan has a choice, never filtered.
    let offered: Set<String>
    /// Whether both Trainers have a movement's full pose pair: a Variation is offered only when they do.
    let hasTrainerArt: (Exercise) -> Bool
    let asOf: Date
    let calendar: Calendar
    /// Movements already claimed by an earlier slot.
    var usedIds: Set<String> = []

    init(
        library: [Exercise],
        pool: [Exercise],
        recentLogs: [WorkoutLog],
        history: [WorkoutLog],
        activities: [OutsideActivity],
        trainable: Set<TrainingDay>,
        level: FitnessLevel,
        phase: Phase,
        injuries: [String],
        progressionRate: Double,
        varietyWindow: Int,
        reentryScale: Double,
        isReturn: Bool,
        practiceDifficultyCap: Int?,
        startingRepMultiplier: Double,
        withheldByStartSeed: Set<String>,
        sitsLong: Bool,
        focusAreas: [FocusArea],
        offered: Set<String>,
        hasTrainerArt: @escaping (Exercise) -> Bool,
        asOf: Date,
        calendar: Calendar
    ) {
        self.library = library
        self.pool = pool
        self.recentLogs = recentLogs
        self.history = history
        self.activities = activities
        self.trainable = trainable
        self.level = level
        self.phase = phase
        self.injuries = injuries
        self.progressionRate = progressionRate
        self.varietyWindow = varietyWindow
        self.reentryScale = reentryScale
        self.isReturn = isReturn
        self.practiceDifficultyCap = practiceDifficultyCap
        self.startingRepMultiplier = startingRepMultiplier
        self.withheldByStartSeed = withheldByStartSeed
        self.sitsLong = sitsLong
        self.focusAreas = focusAreas
        self.offered = offered
        self.hasTrainerArt = hasTrainerArt
        self.asOf = asOf
        self.calendar = calendar
    }

    // MARK: Plan

    mutating func plan(day: TrainingDay, requestedMinutes: Int) -> SessionPlan {
        // Every bookend stretch complements the day's group; the others fill only once those run out
        // (ADR-0018). The cooldown picks first and takes holds first, so the day's matching holds close the
        // session and the warm-up does not use them up when only a few match (a beginner's Push Day has
        // four); the warm-up then takes the freshest matches left.
        let cooldown = mobilityItems(
            from: orderedMobility(matching: day.patterns, holdsFirst: true),
            cap: SessionAssembly.cooldownExerciseCount(forRequestedMinutes: requestedMinutes)
        )
        let warmup = mobilityItems(
            from: orderedMobility(matching: day.patterns),
            cap: SessionAssembly.warmupExerciseCount(forRequestedMinutes: requestedMinutes)
        )

        let stations = mainStations(day: day, slots: SessionAssembly.mainSlotCount(forRequestedMinutes: requestedMinutes))
            + coreStations(count: SessionAssembly.coreSprinkleCount(
                forRequestedMinutes: requestedMinutes,
                focusAreas: focusAreas
            ))

        let isLong = requestedMinutes > SessionAssembly.shortSessionMaxMinutes
        return SessionPlan(
            trainingDay: day,
            warmup: warmup,
            stations: stations,
            cooldown: cooldown,
            transitionSeconds: SessionAssembly.transitionSeconds,
            roundRestSeconds: SessionAssembly.baseRoundRestSeconds,
            transitionCap: isLong ? SessionAssembly.maxTransitionSeconds : SessionAssembly.transitionSeconds,
            roundRestCap: SessionAssembly.roundRestCap(for: level, requestedMinutes: requestedMinutes)
        )
    }

    /// The Recovery flow's stretches: two moving stretches then two holds where the pool allows, freshest
    /// first, each one set at its catalog length.
    mutating func recoveryStretches(count: Int) -> [PlannedItem] {
        let ordered = orderedMobility(matching: nil)
        var picked = Array(ordered.filter { !$0.isHold }.prefix(count / 2))
        let holds = ordered.filter { hold in hold.isHold && !picked.contains { $0.id == hold.id } }
        picked += holds.prefix(count - picked.count)
        if picked.count < count {
            let rest = ordered.filter { stretch in !picked.contains { $0.id == stretch.id } }
            picked += rest.prefix(count - picked.count)
        }
        return picked.map { exercise in
            usedIds.insert(exercise.id)
            return .fixed(exercise, role: .recovery, value: SessionAssembly.bookendValue(for: exercise), sets: 1)
        }
    }

    // MARK: Main stations

    /// The main, Practice and Variation stations (decisions 8-11, ADR-0018): each due ladder's current
    /// rung, in slot order, then - for the slots the day's ladders cannot fill - a Practice Movement for
    /// the first ladder, then the second, then - on the slots beyond a rung and a Practice Movement for
    /// every ladder (a Push or Pull Day's fifth) - a Variation of a current rung, or nothing. A ladder
    /// with no eligible rung (movement access, an injury) contributes nothing.
    ///
    /// Focus Areas (decision 20): a ladder whose current rung a Focus Area covers goes ahead of the others
    /// (behind only a Different workout press, which asks for other moves), and the Practice slot goes
    /// first to a ladder a Focus Area covers - by its current rung or by the rung above it.
    private mutating func mainStations(day: TrainingDay, slots: Int) -> [PlannedItem] {
        let eligibleIds = Set(pool.map(\.id))
        let selections = orderedLadders(for: day).compactMap { ladder -> ChainSelection? in
            ProgressionChainSelection.selectInChain(
                library.filter { $0.progressionChainId == ladder },
                eligibleIds: eligibleIds,
                recentLogs: recentLogs,
                level: level,
                withheldByStartSeed: withheldByStartSeed
            )
        }
        let ladders = focusFirst(selections) { selection in
            offered.contains(selection.exercise.id) ? nil : focusAreas.covers(selection.exercise)
        }
        let mains = Array(ladders.prefix(slots))
        var items = mains.compactMap { mainItem(for: $0.exercise, role: .main) }
        let practiceOrder = focusFirst(mains) { main in
            focusAreas.covers(main.exercise) || nextRung(above: main).map(focusAreas.covers) == true
        }
        for main in practiceOrder.prefix(max(0, slots - mains.count)) {
            if let practice = practiceItem(for: main) { items.append(practice) }
        }
        let variationSlots = max(0, slots - 2 * day.ladders.count)
        return items + variationStations(count: variationSlots, mains: items.filter { $0.role == .main })
    }

    /// The Variation slots (ADR-0018): Variations of the day's current rungs (`Exercise.variationOf`) that
    /// the eligible pool offers - so every movement-access, injury and skip rule applies - and that both
    /// Trainers have art for, least recently done first. A rung's Variations rotate that way; with none
    /// eligible the slot stays empty and the fit fills the time with reps and rest.
    private mutating func variationStations(count: Int, mains: [PlannedItem]) -> [PlannedItem] {
        guard count > 0 else { return [] }
        let parentOrder = Dictionary(mains.enumerated().map { ($1.exercise.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lastDone = lastDoneDates()
        let candidates = pool
            .filter { variation in
                variation.variationOf.map { parentOrder[$0] != nil } == true
                    && !usedIds.contains(variation.id)
                    && hasTrainerArt(variation)
            }
            .sorted { lhs, rhs in
                // A Variation a Different workout press already showed goes behind the others.
                let lOffered = offered.contains(lhs.id)
                let rOffered = offered.contains(rhs.id)
                if lOffered != rOffered { return !lOffered }
                let l = lastDone[lhs.id]
                let r = lastDone[rhs.id]
                if (l == nil) != (r == nil) { return l == nil }
                if let l, let r, l != r { return l < r }
                let lParent = lhs.variationOf.flatMap { parentOrder[$0] } ?? 0
                let rParent = rhs.variationOf.flatMap { parentOrder[$0] } ?? 0
                return lParent != rParent ? lParent < rParent : lhs.id < rhs.id
            }
        var items: [PlannedItem] = []
        for variation in candidates where items.count < count {
            guard let parent = mains.first(where: { $0.exercise.id == variation.variationOf }) else { continue }
            items.append(variationItem(for: variation, parent: parent))
        }
        return items
    }

    /// A Variation station: four sets at its parent rung's number when the two are counted alike (reps,
    /// reps per side, or a hold), else at the opening number of its own range, cut and padded like a main
    /// station. It records no Earned Reps, so nothing it logs moves a rung or the Rep Ramp.
    private mutating func variationItem(for variation: Exercise, parent: PlannedItem) -> PlannedItem {
        usedIds.insert(variation.id)
        let kind = RepGrammar.kind(of: variation)
        let isHeld = reentryScale < AdaptiveOverload.neutralReentryScale
        let value: Int
        if kind == RepGrammar.kind(of: parent.exercise) {
            value = parent.start
        } else {
            value = AdaptiveOverload.target(
                for: variation,
                level: level,
                recentLogs: [],
                progressionRate: progressionRate,
                reentryScale: reentryScale,
                steppedDownSince: nil,
                startingRepMultiplier: startingRepMultiplier
            ).value
        }
        return PlannedItem(
            exercise: variation,
            role: .variation,
            value: value,
            earned: nil,
            sets: RepGrammar.setsPerStation,
            floor: RepGrammar.shortSessionFloor(for: kind),
            ceiling: isHeld ? value : RepGrammar.earnedRange(for: kind, level: level).upperBound,
            isFocused: parent.isFocused
        )
    }

    /// `items` with the focused ones first, each group keeping its incoming order. `isFocused` returns
    /// `nil` for an item that must stay behind both groups (a Different workout press already showed it).
    private func focusFirst<Item>(_ items: [Item], isFocused: (Item) -> Bool?) -> [Item] {
        guard !focusAreas.isEmpty else { return items }
        let ranked = items.map { item -> Int in
            switch isFocused(item) {
            case true?: return 0
            case false?: return 1
            case nil: return 2
            }
        }
        return items.indices.sorted { ranked[$0] != ranked[$1] ? ranked[$0] < ranked[$1] : $0 < $1 }.map { items[$0] }
    }

    /// The rung above `main` on its ladder, if there is one.
    private func nextRung(above main: ChainSelection) -> Exercise? {
        library.first { $0.progressionChainId == main.chainId && $0.progressionOrder == main.order + 1 }
    }

    /// The day's ladders in slot order: least recently worked first (never worked ahead of worked, then
    /// the canonical order). A Legs Day leads with one squat-side and one hinge-side ladder - the side
    /// worked longest ago first - before the remaining two. A ladder whose current rung a Different
    /// workout press already showed goes behind the others.
    private func orderedLadders(for day: TrainingDay) -> [String] {
        let ladderById = Dictionary(library.map { ($0.id, $0.progressionChainId) }, uniquingKeysWith: { first, _ in first })
        var lastWorked: [String: Date] = [:]
        var shownLadders: Set<String> = []
        for log in recentLogs {
            for logged in log.exercises where logged.countsForProgression {
                guard let ladder = ladderById[logged.exerciseId] else { continue }
                lastWorked[ladder] = max(lastWorked[ladder] ?? .distantPast, log.completedAt)
            }
        }
        for id in offered { if let ladder = ladderById[id] { shownLadders.insert(ladder) } }
        let canonical = day.ladders
        func isDue(_ lhs: String, before rhs: String) -> Bool {
            let lShown = shownLadders.contains(lhs)
            let rShown = shownLadders.contains(rhs)
            if lShown != rShown { return !lShown }
            let l = lastWorked[lhs]
            let r = lastWorked[rhs]
            if (l == nil) != (r == nil) { return l == nil }
            if let l, let r, l != r { return l < r }
            return (canonical.firstIndex(of: lhs) ?? 0) < (canonical.firstIndex(of: rhs) ?? 0)
        }
        guard day == .legs else { return canonical.sorted(by: isDue) }
        let sides = [["squat", "lunge"], ["hinge_bridge", "hinge_hip"]]
            .map { $0.sorted(by: isDue) }
            .sorted { isDue($0[0], before: $1[0]) }
        let leads = sides.map { $0[0] }
        let rest = sides.flatMap { $0.dropFirst() }.sorted(by: isDue)
        return leads + rest
    }

    /// A main or core station for `exercise`: four sets at its served Earned Reps (held under them on a
    /// Return), which the fit may cut to the short-session floor or pad to the top of the range - except
    /// on a Return or ramp session, which is never padded.
    private mutating func mainItem(for exercise: Exercise, role: StationRole) -> PlannedItem? {
        guard !usedIds.contains(exercise.id) else { return nil }
        usedIds.insert(exercise.id)
        let kind = RepGrammar.kind(of: exercise)
        let target = AdaptiveOverload.target(
            for: exercise,
            level: level,
            recentLogs: recentLogs,
            progressionRate: progressionRate,
            reentryScale: reentryScale,
            steppedDownSince: ProgressionChainSelection.stepDownDate(
                onto: exercise,
                library: library,
                recentLogs: recentLogs,
                level: level
            ),
            startingRepMultiplier: startingRepMultiplier
        )
        let isHeld = reentryScale < AdaptiveOverload.neutralReentryScale
        return PlannedItem(
            exercise: exercise,
            role: role,
            value: target.value,
            earned: RepGrammar.served(earned: target.earned, for: kind, level: level),
            sets: RepGrammar.setsPerStation,
            floor: RepGrammar.shortSessionFloor(for: kind),
            ceiling: isHeld ? target.value : RepGrammar.earnedRange(for: kind, level: level).upperBound,
            isFocused: focusAreas.covers(exercise)
        )
    }

    /// The Practice Movement for `main` (decisions 9-10, ADR-0015): the next harder rung at Practice
    /// reps. It bypasses the staple gate but never an injury, a Strength-Phase lock, a withdrawn rung or
    /// the cold-start difficulty cap, and is not offered on a Return. With no such rung, the rung below at volume reps; with neither,
    /// no station.
    private mutating func practiceItem(for main: ChainSelection) -> PlannedItem? {
        let chain = library.filter { $0.progressionChainId == main.chainId }
        if !isReturn, let harder = chain.first(where: { $0.progressionOrder == main.order + 1 }),
           isPracticeEligible(harder), !usedIds.contains(harder.id) {
            usedIds.insert(harder.id)
            return .fixed(
                harder,
                role: .practice,
                value: RepGrammar.practiceValue(for: RepGrammar.kind(of: harder)),
                sets: RepGrammar.setsPerStation,
                isFocused: focusAreas.covers(harder)
            )
        }
        guard let lower = chain.first(where: { $0.progressionOrder == main.order - 1 }),
              isPracticeEligible(lower),
              let item = mainItem(for: lower, role: .practice) else { return nil }
        return PlannedItem(
            exercise: item.exercise,
            role: .practice,
            value: item.value,
            earned: nil,
            sets: item.sets,
            floor: item.floor,
            ceiling: item.ceiling,
            isFocused: item.isFocused
        )
    }

    /// Practice eligibility: in the offered catalog (never withdrawn), its phase earned, safe for the
    /// user's injuries, and inside the cold-start difficulty cap while that is in force. Only the staple
    /// restriction does not apply (ADR-0015).
    private func isPracticeEligible(_ exercise: Exercise) -> Bool {
        !MovementAccess.isWithdrawn(exercise)
            && MovementAccess.isPhaseEarned(exercise, phase: phase)
            && ExercisePoolFilter.isInjurySafe(exercise, injuries: injuries)
            && practiceDifficultyCap.map { exercise.difficulty <= $0 } ?? true
    }

    // MARK: Core Sprinkle

    /// The Core Sprinkle(s): the current rung of this Cycle's core ladder (`TrainingRotation
    /// .coreLadderOrder`), then the next when a second is asked for.
    private mutating func coreStations(count: Int) -> [PlannedItem] {
        guard count > 0 else { return [] }
        let eligibleIds = Set(pool.map(\.id))
        let ordered = TrainingRotation.coreLadderOrder(
            canonical: SessionAssembly.coreLadders,
            library: library,
            logs: history,
            activities: activities,
            trainable: trainable,
            asOf: asOf,
            calendar: calendar
        )
        var items: [PlannedItem] = []
        let selections = ordered.compactMap { ladder in
            ProgressionChainSelection.selectInChain(
                library.filter { $0.progressionChainId == ladder },
                eligibleIds: eligibleIds,
                recentLogs: recentLogs,
                level: level,
                withheldByStartSeed: withheldByStartSeed
            )
        }
        // A core rung a Different workout press already showed goes behind the other ladders' rungs.
        let preferred = selections.filter { !offered.contains($0.exercise.id) } + selections.filter { offered.contains($0.exercise.id) }
        for selection in preferred where items.count < count {
            if let item = mainItem(for: selection.exercise, role: .core) { items.append(item) }
        }
        return items
    }

    // MARK: Bookends

    /// One-set stretches at their catalog lengths, claiming each id so no later slot reuses it.
    private mutating func mobilityItems(from exercises: [Exercise], cap: Int) -> [PlannedItem] {
        exercises.prefix(cap).map { exercise in
            usedIds.insert(exercise.id)
            return .fixed(exercise, role: nil, value: SessionAssembly.bookendValue(for: exercise), sets: 1)
        }
    }

    // MARK: Bookend ordering

    /// Eligible, not-yet-claimed mobility movements ordered for variety: never-worked and longest-ago
    /// first, movements used in the last few sessions pushed back, then shortest (finest timing
    /// granularity) and id as deterministic tie-breaks. Ahead of all of that, a stretch a **Different
    /// workout** press already showed (`offered`) goes behind every stretch that press has not.
    ///
    /// `matching` makes the bookends day-matched (ADR-0018, replacing US-M02's prefer-then-fill lead):
    /// given the day's patterns, every stretch whose `complements` names one of them comes first, in that
    /// variety order, and the others follow only as the fallback for when the matches run out - so a
    /// bookend is never starved, and never holds an unmatched stretch while a match is left. `nil` (the
    /// Recovery flow) keeps the plain variety order. `holdsFirst` (the cooldown) puts holds ahead of moving
    /// stretches inside each of those two groups, never across them.
    ///
    /// `sitsLong` layers the US-M03 posture/hip bias inside each group (`postureHipLean`): a desk worker's
    /// matching stretches lead with posture/hip openers, but the bias never brings an unmatched stretch
    /// ahead of a match. Every step is a pure, stable reorder of a deterministically-sorted array, so the
    /// assembled session stays an `asOf`-pure function of its inputs, and none changes a bookend's count -
    /// though the reorder does change which stretches fill it, so bookend duration (and, through the timing
    /// fit, the reps and rest) can differ between profiles.
    private func orderedMobility(matching patterns: Set<MovementPattern>?, holdsFirst: Bool = false) -> [Exercise] {
        let lastWorked = lastDoneDates()
        let recent = recentlyUsedIds()
        let ordered = pool
            .filter { $0.pillar == .mobility && !usedIds.contains($0.id) }
            .sorted { lhs, rhs in
                // A Different workout press: a stretch an earlier press already showed goes behind every
                // other, ahead of the variety window, since the user has just asked for other moves.
                let lhsOffered = offered.contains(lhs.id)
                let rhsOffered = offered.contains(rhs.id)
                if lhsOffered != rhsOffered { return !lhsOffered }

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
        func arranged(_ group: [Exercise]) -> [Exercise] {
            let leaned = Self.postureHipLean(group, apply: sitsLong)
            guard holdsFirst else { return leaned }
            return leaned.filter(\.isHold) + leaned.filter { !$0.isHold }
        }
        guard let patterns else { return arranged(ordered) }
        let matches = ordered.filter { SessionAssembly.complements($0, anyOf: patterns) }
        let others = ordered.filter { !SessionAssembly.complements($0, anyOf: patterns) }
        return arranged(matches) + arranged(others)
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
    /// worker's bookend duration - and, through the timing fit, the reps and rest - can differ from the
    /// general profile's. What is guarded is the training movements and their Earned Reps
    /// (`testSitsLongChangesNoTrainingMovementOrEarnedLevel`). `orderedMobility` applies it inside the
    /// day's matching stretches and inside the fallback separately, so it never brings an unmatched
    /// stretch ahead of a match (ADR-0018). Pure and deterministic: a stable partition of an already
    /// deterministically-sorted array (`filter` preserves order), with no set-iteration dependence and no
    /// clock, so the assembled session stays an `asOf`-pure function of its inputs.
    private static func postureHipLean(_ ordered: [Exercise], apply: Bool) -> [Exercise] {
        guard apply else { return ordered }
        return ordered.filter(SessionAssembly.isPostureHipOpener)
            + ordered.filter { !SessionAssembly.isPostureHipOpener($0) }
    }

    /// Most recent completed (non-skipped) date per exercise id, for the variety order of the bookends and
    /// the Variation slot.
    private func lastDoneDates() -> [String: Date] {
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
