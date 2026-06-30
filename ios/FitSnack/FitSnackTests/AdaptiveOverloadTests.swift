import XCTest
@testable import FitSnack

/// Tests pipeline Step 6 of the deterministic engine (US-C06): turning a chosen exercise into a
/// capacity-relative rep/set/hold target.
///
/// Coverage mirrors the PRD acceptance criteria: the progressive bump from demonstrated capacity,
/// the `tooHard` ease and `tooEasy` intensify (both within one cycle), the same logic for holds in
/// seconds, the no-history fallback to the exercise's own defaults, and the guarantee that every
/// target is derived from capacity rather than a fixed heroic number. The final two tests run the
/// PRD's own validation case (3x12 squats marked `tooHard`) over the real bundled library.
final class AdaptiveOverloadTests: XCTestCase {

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

    /// A rep-based exercise with the given defaults; everything else is filler the step ignores.
    private func repsExercise(id: String = "ex", defaultReps: Int = 10) -> Exercise {
        exercise(id: id, isHold: false, defaultReps: defaultReps, defaultDurationSeconds: nil)
    }

    /// A hold exercise with the given default duration.
    private func holdExercise(id: String = "ex", defaultDurationSeconds: Int = 20) -> Exercise {
        exercise(id: id, isHold: true, defaultReps: nil, defaultDurationSeconds: defaultDurationSeconds)
    }

