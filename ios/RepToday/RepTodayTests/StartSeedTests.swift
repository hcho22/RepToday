import XCTest
@testable import RepToday

/// Tests the fitness-level **Start Seed** (US-O02): the cold-start contract now carries a difficulty
/// *floor* and a volume seed alongside the existing cap, so an active user's first sessions are matched
/// to their self-reported fitness level instead of opening at the library's absolute beginner tier.
///
/// The seed has three halves, covered here in order:
/// - the pure mapping and its backward-compatible persistence (`SessionPolicy.ColdStartContract`),
/// - the pool band the engine applies in Step 0 (`ColdStartOverride.startBandedPool`), which floors only
///   the strength/primal training pool and never empties a movement pattern, and
/// - the no-history volume (`AdaptiveOverload.target`), which scales only the very first prescription of
///   a movement and leaves every capacity-derived target alone.
///
/// The safety net for a dishonest self-report is the Asymmetric Ramp (US-E05), asserted here to still
/// back off fast, and the whole thing is validated end-to-end over the real bundled library.
final class StartSeedTests: XCTestCase {

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

    /// A fresh, freshly-onboarded user at the given fitness level: cold-start active, no history, no
    /// `why` bias and not desk-bound, so the First-Week Contrast rotation opens on strength.
    private func freshUser(level: FitnessLevel) -> User {
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
                sitsLong: false,
                injuries: [],
                typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 0,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            ),
            coldStart: .fresh
        )
    }

    private func exercise(
        id: String,
        pillar: Pillar = .strength,
        pattern: MovementPattern = .push,
        difficulty: Int = 2,
        isHold: Bool = false,
        defaultReps: Int? = 10,
        defaultDurationSeconds: Int? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: pattern,
            category: pillar == .mobility ? .mobility : .strength,
            difficulty: difficulty,
            phase: .discipline,
            equipment: [],
            isHold: isHold,
            defaultReps: defaultReps,
            defaultDurationSeconds: defaultDurationSeconds,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "chain_\(id)",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x15 clean reps",
            apartmentFriendly: true
        )
    }

    /// A session `daysAgo` that worked `id` with the given per-set reps and an optional rating.
    private func repsLog(
        id: String,
        reps: [Int],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: difficulty,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
                    skipped: false
                )
            ]
        )
    }

    /// The pool the engine hands Steps 1-6 for a cold-start user: eligible, capped, then Start-Seed
    /// banded - exactly the composition `SessionAssembly.planBlocks` performs.
    private func bandedPool(
        user: User,
        policy: SessionPolicy,
        library: [Exercise],
        recentLogs: [WorkoutLog] = []
    ) -> [Exercise] {
        ColdStartOverride.startBandedPool(
            ColdStartOverride.cappedPool(
                ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: recentLogs),
                user: user,
                sessionPolicy: policy
            ),
            user: user,
            sessionPolicy: policy,
            recentLogs: recentLogs
        )
    }

    // MARK: - The seed per fitness level

    func testStartSeedPerFitnessLevel() {
        typealias Contract = SessionPolicy.ColdStartContract

        XCTAssertEqual(Contract.startingDifficultyFloor(for: .beginner), 1)
        XCTAssertEqual(Contract.startingDifficultyFloor(for: .intermediate), 2)
        XCTAssertEqual(Contract.startingDifficultyFloor(for: .advanced), 3)

        XCTAssertEqual(Contract.startingRepMultiplier(for: .beginner), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Contract.startingRepMultiplier(for: .intermediate), 1.15, accuracy: 0.0001)
        XCTAssertEqual(Contract.startingRepMultiplier(for: .advanced), 1.30, accuracy: 0.0001)

        XCTAssertEqual(Contract.startingSets(for: .beginner), 3)
        XCTAssertEqual(Contract.startingSets(for: .intermediate), 3)
        XCTAssertEqual(Contract.startingSets(for: .advanced), 4)
    }

    /// A beginner's seed is exactly neutral, so the beginner experience is unchanged by US-O02.
    func testBeginnerSeedIsNeutral() {
        typealias Contract = SessionPolicy.ColdStartContract
        let contract = Contract.seeded(for: .beginner)

        XCTAssertEqual(contract.startingDifficultyFloor, Contract.neutralStartingDifficultyFloor)
        XCTAssertEqual(contract.startingRepMultiplier, Contract.neutralStartingRepMultiplier)
        XCTAssertEqual(contract.startingSets, Contract.neutralStartingSets)
    }

    /// The onboarding-seeded contract carries the level's whole Start Seed alongside the US-G01 cap.
    func testSeededContractCarriesTheStartSeed() {
        typealias Contract = SessionPolicy.ColdStartContract
        for level in FitnessLevel.allCases {
            let contract = Contract.seeded(for: level)
            XCTAssertEqual(contract.cappedMaxDifficulty, Contract.cappedMaxDifficulty(for: level))
            XCTAssertEqual(contract.startingDifficultyFloor, Contract.startingDifficultyFloor(for: level))
            XCTAssertEqual(contract.startingRepMultiplier, Contract.startingRepMultiplier(for: level))
            XCTAssertEqual(contract.startingSets, Contract.startingSets(for: level))
        }
    }

    /// The floor never exceeds the cap, so the band `[floor, cap]` is always well-formed - and for an
    /// active level it sits strictly *beneath* the cap, so the band is a real range rather than a
    /// single tier the variety window has nothing to rotate over.
    func testFloorLeavesARealBandBeneathTheCap() {
        typealias Contract = SessionPolicy.ColdStartContract
        for level in FitnessLevel.allCases {
            XCTAssertLessThanOrEqual(
                Contract.startingDifficultyFloor(for: level),
                Contract.cappedMaxDifficulty(for: level),
                "\(level)'s Start Seed floor must sit inside its capped band"
            )
        }
        for level in [FitnessLevel.intermediate, .advanced] {
            XCTAssertLessThan(
                Contract.startingDifficultyFloor(for: level),
                Contract.cappedMaxDifficulty(for: level),
                "\(level)'s band must span more than one tier"
            )
        }
    }

    /// The three levels are genuinely different starting points, not three names for one pool. This is
    /// the regression guard for the floor being tuned against the nominal 1-5 scale instead of the
    /// library a Discipline-Phase user can actually reach (which tops out at difficulty 3, so equal
    /// floors and caps collapsed intermediate and advanced onto the same seven movements).
    func testEachFitnessLevelResolvesToADistinctBandedPool() async throws {
        let library = try await library()

        func trainingIds(_ level: FitnessLevel) -> [String] {
            bandedPool(
                user: freshUser(level: level),
                policy: SessionPolicy.seeded(forFitnessLevel: level),
                library: library
            )
            .filter { $0.pillar == .strength || $0.pillar == .primal }
            .map(\.id)
        }

        let beginner = trainingIds(.beginner)
        let intermediate = trainingIds(.intermediate)
        let advanced = trainingIds(.advanced)

        XCTAssertNotEqual(Set(intermediate), Set(advanced), "intermediate and advanced must differ")
        XCTAssertNotEqual(Set(beginner), Set(intermediate))
        // Harder self-report, tighter pool: each level's band starts above the last one's.
        XCTAssertGreaterThan(advanced.count, 0)
        XCTAssertLessThan(advanced.count, intermediate.count)
    }

    /// Whatever the floor, every movement pattern the capped pool offers survives the band with at
    /// least one movement, so banding can never starve a pattern - or the generation - of options.
    func testEveryBandedPatternSurvivesTheFloor() async throws {
        let library = try await library()

        for level in FitnessLevel.allCases {
            let user = freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            let capped = ColdStartOverride.cappedPool(
                ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
                user: user,
                sessionPolicy: policy
            )
            let banded = bandedPool(user: user, policy: policy, library: library)

            let isTraining: (Exercise) -> Bool = { $0.pillar == .strength || $0.pillar == .primal }
            for pattern in Set(capped.filter(isTraining).map(\.movementPattern)) {
                XCTAssertFalse(
                    banded.filter { isTraining($0) && $0.movementPattern == pattern }.isEmpty,
                    "\(level)'s band starved the \(pattern) pattern"
                )
            }
        }
    }

    /// The contract's neutral values are the engine's own defaults, so a neutral seed is a true no-op.
    /// The engine aliases the contract rather than restating it, so this holds by construction.
    func testNeutralSeedMatchesTheEngineDefaults() {
        XCTAssertEqual(
            SessionPolicy.ColdStartContract.neutralStartingSets,
            AdaptiveOverload.defaultSets,
            "the neutral set seed must be the engine's own default set count"
        )
        XCTAssertEqual(
            SessionPolicy.ColdStartContract.neutralStartingRepMultiplier,
            AdaptiveOverload.neutralStartingRepMultiplier
        )
        XCTAssertEqual(SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor, 1)
        XCTAssertEqual(
            ColdStartOverride.VolumeSeed.neutral,
            ColdStartOverride.VolumeSeed(
                repMultiplier: AdaptiveOverload.neutralStartingRepMultiplier,
                sets: AdaptiveOverload.defaultSets
            )
        )
        XCTAssertEqual(ColdStartOverride.StartSeed.neutral.volume, .neutral)
    }

    // MARK: - Backward-compatible persistence

    /// The memberwise initializer the pre-US-O02 call sites use still compiles and yields a neutral seed.
    func testMemberwiseContractDefaultsToTheNeutralSeed() {
        typealias Contract = SessionPolicy.ColdStartContract
        let contract = Contract(forceContrastSpread: true, cappedMaxDifficulty: 2)

        XCTAssertEqual(contract.startingDifficultyFloor, Contract.neutralStartingDifficultyFloor)
        XCTAssertEqual(contract.startingRepMultiplier, Contract.neutralStartingRepMultiplier)
        XCTAssertEqual(contract.startingSets, Contract.neutralStartingSets)
    }

    /// A contract persisted before US-O02 still decodes, defaulting to the neutral seed rather than
    /// failing and losing the user's in-force policy.
    func testLegacyContractDecodesToTheNeutralSeed() throws {
        typealias Contract = SessionPolicy.ColdStartContract
        let legacy = Data(#"{"forceContrastSpread":true,"cappedMaxDifficulty":3}"#.utf8)

        let decoded = try JSONDecoder().decode(Contract.self, from: legacy)

        XCTAssertTrue(decoded.forceContrastSpread)
        XCTAssertEqual(decoded.cappedMaxDifficulty, 3)
        XCTAssertEqual(decoded.startingDifficultyFloor, Contract.neutralStartingDifficultyFloor)
        XCTAssertEqual(decoded.startingRepMultiplier, Contract.neutralStartingRepMultiplier)
        XCTAssertEqual(decoded.startingSets, Contract.neutralStartingSets)
        XCTAssertEqual(decoded, Contract(forceContrastSpread: true, cappedMaxDifficulty: 3))
    }

    /// A whole policy persisted before US-O02 - contract nested inside - still decodes intact.
    func testLegacyPolicyDecodesWithTheNeutralSeed() throws {
        let legacy = Data(
            """
            {
              "version": 4,
              "updatedAt": 0,
              "updatedBy": "deterministic",
              "progressionRate": 1.15,
              "pillarWeighting": ["strength", 1.0, "mobility", 1.0, "primal", 1.0],
              "varietyWindow": 3,
              "coldStartContract": {"forceContrastSpread": true, "cappedMaxDifficulty": 4}
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(SessionPolicy.self, from: legacy)

        XCTAssertEqual(decoded.version, 4)
        XCTAssertEqual(decoded.coldStartContract?.cappedMaxDifficulty, 4)
        XCTAssertEqual(
            decoded.coldStartContract?.startingDifficultyFloor,
            SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        )
        XCTAssertEqual(decoded.coldStartContract?.startingSets, SessionPolicy.ColdStartContract.neutralStartingSets)
    }

    /// A seeded contract round-trips losslessly, so the seed survives relaunch and CloudKit sync.
    func testSeededContractRoundTrips() throws {
        for level in FitnessLevel.allCases {
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            let decoded = try JSONDecoder().decode(
                SessionPolicy.self,
                from: JSONEncoder().encode(policy)
            )
            XCTAssertEqual(decoded, policy, "\(level)'s seeded policy must round-trip identically")
        }
    }

    // MARK: - The difficulty floor: pool banding

    /// An active user's strength and primal pool is banded to `[floor, cap]`, so Step 5's
    /// lowest-eligible selection starts at the band entry rather than the chain's entry tier.
    func testBandedPoolFloorsTheStrengthAndPrimalPool() async throws {
        let library = try await library()

        for level in [FitnessLevel.intermediate, .advanced] {
            let user = freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            let banded = bandedPool(user: user, policy: policy, library: library)
            let training = banded.filter { $0.pillar == .strength || $0.pillar == .primal }

            XCTAssertFalse(training.isEmpty, "\(level) must keep a strength/primal pool")
            // Every surviving movement is at the hardest tier its pattern offers inside the cap, so a
            // gentler tier can never be selected for a no-history user.
            for pattern in Set(training.map(\.movementPattern)) {
                let inPattern = training.filter { $0.movementPattern == pattern }
                let cappedInPattern = ColdStartOverride.cappedPool(
                    ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
                    user: user,
                    sessionPolicy: policy
                ).filter { $0.movementPattern == pattern && ($0.pillar == .strength || $0.pillar == .primal) }
                let expectedFloor = min(
                    policy.coldStartContract!.startingDifficultyFloor,
                    cappedInPattern.map(\.difficulty).max()!
                )
                for exercise in inPattern {
                    XCTAssertGreaterThanOrEqual(
                        exercise.difficulty, expectedFloor,
                        "\(level) kept \(exercise.id) below the \(pattern) band entry \(expectedFloor)"
                    )
                }
            }
        }
    }

    /// A beginner's floor is neutral, so their pool is byte-for-byte the capped pool.
    func testBandedPoolIsUnchangedForABeginner() async throws {
        let library = try await library()
        let user = freshUser(level: .beginner)
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        let capped = ColdStartOverride.cappedPool(
            ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
            user: user,
            sessionPolicy: policy
        )
        XCTAssertEqual(
            ColdStartOverride.startBandedPool(capped, user: user, sessionPolicy: policy, recentLogs: []),
            capped
        )
    }

    /// The floor is a training-load lever, so mobility - the warm-up, Movement Practice, and cooldown
    /// pool - is never banded: gating there is identical at every fitness level.
    func testBandedPoolNeverFloorsMobility() async throws {
        let library = try await library()

        let mobilityIds: (FitnessLevel) -> [String] = { level in
            let user = self.freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            return self.bandedPool(user: user, policy: policy, library: library)
                .filter { $0.pillar == .mobility }
                .map(\.id)
        }

        XCTAssertFalse(mobilityIds(.advanced).isEmpty)
        XCTAssertEqual(mobilityIds(.advanced), mobilityIds(.beginner))
        XCTAssertEqual(mobilityIds(.advanced), mobilityIds(.intermediate))
    }

    /// The band never empties a movement pattern: when the library offers nothing as hard as the floor,
    /// the floor is clamped down to that pattern's hardest movement rather than starving the pattern.
    func testBandNeverEmptiesAPattern() {
        let pool = [
            exercise(id: "push_easy", pattern: .push, difficulty: 1),
            exercise(id: "push_mid", pattern: .push, difficulty: 2),
            exercise(id: "squat_easy", pattern: .squat, difficulty: 1),
            exercise(id: "squat_hard", pattern: .squat, difficulty: 4),
        ]
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(
            forceContrastSpread: false,
            cappedMaxDifficulty: 4,
            startingDifficultyFloor: 4
        )

        let banded = ColdStartOverride.startBandedPool(
            pool,
            user: freshUser(level: .advanced),
            sessionPolicy: policy,
            recentLogs: []
        )

        // Push offers nothing at difficulty 4, so it keeps its own hardest (2) instead of vanishing.
        XCTAssertEqual(banded.filter { $0.movementPattern == .push }.map(\.id), ["push_mid"])
        // Squat does offer the floor, so only the floor survives.
        XCTAssertEqual(banded.filter { $0.movementPattern == .squat }.map(\.id), ["squat_hard"])
        XCTAssertFalse(banded.isEmpty)
    }

    /// Banding preserves the pool's order, so downstream selection stays deterministic.
    func testBandedPoolPreservesOrder() async throws {
        let library = try await library()
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)

        let banded = bandedPool(user: user, policy: policy, library: library)
        let bandedIds = Set(banded.map(\.id))
        let expected = library.filter { bandedIds.contains($0.id) }.map(\.id)

        XCTAssertEqual(banded.map(\.id), expected)
        XCTAssertEqual(banded, bandedPool(user: user, policy: policy, library: library))
    }

    /// Step 0's band retires with cold-start, so a warmed-up user's pool is untouched.
    func testBandedPoolIsNoOpOnceColdStartRetires() {
        let pool = [
            exercise(id: "push_easy", pattern: .push, difficulty: 1),
            exercise(id: "push_hard", pattern: .push, difficulty: 3),
        ]
        var warm = freshUser(level: .advanced)
        warm.coldStart = User.ColdStart(sessionsLogged: 6, active: false)

        XCTAssertEqual(
            ColdStartOverride.startBandedPool(
                pool,
                user: warm,
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced),
                recentLogs: []
            ),
            pool,
            "a warmed-up user is never floored"
        )
        XCTAssertEqual(
            ColdStartOverride.startBandedPool(
                pool,
                user: freshUser(level: .advanced),
                sessionPolicy: .default,
                recentLogs: []
            ),
            pool,
            "no contract means no band"
        )
    }

    // MARK: - The volume seed: no-history targets

    func testNoHistoryTargetScalesRepsAndSetsByTheSeed() {
        let target = AdaptiveOverload.target(
            for: exercise(id: "ex", defaultReps: 10),
            recentLogs: [],
            startingRepMultiplier: 1.30,
            startingSets: 4
        )
        XCTAssertEqual(target.reps, 13, "10 default reps x1.30 rounds to 13")
        XCTAssertEqual(target.sets, 4)
    }

    func testNoHistoryHoldTargetScalesByTheSeed() {
        let target = AdaptiveOverload.target(
            for: exercise(
                id: "hold", isHold: true, defaultReps: nil, defaultDurationSeconds: 20
            ),
            recentLogs: [],
            startingRepMultiplier: 1.15,
            startingSets: 3
        )
        XCTAssertEqual(target.durationSeconds, 23, "20 default seconds x1.15 rounds to 23")
        XCTAssertNil(target.reps)
        XCTAssertEqual(target.sets, 3)
    }

    /// The neutral seed reproduces the pre-US-O02 default target exactly.
    func testNeutralSeedReproducesTheDefaultTarget() {
        let movement = exercise(id: "ex", defaultReps: 12)
        let unseeded = AdaptiveOverload.target(for: movement, recentLogs: [])
        let neutral = AdaptiveOverload.target(
            for: movement,
            recentLogs: [],
            startingRepMultiplier: AdaptiveOverload.neutralStartingRepMultiplier,
            startingSets: AdaptiveOverload.defaultSets
        )
        XCTAssertEqual(neutral, unseeded)
        XCTAssertEqual(unseeded.reps, 12)
        XCTAssertEqual(unseeded.sets, AdaptiveOverload.defaultSets)
    }

    /// A runaway seed can never produce an absurd prescription: the existing rep/hold/set rails hold.
    func testSeededTargetIsClampedToTheRails() {
        let reps = AdaptiveOverload.target(
            for: exercise(id: "ex", defaultReps: 40),
            recentLogs: [],
            startingRepMultiplier: 10,
            startingSets: 9
        )
        XCTAssertEqual(reps.reps, AdaptiveOverload.maxReps)
        XCTAssertEqual(reps.sets, AdaptiveOverload.maxSets)

        let hold = AdaptiveOverload.target(
            for: exercise(id: "hold", isHold: true, defaultReps: nil, defaultDurationSeconds: 90),
            recentLogs: [],
            startingRepMultiplier: 10,
            startingSets: 9
        )
        XCTAssertEqual(hold.durationSeconds, AdaptiveOverload.maxHoldSeconds)
        XCTAssertEqual(hold.sets, AdaptiveOverload.maxSets)
    }

    /// The seed is a *start*: once the user has logged the movement, Step 6 is capacity-relative and
    /// the seed no longer applies at all.
    func testSeedNeverTouchesACapacityDerivedTarget() {
        let movement = exercise(id: "ex", defaultReps: 10)
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 2, difficulty: .justRight)]

        let seeded = AdaptiveOverload.target(
            for: movement,
            recentLogs: logs,
            startingRepMultiplier: 1.30,
            startingSets: 4
        )
        XCTAssertEqual(seeded, AdaptiveOverload.target(for: movement, recentLogs: logs))
        XCTAssertEqual(seeded.sets, 3, "the set count tracks what the user sustained, not the seed")
    }

    // MARK: - The safety net: the Asymmetric Ramp still backs off fast

    /// An over-reported fitness level is corrected downward within one cycle: after a seeded first
    /// session rated `too_hard`, the next target drops below demonstrated capacity - and drops by more
    /// than a `too_easy` would climb, so the seed can never trap a user at an unsustainable volume.
    func testOverReportedLevelSelfCorrectsWithinOneCycle() {
        let movement = exercise(id: "ex", defaultReps: 10)

        // The seeded advanced first prescription, which the user then works and rates.
        let seeded = AdaptiveOverload.target(
            for: movement,
            recentLogs: [],
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced),
            startingSets: SessionPolicy.ColdStartContract.startingSets(for: .advanced)
        )
        let worked = Array(repeating: seeded.reps!, count: seeded.sets)

        let eased = AdaptiveOverload.target(
            for: movement,
            recentLogs: [repsLog(id: "ex", reps: worked, daysAgo: 1, difficulty: .tooHard)],
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced),
            startingSets: SessionPolicy.ColdStartContract.startingSets(for: .advanced)
        )
        let intensified = AdaptiveOverload.target(
            for: movement,
            recentLogs: [repsLog(id: "ex", reps: worked, daysAgo: 1, difficulty: .tooEasy)],
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced),
            startingSets: SessionPolicy.ColdStartContract.startingSets(for: .advanced)
        )

        XCTAssertLessThan(eased.reps!, seeded.reps!, "a too-hard seeded session eases within one cycle")
        XCTAssertGreaterThan(
            seeded.reps! - eased.reps!, intensified.reps! - seeded.reps!,
            "the ramp still backs off faster than it climbs"
        )

        // A skip of the seeded movement is the same eager down-signal.
        let afterSkip = AdaptiveOverload.target(
            for: movement,
            recentLogs: [
                repsLog(id: "ex", reps: worked, daysAgo: 3, difficulty: .justRight),
                skipLog(id: "ex", daysAgo: 1),
            ]
        )
        XCTAssertLessThan(afterSkip.reps!, seeded.reps!, "a bailed-on seeded session also eases")
    }

    /// The correction reaches the **tier**, not just the reps: one `too_hard` session steps the Start
    /// Seed's difficulty floor down, so the next session's banded pool opens on an easier movement
    /// rather than holding the user at an unwinnable tier for the whole cold-start window.
    func testTooHardRatingEasesTheStartSeedTier() {
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let seeded = policy.coldStartContract!

        let untouched = ColdStartOverride.startSeed(user: user, sessionPolicy: policy, recentLogs: [])
        XCTAssertEqual(untouched.difficultyFloor, seeded.startingDifficultyFloor)

        let afterTooHard = ColdStartOverride.startSeed(
            user: user,
            sessionPolicy: policy,
            recentLogs: [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 1, difficulty: .tooHard)]
        )
        XCTAssertEqual(
            afterTooHard.difficultyFloor, seeded.startingDifficultyFloor - 1,
            "a too-hard session must step the tier down, not just the reps"
        )

        // A bailed-on strength movement is the same eager down-signal the Asymmetric Ramp reacts to.
        let afterSkip = ColdStartOverride.startSeed(
            user: user,
            sessionPolicy: policy,
            recentLogs: [skipLog(id: "push_diamond", daysAgo: 1)]
        )
        XCTAssertEqual(afterSkip.difficultyFloor, seeded.startingDifficultyFloor - 1)
    }

    /// The tier and the volume ease together. Otherwise de-escalating onto an easier movement - which
    /// the user has never logged - would simply re-apply the full volume seed to it.
    func testDownSignalEasesTheVolumeSeedToo() {
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let seeded = policy.coldStartContract!

        let eased = ColdStartOverride.volumeSeed(
            user: user,
            sessionPolicy: policy,
            recentLogs: [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 1, difficulty: .tooHard)]
        )
        XCTAssertLessThan(eased.repMultiplier, seeded.startingRepMultiplier)
        XCTAssertEqual(eased.sets, seeded.startingSets - 1)
    }

    /// Easing stops at neutral: repeated down-signals can never push the seed *below* the un-seeded
    /// default, and a beginner - whose seed is already neutral - is never touched at all.
    func testEasingNeverOvershootsNeutral() {
        typealias Contract = SessionPolicy.ColdStartContract
        let logs = (1...6).map { repsLog(id: "push_diamond", reps: [8], daysAgo: $0, difficulty: .tooHard) }

        let advanced = ColdStartOverride.startSeed(
            user: freshUser(level: .advanced),
            sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced),
            recentLogs: logs
        )
        XCTAssertEqual(advanced, .neutral, "a hammered seed bottoms out at neutral, never below it")

        let beginner = ColdStartOverride.startSeed(
            user: freshUser(level: .beginner),
            sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .beginner),
            recentLogs: logs
        )
        XCTAssertEqual(beginner, .neutral, "a beginner's already-neutral seed is never moved")
    }

    /// End-to-end: an over-reported advanced user who rates their first session `too_hard` is served a
    /// strictly *easier lead movement* next time, not the same movement with fewer reps.
    func testOverReportedLevelIsServedAnEasierTierNextSession() async throws {
        let library = try await library()
        var user = freshUser(level: .advanced)
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)

        func strengthLead(rating: PerceivedDifficulty) throws -> PlannedItem {
            let blocks = SessionAssembly.planBlocks(
                requestedMinutes: 30,
                user: user,
                library: library,
                recentLogs: [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 1, difficulty: rating)],
                sessionPolicy: policy,
                asOf: asOf,
                calendar: calendar
            )
            return try XCTUnwrap(blocks.first { $0.category == .strength }?.items.first)
        }

        let held = try strengthLead(rating: .justRight)
        let eased = try strengthLead(rating: .tooHard)

        XCTAssertLessThan(
            eased.exercise.difficulty, held.exercise.difficulty,
            "a too-hard first session must de-escalate the tier (got \(eased.exercise.id) vs "
                + "\(held.exercise.id))"
        )
    }

    // MARK: - The seed survives the seam it is handed across

    /// A mid-session swap keeps the session's Start Seed: the substitute's no-history target is sized
    /// by the same seed the rest of the lineup was, instead of silently reverting to the neutral x1.0.
    func testSwapKeepsTheSessionsStartSeed() async throws {
        let library = try await library()
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let original = try XCTUnwrap(library.first { $0.id == "push_diamond" })
        let seed = ColdStartOverride.volumeSeed(user: user, sessionPolicy: policy, recentLogs: [])

        let slot = PrescribedExercise(
            id: UUID(),
            exercise: original,
            sets: seed.sets,
            reps: AdaptiveOverload.target(
                for: original,
                recentLogs: [],
                startingRepMultiplier: seed.repMultiplier,
                startingSets: seed.sets
            ).reps,
            durationSeconds: nil,
            restSeconds: SessionAssembly.strengthRestSeconds
        )
        let session = Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .singleFocus,
            focusPillar: .strength,
            requestedMinutes: 15,
            wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [slot])]
        )

        let seeded = ExerciseSwap.swap(
            slot, in: session, user: user, library: library, recentLogs: [], sessionPolicy: policy
        )
        guard case .substituted(let substitute) = seeded else {
            return XCTFail("the advanced push slot must have an in-band substitute")
        }
        let defaultReps = try XCTUnwrap(substitute.exercise.defaultReps)
        XCTAssertEqual(
            substitute.reps,
            Int((Double(defaultReps) * seed.repMultiplier).rounded()),
            "the substitute must carry the session's Start Seed, not the neutral seed"
        )

        // Without the policy the same swap falls back to the neutral seed - the exact divergence this
        // seam exists to close.
        let unseeded = ExerciseSwap.swap(slot, in: session, user: user, library: library, recentLogs: [])
        guard case .substituted(let neutral) = unseeded else {
            return XCTFail("the unseeded swap must still substitute")
        }
        XCTAssertEqual(neutral.exercise.id, substitute.exercise.id, "the same movement is chosen either way")
        XCTAssertEqual(neutral.reps, defaultReps, "the neutral seed opens at the movement's own default")
        XCTAssertGreaterThan(try XCTUnwrap(substitute.reps), try XCTUnwrap(neutral.reps))
    }

    // MARK: - The seeded target is reflected in the planned wall-clock

    /// A seeded set really does take longer than a default-sized one, and the engine now sizes it that
    /// way - so the ±1 minute timing-fit promise is measured against the session the user will do.
    func testPlannedTimeAccountsForTheSeededPerSetTarget() {
        let movement = exercise(id: "ex", defaultReps: 10) // 40s per set at its own default

        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: movement, reps: 10, durationSeconds: nil),
            movement.estimatedTimePerSetSeconds,
            "a default-sized set is the movement's own estimate, unchanged"
        )
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: movement, reps: 13, durationSeconds: nil),
            52,
            "13 reps of a 10-rep movement is 1.3x the work"
        )
        // A movement with no default to scale against falls back to the flat estimate.
        let unscalable = exercise(id: "unscalable", defaultReps: nil)
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: unscalable, reps: 20, durationSeconds: nil),
            unscalable.estimatedTimePerSetSeconds
        )
    }

    /// The whole seeded session lands inside the timing tolerance when measured with the rep-aware
    /// clock - the fit and the measurement agree, so the promise is not honest-by-omission.
    func testSeededSessionStillLandsWithinTheTimingTolerance() async throws {
        let library = try await library()

        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            for level in FitnessLevel.allCases {
                let workout = SessionAssembly.assemble(
                    requestedMinutes: minutes,
                    user: freshUser(level: level),
                    library: library,
                    recentLogs: [],
                    sessionPolicy: SessionPolicy.seeded(forFitnessLevel: level),
                    asOf: asOf,
                    calendar: calendar
                )
                let drift = abs(SessionAssembly.plannedSeconds(of: workout) - minutes * 60)
                XCTAssertLessThanOrEqual(
                    drift, SessionAssembly.toleranceSeconds,
                    "\(level)'s \(minutes)-minute seeded session drifted \(drift)s"
                )
            }
        }
    }

    private func skipLog(id: String, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: [],
                    skipped: true
                )
            ]
        )
    }

    // MARK: - End-to-end (US-O02 validation)

    /// PRD validation: two freshly onboarded no-history users, one advanced and one beginner, generate
    /// their first session. The advanced user's strength block leads with a harder tier at more volume;
    /// the beginner's is unchanged; warm-up and mobility are identical for both.
    ///
    /// Asserted against `planBlocks` (the pre-timing-fit skeleton) so the seeded set count is read as
    /// Step 6 prescribed it, before the timing fit trades sets for wall-clock.
    func testAdvancedFirstSessionStartsHarderThanABeginners() async throws {
        let library = try await library()

        func plan(_ level: FitnessLevel) -> [PlannedBlock] {
            SessionAssembly.planBlocks(
                requestedMinutes: 30,
                user: freshUser(level: level),
                library: library,
                recentLogs: [],
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: level),
                asOf: asOf,
                calendar: calendar
            )
        }
        func strengthLead(_ blocks: [PlannedBlock]) throws -> PlannedItem {
            try XCTUnwrap(blocks.first { $0.category == .strength }?.items.first)
        }

        let beginnerBlocks = plan(.beginner)
        let advancedBlocks = plan(.advanced)
        let beginner = try strengthLead(beginnerBlocks)
        let advanced = try strengthLead(advancedBlocks)

        // Tier: the advanced user starts above the chain's entry tier, the beginner at it.
        XCTAssertEqual(beginner.exercise.difficulty, 1, "a beginner still starts at the entry tier")
        XCTAssertGreaterThan(
            advanced.exercise.difficulty, beginner.exercise.difficulty,
            "an advanced user's first strength movement must be a harder tier than a beginner's "
                + "(got \(advanced.exercise.id) vs \(beginner.exercise.id))"
        )

        // Volume: 4 sets at ~x1.3 the movement's own default reps.
        XCTAssertEqual(advanced.sets, SessionPolicy.ColdStartContract.startingSets(for: .advanced))
        let defaultReps = try XCTUnwrap(advanced.exercise.defaultReps)
        XCTAssertEqual(
            advanced.reps,
            Int((Double(defaultReps) * 1.30).rounded()),
            "the advanced first prescription carries the x1.30 volume seed"
        )

        // The beginner is untouched: their own default reps over the default set count.
        XCTAssertEqual(beginner.reps, beginner.exercise.defaultReps)
        XCTAssertEqual(beginner.sets, AdaptiveOverload.defaultSets)

        // Warm-up and mobility gating is identical for both.
        for category in [ExerciseCategory.warmup, .mobility, .cooldown] {
            let beginnerBlock = beginnerBlocks.first { $0.category == category }
            let advancedBlock = advancedBlocks.first { $0.category == category }
            XCTAssertEqual(beginnerBlock?.items, advancedBlock?.items, "\(category) must not be seeded")
            XCTAssertEqual(beginnerBlock?.reserve, advancedBlock?.reserve, "\(category) must not be seeded")
        }
    }

    /// The band must not create a cliff on the other side of the handoff. An advanced user walks the
    /// whole five-session cold-start window, completing everything the engine prescribes, and then
    /// generates the session *after* cold start retires - the first one with no contract, no cap and
    /// no band. Nothing in that session may be gentler than what they trained on all week.
    ///
    /// The failure this guards is subtle: banding withholds whole progression chains, so those chains
    /// accrue no history; the moment the band lifts their untouched entry tiers are the only movements
    /// the variety window has never seen, and freshness alone would hand an advanced user a
    /// difficulty-1 movement. It takes both halves to hold - a library with in-band tiers in every
    /// chain, and Step 5 refusing to let freshness regress below demonstrated ability.
    func testSessionAfterTheHandoffNeverRegressesBelowTheColdStartTiers() async throws {
        let library = try await library()
        var user = freshUser(level: .advanced)
        var policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        var logs: [WorkoutLog] = []
        var coldStartTiers: [String: Int] = [:] // exercise id -> difficulty, for the failure message

        for session in 0..<ColdStartHandoff.handoffThreshold {
            let workout = SessionAssembly.assemble(
                requestedMinutes: 30,
                user: user,
                library: library,
                recentLogs: logs,
                sessionPolicy: policy,
                asOf: date(daysAgo: 12 - session * 2),
                calendar: calendar
            )
            for prescribed in trainingItems(of: workout) {
                coldStartTiers[prescribed.exercise.id] = prescribed.exercise.difficulty
            }
            logs.append(completedLog(of: workout, on: date(daysAgo: 12 - session * 2)))

            let handoff = ColdStartHandoff.afterCompletedSession(user: user, sessionPolicy: policy)
            user = handoff.user
            policy = handoff.sessionPolicy
        }

        XCTAssertFalse(user.coldStart.active, "cold start must have retired after the fifth session")
        XCTAssertNil(policy.coldStartContract, "the contract must be cleared at the handoff")
        let floor = try XCTUnwrap(coldStartTiers.values.min())
        XCTAssertGreaterThanOrEqual(
            floor,
            SessionPolicy.ColdStartContract.startingDifficultyFloor(for: .advanced),
            "the cold-start week itself must have trained at the seeded floor"
        )

        let afterHandoff = SessionAssembly.assemble(
            requestedMinutes: 30,
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            asOf: asOf,
            calendar: calendar
        )

        let training = trainingItems(of: afterHandoff)
        XCTAssertFalse(training.isEmpty, "the session after the handoff must still train something")
        for prescribed in training {
            XCTAssertGreaterThanOrEqual(
                prescribed.exercise.difficulty, floor,
                "the session after the handoff regressed to \(prescribed.exercise.id) "
                    + "(difficulty \(prescribed.exercise.difficulty)) after a cold-start week trained "
                    + "at \(floor)+: \(coldStartTiers.sorted { $0.key < $1.key })"
            )
        }
    }

    /// The strength and primal (i.e. banded) movements a generated session prescribes.
    private func trainingItems(of workout: Workout) -> [PrescribedExercise] {
        workout.blocks
            .flatMap(\.exercises)
            .filter { $0.exercise.pillar == .strength || $0.exercise.pillar == .primal }
    }

    /// The log of a session the user completed exactly as prescribed, rated `justRight` so the Start
    /// Seed neither eases nor hardens across the simulated week.
    private func completedLog(of workout: Workout, on completedAt: Date) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: workout.id,
            completedAt: completedAt,
            requestedMinutes: workout.requestedMinutes,
            durationMinutes: workout.requestedMinutes,
            shape: workout.shape,
            focusPillar: workout.focusPillar,
            perceivedDifficulty: .justRight,
            exercises: workout.blocks.flatMap(\.exercises).map { prescribed in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: prescribed.exercise.id,
                    pillar: prescribed.exercise.pillar,
                    movementPattern: prescribed.exercise.movementPattern,
                    completedSets: (0..<prescribed.sets).map { _ in
                        CompletedSet(reps: prescribed.reps, durationSeconds: prescribed.durationSeconds)
                    },
                    skipped: false
                )
            }
        )
    }

    /// The whole seeded pipeline stays deterministic - identical inputs, identical session content.
    func testSeededAssemblyIsDeterministic() async throws {
        let library = try await library()
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)

        func signature() -> [String] {
            SessionAssembly.assemble(
                requestedMinutes: 20, user: user, library: library,
                recentLogs: [], sessionPolicy: policy, asOf: asOf, calendar: calendar
            )
            .blocks
            .flatMap(\.exercises)
            .map { "\($0.exercise.id):\($0.sets)x\($0.reps ?? $0.durationSeconds ?? 0)" }
        }

        XCTAssertEqual(signature(), signature())
    }
}
