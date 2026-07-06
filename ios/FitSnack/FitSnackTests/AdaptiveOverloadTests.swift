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
        difficulty: PerceivedDifficulty? = nil,
        skipped: Bool = false
    ) -> WorkoutLog {
        log(
            id: id,
            sets: seconds.map { CompletedSet(reps: nil, durationSeconds: $0) },
            daysAgo: daysAgo,
            difficulty: difficulty,
            skipped: skipped
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
        XCTAssertGreaterThan(target.reps!, 10) // round(10 * 1.05) = 11, strictly above capacity
    }

    /// A just-right rating on a small capacity that rounding would otherwise stall (round(8 * 1.05)
    /// == 8) still climbs by at least one, matching the directional guarantee on too_easy/too_hard.
    func testSmallCapacityJustRightStillClimbs() {
        let logs = [repsLog(id: "ex", reps: [8, 8], daysAgo: 1, difficulty: .justRight)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.reps, 9) // forced to capacity + 1
    }

    // MARK: - too_hard / too_easy within one cycle

    func testTooHardReducesBelowCapacity() {
        // PRD validation shape: 3x12 marked too_hard -> at or below 3x12, capacity-derived.
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 3)
        XCTAssertLessThan(target.reps!, 12)
        XCTAssertEqual(target.reps, 10) // round(12 * 0.80), the eager down-step (US-E05)
    }

    func testTooEasyIncreasesAboveCapacity() {
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooEasy)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertGreaterThan(target.reps!, 12)
        XCTAssertEqual(target.reps, 13) // round(12 * 1.10), the patient up-step (US-E05)
    }

    /// Direction is guaranteed even when rounding would otherwise stall: a small capacity still
    /// moves by at least one in the signalled direction.
    func testSmallCapacityStillMovesInSignalledDirection() {
        let easy = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [3, 3], daysAgo: 1, difficulty: .tooEasy)]
        )
        XCTAssertEqual(easy.reps, 4) // round(3 * 1.10) = 3, forced to capacity + 1

        let hard = AdaptiveOverload.target(
            for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [5, 5], daysAgo: 1, difficulty: .tooHard)]
        )
        XCTAssertEqual(hard.reps, 4) // round(5 * 0.80) = 4, which is already capacity - 1
    }

    /// Easing never drops below the rep floor, so the prescription stays meaningful.
    func testTooHardNeverDropsBelowFloor() {
        let logs = [repsLog(id: "ex", reps: [3, 3], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.reps, AdaptiveOverload.minReps)
    }

    // MARK: - Asymmetric Ramp (US-E05)

    /// The core invariant: from the same demonstrated capacity, a `too_hard` backs off by at least as
    /// much as a `too_easy` climbs - the eager down-step is never smaller than the patient up-step.
    func testAsymmetricRampBacksOffAtLeastAsFastAsItClimbs() {
        let capacity = 20
        let hard = AdaptiveOverload.target(
            for: repsExercise(),
            recentLogs: [repsLog(id: "ex", reps: [capacity, capacity], daysAgo: 1, difficulty: .tooHard)]
        )
        let easy = AdaptiveOverload.target(
            for: repsExercise(),
            recentLogs: [repsLog(id: "ex", reps: [capacity, capacity], daysAgo: 1, difficulty: .tooEasy)]
        )
        let downStep = capacity - hard.reps!  // magnitude of the eager back-off (20 -> 16 = 4)
        let upStep = easy.reps! - capacity     // magnitude of the patient climb (20 -> 22 = 2)
        XCTAssertGreaterThan(downStep, 0, "too_hard must move down")
        XCTAssertGreaterThan(upStep, 0, "too_easy must move up")
        XCTAssertGreaterThanOrEqual(downStep, upStep, "the ramp backs off at least as fast as it climbs")
    }

    /// The asymmetry is pinned on the tunable constants themselves, so a future re-tune that violates
    /// it (an up-step larger than the down-step) fails loudly.
    func testRampConstantsAreAsymmetric() {
        let downMagnitude = 1.0 - AdaptiveOverload.hardStep   // 0.20
        let upMagnitude = AdaptiveOverload.easyStep - 1.0     // 0.10
        XCTAssertGreaterThanOrEqual(downMagnitude, upMagnitude)
        // And the gentle progressive nudge never out-climbs the explicit too_easy up-step.
        XCTAssertLessThanOrEqual(AdaptiveOverload.progressiveStep - 1.0, upMagnitude)
    }

    /// A single recent skip of this exercise is an eager down-signal: the next target eases below the
    /// capacity from the earlier worked session, exactly as a `too_hard` would.
    func testRecentSkipEasesTargetLikeTooHard() {
        let skipHistory = [
            repsLog(id: "ex", reps: [], daysAgo: 1, skipped: true),
            repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 3, difficulty: .justRight),
        ]
        let skipTarget = AdaptiveOverload.target(for: repsExercise(), recentLogs: skipHistory)

        let hardHistory = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]
        let hardTarget = AdaptiveOverload.target(for: repsExercise(), recentLogs: hardHistory)

        XCTAssertEqual(skipTarget.reps, hardTarget.reps, "a skip eases like a too_hard")
        XCTAssertLessThan(skipTarget.reps!, 12)
    }

    /// The recent skip wins even over an earlier `too_easy`: the more-recent bail is the stronger
    /// signal, so the target eases rather than intensifying off the older rating.
    func testRecentSkipOverridesEarlierTooEasy() {
        let logs = [
            repsLog(id: "ex", reps: [], daysAgo: 1, skipped: true),
            repsLog(id: "ex", reps: [10, 10], daysAgo: 4, difficulty: .tooEasy),
        ]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertLessThan(target.reps!, 10, "the recent skip eases even over an earlier too_easy")
        XCTAssertEqual(target.reps, 8) // round(10 * 0.80)
    }

    /// A skip eases holds too, in seconds.
    func testRecentSkipEasesHold() {
        let logs = [
            holdLog(id: "ex", seconds: [], daysAgo: 1, skipped: true),
            holdLog(id: "ex", seconds: [40, 40], daysAgo: 3, difficulty: .justRight),
        ]
        let target = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs)
        XCTAssertLessThan(target.durationSeconds!, 40)
        XCTAssertEqual(target.durationSeconds, 32) // round(40 * 0.80)
    }

    // MARK: - Holds

    func testHoldProgressionUsesSeconds() {
        let logs = [holdLog(id: "ex", seconds: [30, 30], daysAgo: 1, difficulty: .tooEasy)]
        let target = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs)
        XCTAssertNil(target.reps)
        XCTAssertEqual(target.sets, 2)
        XCTAssertEqual(target.durationSeconds, 33) // round(30 * 1.10), the patient up-step
    }

    func testHoldTooHardEasesSeconds() {
        let logs = [holdLog(id: "ex", seconds: [40, 40, 40], daysAgo: 1, difficulty: .tooHard)]
        let target = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs)
        XCTAssertEqual(target.durationSeconds, 32) // round(40 * 0.80), the eager down-step
        XCTAssertLessThan(target.durationSeconds!, 40)
    }

    // MARK: - progressionRate lever (US-E03)

    /// A higher `progressionRate` advances a too-easy target faster; the neutral rate reproduces
    /// the prior curve exactly.
    func testProgressionRateAdvancesTooEasyFaster() {
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooEasy)]
        let neutral = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 1.0)
        let fast = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 2.0)
        XCTAssertEqual(neutral.reps, 13) // round(12 * 1.10)
        XCTAssertEqual(fast.reps, 14)    // round(12 * (1 + 0.10*2)) = round(14.4)
        XCTAssertGreaterThan(fast.reps!, neutral.reps!)
    }

    /// The progressive (unrated / just-right) nudge is paced by the rate too.
    func testProgressionRateAdvancesProgressiveNudgeFaster() {
        let logs = [repsLog(id: "ex", reps: [20, 20], daysAgo: 1)] // unrated
        let neutral = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 1.0)
        let fast = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 3.0)
        XCTAssertEqual(neutral.reps, 21) // round(20 * 1.05)
        XCTAssertEqual(fast.reps, 23)    // round(20 * (1 + 0.05*3)) = round(23.0)
    }

    /// The default rate parameter equals an explicit neutral `1.0`, so no caller that omits it
    /// changes behavior (the no-regression guarantee at the unit level).
    func testDefaultProgressionRateIsNeutral() {
        let logs = [repsLog(id: "ex", reps: [12, 12], daysAgo: 1, difficulty: .tooEasy)]
        XCTAssertEqual(
            AdaptiveOverload.target(for: repsExercise(), recentLogs: logs),
            AdaptiveOverload.target(
                for: repsExercise(), recentLogs: logs, progressionRate: AdaptiveOverload.neutralProgressionRate
            )
        )
    }

    /// The rate never scales the `too_hard` ease: a faster program must not back off harder (the
    /// eager down-step is the Asymmetric Ramp's job in US-E05, not `progressionRate`'s).
    func testProgressionRateDoesNotScaleTooHardEase() {
        let logs = [repsLog(id: "ex", reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]
        let neutral = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 1.0)
        let fast = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 3.0)
        XCTAssertEqual(neutral.reps, 10) // round(12 * 0.80)
        XCTAssertEqual(fast.reps, neutral.reps, "the too_hard ease is rate-independent")
    }

    /// A high rate still clamps to the rep safety rail.
    func testProgressionRateStaysWithinRails() {
        let logs = [repsLog(id: "ex", reps: [45, 45], daysAgo: 1, difficulty: .tooEasy)]
        let fast = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, progressionRate: 5.0)
        XCTAssertEqual(fast.reps, AdaptiveOverload.maxReps) // round(45 * 1.50)=68, clamped to 50
    }

    /// Holds advance faster under a higher rate too, in seconds.
    func testProgressionRateAdvancesHoldsFaster() {
        let logs = [holdLog(id: "ex", seconds: [30, 30], daysAgo: 1, difficulty: .tooEasy)]
        let neutral = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs, progressionRate: 1.0)
        let fast = AdaptiveOverload.target(for: holdExercise(), recentLogs: logs, progressionRate: 2.0)
        XCTAssertEqual(neutral.durationSeconds, 33) // round(30 * 1.10)
        XCTAssertEqual(fast.durationSeconds, 36)    // round(30 * 1.20)
        XCTAssertGreaterThan(fast.durationSeconds!, neutral.durationSeconds!)
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
        XCTAssertEqual(low.reps, 9)  // round(8 * 1.05) = 8, forced to capacity + 1
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
        XCTAssertEqual(target.reps, 8) // eased from 10 (round(10 * 0.80)), not progressed from 20
        XCTAssertLessThan(target.reps!, 10)
    }

    /// A skipped most-recent performance is not the capacity *source* (the set count still tracks the
    /// earlier worked session), but under the Asymmetric Ramp (US-E05) the skip is an eager
    /// down-signal, so the next target eases below that demonstrated capacity.
    func testSkippedPerformanceIsNotCapacityAndEasesTarget() {
        let logs = [
            repsLog(id: "ex", reps: [], daysAgo: 1, skipped: true),
            repsLog(id: "ex", reps: [12, 12], daysAgo: 3, difficulty: .justRight),
        ]
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        XCTAssertEqual(target.sets, 2)           // sets from the worked session, not the skip
        XCTAssertLessThan(target.reps!, 12)      // the skip eases rather than progressing up
        XCTAssertEqual(target.reps, 10)          // round(12 * 0.80), the eager down-step
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

    /// The PRD's US-E05 validation case over the real library: 3x12 squats marked `too_hard` vs a
    /// separate 3x12 history marked `too_easy` -> the too_hard history eases immediately and by more
    /// than the too_easy history raises its target, and both stay within the rails.
    func testPRDAsymmetricRampEasesMoreThanItClimbs() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })

        let hard = AdaptiveOverload.target(
            for: squat, recentLogs: [repsLog(id: squat.id, reps: [12, 12, 12], daysAgo: 1, difficulty: .tooHard)]
        )
        let easy = AdaptiveOverload.target(
            for: squat, recentLogs: [repsLog(id: squat.id, reps: [12, 12, 12], daysAgo: 1, difficulty: .tooEasy)]
        )

        let downStep = 12 - hard.reps!  // eager back-off
        let upStep = easy.reps! - 12     // patient climb
        XCTAssertLessThan(hard.reps!, 12, "too_hard eases immediately")
        XCTAssertGreaterThan(easy.reps!, 12, "too_easy climbs")
        XCTAssertGreaterThan(downStep, upStep, "the drop is larger than the rise")

        // Rails honored on both sides.
        XCTAssertGreaterThanOrEqual(hard.reps!, AdaptiveOverload.minReps)
        XCTAssertLessThanOrEqual(easy.reps!, AdaptiveOverload.maxReps)
    }
}
