import XCTest
@testable import RepToday

/// Tests pipeline Step 4 of the deterministic engine (US-C04): filtering the library down to the
/// safe, level-appropriate pool.
///
/// Two halves: `InjuryContraindication` tests pin the injury-tag -> pattern mapping (including tag
/// normalization); the `ExercisePoolFilter` tests pin each removal rule independently (phase,
/// difficulty cap, injury, recent-skip, equipment floor), the combined validation-test case, and
/// the per-pattern fallback paths (relaxed soft filters vs. no safe option).
final class ExercisePoolFilterTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    /// Builds an exercise with sensible defaults; only the fields a test cares about are passed.
    private func exercise(
        id: String,
        pattern: MovementPattern,
        difficulty: Int = 1,
        phase: Phase = .discipline,
        pillar: Pillar = .strength,
        order: Int = 0,
        equipment: [Equipment] = []
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: pattern,
            category: .strength,
            difficulty: difficulty,
            phase: phase,
            equipment: equipment,
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4.0,
            progressionChainId: "chain_\(pattern.rawValue)",
            progressionOrder: order,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x10 clean reps",
            apartmentFriendly: true
        )
    }

    private func user(
        level: FitnessLevel = .beginner,
        phase: Phase = .discipline,
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
                sitsLong: true,
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

    /// A log `daysAgo` whose listed exercise ids were all skipped (used to drive the skip filter).
    private func skipLog(skippedIds: [String], daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!,
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: skippedIds.map { id in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: [],
                    skipped: true
                )
            }
        )
    }

    // MARK: - InjuryContraindication

    func testInjuryMapsKneesToSquat() {
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "knees"), [.squat])
    }

    func testInjuryTagNormalizationIsCasePluralAndSeparatorInsensitive() {
        // "Knees", "knee", and trailing-space all resolve to the same key.
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "Knees"), [.squat])
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "knee"), [.squat])
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "knee "), [.squat])
        // "lower_back" / "lower back" collapse to the lowerback key.
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "lower_back"), [.hinge])
        XCTAssertEqual(InjuryContraindication.patterns(forInjury: "lower back"), [.hinge])
    }

    func testUnknownInjuryContraindicatesNothing() {
        XCTAssertTrue(InjuryContraindication.patterns(forInjury: "elbow").isEmpty)
    }

    func testContraindicatedPatternsUnionsAllInjuries() {
        XCTAssertEqual(
            InjuryContraindication.contraindicatedPatterns(for: ["knees", "shoulders"]),
            [.squat, .push, .pull]
        )
    }

    // MARK: - Difficulty cap

    func testDifficultyCapsByLevel() {
        XCTAssertEqual(ExercisePoolFilter.difficultyCap(for: .beginner), 1...2)
        XCTAssertEqual(ExercisePoolFilter.difficultyCap(for: .intermediate), 1...3)
        XCTAssertEqual(ExercisePoolFilter.difficultyCap(for: .advanced), 1...5)
    }

    // MARK: - Individual rules

    func testPhaseFilterRemovesStrengthPhaseForDisciplineUser() {
        let library = [
            exercise(id: "disc", pattern: .push, phase: .discipline),
            exercise(id: "str", pattern: .push, difficulty: 1, phase: .strength),
        ]
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: [])
        XCTAssertEqual(pool.map(\.id), ["disc"])
    }

    func testStrengthPhaseUserKeepsStrengthPhaseExercises() {
        let library = [
            exercise(id: "disc", pattern: .push, phase: .discipline),
            exercise(id: "str", pattern: .push, difficulty: 1, phase: .strength),
        ]
        // A strength-phase user (none exist at MVP launch, but the rule must hold) keeps both.
        let pool = ExercisePoolFilter.eligiblePool(
            from: library, user: user(phase: .strength), recentLogs: []
        )
        XCTAssertEqual(pool.map(\.id), ["disc", "str"])
    }

    func testDifficultyCapRemovesTooHardExercises() {
        let library = [
            exercise(id: "d1", pattern: .push, difficulty: 1),
            exercise(id: "d2", pattern: .push, difficulty: 2),
            exercise(id: "d3", pattern: .push, difficulty: 3),
        ]
        XCTAssertEqual(
            ExercisePoolFilter.eligiblePool(from: library, user: user(level: .beginner), recentLogs: []).map(\.id),
            ["d1", "d2"]
        )
        XCTAssertEqual(
            ExercisePoolFilter.eligiblePool(from: library, user: user(level: .intermediate), recentLogs: []).map(\.id),
            ["d1", "d2", "d3"]
        )
    }

    func testInjuryFilterRemovesContraindicatedPattern() {
        let library = [
            exercise(id: "squat1", pattern: .squat),
            exercise(id: "push1", pattern: .push),
            exercise(id: "hinge1", pattern: .hinge),
        ]
        let pool = ExercisePoolFilter.eligiblePool(
            from: library, user: user(injuries: ["knees"]), recentLogs: []
        )
        XCTAssertEqual(pool.map(\.id), ["push1", "hinge1"])
    }

    func testRecentSkipFilterRemovesAfterMoreThanThreeSkips() {
        let library = [exercise(id: "skippy", pattern: .push)]
        // Three skips -> stays (at the threshold, not over it).
        let threeSkips = (0..<3).map { skipLog(skippedIds: ["skippy"], daysAgo: $0 + 1) }
        XCTAssertEqual(
            ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: threeSkips).map(\.id),
            ["skippy"]
        )
        // A fourth skip pushes it over the threshold -> removed.
        let fourSkips = threeSkips + [skipLog(skippedIds: ["skippy"], daysAgo: 5)]
        XCTAssertTrue(
            ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: fourSkips).isEmpty
        )
    }

    func testRecentSkipCountCountsOnlySkippedEntriesForThatId() {
        let logs = [
            skipLog(skippedIds: ["a", "a", "b"], daysAgo: 1),
            skipLog(skippedIds: ["a"], daysAgo: 2),
        ]
        XCTAssertEqual(ExercisePoolFilter.recentSkipCount(forExerciseId: "a", in: logs), 3)
        XCTAssertEqual(ExercisePoolFilter.recentSkipCount(forExerciseId: "b", in: logs), 1)
        XCTAssertEqual(ExercisePoolFilter.recentSkipCount(forExerciseId: "c", in: logs), 0)
    }

    func testEquipmentFloorRemovesNonBodyweightExercises() {
        // The library is validated bodyweight-only at load (US-B02), but the filter still guards.
        let library = [
            exercise(id: "body", pattern: .push, equipment: []),
            exercise(id: "loaded", pattern: .push, equipment: [.dumbbells]),
        ]
        XCTAssertEqual(
            ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: []).map(\.id),
            ["body"]
        )
    }

    // MARK: - Combined (US-C04 validation test)

    /// Beginner, discipline phase, `injuries: ["knees"]`: no strength-phase, no difficulty 3+, and
    /// no knee-flagged (squat) exercises survive; everything left is bodyweight.
    func testEligiblePoolCombinesEveryRule() {
        let library = [
            exercise(id: "push_easy", pattern: .push, difficulty: 1),
            exercise(id: "push_hard", pattern: .push, difficulty: 3),          // over beginner cap
            exercise(id: "squat_easy", pattern: .squat, difficulty: 1),         // knee-flagged
            exercise(id: "core_strength", pattern: .core, difficulty: 1, phase: .strength), // gated
            exercise(id: "hinge_ok", pattern: .hinge, difficulty: 2),
        ]
        let pool = ExercisePoolFilter.eligiblePool(
            from: library, user: user(level: .beginner, phase: .discipline, injuries: ["knees"]), recentLogs: []
        )
        XCTAssertEqual(pool.map(\.id), ["push_easy", "hinge_ok"])
        XCTAssertFalse(pool.contains { $0.phase == .strength })
        XCTAssertFalse(pool.contains { $0.difficulty > 2 })
        XCTAssertFalse(pool.contains { $0.movementPattern == .squat })
        XCTAssertTrue(pool.allSatisfy { $0.equipment.isEmpty })
    }

    // MARK: - Per-pattern pool & fallback

    func testPatternPoolReturnsFilteredPoolWithNoFallback() {
        let library = [
            exercise(id: "push1", pattern: .push, difficulty: 1),
            exercise(id: "push2", pattern: .push, difficulty: 2),
            exercise(id: "squat1", pattern: .squat, difficulty: 1),
        ]
        let pool = ExercisePoolFilter.pool(forPattern: .push, from: library, user: user(), recentLogs: [])
        XCTAssertEqual(pool.exercises.map(\.id), ["push1", "push2"])
        XCTAssertNil(pool.fallback)
    }

    func testPatternPoolFallsBackToSafestWhenSoftFiltersEmptyPattern() {
        // Every push option is above the beginner cap, so the normal pool for push is empty; the
        // fallback relaxes the cap and offers the single safest (lowest-difficulty) option.
        let library = [
            exercise(id: "push_d4", pattern: .push, difficulty: 4, order: 2),
            exercise(id: "push_d3", pattern: .push, difficulty: 3, order: 1),
            exercise(id: "push_d5", pattern: .push, difficulty: 5, order: 3),
        ]
        let pool = ExercisePoolFilter.pool(
            forPattern: .push, from: library, user: user(level: .beginner), recentLogs: []
        )
        XCTAssertEqual(pool.exercises.map(\.id), ["push_d3"])
        XCTAssertEqual(pool.fallback, .relaxedSoftFilters)
    }

    func testPatternPoolReportsNoSafeOptionWhenInjuryRemovesWholePattern() {
        // A knee injury rules out the entire squat pattern; no fallback can safely fill it.
        let library = [
            exercise(id: "squat1", pattern: .squat, difficulty: 1),
            exercise(id: "squat2", pattern: .squat, difficulty: 2),
        ]
        let pool = ExercisePoolFilter.pool(
            forPattern: .squat, from: library, user: user(injuries: ["knees"]), recentLogs: []
        )
        XCTAssertTrue(pool.exercises.isEmpty)
        XCTAssertEqual(pool.fallback, .noSafeOption)
    }

    func testPatternPoolFallbackNeverReturnsAPhaseGatedExercise() {
        // The only push option that fits the cap is strength-phase-gated; for a discipline user the
        // pattern has no safe option rather than leaking the gated movement through the fallback.
        let library = [
            exercise(id: "push_str", pattern: .push, difficulty: 1, phase: .strength),
        ]
        let pool = ExercisePoolFilter.pool(
            forPattern: .push, from: library, user: user(phase: .discipline), recentLogs: []
        )
        XCTAssertTrue(pool.exercises.isEmpty)
        XCTAssertEqual(pool.fallback, .noSafeOption)
    }

    // MARK: - Real bundled library (PRD US-C04 validation test, over the shipped data)

    /// The PRD's own validation test, run end-to-end over the real bundled `Exercises.json` (the
    /// 42 movements an end user actually receives) rather than a synthetic fixture:
    ///
    ///   Setup:  Beginner user in discipline phase with `injuries: ["knees"]`
    ///   Steps:  Run the filter over the full library
    ///   Expect: No strength-phase exercises, no difficulty 3+ exercises, and no knee-flagged
    ///           (squat-pattern) exercises remain in the pool.
    ///   Fail:   A gated exercise survives the filter, or the pool becomes empty without a fallback.
    ///
    /// Prints a human-readable transcript of the resulting pool so the safe-pool behavior is
    /// reviewable as a product-level artifact, not just an assertion.
    func testPRDValidationOverRealBundledLibrary() async throws {
        let library = try await MockExerciseService().exercises()
        XCTAssertEqual(library.count, 71, "should run over the full shipped library")

        let validationUser = user(level: .beginner, phase: .discipline, injuries: ["knees"])
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: validationUser, recentLogs: [])

        // PRD expected result.
        XCTAssertFalse(pool.isEmpty, "pool must not be empty (failure indicator)")
        XCTAssertFalse(pool.contains { $0.phase == .strength }, "no strength-phase exercise survives")
        XCTAssertFalse(pool.contains { $0.difficulty > 2 }, "no difficulty 3+ exercise survives (beginner cap)")
        XCTAssertFalse(pool.contains { $0.movementPattern == .squat }, "no knee-flagged (squat) exercise survives")
        XCTAssertTrue(pool.allSatisfy { $0.equipment.isEmpty }, "Zero-Equipment Floor holds")

        // ---- Evidence transcript ----
        let kept = Set(pool.map(\.id))
        func reasons(_ e: Exercise) -> [String] {
            var r: [String] = []
            if !ExercisePoolFilter.isPhaseAllowed(e, for: validationUser) { r.append("phase-gated(strength)") }
            if !ExercisePoolFilter.isInjurySafe(e, injuries: validationUser.profile.injuries) { r.append("injury(knees->\(e.movementPattern.rawValue))") }
            if !ExercisePoolFilter.isWithinDifficultyCap(e, for: .beginner) { r.append("over-cap(d\(e.difficulty)>2)") }
            if !ExercisePoolFilter.isBodyweight(e) { r.append("non-bodyweight") }
            return r
        }
        let removed = library.filter { !kept.contains($0.id) }

        print("=== US-C04 exercise pool filter - PRD validation over real Exercises.json ===")
        print("User: beginner · discipline phase · injuries: [\"knees\"] · no recent logs")
        print("Library: \(library.count) movements  ->  Eligible pool: \(pool.count)  ·  Removed: \(removed.count)")
        print("")
        print("SAFE POOL (\(pool.count)) by pattern:")
        for pattern in MovementPattern.allCases {
            let inPattern = pool.filter { $0.movementPattern == pattern }
            guard !inPattern.isEmpty else { continue }
            let names = inPattern.map { "\($0.id) (d\($0.difficulty))" }.joined(separator: ", ")
            print("  \(pattern.rawValue): \(names)")
        }
        print("")
        print("REMOVED (\(removed.count)) with reason(s):")
        for e in removed {
            print("  \(e.id) [\(e.movementPattern.rawValue), d\(e.difficulty), \(e.phase.rawValue)] -> \(reasons(e).joined(separator: " + "))")
        }
        print("=== end ===")
    }

    // MARK: - Determinism

    func testEligiblePoolIsDeterministicAndPreservesLibraryOrder() {
        let library = [
            exercise(id: "a", pattern: .push, difficulty: 1),
            exercise(id: "b", pattern: .squat, difficulty: 2),
            exercise(id: "c", pattern: .hinge, difficulty: 1),
        ]
        let first = ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: []).map(\.id)
        for _ in 0..<50 {
            XCTAssertEqual(
                ExercisePoolFilter.eligiblePool(from: library, user: user(), recentLogs: []).map(\.id),
                first
            )
        }
        XCTAssertEqual(first, ["a", "b", "c"]) // order follows the input library
    }

    // MARK: - Effective difficulty cap (US-SP01: earned Strength Phase lifts the cap)

    /// A `.discipline` user's effective cap is byte-identical to the level-only band at every level,
    /// so their eligible pool is unchanged (scope-discipline: neutral behavior stays exactly as-is).
    func testEffectiveCapForDisciplineUserEqualsLevelBand() {
        for level in FitnessLevel.allCases {
            XCTAssertEqual(
                ExercisePoolFilter.effectiveDifficultyCap(for: level, phase: .discipline),
                ExercisePoolFilter.difficultyCap(for: level),
                "a discipline user's cap must be the untouched fitness-level band"
            )
        }
    }

    /// An *earned* Strength-Phase user's effective cap is lifted to the full `1...5` catalog range at
    /// every onboarding level, so a conservative self-report can no longer hide the hardest skills.
    func testEffectiveCapForStrengthUserIsLiftedToFullRangeAtEveryLevel() {
        for level in FitnessLevel.allCases {
            XCTAssertEqual(
                ExercisePoolFilter.effectiveDifficultyCap(for: level, phase: .strength),
                1...5,
                "a strength-phase user's cap must be lifted regardless of onboarding level"
            )
        }
    }

    /// The boundary sits exactly at the phase transition: for one fixed user (intermediate, whose
    /// level band tops out at difficulty 3) a difficulty-5 exercise is out-of-cap in `.discipline`
    /// and in-cap in `.strength` - flipping only the phase flips eligibility of the harder skill,
    /// while an in-band difficulty-3 exercise is eligible in both.
    func testDifficultyFiveCrossesTheCapExactlyAtThePhaseTransition() {
        let hard = exercise(id: "hard_d5", pattern: .push, difficulty: 5)
        let mid = exercise(id: "mid_d3", pattern: .push, difficulty: 3)

        let disciplineUser = user(level: .intermediate, phase: .discipline)
        XCTAssertFalse(ExercisePoolFilter.isWithinEffectiveDifficultyCap(hard, for: disciplineUser))
        XCTAssertTrue(ExercisePoolFilter.isWithinEffectiveDifficultyCap(mid, for: disciplineUser))

        let strengthUser = user(level: .intermediate, phase: .strength)
        XCTAssertTrue(ExercisePoolFilter.isWithinEffectiveDifficultyCap(hard, for: strengthUser))
        XCTAssertTrue(ExercisePoolFilter.isWithinEffectiveDifficultyCap(mid, for: strengthUser))
    }

    /// A phase-gated difficulty-5 skill becomes reachable for a Strength-Phase user (it clears both
    /// the phase gate *and* the lifted difficulty cap), while the same intermediate user in
    /// `.discipline` never sees it - the double-gate trap resolved, on synthetic exercises.
    func testPhaseGatedDifficultyFiveSkillBecomesReachableForStrengthUser() {
        let library = [
            exercise(id: "push_easy", pattern: .push, difficulty: 1),
            exercise(id: "push_skill", pattern: .push, difficulty: 5, phase: .strength),
        ]
        let disciplinePool = ExercisePoolFilter.eligiblePool(
            from: library, user: user(level: .intermediate, phase: .discipline), recentLogs: []
        )
        XCTAssertEqual(disciplinePool.map(\.id), ["push_easy"], "the gated d5 skill is hidden in discipline")

        let strengthPool = ExercisePoolFilter.eligiblePool(
            from: library, user: user(level: .intermediate, phase: .strength), recentLogs: []
        )
        XCTAssertEqual(strengthPool.map(\.id), ["push_easy", "push_skill"], "the gated d5 skill is reachable in strength")
    }

    /// PRD US-SP01 validation, end-to-end over the real bundled catalog: a synthetic
    /// `FitnessLevel.intermediate` user with a log history that *earns* `.strength` (8 fully on-goal
    /// weeks + all four foundation entry tiers cleared) sees `push_one_arm` (difficulty 5,
    /// `phase == .strength`) in the eligible push pool; the same user forced to `.discipline` never
    /// does. Failure indicator: an intermediate Strength-Phase user still cannot reach any
    /// difficulty-5 skill (the double gate still binds).
    func testStrengthPhaseIntermediateUserReachesDifficultyFivePushOverRealCatalog() async throws {
        let library = try await MockExerciseService().exercises()

        // A Sunday-start Gregorian/UTC calendar and a mid-week anchor, matching PhaseEvaluatorTests
        // so week bucketing is deterministic.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        let anchor = cal.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
        func day(weeksAgo: Int, dayOffset: Int) -> Date {
            cal.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: anchor)!
        }

        // Sustained consistency: 3 show-ups/week for 8 weeks (Consistency Score 100, span 8).
        func showUp(weeksAgo: Int, dayOffset: Int) -> WorkoutLog {
            WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: day(weeksAgo: weeksAgo, dayOffset: dayOffset),
                requestedMinutes: 15, durationMinutes: 15, shape: .singleFocus, focusPillar: .strength,
                perceivedDifficulty: nil, exercises: []
            )
        }
        // Competence: clear one entry tier of each foundational pattern from the real catalog.
        func clearing(_ exerciseId: String, pattern: MovementPattern, isHold: Bool, value: Int) -> WorkoutLog {
            let sets = (0..<3).map { _ in CompletedSet(reps: isHold ? nil : value, durationSeconds: isHold ? value : nil) }
            return WorkoutLog(
                id: UUID(), workoutId: UUID(), completedAt: day(weeksAgo: 0, dayOffset: 0),
                requestedMinutes: 20, durationMinutes: 20, shape: .singleFocus, focusPillar: .strength,
                perceivedDifficulty: nil,
                exercises: [LoggedExercise(id: UUID(), exerciseId: exerciseId, pillar: .strength,
                                           movementPattern: pattern, completedSets: sets, skipped: false)]
            )
        }
        let history =
            (0..<8).flatMap { w in (0..<3).map { showUp(weeksAgo: w, dayOffset: $0) } }
            + [
                clearing("push_wall", pattern: .push, isHold: false, value: 15),        // "3x15 clean reps"
                clearing("squat_wall_sit", pattern: .squat, isHold: true, value: 45),    // "3x45s hold"
                clearing("hinge_glute_bridge", pattern: .hinge, isHold: false, value: 20),// "3x20 clean reps"
                clearing("core_forearm_plank", pattern: .core, isHold: true, value: 45),  // "3x45s hold"
            ]

        // Step 1: evaluate phase - the earned phase must be Strength.
        let earned = PhaseEvaluator.evaluate(logs: history, weeklyGoal: 3, library: library, asOf: anchor, calendar: cal)
        XCTAssertEqual(earned, .strength, "the synthetic intermediate history must earn the Strength Phase")

        // Step 2: the eligible push pool for the earned Strength-Phase intermediate user includes the
        // phase-gated difficulty-5 one-arm push-up.
        let strengthUser = user(level: .intermediate, phase: earned)
        let strengthPush = ExercisePoolFilter
            .eligiblePool(from: library, user: strengthUser, recentLogs: [])
            .filter { $0.movementPattern == .push }
        XCTAssertTrue(strengthPush.contains { $0.id == "push_one_arm" },
                      "push_one_arm (d5, strength-gated) must be eligible for the earned Strength-Phase user")
        XCTAssertTrue(strengthPush.contains { $0.difficulty == 5 },
                      "at least one difficulty-5 push skill must be reachable (failure indicator)")

        // The same user forced to Discipline never sees it (both gates bind).
        let disciplineUser = user(level: .intermediate, phase: .discipline)
        let disciplinePush = ExercisePoolFilter
            .eligiblePool(from: library, user: disciplineUser, recentLogs: [])
            .filter { $0.movementPattern == .push }
        XCTAssertFalse(disciplinePush.contains { $0.id == "push_one_arm" },
                       "push_one_arm must be hidden from a discipline-phase user")
        XCTAssertFalse(disciplinePush.contains { $0.phase == .strength },
                       "no strength-gated push survives for a discipline user")
    }

    /// Scope-discipline pin: a `.discipline` user's eligible pool over the real bundled catalog is
    /// byte-identical to the pre-US-SP01 behavior (the level-only difficulty cap), so lifting the
    /// cap for Strength users changed nothing for everyone else.
    func testDisciplineUserPoolMatchesLevelOnlyCapOverRealCatalog() async throws {
        let library = try await MockExerciseService().exercises()
        for level in FitnessLevel.allCases {
            let disciplineUser = user(level: level, phase: .discipline)
            let actual = ExercisePoolFilter.eligiblePool(from: library, user: disciplineUser, recentLogs: []).map(\.id)
            // Recompute the pool using the level-only cap, exactly the pre-change logic.
            let expected = library.filter { e in
                ExercisePoolFilter.isBodyweight(e)
                    && ExercisePoolFilter.isPhaseAllowed(e, for: disciplineUser)
                    && ExercisePoolFilter.isInjurySafe(e, injuries: disciplineUser.profile.injuries)
                    && ExercisePoolFilter.isWithinDifficultyCap(e, for: level)
            }.map(\.id)
            XCTAssertEqual(actual, expected, "discipline pool at \(level) must be unchanged by US-SP01")
        }
    }
}
