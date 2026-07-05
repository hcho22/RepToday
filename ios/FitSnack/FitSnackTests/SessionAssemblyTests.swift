import XCTest
@testable import FitSnack

/// Tests pipeline Step 7 of the deterministic engine (US-C07): assembling Steps 1-6 into a complete,
/// timing-fit `Workout`.
///
/// Coverage mirrors the PRD acceptance criteria, run end-to-end over the real bundled library so the
/// whole pipeline is exercised: every session opens with a warm-up; a cooldown closes a session only
/// when it runs past 10 minutes; the planned wall-clock lands within ±1 minute of the request for
/// 5/10/15/20/30; generation is under 100ms; the output is a fully-formed, capacity-relative session;
/// and assembly is deterministic. The final block is the PRD's own validation case (intermediate user,
/// some history, 20 minutes).
final class SessionAssemblyTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        sitsLong: Bool = false,
        injuries: [String] = []
    ) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: level,
                primaryGoal: .stayActive,
                sitsLong: sitsLong,
                injuries: injuries,
                typicalAvailableMinutes: 15
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 1,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
    }

    /// A completed session `daysAgo` working `exercises` (id, pillar, pattern, per-set reps), used to
    /// give the user "some history" so Steps 2-6 have signal.
    private func log(
        _ exercises: [(id: String, pillar: Pillar, pattern: MovementPattern, reps: Int)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: difficulty,
            exercises: exercises.map { entry in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: entry.id,
                    pillar: entry.pillar,
                    movementPattern: entry.pattern,
                    completedSets: [
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                        CompletedSet(reps: entry.reps, durationSeconds: nil),
                    ],
                    skipped: false
                )
            }
        )
    }

    /// A few days of mixed history so the engine has staleness and capacity signal to read.
    private func someHistory() -> [WorkoutLog] {
        [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 2, difficulty: .justRight),
            log([
                ("mobility_cat_cow", .mobility, .mobility, 10),
            ], daysAgo: 4),
        ]
    }

    private let durations = [5, 10, 15, 20, 30]

    private func assemble(
        minutes: Int,
        user: User,
        library: [Exercise],
        logs: [WorkoutLog]
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - Warm-up always opens the session

    func testEverySessionOpensWithAWarmUp() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let first = try XCTUnwrap(workout.blocks.first, "\(minutes) min produced no blocks")
            XCTAssertEqual(first.category, .warmup, "\(minutes) min must open with a warm-up")
            XCTAssertFalse(first.exercises.isEmpty, "\(minutes) min warm-up must have an exercise")
        }
    }

    func testMobilityLedSessionStillOpensWithAWarmUp() async throws {
        let library = try await library()
        // A desk worker whose mobility is the stalest pillar gets a mobility-led short session that
        // still opens with a warm-up (the opening flow doubles as warm-up + training).
        let logs = [log([("push_standard", .strength, .push, 12)], daysAgo: 1)]
        let workout = assemble(minutes: 10, user: user(sitsLong: true), library: library, logs: logs)
        XCTAssertEqual(workout.blocks.first?.category, .warmup)
        XCTAssertEqual(workout.focusPillar, .mobility, "stale mobility + desk worker leads to a mobility focus")
    }

    // MARK: - Cooldown only past 10 minutes

    func testCooldownPresentOnlyWhenOverTenMinutes() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let hasCooldown = workout.blocks.contains { $0.category == .cooldown }
            if minutes > 10 {
                XCTAssertTrue(hasCooldown, "\(minutes) min should end with a cooldown")
                XCTAssertEqual(workout.blocks.last?.category, .cooldown, "\(minutes) min cooldown must be last")
            } else {
                XCTAssertFalse(hasCooldown, "\(minutes) min should not have a cooldown")
            }
        }
    }

    // MARK: - Timing fit: within ±1 minute

    func testTotalTimeLandsWithinOneMinuteForEveryDuration() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let planned = SessionAssembly.plannedSeconds(of: workout)
            let target = minutes * 60
            XCTAssertLessThanOrEqual(
                abs(planned - target),
                SessionAssembly.toleranceSeconds,
                "\(minutes) min planned \(planned)s is outside ±60s of \(target)s"
            )
        }
    }

    func testTimingFitHoldsForAFreshUserToo() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: [])
            let planned = SessionAssembly.plannedSeconds(of: workout)
            XCTAssertLessThanOrEqual(abs(planned - minutes * 60), SessionAssembly.toleranceSeconds,
                                     "fresh-user \(minutes) min planned \(planned)s outside tolerance")
        }
    }

    // MARK: - Latency under 100ms

    func testGenerationLatencyUnder100ms() async throws {
        let library = try await library()
        let user = user()
        let logs = someHistory()
        // Warm the path once, then measure a single end-to-end assembly.
        _ = assemble(minutes: 20, user: user, library: library, logs: logs)

        let start = DispatchTime.now()
        _ = assemble(minutes: 20, user: user, library: library, logs: logs)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }

    // MARK: - Fully-formed, playable output

    func testOutputIsFullyFormedAndCapacityRelative() async throws {
        let library = try await library()
        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            XCTAssertEqual(workout.requestedMinutes, minutes)
            XCTAssertFalse(workout.blocks.isEmpty, "\(minutes) min produced no blocks")

            for block in workout.blocks {
                XCTAssertFalse(block.exercises.isEmpty, "block '\(block.title)' is empty")
                for prescription in block.exercises {
                    XCTAssertGreaterThanOrEqual(prescription.sets, 1, "every prescription needs >=1 set")
                    if prescription.exercise.isHold {
                        XCTAssertNotNil(prescription.durationSeconds, "\(prescription.exercise.id) hold needs seconds")
                        XCTAssertNil(prescription.reps, "\(prescription.exercise.id) hold must not carry reps")
                    } else {
                        XCTAssertNotNil(prescription.reps, "\(prescription.exercise.id) rep movement needs reps")
                        XCTAssertNil(prescription.durationSeconds, "\(prescription.exercise.id) reps must not carry seconds")
                        // Capacity-relative, never a fixed heroic number: within the overload rails.
                        XCTAssertLessThanOrEqual(prescription.reps!, AdaptiveOverload.maxReps,
                                                 "\(prescription.exercise.id) reps must stay within the safety rail")
                    }
                    XCTAssertTrue(prescription.exercise.equipment.isEmpty, "Zero-Equipment Floor")
                }
            }
        }
    }

    func testNoExerciseRepeatsAcrossBlocks() async throws {
        let library = try await library()
        let workout = assemble(minutes: 30, user: user(), library: library, logs: someHistory())
        let ids = workout.blocks.flatMap { $0.exercises.map { $0.exercise.id } }
        XCTAssertEqual(Set(ids).count, ids.count, "an exercise appeared in more than one block")
    }

    // MARK: - Blend honors the Step 2 pillar weights

    /// Planned wall-clock of a single materialized block (`Σ sets × est + (sets - 1) × rest`), used to
    /// compare how much session time each pillar block actually owns.
    private func plannedSeconds(_ block: WorkoutBlock) -> Int {
        block.exercises.reduce(0) { sum, p in
            sum + p.sets * p.exercise.estimatedTimePerSetSeconds + max(0, p.sets - 1) * p.restSeconds
        }
    }

    func testBlendSizesTrainingBlocksByPillarStaleness() async throws {
        let library = try await library()

        // Mobility never worked, strength worked yesterday -> mobility is the staler, heavier pillar,
        // so its Movement Practice block should own more session time than the strength block.
        let mobilityStaleLogs = [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 1)
        ]
        let mobilityStale = assemble(minutes: 20, user: user(), library: library, logs: mobilityStaleLogs)
        let mobBlock = try XCTUnwrap(mobilityStale.blocks.first { $0.category == .mobility })
        let strBlock = try XCTUnwrap(mobilityStale.blocks.first { $0.category == .strength })
        XCTAssertGreaterThan(
            plannedSeconds(mobBlock), plannedSeconds(strBlock),
            "a strongly mobility-stale blend should give the mobility block more planned time"
        )

        // Strength never worked, mobility worked yesterday -> the weights flip and strength is heavier.
        let strengthStaleLogs = [log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 1)]
        let strengthStale = assemble(minutes: 20, user: user(), library: library, logs: strengthStaleLogs)
        let mob2 = try XCTUnwrap(strengthStale.blocks.first { $0.category == .mobility })
        let str2 = try XCTUnwrap(strengthStale.blocks.first { $0.category == .strength })
        XCTAssertGreaterThan(
            plannedSeconds(str2), plannedSeconds(mob2),
            "a strongly strength-stale blend should give the strength block more planned time"
        )
    }

    // MARK: - Extended blend promotes primal to its own block (US-E02)

    /// A few days of mixed history that leaves primal stale: strength/mobility worked recently, the
    /// last primal session was long ago.
    private func stalePrimalHistory() -> [WorkoutLog] {
        [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 2, difficulty: .justRight),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 3),
            log([("primal_bear_crawl", .primal, .locomotion, 10)], daysAgo: 12),
        ]
    }

    /// The validation test: a 50-min session for a user with stale primal history contains a dedicated
    /// primal block (a `WorkoutBlock` of `pillar == .primal` movements) alongside strength and mobility.
    func testExtendedSessionProducesADedicatedPrimalBlock() async throws {
        let library = try await library()
        let workout = assemble(minutes: 50, user: user(level: .intermediate), library: library, logs: stalePrimalHistory())

        let primalBlock = try XCTUnwrap(
            workout.blocks.first { $0.category == .primal },
            "a 50-min session must contain a dedicated primal block"
        )
        XCTAssertFalse(primalBlock.exercises.isEmpty, "the primal block must hold at least one movement")
        for prescription in primalBlock.exercises {
            XCTAssertEqual(prescription.exercise.pillar, .primal, "the primal block holds only primal movements")
            XCTAssertEqual(prescription.exercise.movementPattern, .locomotion, "primal is driven by the locomotion pattern")
            XCTAssertTrue(prescription.exercise.equipment.isEmpty, "Zero-Equipment Floor still holds")
            XCTAssertGreaterThanOrEqual(prescription.sets, 1, "every prescription needs >=1 set")
        }

        // The primal block joins strength and mobility rather than replacing them.
        XCTAssertTrue(workout.blocks.contains { $0.category == .strength }, "strength block still present")
        XCTAssertTrue(workout.blocks.contains { $0.category == .mobility }, "mobility block still present")

        // With primal carved out, the strength block must not also fold a primal movement in (no
        // double-booking the same locomotion exercise across two blocks).
        let strengthBlock = try XCTUnwrap(workout.blocks.first { $0.category == .strength })
        XCTAssertFalse(
            strengthBlock.exercises.contains { $0.exercise.pillar == .primal },
            "an extended blend sheds primal from the strength block"
        )

        // The extended session is still well-structured: warm-up opens it, cooldown closes it.
        XCTAssertEqual(workout.blocks.first?.category, .warmup, "opens with a warm-up")
        XCTAssertEqual(workout.blocks.last?.category, .cooldown, "closes with a cooldown")
    }

    /// Short and full blends do not regress: primal is still folded into strength, so no dedicated
    /// `.primal` block appears even when primal is the stalest pillar.
    func testShorterSessionsDoNotCarveOutAPrimalBlock() async throws {
        let library = try await library()
        // Primal stale, strength/mobility fresh - the shape, not staleness, gates the dedicated block.
        let logs = [
            log([("push_standard", .strength, .push, 12)], daysAgo: 1),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 1),
            log([("primal_bear_crawl", .primal, .locomotion, 10)], daysAgo: 20),
        ]
        for minutes in [10, 20, 30] {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: logs)
            XCTAssertFalse(
                workout.blocks.contains { $0.category == .primal },
                "\(minutes) min must not carve out a dedicated primal block"
            )
        }
    }

    /// Extended assembly is deterministic run to run, just like the shorter shapes.
    func testExtendedAssemblyIsDeterministic() async throws {
        let library = try await library()
        let user = user()
        let logs = stalePrimalHistory()
        let first = structuralSignature(assemble(minutes: 50, user: user, library: library, logs: logs))
        for _ in 0..<10 {
            let next = structuralSignature(assemble(minutes: 50, user: user, library: library, logs: logs))
            XCTAssertEqual(next, first, "extended assembly is not deterministic")
        }
    }

    // MARK: - Cooldown keeps real static holds in a blend

    func testBlendCooldownReservesMultipleStaticHolds() async throws {
        let library = try await library()
        // The pre-fit plan is where block reserves are intact: a blend's cooldown must keep more than a
        // single leftover stretch, and every movement it draws (active or reserve) must be a static hold.
        let blocks = SessionAssembly.planBlocks(
            requestedMinutes: 20,
            user: user(),
            library: library,
            recentLogs: someHistory(),
            asOf: asOf,
            calendar: calendar
        )
        let cooldown = try XCTUnwrap(blocks.first { $0.category == .cooldown })
        let cooldownMovements = cooldown.items + cooldown.reserve
        XCTAssertGreaterThan(
            cooldownMovements.count, 1,
            "a blend cooldown should have more than one static stretch available, not be starved to one"
        )
        XCTAssertTrue(
            cooldownMovements.allSatisfy { $0.exercise.isHold },
            "the cooldown's holds-only static-stretch preference must actually be honored"
        )
    }

    // MARK: - Session Policy levers (US-E03)

    /// Passing `SessionPolicy.default` reproduces the unpoliced assembly exactly - wiring the policy
    /// through the pipeline is a no-op at the neutral levers (no regression).
    func testDefaultPolicyReproducesUnpolicedOutput() async throws {
        let library = try await library()
        let user = user()
        let logs = someHistory()
        for minutes in [10, 20, 30, 50] {
            let unpoliced = assemble(minutes: minutes, user: user, library: library, logs: logs)
            let defaulted = SessionAssembly.assemble(
                requestedMinutes: minutes, user: user, library: library,
                recentLogs: logs, sessionPolicy: .default, asOf: asOf, calendar: calendar
            )
            XCTAssertEqual(
                structuralSignature(defaulted), structuralSignature(unpoliced),
                "\(minutes) min: passing SessionPolicy.default must match the unpoliced call"
            )
        }
    }

    /// The PRD validation: doubling `pillarWeighting[.mobility]` gives the mobility block a larger
    /// share of session time than the neutral default policy does. Strength and mobility are equally
    /// stale here, so the neutral split is even and the weighting lever is the only mover.
    func testPillarWeightingIncreasesMobilityTimeShare() async throws {
        let library = try await library()
        let logs = [log([
            ("push_standard", .strength, .push, 12),
            ("mobility_cat_cow", .mobility, .mobility, 10),
        ], daysAgo: 2)]

        func mobilitySeconds(_ policy: SessionPolicy) throws -> Int {
            let workout = SessionAssembly.assemble(
                requestedMinutes: 30, user: user(), library: library,
                recentLogs: logs, sessionPolicy: policy, asOf: asOf, calendar: calendar
            )
            return plannedSeconds(try XCTUnwrap(workout.blocks.first { $0.category == .mobility }))
        }

        var heavyMobility = SessionPolicy.default
        heavyMobility.pillarWeighting[.mobility] = 2.0

        let neutral = try mobilitySeconds(.default)
        let weighted = try mobilitySeconds(heavyMobility)
        XCTAssertGreaterThan(
            weighted, neutral,
            "doubling mobility weighting must give the mobility block more planned time"
        )
    }

    /// A higher `progressionRate` paces Step 6's overload bump end-to-end: the squat lead of this
    /// single-focus strength session (worked six days ago at capacity 15, below its 3x20 criteria so
    /// it stays on tier) carries a heavier rep target under a faster program, still within the rails.
    func testProgressionRatePacesTheOverloadBumpInAssembly() async throws {
        let library = try await library()
        // Squat is the stalest strength/primal pattern (worked 6 days ago); every other pattern is
        // fresh (worked yesterday) and mobility was worked today, so a not-sits-long single-focus
        // session trains strength and leads with squat_bodyweight.
        let logs = [
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 0),
            log([
                ("push_standard", .strength, .push, 10),
                ("hinge_glute_bridge", .strength, .hinge, 10),
                ("core_bird_dog", .strength, .core, 10),
                ("pull_superman", .strength, .pull, 10),
                ("primal_bear_crawl", .primal, .locomotion, 10),
            ], daysAgo: 1),
            log([("squat_bodyweight", .strength, .squat, 15)], daysAgo: 6, difficulty: .justRight),
        ]

        func squatReps(rate: Double) throws -> Int {
            var policy = SessionPolicy.default
            policy.progressionRate = rate
            // Pin the variety window to 1 so both runs select identically (squat_bodyweight, worked
            // six days ago, is outside a 1-session no-repeat window and stays the active-chain pick)
            // - isolating progressionRate as the only difference between the two targets.
            policy.varietyWindow = 1
            let workout = SessionAssembly.assemble(
                requestedMinutes: 10, user: user(), library: library,
                recentLogs: logs, sessionPolicy: policy, asOf: asOf, calendar: calendar
            )
            let squat = try XCTUnwrap(
                workout.blocks.flatMap(\.exercises).first { $0.exercise.id == "squat_bodyweight" },
                "squat_bodyweight should lead this single-focus strength session"
            )
            return try XCTUnwrap(squat.reps)
        }

        let neutral = try squatReps(rate: 1.0)
        let fast = try squatReps(rate: 4.0)
        XCTAssertGreaterThan(fast, neutral, "a higher progressionRate must advance the rep target faster")
        XCTAssertLessThanOrEqual(fast, AdaptiveOverload.maxReps, "still clamped to the safety rail")
    }

    // MARK: - Step 0 cold-start override (US-E04)

    /// A cold-start user: the shared fixture user plus an explicit cold-start state (and optional
    /// `why.openingBias`), so tests can advance the First-Week day (`sessionsLogged`) and retire
    /// cold-start (`active == false`).
    private func coldStartUser(
        level: FitnessLevel = .beginner,
        sessionsLogged: Int = 0,
        active: Bool = true,
        sitsLong: Bool = false,
        openingBias: Pillar? = nil,
        injuries: [String] = []
    ) -> User {
        var user = user(level: level, sitsLong: sitsLong, injuries: injuries)
        user.coldStart = User.ColdStart(sessionsLogged: sessionsLogged, active: active)
        user.why = User.Why(statement: "", openingBias: openingBias)
        return user
    }

    /// A `SessionPolicy.default` carrying a cold-start contract with the given levers.
    private func coldStartPolicy(forceContrastSpread: Bool, cappedMaxDifficulty: Int) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(
            forceContrastSpread: forceContrastSpread,
            cappedMaxDifficulty: cappedMaxDifficulty
        )
        return policy
    }

    private func assemble(minutes: Int, user: User, library: [Exercise], logs: [WorkoutLog], policy: SessionPolicy) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes, user: user, library: library,
            recentLogs: logs, sessionPolicy: policy, asOf: asOf, calendar: calendar
        )
    }

    /// The capped pool removes every over-cap movement while Step 0 is active, and is a no-op once
    /// cold-start is retired or the policy carries no contract.
    func testColdStartCappedPoolRemovesTooHardMovements() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        // Guard: the library actually contains movements the cap should remove.
        XCTAssertTrue(library.contains { $0.difficulty > 2 }, "library must have >2-difficulty movements")

        let active = coldStartUser(level: .advanced, sessionsLogged: 0, active: true)
        let capped = ColdStartOverride.cappedPool(library, user: active, sessionPolicy: policy)
        XCTAssertFalse(capped.isEmpty, "the cap must never empty the pool")
        XCTAssertTrue(capped.allSatisfy { $0.difficulty <= 2 }, "every capped movement is at or below the cap")

        // Warmed-up user: the cap is a no-op even with the contract still present.
        let warm = coldStartUser(level: .advanced, sessionsLogged: 6, active: false)
        XCTAssertEqual(
            ColdStartOverride.cappedPool(library, user: warm, sessionPolicy: policy).count,
            library.count, "a retired cold-start user's pool is never capped"
        )
        // No contract: also a no-op even while active.
        XCTAssertEqual(
            ColdStartOverride.cappedPool(library, user: active, sessionPolicy: .default).count,
            library.count, "no contract means no cap"
        )
    }

    /// End-to-end difficulty cap: an advanced user whose history advances push onto a difficulty-3
    /// movement gets it in the plain engine, but the cold-start cap (contrast off, so the cap is the
    /// only override) keeps every prescribed movement at or below the cap.
    func testColdStartSessionRespectsTheDifficultyCap() async throws {
        let library = try await library()
        // push_standard cleared long ago -> push is the stalest strength pattern (leads a strength
        // single-focus) and is advanceable to push_diamond (difficulty 3); every other pattern was
        // worked yesterday, so push leads.
        let logs = [
            log([
                ("squat_bodyweight", .strength, .squat, 15),
                ("hinge_glute_bridge", .strength, .hinge, 15),
                ("core_bird_dog", .strength, .core, 12),
                ("pull_superman", .strength, .pull, 12),
                ("mobility_cat_cow", .mobility, .mobility, 10),
                ("primal_bear_crawl", .primal, .locomotion, 10),
            ], daysAgo: 1),
            log([("push_standard", .strength, .push, 12)], daysAgo: 10, difficulty: .justRight),
        ]
        let advanced = coldStartUser(level: .advanced, sessionsLogged: 0)

        // Baseline (no contract): push advances onto push_diamond (difficulty 3).
        let baseline = assemble(minutes: 10, user: advanced, library: library, logs: logs, policy: .default)
        XCTAssertTrue(
            baseline.blocks.flatMap(\.exercises).contains { $0.exercise.difficulty >= 3 },
            "without the cap an advanced user advances onto a difficulty-3 movement (guards the test)"
        )

        // Cold-start cap 2 (contrast off): nothing exceeds difficulty 2.
        let capped = assemble(
            minutes: 10, user: advanced, library: library, logs: logs,
            policy: coldStartPolicy(forceContrastSpread: false, cappedMaxDifficulty: 2)
        )
        XCTAssertTrue(
            capped.blocks.flatMap(\.exercises).allSatisfy { $0.exercise.difficulty <= 2 },
            "a cold-start session must cap difficulty at the contract's cappedMaxDifficulty"
        )
        XCTAssertFalse(
            capped.blocks.flatMap(\.exercises).contains { $0.exercise.id == "push_diamond" },
            "the capped session never reaches the over-cap advancement"
        )
    }

    /// Consecutive First-Week single-focus days rotate the pillar, so the week never collapses to a
    /// single theme and no pillar repeats back-to-back - even for a desk worker whose bias is mobility.
    func testConsecutiveColdStartDaysDifferInPillar() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        var pillars: [Pillar] = []
        for day in 0..<4 {
            let user = coldStartUser(level: .beginner, sessionsLogged: day, sitsLong: true)
            let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)
            pillars.append(try XCTUnwrap(workout.focusPillar, "a single-focus day must have a focus pillar"))
        }
        XCTAssertGreaterThan(Set(pillars).count, 1, "the first week must span more than one pillar")
        for index in 1..<pillars.count {
            XCTAssertNotEqual(pillars[index], pillars[index - 1], "no pillar repeats back-to-back in cold start")
        }
    }

    /// The `why.openingBias` sets where the First-Week rotation opens; a mobility-biased user opens on
    /// a mobility day, then rotates off it.
    func testColdStartRotationOpensOnTheWhyOpeningBias() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        let day0 = coldStartUser(level: .beginner, sessionsLogged: 0, openingBias: .mobility)
        let day1 = coldStartUser(level: .beginner, sessionsLogged: 1, openingBias: .mobility)
        XCTAssertEqual(
            assemble(minutes: 8, user: day0, library: library, logs: [], policy: policy).focusPillar,
            .mobility, "the first cold-start day opens on the stated why.openingBias"
        )
        XCTAssertNotEqual(
            assemble(minutes: 8, user: day1, library: library, logs: [], policy: policy).focusPillar,
            .mobility, "the rotation moves off the opening pillar the next day"
        )
    }

    /// The PRD validation: a beginner's three First-Week sessions never exceed the difficulty cap and
    /// span different pillars.
    func testColdStartValidationCapsDifficultyAndSpreadsPillars() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        var focusPillars: [Pillar] = []
        for day in 0..<3 {
            let user = coldStartUser(level: .beginner, sessionsLogged: day)
            let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)
            for prescription in workout.blocks.flatMap(\.exercises) {
                XCTAssertLessThanOrEqual(
                    prescription.exercise.difficulty, 2,
                    "cold-start day \(day) prescribed \(prescription.exercise.id) above the difficulty-2 cap"
                )
            }
            focusPillars.append(try XCTUnwrap(workout.focusPillar))
        }
        XCTAssertGreaterThan(Set(focusPillars).count, 1, "three cold-start days must span different pillars")
    }

    /// A warmed-up user (cold-start retired) is unaffected by Step 0: even a lingering contract in the
    /// policy is a no-op, so the session matches the plain US-E03 engine exactly.
    func testWarmedUpUserIsUnaffectedByColdStart() async throws {
        let library = try await library()
        let logs = someHistory()
        let warm = coldStartUser(level: .intermediate, sessionsLogged: 6, active: false)
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        for minutes in [8, 20, 50] {
            let withContract = assemble(minutes: minutes, user: warm, library: library, logs: logs, policy: policy)
            let withoutContract = assemble(minutes: minutes, user: warm, library: library, logs: logs, policy: .default)
            XCTAssertEqual(
                structuralSignature(withContract), structuralSignature(withoutContract),
                "\(minutes) min: a retired cold-start user must run exactly the US-E03 pipeline"
            )
        }
    }

    /// Cold-start assembly is deterministic run to run, including on a forced single-focus primal day.
    func testColdStartAssemblyIsDeterministic() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)
        let user = coldStartUser(level: .beginner, sessionsLogged: 2) // rotates onto a primal day
        let signature = structuralSignature(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy))
        XCTAssertEqual(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy).focusPillar, .primal)
        for _ in 0..<10 {
            let next = structuralSignature(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy))
            XCTAssertEqual(next, signature, "cold-start assembly is not deterministic")
        }
    }

    /// When a First-Week Contrast day rotates onto primal but the primal block cannot be built (an
    /// `ankle` injury contraindicates the whole `locomotion` pattern, so no eligible primal movement
    /// survives), the `.single(.primal)` plan degrades to a strength/mobility block. `focusPillar` must
    /// report the pillar the session actually delivers, not the aspirational `.primal` from the plan.
    func testColdStartPrimalDegradationReportsTheActualPillar() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)
        // Beginner, no desk bias, no openingBias -> rotation starts at strength; sessionsLogged 2 lands
        // on the primal slot. The ankle injury then strips every locomotion movement from the pool.
        let user = coldStartUser(level: .beginner, sessionsLogged: 2, injuries: ["ankle"])

        // Guard: the plan really does rotate onto primal here (so this exercises the degradation path).
        XCTAssertEqual(
            ColdStartOverride.contrastPillar(user: user, available: Pillar.allCases), .primal,
            "sessionsLogged 2 must rotate onto the primal slot for this test to mean anything"
        )

        let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)

        let focus = try XCTUnwrap(workout.focusPillar, "a single-focus day must still report a focus pillar")
        XCTAssertNotEqual(focus, .primal, "a degraded primal day must not falsely advertise a primal focus")

        // The reported focus is the single training block the session actually built.
        let trainingBlocks = workout.blocks.filter { $0.category != .warmup && $0.category != .cooldown }
        XCTAssertEqual(trainingBlocks.count, 1, "a single-focus session has exactly one training block")
        XCTAssertEqual(
            SessionAssembly.pillar(of: trainingBlocks[0].category), focus,
            "focusPillar must equal the actually-built training block's pillar"
        )
        XCTAssertFalse(
            trainingBlocks[0].exercises.contains { $0.exercise.movementPattern == .locomotion },
            "the ankle injury leaves no locomotion movement in the degraded block"
        )
    }

    // MARK: - Determinism (content, not ids)

    func testAssemblyIsDeterministic() async throws {
        let library = try await library()
        let user = user()
        let logs = someHistory()
        let first = assemble(minutes: 20, user: user, library: library, logs: logs)
        let signature = structuralSignature(first)
        for _ in 0..<20 {
            let next = assemble(minutes: 20, user: user, library: library, logs: logs)
            XCTAssertEqual(structuralSignature(next), signature, "assembly is not deterministic")
        }
    }

    /// A run-to-run-stable description of a workout's content (the ids vary by design, so this
    /// captures structure, ordering, and targets while ignoring `UUID`s).
    private func structuralSignature(_ workout: Workout) -> String {
        workout.blocks.map { block in
            let items = block.exercises.map { p in
                "\(p.exercise.id):\(p.sets):\(p.reps.map(String.init) ?? "-"):\(p.durationSeconds.map(String.init) ?? "-"):\(p.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }.joined(separator: "|")
    }

    // MARK: - PRD validation test (intermediate user, some history, 20 minutes)

    func testPRDValidationTwentyMinuteSession() async throws {
        let library = try await library()
        let user = user(level: .intermediate)

        let start = DispatchTime.now()
        let workout = assemble(minutes: 20, user: user, library: library, logs: someHistory())
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        XCTAssertEqual(workout.blocks.first?.category, .warmup, "opens with a warm-up")
        XCTAssertEqual(workout.blocks.last?.category, .cooldown, "closes with a cooldown")

        let planned = SessionAssembly.plannedSeconds(of: workout)
        XCTAssertGreaterThanOrEqual(planned, 19 * 60, "20-min session should total at least 19 min")
        XCTAssertLessThanOrEqual(planned, 21 * 60, "20-min session should total at most 21 min")
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }
}
