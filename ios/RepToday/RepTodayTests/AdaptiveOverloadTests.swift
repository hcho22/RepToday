import XCTest
@testable import RepToday

/// Tests pipeline Step 6 of the deterministic engine (US-C06): turning a chosen exercise into a
/// capacity-relative rep/set/hold target, on the grid of round numbers (ADR-0011).
///
/// Coverage: every target is a multiple of five, never below ten; a number logged before the grid
/// rounds down onto it; the climb (three "just right" sessions in a row at one number add five, "too
/// easy" adds five at once, "too hard" or a skip takes five off); the completion screen's "couldn't
/// finish" marks; the floor step-back signal Step 5 reads; holds and per-side moves on the same rule;
/// and the three levers (`progressionRate`, the Re-entry Ramp scale, the Start Seed) mapped onto
/// five-steps. The last tests run the PRD's validation cases over the real bundled library.
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

    /// A session `daysAgo` rated `difficulty` that worked several moves, each `(id, reps, couldNotFinish)`.
    private func multiLog(
        _ moves: [(id: String, reps: Int, couldNotFinish: Bool?)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty?
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
            exercises: moves.map { move in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: move.id,
                    pillar: .strength,
                    movementPattern: .squat,
                    completedSets: Array(repeating: CompletedSet(reps: move.reps, durationSeconds: nil), count: 3),
                    skipped: false,
                    couldNotFinish: move.couldNotFinish
                )
            }
        )
    }

    /// A per-side variant of `holdExercise`.
    private func perSideHold(defaultDurationSeconds: Int = 30) -> Exercise {
        var exercise = holdExercise(defaultDurationSeconds: defaultDurationSeconds)
        exercise.isPerSide = true
        return exercise
    }

    /// `n` "just right" sessions at `reps`, the newest `firstDaysAgo` days ago, one day apart.
    private func justRightRun(_ n: Int, reps: Int, firstDaysAgo: Int = 1, difficulty: PerceivedDifficulty? = .justRight) -> [WorkoutLog] {
        (0..<n).map { repsLog(id: "ex", reps: [reps, reps, reps], daysAgo: firstDaysAgo + $0, difficulty: difficulty) }
    }

    // MARK: - No history -> grid-rounded defaults

    func testNoHistoryUsesTheDefaultRoundedDownOntoTheGrid() {
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(defaultReps: 15), recentLogs: []).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(defaultReps: 12), recentLogs: []).reps, 10,
                       "a default of 12 is served as the round number below it")
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(defaultReps: 3), recentLogs: []).reps, 10,
                       "a default below the floor is raised to ten")
        let target = AdaptiveOverload.target(for: repsExercise(defaultReps: 12), recentLogs: [])
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
        XCTAssertNil(target.durationSeconds)
    }

    func testNoHistoryHoldUsesTheDefaultRoundedDownOntoTheGrid() {
        XCTAssertEqual(AdaptiveOverload.target(for: holdExercise(defaultDurationSeconds: 30), recentLogs: []).durationSeconds, 30)
        XCTAssertEqual(AdaptiveOverload.target(for: holdExercise(defaultDurationSeconds: 12), recentLogs: []).durationSeconds, 10)
        XCTAssertEqual(AdaptiveOverload.target(for: holdExercise(defaultDurationSeconds: 8), recentLogs: []).durationSeconds, 10)
    }

    func testEmptyOrZeroSetsFallBackToDefaults() {
        let logs = [repsLog(id: "ex", reps: [0, 0], daysAgo: 1)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(defaultReps: 15), recentLogs: logs).reps, 15)
    }

    // MARK: - Round-down of numbers logged before the grid

    func testAnOldOddNumberRoundsDownToTheGridAtTheNextSession() {
        // 13s rated too easy would once have become 14; on the grid, 13 is served as 10, plus five.
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [13, 13, 13], daysAgo: 1, difficulty: .tooEasy)]).reps, 15)
        // A single just-right 14 holds at the round number below it.
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [14, 14, 14], daysAgo: 1)]).reps, 10)
        // 22 rounds down to 20.
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [22, 22, 22], daysAgo: 1)]).reps, 20)
    }

    func testAnOldNumberBelowTheFloorRoundsUpToTen() {
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [6, 6, 6], daysAgo: 1)])
        XCTAssertEqual(target.reps, 10, "the floor is ten, so a logged six is served as ten")
    }

    func testOnGridIsAlwaysAMultipleOfFiveWithinTheRails() {
        for value in -5...80 {
            let reps = AdaptiveOverload.onGrid(value, isHold: false, sides: 1)
            XCTAssertEqual(reps % AdaptiveOverload.step, 0)
            XCTAssertTrue((AdaptiveOverload.minReps...AdaptiveOverload.maxReps).contains(reps))
            let perSide = AdaptiveOverload.onGrid(value * 3, isHold: true, sides: 2)
            XCTAssertEqual(perSide % AdaptiveOverload.step, 0)
            XCTAssertTrue((10...90).contains(perSide), "a per-side hold tops out at half the 180s ceiling")
        }
    }

    // MARK: - The climb

    func testThreeJustRightSessionsAtOneNumberAddFive() {
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(1, reps: 15)).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(2, reps: 15)).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(3, reps: 15)).reps, 20)
    }

    func testAnUnratedSessionCountsAsJustRight() {
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(3, reps: 15, difficulty: nil)).reps, 20)
    }

    func testTheRunCountsOnlySessionsAtTheSameNumber() {
        // Two at 20 after a climb from 15: the run at 20 is two, so it holds.
        let logs = justRightRun(2, reps: 20) + justRightRun(3, reps: 15, firstDaysAgo: 3)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs).reps, 20)
    }

    func testAnyOtherSessionBreaksTheRun() {
        let logs = justRightRun(2, reps: 15)
            + [repsLog(id: "ex", reps: [15, 15, 15], daysAgo: 3, difficulty: .tooEasy)]
            + justRightRun(2, reps: 15, firstDaysAgo: 4)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs).reps, 15)
    }

    func testTooEasyAddsFiveAtOnce() {
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [15, 15, 15], daysAgo: 1, difficulty: .tooEasy)])
        XCTAssertEqual(target.reps, 20)
    }

    func testTooHardTakesFiveOff() {
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [20, 20, 20], daysAgo: 1, difficulty: .tooHard)])
        XCTAssertEqual(target.reps, 15)
    }

    func testTooHardAtTheFloorStaysAtTenAndSignalsAChainStepDown() {
        let logs = [repsLog(id: "ex", reps: [10, 10, 10], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs).reps, 10)
        XCTAssertEqual(AdaptiveOverload.floorStepBackDate(for: repsExercise(), recentLogs: logs), date(daysAgo: 1))
    }

    func testAStepBackAboveTheFloorDoesNotSignalAChainStepDown() {
        let logs = [repsLog(id: "ex", reps: [15, 15, 15], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(), recentLogs: logs))
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(), recentLogs: justRightRun(1, reps: 10)))
    }

    func testRecentSkipTakesFiveOffEvenAfterTooEasy() {
        let logs = [
            repsLog(id: "ex", reps: [], daysAgo: 1, skipped: true),
            repsLog(id: "ex", reps: [20, 20, 20], daysAgo: 3, difficulty: .tooEasy)
        ]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs).reps, 15)
    }

    func testRecentSkipAtTheFloorSignalsAChainStepDownDatedAtTheSkip() {
        let logs = [
            repsLog(id: "ex", reps: [], daysAgo: 1, skipped: true),
            repsLog(id: "ex", reps: [10, 10, 10], daysAgo: 3)
        ]
        XCTAssertEqual(AdaptiveOverload.floorStepBackDate(for: repsExercise(), recentLogs: logs), date(daysAgo: 1))
    }

    func testTheClimbNeverPassesTheCeiling() {
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [50, 50, 50], daysAgo: 1, difficulty: .tooEasy)])
        XCTAssertEqual(target.reps, AdaptiveOverload.maxReps)
    }

    func testItStillBacksOffFasterThanItClimbs() {
        // One "too hard" day takes five off; a climb of five takes three good days.
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [20, 20, 20], daysAgo: 1, difficulty: .tooHard)]).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(1, reps: 20)).reps, 20)
    }

    // MARK: - Holds and per-side moves

    func testHoldsClimbInFiveSecondSteps() {
        let hold = holdExercise()
        let run = (0..<3).map { holdLog(id: "ex", seconds: [30, 30, 30], daysAgo: 1 + $0, difficulty: .justRight) }
        XCTAssertEqual(AdaptiveOverload.target(for: hold, recentLogs: run).durationSeconds, 35)
        XCTAssertEqual(AdaptiveOverload.target(for: hold, recentLogs: [holdLog(id: "ex", seconds: [30], daysAgo: 1, difficulty: .tooHard)]).durationSeconds, 25)
        XCTAssertEqual(AdaptiveOverload.target(for: hold, recentLogs: [holdLog(id: "ex", seconds: [32], daysAgo: 1)]).durationSeconds, 30,
                       "an old 32-second hold rounds down to 30")
    }

    func testPerSideHoldFollowsTheRulePerSideAndStopsAtTheGridCeiling() {
        let sidePlank = perSideHold()
        let target = AdaptiveOverload.target(for: sidePlank, recentLogs: [holdLog(id: "ex", seconds: [90], daysAgo: 1, difficulty: .tooEasy)])
        XCTAssertEqual(target.durationSeconds, 90, "180 seconds of work a set is 90 a side")
        let climb = AdaptiveOverload.target(for: sidePlank, recentLogs: [holdLog(id: "ex", seconds: [30], daysAgo: 1, difficulty: .tooEasy)])
        XCTAssertEqual(climb.durationSeconds, 35)
    }

    // MARK: - "Couldn't finish" marks

    func testTooHardWithMarksStepsBackOnlyTheMarkedMoves() {
        let a = repsExercise(id: "a"), b = repsExercise(id: "b")
        let logs = [multiLog([("a", 20, true), ("b", 20, nil)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(AdaptiveOverload.target(for: a, recentLogs: logs).reps, 15, "the marked move steps back")
        XCTAssertEqual(AdaptiveOverload.target(for: b, recentLogs: logs).reps, 20, "the unmarked move holds")
    }

    func testAnUnmarkedMoveInAMarkedTooHardSessionDoesNotCountTowardTheClimb() {
        let b = repsExercise(id: "b")
        let logs = [multiLog([("a", 20, true), ("b", 20, nil)], daysAgo: 1, difficulty: .tooHard)]
            + (0..<3).map { multiLog([("b", 20, nil)], daysAgo: 2 + $0, difficulty: .justRight) }
        XCTAssertEqual(AdaptiveOverload.target(for: b, recentLogs: logs).reps, 20,
                       "the held session ends the run, so three older good sessions do not climb it")
        XCTAssertEqual(AdaptiveOverload.signal(for: logs[0].exercises[1], in: logs[0]), .hold)
    }

    func testTooHardWithNothingMarkedStepsEveryMoveBack() {
        let logs = [multiLog([("a", 20, nil), ("b", 15, nil)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(id: "a"), recentLogs: logs).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(id: "b"), recentLogs: logs).reps, 10)
    }

    func testAMarkedMoveAtTheFloorSignalsAChainStepDown() {
        let logs = [multiLog([("a", 10, true), ("b", 10, nil)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertNotNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(id: "a"), recentLogs: logs))
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(id: "b"), recentLogs: logs),
                     "an unmarked move at ten holds rather than stepping down")
    }

    func testOnlyAMoveTheSessionStepsBackIsKeptFromAdvancement() {
        let marked = multiLog([("a", 15, true), ("b", 15, false)], daysAgo: 1, difficulty: .tooHard)
        XCTAssertFalse(marked.countsTowardAdvancement(marked.exercises[0]), "the tapped move never counts")
        XCTAssertTrue(marked.countsTowardAdvancement(marked.exercises[1]), "an untapped move beside it still counts")

        let noneMarked = multiLog([("a", 15, false), ("b", 15, false)], daysAgo: 1, difficulty: .tooHard)
        XCTAssertFalse(noneMarked.exercises.contains { noneMarked.countsTowardAdvancement($0) },
                       "too hard with nothing tapped eases every move, so none counts")

        let beforeTheFollowUp = multiLog([("a", 15, nil), ("b", 15, nil)], daysAgo: 1, difficulty: .tooHard)
        XCTAssertTrue(beforeTheFollowUp.exercises.allSatisfy { beforeTheFollowUp.countsTowardAdvancement($0) },
                      "a log the follow-up never reached counts every worked move, as it always has")
        XCTAssertEqual(AdaptiveOverload.signal(for: beforeTheFollowUp.exercises[0], in: beforeTheFollowUp), .stepBack,
                       "while its too hard still steps every move back")

        var justRight = multiLog([("a", 15, nil)], daysAgo: 1, difficulty: .justRight)
        XCTAssertTrue(justRight.countsTowardAdvancement(justRight.exercises[0]))
        justRight.exercises[0].skipped = true
        XCTAssertFalse(justRight.countsTowardAdvancement(justRight.exercises[0]), "a skip never counts")
    }

    // MARK: - Levers mapped onto five-steps

    func testProgressionRateSetsHowManyGoodSessionsAClimbTakes() {
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 1.0), 3)
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 0.5), 6)
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 0.85), 4)
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 1.15), 3)
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 2.0), 2)
        XCTAssertEqual(AdaptiveOverload.justRightSessionsToClimb(progressionRate: 0.1), 6, "clamped to the rate rail")
        // Monotone: a faster rate never asks for more sessions.
        var previous = Int.max
        for rate in stride(from: 0.5, through: 2.0, by: 0.05) {
            let sessions = AdaptiveOverload.justRightSessionsToClimb(progressionRate: rate)
            XCTAssertLessThanOrEqual(sessions, previous)
            previous = sessions
        }
    }

    func testAFasterRateClimbsSoonerAndAnEasedRateLater() {
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(2, reps: 15), progressionRate: 2.0).reps, 20)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(3, reps: 15), progressionRate: 0.5).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: justRightRun(6, reps: 15), progressionRate: 0.5).reps, 20)
    }

    func testTheRateNeverChangesTheStepSizeOrTheBackOff() {
        let tooEasy = [repsLog(id: "ex", reps: [15, 15, 15], daysAgo: 1, difficulty: .tooEasy)]
        let tooHard = [repsLog(id: "ex", reps: [20, 20, 20], daysAgo: 1, difficulty: .tooHard)]
        for rate in [0.5, 1.0, 2.0] {
            XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: tooEasy, progressionRate: rate).reps, 20)
            XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: tooHard, progressionRate: rate).reps, 15)
        }
    }

    func testReentryScaleHoldsTheTargetAtLeastOneStepBelowOnTheGrid() {
        let logs = [repsLog(id: "ex", reps: [20, 20, 20], daysAgo: 1)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, reentryScale: 0.9).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, reentryScale: 0.7).reps, 10)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, reentryScale: 1.0).reps, 20)
        let deep = [repsLog(id: "ex", reps: [40, 40, 40], daysAgo: 1)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: deep, reentryScale: 0.7).reps, 25)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: deep, reentryScale: 0.9).reps, 35)
    }

    func testReentryScaleNeverGoesBelowTheFloorOrTouchesADefault() {
        let logs = [repsLog(id: "ex", reps: [10, 10, 10], daysAgo: 1)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, reentryScale: 0.7).reps, 10)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(defaultReps: 15), recentLogs: [], reentryScale: 0.7).reps, 15)
    }

    func testStartSeedScalesTheGridDefaultToTheNearestGridNumber() {
        let squat = repsExercise(defaultReps: 15)
        XCTAssertEqual(AdaptiveOverload.target(for: squat, recentLogs: [], startingRepMultiplier: 1.0).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: squat, recentLogs: [], startingRepMultiplier: 1.15).reps, 15)
        XCTAssertEqual(AdaptiveOverload.target(for: squat, recentLogs: [], startingRepMultiplier: 1.30).reps, 20)
        let hold = holdExercise(defaultDurationSeconds: 30)
        XCTAssertEqual(AdaptiveOverload.target(for: hold, recentLogs: [], startingRepMultiplier: 1.15).durationSeconds, 35)
        XCTAssertEqual(AdaptiveOverload.target(for: hold, recentLogs: [], startingRepMultiplier: 1.30).durationSeconds, 40)
        // A larger multiplier never serves less.
        for base in [10, 15, 20, 30] {
            let low = AdaptiveOverload.target(for: repsExercise(defaultReps: base), recentLogs: [], startingRepMultiplier: 1.0).reps!
            let high = AdaptiveOverload.target(for: repsExercise(defaultReps: base), recentLogs: [], startingRepMultiplier: 1.30).reps!
            XCTAssertGreaterThanOrEqual(high, low)
        }
    }

    func testStartSeedNeverTouchesACapacityDerivedTarget() {
        let logs = [repsLog(id: "ex", reps: [15, 15, 15], daysAgo: 1)]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs, startingRepMultiplier: 1.30, startingSets: 4).reps, 15)
    }

    // MARK: - Sets and determinism

    func testSetCountTracksDemonstratedSets() {
        let target = AdaptiveOverload.target(for: repsExercise(), recentLogs: [repsLog(id: "ex", reps: [15, 15], daysAgo: 1)])
        XCTAssertEqual(target.sets, 2)
    }

    func testUsesMostRecentUsablePerformance() {
        let logs = [
            repsLog(id: "ex", reps: [25, 25, 25], daysAgo: 1, difficulty: .tooEasy),
            repsLog(id: "ex", reps: [10, 10, 10], daysAgo: 8, difficulty: .tooEasy)
        ]
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs).reps, 30)
    }

    func testTargetIsDeterministic() {
        let logs = [repsLog(id: "ex", reps: [11, 13, 12], daysAgo: 2, difficulty: .tooEasy)]
        let first = AdaptiveOverload.target(for: repsExercise(), recentLogs: logs)
        for _ in 0..<50 {
            XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), recentLogs: logs), first)
        }
    }

    // MARK: - Real bundled library (PRD validation)

    /// The PRD's validation case over the real library: last log 3x15 bodyweight squats marked
    /// `too_hard` -> the next squat target steps back to 10, computed from capacity.
    func testPRDValidationEasesSquatsMarkedTooHard() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })
        let logs = [repsLog(id: squat.id, reps: [15, 15, 15], daysAgo: 1, difficulty: .tooHard)]

        let target = AdaptiveOverload.target(for: squat, recentLogs: logs)
        XCTAssertEqual(target.sets, 3)
        XCTAssertEqual(target.reps, 10)
    }

    /// A fresh user gets the real squat's own (round) default, never a heroic constant.
    func testPRDFreshUserGetsSquatDefaultOverRealLibrary() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })

        let target = AdaptiveOverload.target(for: squat, recentLogs: [])
        XCTAssertEqual(target.reps, 15)
        XCTAssertEqual(target.sets, AdaptiveOverload.defaultSets)
    }

    /// Every catalog movement's no-history target sits on the grid: reps and training holds a multiple
    /// of five from ten, at every Start Seed level.
    func testEveryCatalogDefaultLandsOnTheGrid() async throws {
        let library = try await MockExerciseService().exercises()
        for exercise in library {
            for multiplier in [1.0, 1.15, 1.30] {
                let target = AdaptiveOverload.target(for: exercise, recentLogs: [], startingRepMultiplier: multiplier)
                let value = try XCTUnwrap(exercise.isHold ? target.durationSeconds : target.reps)
                XCTAssertEqual(value % 5, 0, "\(exercise.id) x\(multiplier) -> \(value)")
                XCTAssertGreaterThanOrEqual(value, 10, exercise.id)
            }
        }
    }
}
