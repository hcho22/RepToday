import XCTest
@testable import RepToday

/// Tests the fitness-level **Start Seed** (US-O02): the cold-start contract now carries a difficulty
/// *floor* and a volume seed alongside the existing cap, so an active user's first sessions are matched
/// to their self-reported fitness level instead of opening at the library's absolute beginner tier.
///
/// The seed has three halves, covered here in order:
/// - the pure mapping and its backward-compatible persistence (`SessionPolicy.ColdStartContract`),
/// - the pool band the engine applies in Step 0 (`ColdStartOverride.startBandedPool`), which floors only
///   the strength training pool and never empties a movement pattern, and
/// - the opening volume (`AdaptiveOverload.target`): a movement with no history opens at the bottom of
///   the level's earned range, and the seed lifts that first number onto the grid - never to the top of
///   the range - while every number earned from a logged session is left alone. The set count is fixed
///   at four for every station (`RepGrammar.setsPerStation`), so the seed never reaches it.
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
    /// `why` bias and not desk-bound. Every cold-start day leads strength (US-004).
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
            advancementCriteria: "4 clean sets at the top of your rep range",
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
    /// banded - exactly the composition `SessionAssembly.planSession` performs.
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

        // The set seed stays on the persisted contract so stored policies round-trip; no prescription
        // reads it, since every station runs `RepGrammar.setsPerStation` sets.
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
    /// library a Discipline-Phase user can actually reach. The per-pattern breadth that makes each
    /// band a real range is gated separately, in `ExerciseLibraryTests`.
    func testEachFitnessLevelResolvesToADistinctBandedPool() async throws {
        let library = try await library()

        func trainingIds(_ level: FitnessLevel) -> [String] {
            bandedPool(
                user: freshUser(level: level),
                policy: SessionPolicy.seeded(forFitnessLevel: level),
                library: library
            )
            .filter { $0.pillar == .strength }
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

            let isTraining: (Exercise) -> Bool = { $0.pillar == .strength }
            for pattern in Set(capped.filter(isTraining).map(\.movementPattern)) {
                XCTAssertFalse(
                    banded.filter { isTraining($0) && $0.movementPattern == pattern }.isEmpty,
                    "\(level)'s band starved the \(pattern) pattern"
                )
            }
        }
    }

    /// The contract's neutral multiplier is the engine's own, so a neutral seed opens a movement exactly
    /// where an unseeded one does. The engine aliases the contract rather than restating it, so this holds
    /// by construction.
    func testNeutralSeedMatchesTheEngineDefaults() {
        XCTAssertEqual(
            SessionPolicy.ColdStartContract.neutralStartingRepMultiplier,
            AdaptiveOverload.neutralStartingRepMultiplier
        )
        XCTAssertEqual(SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor, 1)
        XCTAssertEqual(ColdStartOverride.VolumeSeed.neutral.repMultiplier, AdaptiveOverload.neutralStartingRepMultiplier)
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

    /// An active user's strength pool is banded to `[floor, cap]`, so Step 5's lowest-eligible selection
    /// starts at the band entry rather than the chain's entry tier.
    func testBandedPoolFloorsTheStrengthPool() async throws {
        let library = try await library()

        for level in [FitnessLevel.intermediate, .advanced] {
            let user = freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            let banded = bandedPool(user: user, policy: policy, library: library)
            let training = banded.filter { $0.pillar == .strength }

            XCTAssertFalse(training.isEmpty, "\(level) must keep a strength pool")
            // Every surviving movement is at the hardest tier its pattern offers inside the cap, so a
            // gentler tier can never be selected for a no-history user.
            for pattern in Set(training.map(\.movementPattern)) {
                let inPattern = training.filter { $0.movementPattern == pattern }
                let cappedInPattern = ColdStartOverride.cappedPool(
                    ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
                    user: user,
                    sessionPolicy: policy
                ).filter { $0.movementPattern == pattern && $0.pillar == .strength }
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

    /// The floor is a training-load lever, so mobility - the warm-up and cooldown bookend pool - is
    /// never banded: the only gate on a level's stretches is the staples rule (`MovementAccess`,
    /// ADR-0007), so the banded pool carries exactly the stretches the level is offered, no fewer.
    func testBandedPoolNeverFloorsMobility() async throws {
        let library = try await library()

        for level in FitnessLevel.allCases {
            let user = self.freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            let banded = self.bandedPool(user: user, policy: policy, library: library)
                .filter { $0.pillar == .mobility }
                .map(\.id)
            let offered = MovementAccess.available(in: library, level: level, phase: .discipline)
                .filter { $0.pillar == .mobility }
                .map(\.id)
            XCTAssertFalse(banded.isEmpty)
            XCTAssertEqual(banded, offered, "\(level): banding must not touch the stretches")
        }
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

    // MARK: - The movements the band withheld

    /// A beginner's floor is neutral, so the band withholds nothing and Step 5 behaves exactly as it
    /// did before the Start Seed existed.
    func testNothingIsWithheldFromABeginner() async throws {
        let library = try await library()
        XCTAssertTrue(
            ColdStartOverride.withheldByStartSeed(
                library: library,
                user: freshUser(level: .beginner),
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .beginner),
                recentLogs: []
            ).isEmpty
        )
    }

    /// The withheld set is exactly the banded movements beneath the live floor - never a mobility
    /// movement, and never a pattern the floor would empty (every strength pattern offers a tier at or
    /// above the advanced floor, so nothing is clamped away).
    func testWithheldSetIsTheBandedMovementsBeneathTheFloor() async throws {
        let library = try await library()
        let withheld = ColdStartOverride.withheldByStartSeed(
            library: library,
            user: freshUser(level: .advanced),
            sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced),
            recentLogs: []
        )
        let expected = Set(
            library
                .filter { $0.pillar == .strength && $0.difficulty < 3 }
                .map(\.id)
        )
        XCTAssertEqual(withheld, expected)
        XCTAssertTrue(
            withheld.allSatisfy { id in library.first { $0.id == id }?.pillar != .mobility },
            "mobility is never banded, so it is never withheld"
        )
    }

    /// A `tooHard` session eases the seed's floor, and the withheld set is resolved from that same
    /// eased seed - so the tiers the seed just reopened stop being withheld in the same move. This is
    /// what makes the de-escalation stick instead of being pulled straight back up.
    func testEasingTheSeedShrinksTheWithheldSet() async throws {
        let library = try await library()
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)

        let held = ColdStartOverride.withheldByStartSeed(
            library: library, user: user, sessionPolicy: policy,
            recentLogs: [repsLog(id: "push_diamond", reps: [8], daysAgo: 1, difficulty: .justRight)]
        )
        let eased = ColdStartOverride.withheldByStartSeed(
            library: library, user: user, sessionPolicy: policy,
            recentLogs: [repsLog(id: "push_diamond", reps: [8], daysAgo: 1, difficulty: .tooHard)]
        )
        XCTAssertTrue(eased.isStrictSubset(of: held), "a down-signal must only ever reopen movements")
        XCTAssertTrue(held.contains("squat_sumo"), "difficulty 2 sits under the advanced floor of 3")
        XCTAssertFalse(eased.contains("squat_sumo"), "easing the floor to 2 reopens the tier")
    }

    /// Once cold start retires the contract is gone, so the band is read from the floor the handoff
    /// recorded - the fact of what ran - rather than re-derived from the never-revised onboarding
    /// self-report.
    func testTheBandPastTheHandoffIsTheRecordedFloor() async throws {
        let library = try await library()
        var warm = freshUser(level: .advanced)
        warm.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold,
            active: false,
            bandFloorAtHandoff: 3
        )

        let withheld = ColdStartOverride.withheldByStartSeed(
            library: library, user: warm, sessionPolicy: .default, recentLogs: []
        )
        XCTAssertTrue(withheld.contains("push_wall"), "difficulty 1 sits under the recorded floor of 3")
        XCTAssertTrue(withheld.contains("squat_sumo"), "difficulty 2 sits under the recorded floor of 3")
        XCTAssertFalse(withheld.contains("push_diamond"), "difficulty 3 is the recorded floor itself")

        // And it is exactly that recorded number, not the level's: a user whose week ran at an eased
        // floor of 2 withholds only the tier beneath 2.
        warm.coldStart.bandFloorAtHandoff = 2
        let eased = ColdStartOverride.withheldByStartSeed(
            library: library, user: warm, sessionPolicy: .default, recentLogs: []
        )
        XCTAssertTrue(eased.contains("push_wall"))
        XCTAssertFalse(eased.contains("squat_sumo"), "the eased floor of 2 keeps difficulty 2 on offer")
    }

    /// The `tooHard` de-escalation has to survive the retirement, not be recomputed away by it. An
    /// advanced user rates their first session too hard, so the rest of the week runs at an eased
    /// floor of 2 and genuinely offers the difficulty-2 tiers - and the session after the handoff must
    /// still treat those tiers as movements the user was offered.
    func testTheEasedFloorSurvivesTheHandoff() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        // The real shape of a cold-start week at the moment the fifth session is recorded: sessions
        // 1-4 already carry the rating their own completion screen collected, and session 5 does not
        // yet - its rating cannot exist until after the log is written.
        let logs = coldStartWeek(ratings: [.tooHard, .justRight, .justRight, .justRight, nil])

        let outcome = ColdStartHandoff.afterCompletedSession(
            user: retiringUser(level: .advanced), sessionPolicy: policy, recentLogs: logs
        )

        XCTAssertFalse(outcome.user.coldStart.active, "the fixture must actually retire the band")
        XCTAssertEqual(
            outcome.user.coldStart.bandFloorAtHandoff, 2,
            "the recorded floor must be the eased one, not the advanced level's aim of 3"
        )
        XCTAssertEqual(
            outcome.user.coldStart.bandAimAtHandoff, 3,
            "the un-eased aim is recorded beside it so a late rating can re-resolve the floor"
        )

        // The reconstruction is now a no-op over `recentLogs`: the eased tier stays on offer even once
        // the cold-start sessions have aged out of the engine's bounded window entirely.
        let withheld = ColdStartOverride.withheldByStartSeed(
            library: library,
            user: outcome.user,
            sessionPolicy: outcome.sessionPolicy,
            recentLogs: []
        )
        XCTAssertFalse(
            withheld.contains("squat_sumo"),
            "the handoff re-raised the tier the too_hard rating eased, got \(withheld.sorted())"
        )
    }

    /// The retiring session's own `tooHard` must count. It is collected on the completion screen, so it
    /// always lands *after* the handoff has already recorded the floor - the strongest signal the user
    /// can send, arriving too late to be seen. `revisedBandFloor` folds it in without re-advancing the
    /// counter, so the band ends up describing the week the user actually had.
    func testALateRatingOnTheRetiringSessionStillEasesTheRecordedFloor() async throws {
        let library = try await library()
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        var logs = coldStartWeek(ratings: [nil, nil, nil, nil, nil])

        let outcome = ColdStartHandoff.afterCompletedSession(
            user: retiringUser(level: .advanced), sessionPolicy: policy, recentLogs: logs
        )
        XCTAssertEqual(outcome.user.coldStart.bandFloorAtHandoff, 3, "nothing rated yet: the full aim")

        // The user now taps "too hard" on the completion screen of that fifth session.
        logs[4].perceivedDifficulty = .tooHard
        let revised = ColdStartHandoff.revisedBandFloor(
            outcome.user,
            coldStartLogs: ColdStartHandoff.coldStartWindowLogs(logs)
        )

        XCTAssertEqual(revised.coldStart.bandFloorAtHandoff, 2, "the late rating eases the recorded tier")
        XCTAssertEqual(
            revised.coldStart.sessionsLogged, outcome.user.coldStart.sessionsLogged,
            "revising a derived fact must never re-advance the cold-start counter"
        )
        XCTAssertFalse(revised.coldStart.active)
        XCTAssertFalse(
            ColdStartOverride.withheldByStartSeed(
                library: library, user: revised, sessionPolicy: outcome.sessionPolicy, recentLogs: []
            ).contains("squat_sumo"),
            "the eased tier must be back on offer for the session after the handoff"
        )

        // Idempotent: the floor is re-resolved from the recorded aim, never stepped from itself, so
        // re-rating (the completion screen lets the user re-tap) converges instead of compounding.
        XCTAssertEqual(
            ColdStartHandoff.revisedBandFloor(
                revised, coldStartLogs: ColdStartHandoff.coldStartWindowLogs(logs)
            ),
            revised
        )
        logs[4].perceivedDifficulty = .justRight
        XCTAssertEqual(
            ColdStartHandoff.revisedBandFloor(
                revised, coldStartLogs: ColdStartHandoff.coldStartWindowLogs(logs)
            ).coldStart.bandFloorAtHandoff,
            3,
            "re-rating away from too_hard re-resolves to the floor that week actually ran at"
        )
    }

    /// A rating on a session long after the handoff is not evidence about a band that retired before
    /// it, so it can neither widen nor narrow the recorded floor.
    func testARatingAfterTheColdStartWeekLeavesTheRecordedBandAlone() {
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        var logs = coldStartWeek(ratings: [nil, nil, nil, nil, nil])
        let outcome = ColdStartHandoff.afterCompletedSession(
            user: retiringUser(level: .advanced), sessionPolicy: policy, recentLogs: logs
        )

        // A sixth session, well past the handoff, rated too hard.
        logs.append(repsLog(id: "push_diamond", reps: [8], daysAgo: 1, difficulty: .tooHard))

        XCTAssertEqual(
            ColdStartHandoff.revisedBandFloor(
                outcome.user, coldStartLogs: ColdStartHandoff.coldStartWindowLogs(logs)
            ),
            outcome.user
        )
    }

    /// A user one session shy of the handoff, with an advanced-level Start Seed contract in play.
    private func retiringUser(level: FitnessLevel) -> User {
        var user = freshUser(level: level)
        user.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold - 1,
            active: true
        )
        return user
    }

    /// A full cold-start week in date order, one log per session, carrying the given ratings.
    private func coldStartWeek(ratings: [PerceivedDifficulty?]) -> [WorkoutLog] {
        ratings.enumerated().map { index, rating in
            repsLog(
                id: "push_diamond",
                reps: [8, 8, 8],
                daysAgo: ratings.count - index,
                difficulty: rating
            )
        }
    }

    /// A band that never ran is never asserted retroactively. `coldStart.active == false` is equally
    /// true *before* a contract exists as after one retires, so the claim rests on the recorded floor
    /// alone - absent it, nothing was ever withheld.
    func testNoBandIsClaimedWhenNoneEverRan() async throws {
        let library = try await library()

        // A record written before US-O02: the persisted contract decodes its Start Seed to the neutral
        // floor, so that user's week ran unbanded and was genuinely offered the gentle tiers.
        var legacy = freshUser(level: .advanced)
        legacy.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold,
            active: false
        )
        XCTAssertTrue(
            ColdStartOverride.withheldByStartSeed(
                library: library, user: legacy, sessionPolicy: .default,
                recentLogs: [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 1)]
            ).isEmpty,
            "a user with no recorded band must withhold nothing, however they self-reported"
        )

        // And a generation against the neutral default policy for an advanced user with no history at
        // all - the `SessionPolicy.default` path - claims nothing either.
        XCTAssertTrue(
            ColdStartOverride.withheldByStartSeed(
                library: library, user: legacy, sessionPolicy: .default, recentLogs: []
            ).isEmpty
        )
    }

    /// A neutral contract records "no band ran" rather than the level's aim, so a legacy policy that
    /// decodes its Start Seed to the neutral floor cannot acquire a band at the handoff.
    func testANeutralContractRecordsNoBand() {
        var contract = SessionPolicy.ColdStartContract.seeded(for: .advanced)
        contract.startingDifficultyFloor =
            SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        var policy = SessionPolicy.default
        policy.coldStartContract = contract

        var user = freshUser(level: .advanced)
        user.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold - 1,
            active: true
        )

        let outcome = ColdStartHandoff.afterCompletedSession(
            user: user, sessionPolicy: policy, recentLogs: []
        )
        XCTAssertEqual(
            outcome.user.coldStart.bandFloorAtHandoff,
            SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        )
    }

    /// Skipping is the product's escape hatch for a movement the user dislikes or has no room for,
    /// not evidence about their ability. Outside cold start it must not move tier selection at all.
    func testARoutineSkipDoesNotChangeTheWithheldSet() async throws {
        let library = try await library()
        var warm = freshUser(level: .advanced)
        warm.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold,
            active: false,
            bandFloorAtHandoff: 3 // a real band, so the comparison below is not vacuously empty
        )

        let completed = [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 1)]
        var skipped = completed
        skipped[0].exercises.append(
            LoggedExercise(
                id: UUID(),
                exerciseId: "squat_cossack",
                pillar: .strength,
                movementPattern: .squat,
                completedSets: [],
                skipped: true
            )
        )

        let unchanged = ColdStartOverride.withheldByStartSeed(
            library: library, user: warm, sessionPolicy: .default, recentLogs: completed
        )
        XCTAssertFalse(unchanged.isEmpty, "the fixture must have a band for the skip to fail to move")
        XCTAssertEqual(
            unchanged,
            ColdStartOverride.withheldByStartSeed(
                library: library, user: warm, sessionPolicy: .default, recentLogs: skipped
            )
        )
    }

    // MARK: - The volume seed: opening numbers

    /// The first number of a movement is the bottom of the earned range lifted by the seed onto the
    /// nearest grid number, at four sets like every station.
    func testNoHistoryTargetScalesRepsByTheSeed() {
        let target = AdaptiveOverload.target(
            for: exercise(id: "ex", defaultReps: 10),
            level: .advanced,
            recentLogs: [],
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced)
        )
        XCTAssertEqual(target.reps, 20, "15 reps x1.30 is 19.5, landing on the nearest grid number, 20")
        XCTAssertEqual(target.earned, 20, "the seeded number is what the user is recorded as having earned")
        XCTAssertEqual(target.sets, RepGrammar.setsPerStation)
    }

    func testNoHistoryHoldTargetScalesByTheSeed() {
        let target = AdaptiveOverload.target(
            for: exercise(id: "hold", isHold: true, defaultReps: nil, defaultDurationSeconds: 30),
            level: .intermediate,
            recentLogs: [],
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .intermediate)
        )
        XCTAssertEqual(target.durationSeconds, 25, "20 seconds x1.15 is 23, landing on the nearest grid number, 25")
        XCTAssertNil(target.reps)
        XCTAssertEqual(target.sets, RepGrammar.setsPerStation)
    }

    /// A beginner's neutral seed opens every movement at the bottom of the range, exactly as an unseeded
    /// generation does, whatever the movement's catalog default.
    func testNeutralSeedReproducesTheUnseededTarget() {
        for defaultReps in [8, 12, 25] {
            let movement = exercise(id: "ex", defaultReps: defaultReps)
            let unseeded = AdaptiveOverload.target(for: movement, level: .beginner, recentLogs: [])
            let neutral = AdaptiveOverload.target(
                for: movement,
                level: .beginner,
                recentLogs: [],
                startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .beginner)
            )
            XCTAssertEqual(neutral, unseeded)
            XCTAssertEqual(unseeded.reps, 15, "default \(defaultReps)")
        }
    }

    /// A runaway seed can never produce an absurd prescription: the first number stops a step under the
    /// top of the level's range, so the seed can never hand out a session that clears the rung.
    func testSeededTargetStopsAStepUnderTheTopOfTheRange() {
        for level in FitnessLevel.allCases {
            for movement in [
                exercise(id: "ex", defaultReps: 40),
                exercise(id: "hold", isHold: true, defaultReps: nil, defaultDurationSeconds: 90),
            ] {
                let top = RepGrammar.earnedRange(for: movement, level: level).upperBound
                let target = AdaptiveOverload.target(for: movement, level: level, recentLogs: [], startingRepMultiplier: 10)
                XCTAssertEqual(target.value, top - RepGrammar.step, "\(movement.id) at \(level)")
                XCTAssertEqual(target.sets, RepGrammar.setsPerStation)
            }
        }
    }

    /// The seed is a *start*: once the user has logged the movement, its Earned Reps come from that
    /// session and the seed no longer applies at all.
    func testSeedNeverTouchesACapacityDerivedTarget() {
        let movement = exercise(id: "ex", defaultReps: 10)
        let logs = [TrainingDayFixtures.log(
            [TrainingDayFixtures.station("ex", pattern: .push, value: 20, earned: 20)],
            completedAt: date(daysAgo: 2)
        )]

        let seeded = AdaptiveOverload.target(
            for: movement,
            level: .advanced,
            recentLogs: logs,
            startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced)
        )
        XCTAssertEqual(seeded, AdaptiveOverload.target(for: movement, level: .advanced, recentLogs: logs))
        XCTAssertEqual(seeded.reps, 25, "one step above the 20 earned, the seed ignored")
    }

    /// The real catalog at the advanced x1.30 seed: rep moves open at 20, per-side moves stay at 5 a side,
    /// and holds open at 25 seconds - each at least a step under the top of its range.
    func testSeededFirstPrescriptionsOverTheRealCatalog() async throws {
        let library = try await library()
        let seed = SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced)
        for (id, expected) in [("push_diamond", 20), ("squat_bodyweight", 20), ("push_archer", 5), ("core_forearm_plank", 25)] {
            let movement = try XCTUnwrap(library.first { $0.id == id })
            let target = AdaptiveOverload.target(for: movement, level: .advanced, recentLogs: [], startingRepMultiplier: seed)
            XCTAssertEqual(target.value, expected, id)
            XCTAssertEqual(target.sets, RepGrammar.setsPerStation, id)
        }
        XCTAssertEqual(try XCTUnwrap(library.first { $0.id == "push_archer" }).isPerSide, true, "the archer's 5 is per side")
    }

    /// No catalog movement's first prescription, at any fitness level's Start Seed, clears its own rung
    /// when performed exactly as prescribed: every move takes more than one session.
    func testNoFirstPrescriptionClearsItsMoveInOneSession() async throws {
        for movement in try await library() {
            for level in FitnessLevel.allCases {
                let target = AdaptiveOverload.target(
                    for: movement,
                    level: level,
                    recentLogs: [],
                    startingRepMultiplier: SessionPolicy.ColdStartContract.startingRepMultiplier(for: level)
                )
                let performed = TrainingDayFixtures.log(
                    [TrainingDayFixtures.station(
                        movement.id,
                        pattern: movement.movementPattern,
                        pillar: movement.pillar,
                        value: target.value,
                        earned: target.earned,
                        sets: target.sets,
                        isHold: movement.isHold
                    )],
                    completedAt: date(daysAgo: 1)
                )
                XCTAssertFalse(RepGrammar.hasCleared(movement, in: [performed], level: level), "\(movement.id) at \(level)")
            }
        }
    }

    // MARK: - The safety net: the Asymmetric Ramp still backs off fast

    /// An over-reported fitness level is corrected downward within one cycle: after a seeded first
    /// session rated `too_hard`, the next number drops a step below the seeded one - by no less than a
    /// `too_easy` would climb - so the seed can never trap a user at an unsustainable volume.
    func testOverReportedLevelSelfCorrectsWithinOneCycle() {
        let movement = exercise(id: "ex", defaultReps: 10)
        let multiplier = SessionPolicy.ColdStartContract.startingRepMultiplier(for: .advanced)

        // The seeded advanced first prescription, which the user then works and rates.
        let seeded = AdaptiveOverload.target(for: movement, level: .advanced, recentLogs: [], startingRepMultiplier: multiplier)
        func worked(_ difficulty: PerceivedDifficulty?, daysAgo: Int = 1) -> WorkoutLog {
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station("ex", pattern: .push, value: seeded.value, earned: seeded.earned)],
                completedAt: date(daysAgo: daysAgo),
                difficulty: difficulty
            )
        }
        func next(_ logs: [WorkoutLog]) -> Int {
            AdaptiveOverload.target(for: movement, level: .advanced, recentLogs: logs, startingRepMultiplier: multiplier).value
        }

        let eased = next([worked(.tooHard)])
        let intensified = next([worked(.tooEasy)])
        XCTAssertLessThan(eased, seeded.value, "a too-hard seeded session eases within one cycle")
        XCTAssertGreaterThanOrEqual(seeded.value - eased, intensified - seeded.value,
                                    "the back-off is never smaller than the climb")

        // A skip of the seeded movement is the same eager down-signal.
        let afterSkip = next([skipLog(id: "ex", daysAgo: 1), worked(.justRight, daysAgo: 3)])
        XCTAssertLessThan(afterSkip, seeded.value, "a bailed-on seeded session also eases")
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

    }

    /// A skip is the product's escape hatch - "not this movement" - and must never be read as a verdict
    /// on the *tier*. It still eases the volume, mirroring the Asymmetric Ramp, but the difficulty floor
    /// is untouched: that floor is the half `ColdStartHandoff` records for the life of the account, so a
    /// preference tap must not permanently erode the band and re-open the post-handoff cliff.
    func testSkipEasesTheVolumeButNeverTheTier() {
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let seeded = policy.coldStartContract!

        let afterSkips = ColdStartOverride.startSeed(
            user: user,
            sessionPolicy: policy,
            recentLogs: [
                skipLog(id: "push_diamond", daysAgo: 2),
                skipLog(id: "squat_cossack", daysAgo: 1),
            ]
        )
        XCTAssertEqual(
            afterSkips.difficultyFloor, seeded.startingDifficultyFloor,
            "two routine skips must leave the tier band exactly where it was"
        )
        XCTAssertLessThan(
            afterSkips.volume.repMultiplier, seeded.startingRepMultiplier,
            "the volume still backs off - the ramp reads a bailed-on set the same way either way"
        )
    }

    /// The tier and the volume ease together on an explicit `too_hard`. Otherwise de-escalating onto an
    /// easier movement - which the user has never logged - would simply re-apply the full volume seed.
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

    /// End-to-end: an over-reported advanced user who rates their first Push Day `too_hard` is served a
    /// strictly *easier* rung on a ladder they have not worked yet, not the same rung with fewer reps -
    /// the eased band opens the ladder's gentler entry.
    func testOverReportedLevelIsServedAnEasierTierNextSession() async throws {
        let library = try await library()
        var user = freshUser(level: .advanced)
        user.coldStart = User.ColdStart(sessionsLogged: 1, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let vertical = Set(library.filter { $0.progressionChainId == "push_vertical" }.map(\.id))

        func verticalRung(rating: PerceivedDifficulty) throws -> Exercise {
            let logs = [repsLog(id: "push_diamond", reps: [20, 20, 20, 20], daysAgo: 1, difficulty: rating)]
            let plan = SessionAssembly.planSession(
                requestedMinutes: 30,
                user: user,
                library: library,
                recentLogs: logs,
                sessionPolicy: policy,
                trainingDay: .push,
                asOf: asOf,
                calendar: calendar
            )
            return try XCTUnwrap(plan.stations.first { $0.role == .main && vertical.contains($0.exercise.id) }).exercise
        }

        let held = try verticalRung(rating: .justRight)
        let eased = try verticalRung(rating: .tooHard)
        XCTAssertEqual(held.id, "push_pike", "the advanced band enters the vertical ladder at difficulty 3")
        XCTAssertLessThan(
            eased.difficulty, held.difficulty,
            "a too-hard first session must de-escalate the tier (got \(eased.id) vs \(held.id))"
        )
    }

    /// The de-escalation reaches a ladder the user *already has history on*: the worked rung's volume
    /// steps back to the bottom of the range first, and a second `too_hard` there steps the ladder down
    /// a rung - and the eased band keeps that easier rung on offer instead of pulling the user back up.
    func testTooHardDeEscalatesEvenInALadderWithDemonstratedHistory() async throws {
        let library = try await library()
        var user = freshUser(level: .advanced)
        user.coldStart = User.ColdStart(sessionsLogged: 2, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let horizontal = Set(library.filter { $0.progressionChainId == "push_horizontal" }.map(\.id))

        func horizontalStation(_ logs: [WorkoutLog]) throws -> PlannedItem {
            let plan = SessionAssembly.planSession(
                requestedMinutes: 30,
                user: user,
                library: library,
                recentLogs: logs,
                sessionPolicy: policy,
                trainingDay: .push,
                asOf: asOf,
                calendar: calendar
            )
            return try XCTUnwrap(plan.stations.first { $0.role == .main && horizontal.contains($0.exercise.id) })
        }
        func session(_ value: Int, _ rating: PerceivedDifficulty, daysAgo: Int) -> WorkoutLog {
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station("push_diamond", pattern: .push, value: value, earned: value)],
                completedAt: date(daysAgo: daysAgo),
                difficulty: rating
            )
        }

        let first = try horizontalStation([])
        XCTAssertEqual(first.exercise.id, "push_diamond", "the advanced band enters the horizontal ladder at difficulty 3")
        XCTAssertEqual(first.value, 20, "15 reps x1.30 lands on 20")

        let afterOne = try horizontalStation([session(20, .tooHard, daysAgo: 3)])
        XCTAssertEqual(afterOne.exercise.id, "push_diamond", "one too-hard above the bottom eases the volume first")
        XCTAssertEqual(afterOne.value, 15)

        let afterTwo = try horizontalStation([session(15, .tooHard, daysAgo: 1), session(20, .tooHard, daysAgo: 3)])
        XCTAssertLessThan(
            afterTwo.exercise.difficulty, first.exercise.difficulty,
            "a too-hard at the bottom must step the ladder down (got \(afterTwo.exercise.id))"
        )
        XCTAssertEqual(afterTwo.value, 15, "the rung stepped down onto opens at the bottom of the range")
    }

    // MARK: - The seed survives the seam it is handed across

    /// A mid-session swap keeps the session's Start Seed: the substitute's opening number is sized by the
    /// same seed the rest of the lineup was, instead of silently reverting to the neutral x1.0. An
    /// advanced user's hollow-hold core station swaps to the forearm plank, whose seed lifts it from 20 to
    /// 25 seconds.
    func testSwapKeepsTheSessionsStartSeed() async throws {
        let library = try await library()
        let user = freshUser(level: .advanced)
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let original = try XCTUnwrap(library.first { $0.id == "core_hollow_hold" })
        let plank = try XCTUnwrap(library.first { $0.id == "core_forearm_plank" })
        let seed = ColdStartOverride.volumeSeed(user: user, sessionPolicy: policy, recentLogs: [])
        let opening = AdaptiveOverload.target(
            for: original,
            level: .advanced,
            recentLogs: [],
            startingRepMultiplier: seed.repMultiplier
        )

        let slot = PrescribedExercise(
            id: UUID(),
            exercise: original,
            sets: opening.sets,
            reps: nil,
            durationSeconds: opening.durationSeconds,
            restSeconds: SessionAssembly.baseRoundRestSeconds,
            role: .core,
            earnedDurationSeconds: opening.earned
        )
        let session = Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .singleFocus,
            focusPillar: .strength,
            requestedMinutes: 15,
            wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Push Day", category: .strength, exercises: [slot])]
        )

        func substitute(_ policy: SessionPolicy) -> PrescribedExercise? {
            let outcome = ExerciseSwap.swap(
                slot, in: session, user: user, library: [original, plank], recentLogs: [], sessionPolicy: policy
            )
            guard case .substituted(let substitute) = outcome else { return nil }
            return substitute
        }

        let seeded = try XCTUnwrap(substitute(policy), "the hollow-hold slot must swap to the forearm plank")
        XCTAssertEqual(seeded.exercise.id, plank.id)
        XCTAssertEqual(seeded.durationSeconds, 25,
                       "the substitute must carry the session's Start Seed: 20 seconds x1.30 lands on 25")
        XCTAssertEqual(seeded.role, .core)
        // Without the policy the same swap falls back to the neutral seed - the exact divergence this
        // seam exists to close.
        let neutral = try XCTUnwrap(substitute(.default), "the unseeded swap must still substitute")
        XCTAssertEqual(neutral.exercise.id, plank.id)
        XCTAssertEqual(neutral.durationSeconds, RepGrammar.earnedRange(for: .hold, level: .advanced).lowerBound,
                       "the neutral seed opens at the bottom of the hold range")
    }

    // MARK: - The seeded target is reflected in the planned wall-clock

    /// A seeded set really does take longer than a default-sized one, and the engine now sizes it that
    /// way - so the ±1 minute timing-fit promise is measured against the session the user will do.
    ///
    /// The extra time is the *work* the extra reps cost, not a proportional scaling of the whole
    /// estimate: a set's fixed setup (get into position, brace, get out again) is paid once whether the
    /// set is 10 reps or 13.
    ///
    /// Every number here is the paced one (US-CC08): the rep branch's authored estimate is scaled by
    /// `workPaceGenerosityFactor` so the seconds the fit budgets are the generous seconds the player's
    /// work window actually gives the user. The *shape* of the model - setup once, cadence per rep - is
    /// what this test pins, so each expectation is written as `paced(...)` of the underlying split rather
    /// than as a bare literal that would say nothing about which half moved.
    func testPlannedTimeAccountsForTheSeededPerSetTarget() {
        let movement = exercise(id: "ex", defaultReps: 10) // 40s per set at its own default
        func paced(_ seconds: Double) -> Int {
            Int((seconds * SessionAssembly.workPaceGenerosityFactor).rounded())
        }

        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: movement, reps: 10, durationSeconds: nil),
            paced(Double(movement.estimatedTimePerSetSeconds)),
            "a default-sized set is the movement's own estimate at the generous runtime pace"
        )
        // The rep branch assumes `setupSecondsPerSet` (10s) of fixed setup and derives the cadence from
        // what this movement itself authors: (40 - 10) / 10 reps = 3.0s a rep. So 3 extra reps costs 9
        // extra authored seconds on top of the same one-off setup, all of it then paced.
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: movement, reps: 13, durationSeconds: nil),
            paced(10 + 3 * 13),
            "13 reps costs the setup once plus 13 reps of work"
        )
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: movement, reps: 5, durationSeconds: nil),
            paced(10 + 3 * 5),
            "a shrunk set still pays the same fixed setup"
        )
        // A movement with no default to scale against falls back to the flat estimate - paced the same
        // way, since it is the same rep-based estimate reached by another route.
        let unscalable = exercise(id: "unscalable", defaultReps: nil)
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: unscalable, reps: 20, durationSeconds: nil),
            paced(Double(unscalable.estimatedTimePerSetSeconds))
        )
    }

    /// The setup/per-unit split reproduces the authored estimate exactly at the movement's own default -
    /// so a default-sized session is priced precisely as the catalog wrote it, at the generous runtime
    /// pace, and only a moved target is re-priced - and the sweep at the end bounds the model from *both*
    /// sides across the whole catalog, because an under-charge accumulates across a session exactly as an
    /// over-charge does.
    ///
    /// Since US-CC08 a **rep-based** movement's authored estimate is scaled by
    /// `workPaceGenerosityFactor` (this is a runtime window, not just a planning proxy), so the sweep
    /// measures each movement against its own *paced* estimate. A **hold** is not split at all: it costs
    /// exactly the seconds the player runs - one leg per side and the "Switch sides" beat between them,
    /// with no setup, since every hold starts itself straight after its get-ready beat (ADR-0010).
    func testWorkPerSetSplitsTheEstimateIntoSetupPlusPerUnitWork() async throws {
        let library = try await library()
        let beat = SessionAssembly.switchSidesSeconds
        let longestHold = RepGrammar.earnedRange(for: .hold, level: .advanced).upperBound
        /// What the model prices a default-sized set at: the authored estimate, paced, for a rep-based
        /// movement; the played seconds for a hold.
        func pricedDefault(_ movement: Exercise, baseline: Int) -> Int {
            movement.isHold
                ? movement.sidesPerSet * baseline + (movement.sidesPerSet - 1) * beat
                : Int((Double(movement.estimatedTimePerSetSeconds) * SessionAssembly.workPaceGenerosityFactor).rounded())
        }

        // A hold costs one second per prescribed second *per side*, plus the beat between the sides: a
        // "30 second" 90/90 is 30s each way and the switch, never the 10s of setup its estimate implies.
        let hip = try XCTUnwrap(library.first { $0.id == "mobility_9090_hip" })
        XCTAssertEqual(hip.sidesPerSet, 2)
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: hip, reps: nil, durationSeconds: 30), 60 + beat)
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: hip, reps: nil, durationSeconds: 40), 80 + beat)
        XCTAssertEqual(
            SessionAssembly.workSecondsPerSet(for: hip, reps: nil, durationSeconds: longestHold),
            2 * longestHold + beat,
            "the longest hold the engine serves costs both sides of the hold and the switch between them"
        )

        // The case that exposed the per-side-blind split: "3x30s hold per side" grown to 40s is 80s of
        // holding plus the switch. Charging it 65s under-counted a single slot by 60s over three sets.
        let sidePlank = try XCTUnwrap(library.first { $0.id == "core_side_plank" })
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: sidePlank, reps: nil, durationSeconds: 20), 40 + beat)
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: sidePlank, reps: nil, durationSeconds: 40), 80 + beat)

        // A single-sided hold costs the hold alone, whatever setup its authored estimate implies.
        let tuckLSit = try XCTUnwrap(library.first { $0.id == "core_tuck_l_sit" })
        XCTAssertEqual(tuckLSit.sidesPerSet, 1)
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: tuckLSit, reps: nil, durationSeconds: 12), 12)
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: tuckLSit, reps: nil, durationSeconds: 20), 20)

        // A rep-based movement takes the fixed setup and derives its cadence from its own estimate:
        // 40s over 15 reps leaves 30s of work, so 2s a rep, and 30 reps costs 10 + 60 - each then paced
        // to the generous runtime window (US-CC08).
        func paced(_ seconds: Double) -> Int {
            Int((seconds * SessionAssembly.workPaceGenerosityFactor).rounded())
        }
        let glutes = try XCTUnwrap(library.first { $0.id == "hinge_glute_bridge" })
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: glutes, reps: 15, durationSeconds: nil), paced(40))
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: glutes, reps: 30, durationSeconds: nil), paced(10 + 2 * 30))

        // A slow per-side rep movement keeps its authored cadence rather than being flattened to a
        // generic one: "3x8 clean reps per side" on a 5-rep / 50s authoring costs 8s a prescribed rep,
        // so 8 reps is 74 authored seconds - not the 59s a fixed 3s-per-rep cadence charged - and the
        // pacing factor scales that shape rather than replacing it.
        let archer = try XCTUnwrap(library.first { $0.id == "push_archer" })
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: archer, reps: 5, durationSeconds: nil), paced(50))
        XCTAssertEqual(SessionAssembly.workSecondsPerSet(for: archer, reps: 8, durationSeconds: nil), paced(10 + 8 * 8))

        // Every rep-based movement in the catalog reproduces its own authored estimate at its own
        // default, and every hold its played seconds, and the implied setup is bounded on both sides:
        // never negative (which would over-charge a grown set as strict proportionality did), and - for
        // a rep-based movement, whose setup is *assumed* rather than observed - never more than
        // `maxSetupShareOfEstimate` of the estimate, which is how a grown set gets under-charged. A
        // hold carries no setup, so it is bounded instead by the physical floor below.
        for movement in library {
            guard let baseline = movement.isHold ? movement.defaultDurationSeconds : movement.defaultReps,
                  baseline > 0 else { continue }
            let estimate = movement.estimatedTimePerSetSeconds
            func work(at prescribed: Int) -> Int {
                SessionAssembly.workSecondsPerSet(
                    for: movement,
                    reps: movement.isHold ? nil : prescribed,
                    durationSeconds: movement.isHold ? prescribed : nil
                )
            }

            let priced = pricedDefault(movement, baseline: baseline)
            XCTAssertEqual(
                work(at: baseline), priced,
                "\(movement.id) must price its own default set at its authored estimate, paced, or its played seconds"
            )
            // work(2×baseline) = setup + 2 × perUnit × baseline = 2 × estimate - setup, so the model's
            // own implied setup is readable straight off the doubled set. Reading it against the *paced*
            // default keeps the bound about the setup/cadence split rather than about the factor, which
            // scales both halves alike; the ±2 absorbs the two roundings it is now read through.
            let doubled = work(at: baseline * 2)
            let impliedSetup = 2 * priced - doubled
            XCTAssertGreaterThanOrEqual(
                impliedSetup, -2,
                "\(movement.id) must not charge a grown set more than strict proportionality"
            )
            if !movement.isHold {
                XCTAssertLessThanOrEqual(
                    Double(impliedSetup),
                    Double(priced) * SessionAssembly.maxSetupShareOfEstimate + 2,
                    "\(movement.id) treats too much of its estimate as fixed, so a grown set is under-charged"
                )
                XCTAssertGreaterThan(
                    work(at: baseline), estimate,
                    "\(movement.id) must price a rep-based set generously above its typical-case authored estimate (US-CC08)"
                )
            } else {
                XCTAssertEqual(
                    work(at: baseline),
                    movement.sidesPerSet * baseline + (movement.sidesPerSet - 1) * beat,
                    "\(movement.id) is a hold: its per-second cost is definitional, so the pacing factor leaves it alone"
                )
            }
            XCTAssertGreaterThan(
                doubled, work(at: baseline),
                "\(movement.id) must still charge more for a bigger set"
            )
            // A hold has a hard physical floor: a set can never cost less than the hold itself, on
            // every side it is held. This is the assertion the per-side-blind split failed.
            if movement.isHold {
                for prescribed in [baseline / 2, baseline, baseline * 2, longestHold]
                where prescribed > 0 {
                    XCTAssertGreaterThanOrEqual(
                        work(at: prescribed), movement.sidesPerSet * prescribed,
                        "\(movement.id) at \(prescribed)s must cost at least the hold itself, on both sides"
                    )
                }
            }
        }
    }

    /// The whole seeded session lands inside the timing tolerance when measured with the rep-aware
    /// clock, or - when even the top of the range and the longest rests cannot fill it - runs short as
    /// an honest shortfall with every lever spent; it never overruns while reps sit above the floor.
    func testSeededSessionStillLandsWithinTheTimingToleranceOrAnHonestShortfall() async throws {
        let library = try await library()

        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            for level in FitnessLevel.allCases {
                for day in TrainingDay.rotation {
                    var plan = SessionAssembly.planSession(
                        requestedMinutes: minutes,
                        user: freshUser(level: level),
                        library: library,
                        recentLogs: [],
                        sessionPolicy: SessionPolicy.seeded(forFitnessLevel: level),
                        trainingDay: day,
                        asOf: asOf,
                        calendar: calendar
                    )
                    SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
                    let gap = plan.totalSeconds - minutes * 60
                    let label = "\(level)'s \(minutes)-minute seeded \(day) session drifted \(gap)s"
                    if gap < -SessionAssembly.toleranceSeconds {
                        XCTAssertTrue(plan.isSaturated, label)
                    } else if gap > SessionAssembly.toleranceSeconds {
                        XCTAssertTrue(plan.stations.allSatisfy { $0.value - RepGrammar.step < $0.floor }, label)
                    }
                    XCTAssertEqual(SessionAssembly.plannedSeconds(of: plan.materialize()), plan.totalSeconds)
                }
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
    /// their first Push Day. The advanced user's circuit opens on a harder rung at more volume; the
    /// beginner's opens at the entry rung at the bottom of the range; every station runs four sets; and
    /// warm-up and cooldown are sized identically for both.
    ///
    /// Asserted against `planSession` (before the timing fit) so each number is read as Step 6 served it,
    /// before the fit cuts or pads toward the requested length.
    func testAdvancedFirstSessionStartsHarderThanABeginners() async throws {
        let library = try await library()
        func plan(_ level: FitnessLevel) -> SessionPlan {
            SessionAssembly.planSession(
                requestedMinutes: 30,
                user: freshUser(level: level),
                library: library,
                recentLogs: [],
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: level),
                trainingDay: .push,
                asOf: asOf,
                calendar: calendar
            )
        }
        func lead(_ plan: SessionPlan) throws -> PlannedItem {
            try XCTUnwrap(plan.stations.first { $0.role == .main })
        }

        let beginnerPlan = plan(.beginner)
        let advancedPlan = plan(.advanced)
        let beginner = try lead(beginnerPlan)
        let advanced = try lead(advancedPlan)

        // Tier: the advanced user starts above the ladder's entry rung, the beginner at it.
        XCTAssertEqual(beginner.exercise.difficulty, 1, "a beginner still starts at the entry rung")
        XCTAssertGreaterThan(
            advanced.exercise.difficulty, beginner.exercise.difficulty,
            "an advanced user's first push must be a harder rung than a beginner's "
                + "(got \(advanced.exercise.id) vs \(beginner.exercise.id))"
        )

        // Volume: every main and core station opens at the bottom of the earned range lifted by the
        // level's seed (x1.0 for the beginner, x1.30 for the advanced user), at four sets.
        for (level, plan) in [(FitnessLevel.beginner, beginnerPlan), (.advanced, advancedPlan)] {
            let multiplier = SessionPolicy.ColdStartContract.startingRepMultiplier(for: level)
            XCTAssertFalse(plan.stations.isEmpty)
            // A Practice Movement runs at its fixed Practice value, not the seeded opening (ADR-0015).
            for station in plan.stations where station.role != .practice {
                XCTAssertEqual(station.sets, RepGrammar.setsPerStation, "\(level) \(station.exercise.id)")
                let opening = AdaptiveOverload.target(
                    for: station.exercise,
                    level: level,
                    recentLogs: [],
                    startingRepMultiplier: multiplier
                )
                XCTAssertEqual(station.value, opening.value, "\(level) \(station.exercise.id)")
            }
        }
        XCTAssertEqual(beginner.value, 15, "the beginner's lead opens at the bottom of the range")
        let advancedCore = try XCTUnwrap(advancedPlan.stations.first { $0.role == .core })
        let beginnerCore = try XCTUnwrap(beginnerPlan.stations.first { $0.role == .core })
        XCTAssertGreaterThan(advancedCore.value, beginnerCore.value, "the core hold carries the x1.30 seed")

        // The bookends are never seeded: the same number of stretches for both levels, one set each at
        // the stretch's own catalog length (which stretches fill them differs by level - ADR-0007 gives
        // beginners staple stretches only - but the Start Seed never reaches them).
        XCTAssertEqual(beginnerPlan.warmup.count, advancedPlan.warmup.count, "warm-up must not be seeded")
        XCTAssertEqual(beginnerPlan.cooldown.count, advancedPlan.cooldown.count, "cooldown must not be seeded")
        for item in beginnerPlan.warmup + beginnerPlan.cooldown + advancedPlan.warmup + advancedPlan.cooldown {
            XCTAssertEqual(item.sets, 1, "\(item.exercise.id) stays one set")
            XCTAssertEqual(item.value, SessionAssembly.bookendValue(for: item.exercise), "\(item.exercise.id) is not volume-seeded")
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
    /// chain, and Step 5 knowing (via `ColdStartOverride.withheldByStartSeed`) that those tiers were
    /// never on offer rather than outgrown.
    ///
    /// The second half of the test covers a pattern the simulated week never reached at all, which is
    /// the harder case: every chain in it is unworked, so freshness has nothing else to prefer.
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

            let handoff = ColdStartHandoff.afterCompletedSession(
                user: user, sessionPolicy: policy, recentLogs: logs
            )
            user = handoff.user
            policy = handoff.sessionPolicy
        }

        XCTAssertFalse(user.coldStart.active, "cold start must have retired after the fifth session")
        XCTAssertNil(policy.coldStartContract, "the contract must be cleared at the handoff")
        XCTAssertEqual(
            user.coldStart.bandFloorAtHandoff,
            SessionPolicy.ColdStartContract.startingDifficultyFloor(for: .advanced),
            "the week ran unproblematically, so the recorded floor is the seeded one"
        )
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

        // The harder half, and the one the generated session above does not necessarily reach: a ladder
        // the cold-start week never touched at all. Strip every `pull` entry from the history and resolve
        // each Pull ladder directly through Step 5 - it now has no history, and without the withheld set
        // its entry would be the gentlest rung (`pull_superman`, difficulty 1). The postural ladder sits
        // wholly below the band, so it enters at its hardest offered rung.
        let withoutPull = logs.map { log -> WorkoutLog in
            var stripped = log
            stripped.exercises = log.exercises.filter { $0.movementPattern != .pull }
            return stripped
        }
        let seededFloor = SessionPolicy.ColdStartContract.startingDifficultyFloor(for: .advanced)
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: withoutPull)
        let withheld = ColdStartOverride.withheldByStartSeed(
            library: library, user: user, sessionPolicy: policy, recentLogs: withoutPull
        )
        for ladder in TrainingDay.pull.ladders {
            let untrained = ProgressionChainSelection.selectInChain(
                library.filter { $0.progressionChainId == ladder },
                eligibleIds: Set(pool.map(\.id)),
                recentLogs: withoutPull,
                level: .advanced,
                withheldByStartSeed: withheld
            )
            let entry = try XCTUnwrap(untrained, ladder).exercise
            let offered = pool.filter { $0.progressionChainId == ladder }
            let expectedFloor = min(seededFloor, try XCTUnwrap(offered.map(\.difficulty).max()))
            XCTAssertGreaterThanOrEqual(
                entry.difficulty, expectedFloor,
                "the untouched \(ladder) ladder regressed to \(entry.id)"
            )
        }
    }

    /// Easing outranks the cliff guard, and it does so by construction rather than by precedence:
    /// `ReturnOverride` caps the pool at difficulty 2, which leaves nothing in-band for the withheld
    /// set to prefer, so the whole candidate set comes back into scope and the gentlest tier is
    /// served exactly as it was before the Start Seed band existed.
    func testReturnServesTheGentlestTierDespiteTheColdStartBand() async throws {
        let library = try await library()
        var user = freshUser(level: .advanced)
        user.coldStart = User.ColdStart(
            sessionsLogged: ColdStartHandoff.handoffThreshold,
            active: false,
            bandFloorAtHandoff: SessionPolicy.ColdStartContract.startingDifficultyFloor(for: .advanced)
        )
        let policy = SessionPolicy.default

        // A strong pre-gap history, then a gap long enough to be a Return.
        let logs = [repsLog(id: "push_diamond", reps: [10, 10, 10], daysAgo: 30)]
        let asOfReturn = asOf
        XCTAssertTrue(
            ReturnOverride.isReturn(recentLogs: logs, asOf: asOfReturn, calendar: calendar),
            "the fixture must actually be a Return"
        )

        let workout = SessionAssembly.assemble(
            requestedMinutes: 30,
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            asOf: asOfReturn,
            calendar: calendar
        )
        for prescribed in trainingItems(of: workout) {
            XCTAssertLessThanOrEqual(
                prescribed.exercise.difficulty, ReturnOverride.returnMaxDifficulty,
                "the Return served \(prescribed.exercise.id) above the return cap"
            )
        }
    }

    /// The strength (i.e. banded) movements a generated session prescribes - its main, Practice and core
    /// stations.
    private func trainingItems(of workout: Workout) -> [PrescribedExercise] {
        workout.blocks
            .flatMap(\.exercises)
            .filter { $0.exercise.pillar == .strength }
    }

    /// The log of a session the user completed exactly as prescribed, rated `justRight` so the Start
    /// Seed neither eases nor hardens across the simulated week. Each station carries its role and Earned
    /// Reps, as the player logs them, so the Rotation moves on to the next Training Day.
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
                    skipped: false,
                    role: prescribed.role,
                    earnedReps: prescribed.earnedReps,
                    earnedDurationSeconds: prescribed.earnedDurationSeconds
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
