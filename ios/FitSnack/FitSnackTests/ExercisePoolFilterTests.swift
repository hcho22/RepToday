import XCTest
@testable import FitSnack

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
}
