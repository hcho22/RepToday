import XCTest
@testable import RepToday

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

    /// US-001 validation case: a fresh (no-history) desk worker - the originally-reported
    /// all-mobility failure profile - gets a **strength**-led single-focus session at 5 and 10
    /// minutes. Each opens with a mobility warm-up and then trains strength; no mobility *training*
    /// block appears (mobility survives only as the warm-up at these lengths).
    func testShortSingleFocusLeadsStrengthForFreshDeskWorker() async throws {
        let library = try await library()
        for minutes in [5, 10] {
            let workout = assemble(minutes: minutes, user: user(sitsLong: true), library: library, logs: [])
            XCTAssertEqual(
                workout.focusPillar, .strength,
                "\(minutes) min single-focus must lead strength (US-001)"
            )
            // Opens with a mobility warm-up.
            let first = try XCTUnwrap(workout.blocks.first, "\(minutes) min produced no blocks")
            XCTAssertEqual(first.category, .warmup, "\(minutes) min must open with a warm-up")
            XCTAssertTrue(
                first.exercises.allSatisfy { $0.exercise.pillar == .mobility },
                "\(minutes) min warm-up is mobility movements"
            )
            // A strength training block is present.
            XCTAssertTrue(
                workout.blocks.contains { $0.category == .strength },
                "\(minutes) min must contain a strength training block"
            )
            // No mobility *training* block: mobility appears only in the warm-up.
            XCTAssertFalse(
                workout.blocks.contains { $0.category == .mobility },
                "\(minutes) min must not contain a mobility training block"
            )
            let nonWarmupExercises = workout.blocks
                .filter { $0.category != .warmup && $0.category != .cooldown }
                .flatMap(\.exercises)
            XCTAssertFalse(nonWarmupExercises.isEmpty, "\(minutes) min must have training exercises")
            XCTAssertFalse(
                nonWarmupExercises.contains { $0.exercise.pillar == .mobility },
                "\(minutes) min: no mobility movement outside the warm-up"
            )
        }
    }

    // MARK: - Warm-up is beefier and scales with session length

    /// The opening warm-up is seeded at the length-scaled count (`warmupExerciseCount`), every one a
    /// distinct one-set mobility movement. This pins the "more fully loosened up before the Strength
    /// block" behavior: a real session opens with 1-4 warm-up movements, not the single stretch the
    /// old fit-dependent seeding usually produced.
    func testWarmUpIsSeededAtTheLengthScaledCount() async throws {
        let library = try await library()
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            let expected = SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes)
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            let warmup = try XCTUnwrap(workout.blocks.first, "\(minutes) min produced no blocks")
            XCTAssertEqual(warmup.category, .warmup)
            XCTAssertEqual(
                warmup.exercises.count, expected,
                "\(minutes) min warm-up should carry \(expected) movements"
            )
            // Every warm-up movement is a distinct one-set stretch (bookend one-set rule).
            XCTAssertTrue(warmup.exercises.allSatisfy { $0.sets == 1 }, "\(minutes) min: warm-up is one set each")
            XCTAssertEqual(
                Set(warmup.exercises.map { $0.exercise.id }).count, warmup.exercises.count,
                "\(minutes) min: warm-up movements are distinct"
            )
            XCTAssertTrue(
                warmup.exercises.allSatisfy { $0.exercise.pillar == .mobility },
                "\(minutes) min: warm-up draws from the mobility pool"
            )
        }
    }

    /// A longer session opens with a warm-up at least as full as a shorter one, and strictly fuller
    /// across the range - the length-scaled thoroughness the objective asks for.
    func testWarmUpGrowsWithSessionLength() async throws {
        let library = try await library()
        func warmupCount(_ minutes: Int) throws -> Int {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: someHistory())
            return try XCTUnwrap(workout.blocks.first { $0.category == .warmup }).exercises.count
        }
        let short = try warmupCount(10)
        let mid = try warmupCount(20)
        let long = try warmupCount(60)
        XCTAssertLessThanOrEqual(short, mid, "a 20 min warm-up is at least as full as a 10 min one")
        XCTAssertLessThan(short, long, "a 60 min session opens with a fuller warm-up than a 10 min one")
        XCTAssertLessThanOrEqual(
            long, SessionAssembly.maxWarmupExercises,
            "the warm-up never exceeds its pool-budget ceiling"
        )
    }

    /// US-003 pins the exact length-scaled band mapping - a lean **1** at ≤10 min so the warm-up does
    /// not crowd out strength in a tiny session, rising to **2 / 3 / 4** across 11-20 / 21-40 / 41-60 -
    /// and the ceiling that caps it. Derived-expectation tests above track whatever the function returns;
    /// this one fails if the band boundaries themselves ever drift.
    func testWarmUpCountBandMappingIsLeanAndLengthScaled() {
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 5), 1)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 10), 1)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 11), 2)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 15), 2)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 20), 2)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 21), 3)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 30), 3)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 40), 3)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 41), 4)
        XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: 60), 4)
        XCTAssertEqual(SessionAssembly.maxWarmupExercises, 4, "the ceiling matches the top band")
    }

    /// The fuller warm-up must not over-drain the shared mobility pool. Since US-M01 the only
    /// mobility-sourced blocks are the warm-up and cooldown bookends (no Movement Practice middle block),
    /// so even the worst case - a long session where the warm-up hits its ceiling and the cooldown fills -
    /// leaves real day-to-day variety headroom, and the cooldown is never starved of its holds.
    func testFullerWarmUpDoesNotStarveThePoolOrCooldown() async throws {
        let library = try await library()
        let mobilityTotal = library.filter { $0.pillar == .mobility }.count
        // Mobility six days stale, strength worked yesterday - the worst case for bookend pool draw.
        let mobilityStale = [
            log([("push_standard", .strength, .push, 12)], daysAgo: 1),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 6),
        ]
        let workout = assemble(minutes: 60, user: user(), library: library, logs: mobilityStale)

        let cooldown = try XCTUnwrap(workout.blocks.first { $0.category == .cooldown }, "60 min must have a cooldown")
        XCTAssertFalse(cooldown.exercises.isEmpty, "the cooldown keeps its holds")

        // Mobility appears only in the warm-up and cooldown bookends - never a mobility training block.
        XCTAssertFalse(
            workout.blocks.contains { $0.category == .mobility },
            "no mobility training block is emitted (US-M01)"
        )

        let mobilityIds = workout.blocks
            .flatMap { $0.exercises }
            .filter { $0.exercise.pillar == .mobility }
            .map { $0.exercise.id }
        XCTAssertEqual(Set(mobilityIds).count, mobilityIds.count, "no mobility movement is reused across bookends")
        XCTAssertLessThanOrEqual(
            Set(mobilityIds).count, mobilityTotal,
            "the bookends cannot draw more movements than the pool holds"
        )
        XCTAssertGreaterThanOrEqual(
            mobilityTotal - Set(mobilityIds).count, 2,
            "the worst-case bookend draw leaves day-to-day variety headroom in the mobility pool"
        )
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

    /// US-002 timing guard: the strength-dominant blend still lands inside ±60s at every blend length,
    /// including the long ones (45, 60) where the lower mobility share leaves the strength/primal set
    /// lever to carry more of the time, for both an active and a sedentary (larger-accessory) profile.
    func testBlendTimingFitHoldsAcrossAllLengthsUnderStrengthDominance() async throws {
        let library = try await library()
        for sitsLong in [false, true] {
            for minutes in [15, 20, 30, 45, 60] {
                let workout = assemble(minutes: minutes, user: user(sitsLong: sitsLong), library: library, logs: [])
                let planned = SessionAssembly.plannedSeconds(of: workout)
                XCTAssertLessThanOrEqual(
                    abs(planned - minutes * 60), SessionAssembly.toleranceSeconds,
                    "sitsLong=\(sitsLong) \(minutes) min planned \(planned)s outside ±60s under US-002"
                )
            }
        }
    }

    /// The ±1 minute promise for the population the per-side work model actually changes: a long-tenured
    /// user whose *holds* have grown well past their defaults.
    ///
    /// The two fit tests above run against `someHistory()`, whose logs sit near the movements' rep
    /// defaults and contain no holds at all - which is precisely the configuration in which the setup /
    /// per-unit split and the per-side doubling are both no-ops, so neither could ever have caught a
    /// per-side slot blowing the budget. This drives every per-side hold in the catalog to the top of its
    /// rail, where `AdaptiveOverload` clamps a per-side hold to `maxHoldSeconds / sidesPerSet` so that
    /// the *set* still costs at most three minutes rather than six.
    func testTimingFitHoldsForCapacityGrownPerSideHolds() async throws {
        let library = try await library()
        let perSideHolds = library.filter { $0.isHold && $0.sidesPerSet > 1 }
        XCTAssertFalse(perSideHolds.isEmpty, "the catalog must carry per-side holds for this to test anything")

        // Worked far above every rail, so the clamp is what decides the target rather than the log.
        let grown = WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: 2),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: .tooEasy,
            exercises: perSideHolds.map { hold in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: hold.id,
                    pillar: hold.pillar,
                    movementPattern: hold.movementPattern,
                    completedSets: Array(
                        repeating: CompletedSet(reps: nil, durationSeconds: 300),
                        count: 3
                    ),
                    skipped: false
                )
            }
        )

        for minutes in durations {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: [grown])

            for item in workout.blocks.flatMap(\.exercises) where item.exercise.sidesPerSet > 1 {
                guard let seconds = item.durationSeconds else { continue }
                XCTAssertLessThanOrEqual(
                    seconds * item.exercise.sidesPerSet,
                    AdaptiveOverload.maxHoldSeconds,
                    "\(item.exercise.id) prescribes \(seconds)s per side, so the set costs "
                        + "\(seconds * item.exercise.sidesPerSet)s - past the rail it is supposed to obey"
                )
            }

            let planned = SessionAssembly.plannedSeconds(of: workout)
            XCTAssertLessThanOrEqual(
                abs(planned - minutes * 60),
                SessionAssembly.toleranceSeconds,
                "\(minutes) min with grown per-side holds planned \(planned)s outside ±60s"
            )
        }
    }

    // MARK: - No mobility middle block; freed minutes go to strength (US-M01)

    /// US-M01 core: the Movement Practice mobility *training* block is no longer emitted at any length or
    /// shape. This runs every blend length (15-60) against a strongly mobility-stale history - the exact
    /// configuration in which the old engine produced (and padded) a Movement Practice block - and pins
    /// that no `.mobility` block appears between the warm-up and cooldown. Mobility survives only as the
    /// bookends. (Single-focus 5-10 is covered by `testShortSingleFocusLeadsStrengthForFreshDeskWorker`.)
    func testNoMobilityMiddleBlockAtAnyBlendLength() async throws {
        let library = try await library()
        // Mobility six days stale, strength worked yesterday: the configuration that used to force the
        // largest Movement Practice block.
        let mobilityStale = [
            log([("push_standard", .strength, .push, 12)], daysAgo: 1),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 6),
        ]
        for minutes in [15, 20, 30, 45, 60] {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: mobilityStale)
            XCTAssertFalse(
                workout.blocks.contains { $0.category == .mobility },
                "\(minutes) min must not emit a mobility training block (US-M01)"
            )
            // The middle (everything but the bookends) trains only strength/primal - no mobility movement.
            let middle = workout.blocks
                .filter { $0.category != .warmup && $0.category != .cooldown }
                .flatMap(\.exercises)
            XCTAssertFalse(
                middle.contains { $0.exercise.pillar == .mobility },
                "\(minutes) min: no mobility movement appears outside the bookends"
            )
        }
    }

    /// US-M01 decision 3: the minutes the Movement Practice block used to hold are reallocated to
    /// **strength**, not to bookend stretching. On the same mobility-stale history, the strength training
    /// time is strictly larger than the (now bookend-only) mobility time at every blend length - and the
    /// session still lands within ±60s, so the freed budget genuinely went into strength sets rather than
    /// being dropped.
    func testFreedMinutesGoToStrengthNotStretching() async throws {
        let library = try await library()
        let mobilityStale = [
            log([("push_standard", .strength, .push, 12)], daysAgo: 1),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 6),
        ]
        for minutes in [15, 20, 30, 45, 60] {
            let workout = assemble(minutes: minutes, user: user(), library: library, logs: mobilityStale)

            let strengthSeconds = workout.blocks
                .filter { $0.category == .strength }
                .reduce(0) { $0 + plannedSeconds($1) }
            let mobilitySeconds = workout.blocks
                .filter { $0.category == .warmup || $0.category == .cooldown }
                .reduce(0) { $0 + plannedSeconds($1) }
            XCTAssertGreaterThan(
                strengthSeconds, mobilitySeconds,
                "\(minutes) min: strength time must dominate the bookend mobility time (freed minutes -> strength)"
            )

            let planned = SessionAssembly.plannedSeconds(of: workout)
            XCTAssertLessThanOrEqual(
                abs(planned - minutes * 60), SessionAssembly.toleranceSeconds,
                "\(minutes) min planned \(planned)s outside ±60s of \(minutes * 60)s"
            )
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

    // MARK: - Blend is a strength session wrapped in bookends (US-002/US-M01)

    /// Planned wall-clock of a single materialized block (`Σ sets × workPerSet + (sets - 1) × rest`),
    /// measured with the engine's own work model, used to compare how much session time each block owns.
    private func plannedSeconds(_ block: WorkoutBlock) -> Int {
        block.exercises.reduce(0) { sum, p in
            sum + p.sets * SessionAssembly.workSecondsPerSet(of: p) + max(0, p.sets - 1) * p.restSeconds
        }
    }

    /// US-002/US-M01: a blend's training middle is a single strength block regardless of staleness -
    /// there is no mobility training block to compare against, whether mobility is the stalest pillar or
    /// the freshest. The old "size the blocks by whichever pillar is staler" behavior, and the mobility
    /// accessory it sized, are both gone.
    func testBlendTrainingMiddleIsStrengthOnlyRegardlessOfStaleness() async throws {
        let library = try await library()

        // Mobility never worked, strength worked yesterday: under the old engine this made mobility lead.
        let mobilityStaleLogs = [
            log([
                ("push_standard", .strength, .push, 12),
                ("squat_bodyweight", .strength, .squat, 15),
            ], daysAgo: 1)
        ]
        let mobilityStale = assemble(minutes: 20, user: user(), library: library, logs: mobilityStaleLogs)
        XCTAssertNil(mobilityStale.blocks.first { $0.category == .mobility }, "no mobility training block, even when mobility is stalest")
        XCTAssertNotNil(mobilityStale.blocks.first { $0.category == .strength }, "the training middle is a strength block")

        // Strength never worked, mobility worked yesterday: still a strength-only middle.
        let strengthStaleLogs = [log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 1)]
        let strengthStale = assemble(minutes: 20, user: user(), library: library, logs: strengthStaleLogs)
        XCTAssertNil(strengthStale.blocks.first { $0.category == .mobility }, "no mobility training block on a strength-stale blend either")
        XCTAssertNotNil(strengthStale.blocks.first { $0.category == .strength }, "the training middle is a strength block")
    }

    /// The US-M01 validation test: for a no-history profile at 20, 30, and 45 minutes, list the blocks
    /// and confirm no mobility *training* block appears between the warm-up and cooldown, then sum the
    /// training-block seconds by pillar and confirm the strength share is higher than the archived
    /// accessory model's ~0.75-0.80 (the freed mobility minutes went to strength, not to stretching).
    /// 20/30 are blendLight/blendFull (strength folds primal in, so strength is ~100% of training); 45 is
    /// an extended blend (a dedicated primal minority block), so strength alone still clears the old
    /// headline share while strength keeps the lead over primal.
    func testTrainingTimeIsStrengthHeavierThanAccessoryModelAtValidationLengths() async throws {
        let library = try await library()
        for minutes in [20, 30, 45] {
            let workout = assemble(minutes: minutes, user: user(sitsLong: false), library: library, logs: [])
            let training = workout.blocks.filter { $0.category != .warmup && $0.category != .cooldown }

            // No mobility training block at any of these lengths (US-M01).
            XCTAssertFalse(
                training.contains { $0.category == .mobility },
                "\(minutes) min must not carry a mobility training block"
            )

            let strengthSeconds = training
                .filter { $0.category == .strength }
                .reduce(0) { $0 + plannedSeconds($1) }
            let primalSeconds = training
                .filter { $0.category == .primal }
                .reduce(0) { $0 + plannedSeconds($1) }
            let totalTraining = training.reduce(0) { $0 + plannedSeconds($1) }
            XCTAssertGreaterThan(totalTraining, 0, "\(minutes) min produced no training time")

            let strengthShare = Double(strengthSeconds) / Double(totalTraining)
            // Higher than the archived accessory model's ~0.75-0.80 headline strength share: with the
            // mobility middle block gone, strength alone clears 0.80 at every validation length.
            XCTAssertGreaterThan(
                strengthShare, 0.80,
                "\(minutes) min strength training share \(strengthShare) is not above the archived ~0.75-0.80 accessory model"
            )
            // Strength always leads any dedicated primal block.
            XCTAssertGreaterThan(
                strengthSeconds, primalSeconds,
                "\(minutes) min: strength must lead any dedicated primal block"
            )
        }
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

        // The primal block joins strength rather than replacing it - and there is no mobility training
        // block at all (US-M01): the extended session is Warm-Up -> Strength -> Primal -> Cooldown.
        XCTAssertTrue(workout.blocks.contains { $0.category == .strength }, "strength block still present")
        XCTAssertFalse(workout.blocks.contains { $0.category == .mobility }, "no mobility training block (US-M01)")

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

    /// Every cold-start single-focus day leads strength (US-004), so the first week builds strength
    /// rather than spreading across pillars - even for a desk worker whose bias is mobility.
    func testConsecutiveColdStartDaysAllLeadStrength() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        for day in 0..<4 {
            let user = coldStartUser(level: .beginner, sessionsLogged: day, sitsLong: true)
            let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)
            let focus = try XCTUnwrap(workout.focusPillar, "a single-focus day must have a focus pillar")
            XCTAssertEqual(focus, .strength, "cold-start day \(day) must lead strength")
        }
    }

    /// The `why.openingBias` no longer steers the cold-start lead: a mobility-biased user still leads
    /// strength on every cold-start day (US-004 overrides the lead regardless of the opening bias).
    func testColdStartLeadsStrengthDespiteMobilityOpeningBias() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        for day in 0..<2 {
            let user = coldStartUser(level: .beginner, sessionsLogged: day, openingBias: .mobility)
            XCTAssertEqual(
                assemble(minutes: 8, user: user, library: library, logs: [], policy: policy).focusPillar,
                .strength, "day \(day): a mobility opening bias does not unseat the cold-start strength lead"
            )
        }
    }

    /// The PRD validation (US-004): a beginner's three First-Week sessions all lead strength and never
    /// exceed the difficulty cap - the lead reverses to strength while the gentleness rail holds.
    func testColdStartValidationCapsDifficultyAndLeadsStrength() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)

        for day in 0..<3 {
            let user = coldStartUser(level: .beginner, sessionsLogged: day)
            let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)
            for prescription in workout.blocks.flatMap(\.exercises) {
                XCTAssertLessThanOrEqual(
                    prescription.exercise.difficulty, 2,
                    "cold-start day \(day) prescribed \(prescription.exercise.id) above the difficulty-2 cap"
                )
            }
            XCTAssertEqual(try XCTUnwrap(workout.focusPillar), .strength, "cold-start day \(day) must lead strength")
        }
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

    /// Cold-start assembly is deterministic run to run, on the forced strength-led single-focus day.
    func testColdStartAssemblyIsDeterministic() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)
        let user = coldStartUser(level: .beginner, sessionsLogged: 2) // US-004: every cold-start day leads strength
        let signature = structuralSignature(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy))
        XCTAssertEqual(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy).focusPillar, .strength)
        for _ in 0..<10 {
            let next = structuralSignature(assemble(minutes: 8, user: user, library: library, logs: [], policy: policy))
            XCTAssertEqual(next, signature, "cold-start assembly is not deterministic")
        }
    }

    /// US-004: an injured beginner's cold-start day leads **strength**, not the primal day the retired
    /// First-Week Contrast rotation used to force at `sessionsLogged 2`. The single training block is a
    /// strength block, and the `ankle` injury (which contraindicates the whole `locomotion` pattern)
    /// leaves the strength lead untouched - strength never draws from locomotion.
    func testColdStartInjuredBeginnerLeadsStrength() async throws {
        let library = try await library()
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)
        // Beginner, no desk bias, sessionsLogged 2 - the day the old rotation landed on primal. Under
        // US-004 it leads strength instead; the ankle injury does not touch that.
        let user = coldStartUser(level: .beginner, sessionsLogged: 2, injuries: ["ankle"])

        let workout = assemble(minutes: 8, user: user, library: library, logs: [], policy: policy)

        let focus = try XCTUnwrap(workout.focusPillar, "a single-focus day must report a focus pillar")
        XCTAssertEqual(focus, .strength, "a cold-start day leads strength (US-004)")

        // The reported focus is the single training block the session actually built.
        let trainingBlocks = workout.blocks.filter { $0.category != .warmup && $0.category != .cooldown }
        XCTAssertEqual(trainingBlocks.count, 1, "a single-focus session has exactly one training block")
        XCTAssertEqual(
            SessionAssembly.pillar(of: trainingBlocks[0].category), focus,
            "focusPillar must equal the actually-built training block's pillar"
        )
        XCTAssertFalse(
            trainingBlocks[0].exercises.contains { $0.exercise.movementPattern == .locomotion },
            "a strength lead never draws from the locomotion pattern"
        )
    }

    // MARK: - Return override and Re-entry Ramp (US-E06)

    /// A strong history that, without a Return, advances push onto push_diamond (difficulty 3). `shift`
    /// ages every session uniformly: `shift == 0` leaves the most recent session 1 day ago (a present
    /// user, no Return), while a larger shift pushes the whole history back so the last session crosses
    /// the Return threshold - the *relative* staleness ranking (and so the pattern selection and
    /// advancement) is preserved, isolating the Return override as the only behavioral change.
    private func advancingHistory(shift: Int) -> [WorkoutLog] {
        [
            log([
                ("squat_bodyweight", .strength, .squat, 15),
                ("hinge_glute_bridge", .strength, .hinge, 15),
                ("core_bird_dog", .strength, .core, 12),
                ("pull_superman", .strength, .pull, 12),
                ("mobility_cat_cow", .mobility, .mobility, 10),
                ("primal_bear_crawl", .primal, .locomotion, 10),
            ], daysAgo: 1 + shift),
            log([("push_standard", .strength, .push, 12)], daysAgo: 10 + shift, difficulty: .justRight),
        ]
    }

    /// A Return caps the eligible difficulty at the gentle end, so a strong pre-gap history that would
    /// otherwise advance onto a hard tier can't make the first session back feel punishing - the Return
    /// is measurably easier than the pre-gap norm.
    func testReturnCapsDifficultyBelowThePreGapTier() async throws {
        let library = try await library()

        // Baseline (present user, most recent session 1 day ago): push advances onto push_diamond (3).
        let baseline = assemble(minutes: 20, user: user(), library: library, logs: advancingHistory(shift: 0))
        let baselineMax = baseline.blocks.flatMap(\.exercises).map(\.exercise.difficulty).max() ?? 0
        XCTAssertGreaterThanOrEqual(baselineMax, 3, "without a Return an advancing history reaches difficulty 3 (guards the test)")

        // The same history aged so the last session is 10 days ago -> a Return, capped at the gentle end.
        let returnLogs = advancingHistory(shift: 9)
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: returnLogs, asOf: asOf, calendar: calendar), "a 10-day gap is a Return")

        let returned = assemble(minutes: 20, user: user(), library: library, logs: returnLogs)
        XCTAssertTrue(returned.wasReturn, "the engine stamps the Return decision on the Workout")
        XCTAssertFalse(baseline.wasReturn, "a present user's session is not flagged as a Return")
        XCTAssertTrue(
            returned.blocks.flatMap(\.exercises).allSatisfy { $0.exercise.difficulty <= ReturnOverride.returnMaxDifficulty },
            "a Return caps every movement at or below returnMaxDifficulty"
        )
        XCTAssertFalse(
            returned.blocks.flatMap(\.exercises).contains { $0.exercise.id == "push_diamond" },
            "the Return never reaches the over-cap advancement"
        )
        let returnedMax = returned.blocks.flatMap(\.exercises).map(\.exercise.difficulty).max() ?? 0
        XCTAssertLessThan(returnedMax, baselineMax, "the Return is easier than the pre-gap norm")
    }

    /// A Return leads with strength (US-005), kept gentle by the difficulty cap and volume floor rather
    /// than the pillar. The lead is structural (US-M01: every session builds a leading strength block),
    /// so the Return and the steady state agree - a Return is just a strength session served gentle.
    func testReturnLeadsWithStrength() async throws {
        let library = try await library()
        // Mobility worked longest ago, strength more recently but still past the Return threshold.
        let logs = [
            log([("squat_bodyweight", .strength, .squat, 15)], daysAgo: 8),
            log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 15),
        ]
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: logs, asOf: asOf, calendar: calendar), "an 8-day gap is a Return")

        let workout = assemble(minutes: 8, user: user(), library: library, logs: logs)
        XCTAssertEqual(workout.focusPillar, .strength, "a Return serves strength, gentle via the cap and floor")
        // Mobility survives only as the warm-up - no mobility training block on a Return.
        XCTAssertFalse(workout.blocks.contains { $0.category == .mobility }, "a Return carries no mobility training block")
    }

    /// The Re-entry Ramp walks Step 6's volume back up over the sessions after a Return: the lead
    /// exercise's rep target climbs from the gentle floor toward normal as `rampSessionsRemaining`
    /// decrements, and the readjustment lands here (never in the Return itself).
    func testReentryRampClimbsRepTargetAcrossSessions() async throws {
        let library = try await library()
        // A present user (most recent session today, so no new Return): squat leads a single-focus
        // strength session, last worked six days ago at capacity 15 (below its 3x20 criteria, so it
        // stays on tier).
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
        XCTAssertFalse(ReturnOverride.isReturn(recentLogs: logs, asOf: asOf, calendar: calendar), "a present user is not returning")

        func squatReps(rampRemaining: Int?) throws -> Int {
            var policy = SessionPolicy.default
            // Pin the variety window to 1 so every run selects squat_bodyweight identically, isolating
            // the reentry ramp as the only mover.
            policy.varietyWindow = 1
            if let rampRemaining { policy.reentry = SessionPolicy.Reentry(rampSessionsRemaining: rampRemaining) }
            let workout = assemble(minutes: 10, user: user(), library: library, logs: logs, policy: policy)
            let squat = try XCTUnwrap(
                workout.blocks.flatMap(\.exercises).first { $0.exercise.id == "squat_bodyweight" },
                "squat_bodyweight should lead this single-focus strength session"
            )
            return try XCTUnwrap(squat.reps)
        }

        let ramp3 = try squatReps(rampRemaining: 3) // first session back: most eased (floor)
        let ramp2 = try squatReps(rampRemaining: 2)
        let ramp1 = try squatReps(rampRemaining: 1)
        let normal = try squatReps(rampRemaining: nil) // ramp retired: back to normal

        XCTAssertEqual([ramp3, ramp2, ramp1, normal], [11, 13, 14, 16], "the rep target climbs back over the ramp")
        XCTAssertLessThan(ramp3, normal, "the ramp holds difficulty below normal, then walks it back up")
    }

    /// The Return override is suppressed while cold-start is active: cold-start already serves gentle,
    /// capped, strength-led sessions, so a "Return" during the First-Week window defers to the
    /// cold-start strength lead. Both now lead strength (US-004/US-005), so the guard is that the
    /// session is a cold-start session, not a Return.
    func testReturnSuppressedDuringColdStart() async throws {
        let library = try await library()
        // A cold-start user (day 0 leads strength under US-004) whose lone prior session was 10 days
        // ago - the raw gap would read as a Return.
        let coldUser = coldStartUser(level: .beginner, sessionsLogged: 0, active: true)
        let policy = coldStartPolicy(forceContrastSpread: true, cappedMaxDifficulty: 2)
        let logs = [log([("mobility_cat_cow", .mobility, .mobility, 10)], daysAgo: 10)]
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: logs, asOf: asOf, calendar: calendar), "the raw gap is a Return")

        let workout = assemble(minutes: 8, user: coldUser, library: library, logs: logs, policy: policy)
        XCTAssertEqual(
            workout.focusPillar, .strength,
            "cold start owns the first sessions: its strength lead applies, not the Return path"
        )
        XCTAssertFalse(workout.wasReturn, "a cold-start session is not flagged as a Return (the two are mutually exclusive)")
    }

    /// A Return session is deterministic run to run, like every other engine path.
    func testReturnAssemblyIsDeterministic() async throws {
        let library = try await library()
        let logs = advancingHistory(shift: 9)
        let signature = structuralSignature(assemble(minutes: 20, user: user(), library: library, logs: logs))
        for _ in 0..<10 {
            let next = structuralSignature(assemble(minutes: 20, user: user(), library: library, logs: logs))
            XCTAssertEqual(next, signature, "Return assembly is not deterministic")
        }
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
