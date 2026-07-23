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
    private func bandedPool(user: User, policy: SessionPolicy, library: [Exercise]) -> [Exercise] {
        ColdStartOverride.startBandedPool(
            ColdStartOverride.cappedPool(
                ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
                user: user,
                sessionPolicy: policy
            ),
            user: user,
            sessionPolicy: policy
        )
    }

    // MARK: - The seed per fitness level

    func testStartSeedPerFitnessLevel() {
        typealias Contract = SessionPolicy.ColdStartContract

        XCTAssertEqual(Contract.startingDifficultyFloor(for: .beginner), 1)
        XCTAssertEqual(Contract.startingDifficultyFloor(for: .intermediate), 3)
        XCTAssertEqual(Contract.startingDifficultyFloor(for: .advanced), 4)

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

    /// The floor never exceeds the cap, so the band `[floor, cap]` is always well-formed.
    func testFloorNeverExceedsTheCap() {
        typealias Contract = SessionPolicy.ColdStartContract
        for level in FitnessLevel.allCases {
            XCTAssertLessThanOrEqual(
                Contract.startingDifficultyFloor(for: level),
                Contract.cappedMaxDifficulty(for: level),
                "\(level)'s Start Seed floor must sit inside its capped band"
            )
        }
    }

    /// The contract's neutral values are the engine's own defaults, so a neutral seed is a true no-op.
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
        XCTAssertEqual(ColdStartOverride.startBandedPool(capped, user: user, sessionPolicy: policy), capped)
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
            sessionPolicy: policy
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
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced)
            ),
            pool,
            "a warmed-up user is never floored"
        )
        XCTAssertEqual(
            ColdStartOverride.startBandedPool(
                pool,
                user: freshUser(level: .advanced),
                sessionPolicy: .default
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