    private func exercise(
        id: String,
        isHold: Bool,
        defaultReps: Int?,
        defaultDurationSeconds: Int?
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: .strength,
            movementPattern: .squat,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: isHold,
            defaultReps: defaultReps,
            defaultDurationSeconds: defaultDurationSeconds,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x15 clean reps",
            apartmentFriendly: true
        )
    }

    /// A session `daysAgo` that worked `id` with the given per-set `reps` and an optional rating.
    private func repsLog(
        id: String,
        reps: [Int],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil,
        skipped: Bool = false
    ) -> WorkoutLog {
        log(
            id: id,
            sets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
            daysAgo: daysAgo,
            difficulty: difficulty,
            skipped: skipped
        )
    }

    /// A session `daysAgo` that worked `id` with the given per-set hold `seconds` and an optional rating.
    private func holdLog(
        id: String,
        seconds: [Int],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        log(
            id: id,
            sets: seconds.map { CompletedSet(reps: nil, durationSeconds: $0) },
            daysAgo: daysAgo,
            difficulty: difficulty,
            skipped: false
        )
    }

    private func log(
        id: String,
        sets: [CompletedSet],
        daysAgo: Int,
        difficulty: PerceivedDifficulty?,
        skipped: Bool
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: difficulty,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .squat,
                    completedSets: sets,
                    skipped: skipped
                )
            ]
        )
    }

    // MARK: - No history -> defaults

    func testNoHistoryUsesExerciseRepDefaults() {
        let target = AdaptiveOverload.target(for: repsExercise(defaultReps: 12), recentLogs: [])
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
        XCTAssertEqual(target.reps, 12)
        XCTAssertNil(target.durationSeconds)
    }

    func testNoHistoryUsesExerciseHoldDefaults() {
        let target = AdaptiveOverload.target(for: holdExercise(defaultDurationSeconds: 25), recentLogs: [])
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
        XCTAssertEqual(target.durationSeconds, 25)
        XCTAssertNil(target.reps)
    }

    /// A non-skipped log with no usable sets (all empty/zero) is not "capacity" - the step still
    /// falls back to defaults rather than reading a phantom 0.
    func testEmptyOrZeroSetsFallBackToDefaults() {
        let logs = [repsLog(id: "ex", reps: [0, 0], daysAgo: 1, difficulty: .tooEasy)]
        let target = AdaptiveOverload.target(for: repsExercise(defaultReps: 10), recentLogs: logs)
        XCTAssertEqual(target.reps, 10)
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
    }

    // MARK: - Progressive (just-right / no rating)

    func testProgressiveBumpFromCapacityWithNoRating() {
        // 3x12, unrated -> sets track capacity (3), reps nudge just above 12.
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 3)
        XCTAssertEqual(target.reps, 13)
    }

    func testJustRightProgressesAtOrAboveCapacity() {
        let logs = [repsLog(id: "ex", reps: [10, 10], daysAgo: 1, difficulty: .justRight)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 2)
        XCTAssertGreaterThanOrEqual(target.reps!, 10)
    }

    // MARK: - too_hard / too_easy within one cycle

    func testTooHardReducesBelowCapacity() {
        // PRD validation shape: 3x12 marked too_hard -> at or below 3x12, capacity-derived.
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 3)
        XCTAssertLessThan(target.reps!, 12)
        XCTAssertEqual(target.reps, 10) // round(12 * 0.85)
    }

    func testTooEasyIncreasesAboveCapacity() {
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooEasy)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertGreaterThan(target.reps!, 12)
        XCTAssertEqual(target.reps, 14) // round(12 * 1.15)
    }

    /// Direction is guaranteed even when rounding would otherwise stall: a small capacity still
    /// moves by at least one in the signalled direction.
    func testSmallCapacityStillMovesInSignalledDirection() {
        let easy = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [3, 3], daysAgo: 1, difficulty: .tooEasy)]
        )
        XCTAssertEqual(easy.reps, 4) // round(3 * 1.15) = 3, forced to capacity + 1

        let hard = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [5, 5], daysAgo: 1, difficulty: .tooHard)]
        )
        XCTAssertEqual(hard.reps, 4) // round(5 * 0.85) = 4, which is already capacity - 1
    }

    /// Easing never drops below the rep floor, so the prescription stays meaningful.
    func testTooHardNeverDropsBelowFloor() {
        let logs = [repsLog(id: "ex", reps: [3, 3], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.reps, AdaptiveOverload.minReps)
    }

    // MARK: - Holds

    func testHoldProgressionUsesSeconds() {
        let logs = [holdLog(id: "ex", seconds: [30, 30], daysAgo: 1, difficulty: .tooEasy)]
        let target = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs)
        XCTAssertNil(target.reps)
        XCTAssertEqual(target.sets, 2)
        XCTAssertEqual(target.durationSeconds, 35) // round(30 * 1.15)
    }

    func testHoldTooHardEasesSeconds() {
        let logs = [holdLog(id: "ex", seconds: [40, 40, 40], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs)
        XCTAssertEqual(target.durationSeconds, 34) // round(40 * 0.85)
        XCTAssertLessThan(target.durationSeconds!, 40)
    }

    // MARK: - Capacity, not a fixed number

    /// Every target is capacity-relative: different demonstrated capacities yield different targets,
    /// so the engine can never be prescribing a fixed heroic constant.
    func testTargetsAreCapacityRelativeNotConstant() {
        let low = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [8, 8], daysAgo: 1)]
        )
        let high = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [20, 20], daysAgo: 1)]
        )
        XCTAssertNotEqual(low.reps, high.reps)
        XCTAssertEqual(low.reps, 8)  // round(8 * 1.05)
        XCTAssertEqual(high.reps, 21) // round(20 * 1.05)
    }

    /// No-history defaults come from the exercise itself, not a shared constant: two exercises with
    /// different defaults prescribe differently.
    func testDefaultsAreExerciseSpecific() {
        let a = AdaptiveOverload.target(for: repsExercise(id: "a", defaultReps: 8), recentLogs: [])
        let b = AdaptiveOverload.target(for: repsExercise(id: "b", defaultReps: 15), recentLogs: [])
        XCTAssertEqual(a.reps, 8)
        XCTAssertEqual(b.reps, 15)
    }

    /// Capacity comes from the most recent usable session, and that session's rating applies.
    func testUsesMostRecentUsablePerformance() {
        let logs = [
            repsLog(id: "ex", reps: [20, 20], daysAgo: 5, difficulty: .tooEasy), // older, ignored
            repsLog(id: "ex", reps: [10, 10], daysAgo: 1, difficulty: .tooHard), // most recent wins
        ]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.reps, 9) // eased from 10 (round(10 * 0.85)), not progressed from 20
        XCTAssertLessThan(target.reps!, 10)
    }

    /// A skipped most-recent performance is not capacity; the step looks past it to the worked one.
    func testSkippedPerformanceIsNotCapacity() {
        let logs = [
            repsLog(id: "ex", reps: [], daysAgo: 1, difficulty: .tooEasy, skipped: true),
            repsLog(id: "ex", reps: [12, 12], daysAgo: 3, difficulty: .justRight),
        ]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 2)
        XCTAssertGreaterThanOrEqual(target.reps!, 12)
    }

    // MARK: - Determinism

    func testTargetIsDeterministic() {
        let logs = [repsLog(id: "ex", reps: [11, 13, 12], daysAgo: 2, difficulty: .tooEasy)]
        let first = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        for _ in 0..<50 {
            XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs), first)
        }
    }

    // MARK: - Real bundled library (PRD US-C06 validation test)

    /// The PRD's own validation case over the real library: last log 3x12 bodyweight squats marked
    /// `too_hard` -> the next squat target is at or below 3x12 and computed from capacity.
    func testPRDValidationEasesSquatsMarkedTooHard() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })
        let logs = [repsLog(id: squat.id, reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]

        let target = AdaptiveOverload.target(for: squat, recentLogs: logs)
        XCTAssertEqual(target.sets, 3)
        XCTAssertLessThanOrEqual(target.reps!, 12, "too_hard must ease at or below demonstrated 3x12")
        XCTAssertNotEqual(target.reps, squat.defaultReps, "target is from capacity, not the static default")
    }

    /// A fresh user with no history gets the real squat's own default, never a heroic constant.
    func testPRDFreshUserGetsSquatDefaultOverRealLibrary() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })

        let target = AdaptiveOverload.target(for: squat, recentLogs: [])
        XCTAssertEqual(target.reps, squat.defaultReps)
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
    }
}
