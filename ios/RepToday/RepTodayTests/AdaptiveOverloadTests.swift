import XCTest
@testable import RepToday

/// Tests pipeline Step 6 of the deterministic engine (US-C06, US-TD03): turning a chosen rung into four
/// sets at the user's Earned Reps, on the grid of five (ADR-0011), inside the level's earned range.
///
/// Coverage: a new move opens at the bottom of the range whatever its catalog default; a log written
/// before Training Days is read as earned = its smallest set; the climb (one step after each session at
/// or above Earned Reps that was not rated too hard, "too easy" a step at once, "too hard" or a skip a
/// step off, the top of the range holds); the floor step-back signal Step 5 reads; holds and per-side
/// moves inside their own ranges; the completion screen's "couldn't finish" marks; Practice stations and
/// held Return sessions never read as earned; and the three levers (`progressionRate`, the Re-entry Ramp
/// scale, the cold-start multiplier). The last tests run the PRD's validation cases over the real library.
final class AdaptiveOverloadTests: XCTestCase {

    // MARK: - Fixtures

    private func date(daysAgo: Int) -> Date { TrainingDayFixtures.date(daysAgo: daysAgo) }

    /// A rep-based exercise with the given catalog default; everything else is filler the step ignores.
    private func repsExercise(id: String = "ex", defaultReps: Int = 10) -> Exercise {
        exercise(id: id, isHold: false, defaultReps: defaultReps, defaultDurationSeconds: nil)
    }

    /// A hold exercise with the given catalog default duration.
    private func holdExercise(id: String = "ex", defaultDurationSeconds: Int = 20) -> Exercise {
        exercise(id: id, isHold: true, defaultReps: nil, defaultDurationSeconds: defaultDurationSeconds)
    }

    /// A rep-based exercise counted per side.
    private func perSideReps(id: String = "ex") -> Exercise {
        var exercise = repsExercise(id: id, defaultReps: 8)
        exercise.isPerSide = true
        return exercise
    }

    /// A hold counted per side.
    private func perSideHold(id: String = "ex") -> Exercise {
        var exercise = holdExercise(id: id, defaultDurationSeconds: 30)
        exercise.isPerSide = true
        return exercise
    }

    private func exercise(id: String, isHold: Bool, defaultReps: Int?, defaultDurationSeconds: Int?) -> Exercise {
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
            advancementCriteria: "4 clean sets at the top of your rep range",
            apartmentFriendly: true
        )
    }

    /// A Training Day session `daysAgo` with one main station on `id`: four sets at `value` (reps, or
    /// seconds for a hold), recording `earned` (defaulting to `value`).
    private func session(
        _ id: String = "ex",
        value: Int,
        earned: Int? = nil,
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = .justRight,
        isHold: Bool = false,
        role: StationRole = .main
    ) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station(id, pattern: .squat, role: role, value: value, earned: earned ?? value, isHold: isHold)],
            completedAt: date(daysAgo: daysAgo),
            difficulty: difficulty
        )
    }

    /// A session `daysAgo` that skipped `id`.
    private func skip(_ id: String = "ex", daysAgo: Int) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station(id, pattern: .squat, skipped: true)],
            completedAt: date(daysAgo: daysAgo),
            difficulty: nil
        )
    }

    /// A log written before Training Days: no role, no Earned Reps, the given per-set reps.
    private func legacy(
        _ id: String = "ex",
        reps: [Int],
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = nil,
        wasReturn: Bool = false
    ) -> WorkoutLog {
        var log = TrainingDayFixtures.log(
            [LoggedExercise(
                id: UUID(),
                exerciseId: id,
                pillar: .strength,
                movementPattern: .squat,
                completedSets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
                skipped: false
            )],
            completedAt: date(daysAgo: daysAgo),
            difficulty: difficulty
        )
        log.wasReturn = wasReturn
        return log
    }

    /// A session `daysAgo` rated `difficulty` that worked several moves at their Earned Reps, each
    /// `(id, reps, couldNotFinish)`.
    private func multiLog(
        _ moves: [(id: String, reps: Int, couldNotFinish: Bool?)],
        daysAgo: Int,
        difficulty: PerceivedDifficulty?
    ) -> WorkoutLog {
        TrainingDayFixtures.log(
            moves.map { move in
                TrainingDayFixtures.station(move.id, pattern: .squat, value: move.reps, earned: move.reps, couldNotFinish: move.couldNotFinish)
            },
            completedAt: date(daysAgo: daysAgo),
            difficulty: difficulty
        )
    }

    private func earned(
        _ exercise: Exercise,
        _ logs: [WorkoutLog],
        level: FitnessLevel = .beginner,
        progressionRate: Double = AdaptiveOverload.neutralProgressionRate
    ) -> Int {
        AdaptiveOverload.earned(for: exercise, level: level, recentLogs: logs, progressionRate: progressionRate)
    }

    private func served(
        _ exercise: Exercise,
        _ logs: [WorkoutLog],
        level: FitnessLevel = .beginner,
        reentryScale: Double = AdaptiveOverload.neutralReentryScale,
        startingRepMultiplier: Double = AdaptiveOverload.neutralStartingRepMultiplier
    ) -> Int {
        AdaptiveOverload.target(
            for: exercise,
            level: level,
            recentLogs: logs,
            reentryScale: reentryScale,
            startingRepMultiplier: startingRepMultiplier
        ).value
    }

    // MARK: - No history -> the bottom of the range

    func testANewMoveOpensAtTheBottomOfTheRangeWhateverItsDefault() {
        for level in FitnessLevel.allCases {
            for defaultReps in [3, 12, 40] {
                let target = AdaptiveOverload.target(for: repsExercise(defaultReps: defaultReps), level: level, recentLogs: [])
                XCTAssertEqual(target.reps, 15, "\(level), default \(defaultReps)")
                XCTAssertEqual(target.earned, 15)
                XCTAssertNil(target.durationSeconds)
                XCTAssertEqual(target.sets, RepGrammar.setsPerStation)
            }
            for defaultSeconds in [8, 45] {
                let target = AdaptiveOverload.target(for: holdExercise(defaultDurationSeconds: defaultSeconds), level: level, recentLogs: [])
                XCTAssertEqual(target.durationSeconds, 20, "\(level), default \(defaultSeconds)s")
                XCTAssertNil(target.reps)
            }
            XCTAssertEqual(served(perSideReps(), [], level: level), 5, "reps per side open at 5")
        }
    }

    func testAMoveWithNoUsableSetsOpensAtTheBottomOfTheRange() {
        XCTAssertEqual(served(repsExercise(), [legacy(reps: [0, 0], daysAgo: 1)]), 15)
    }

    // MARK: - Logs written before Training Days

    /// An older log recorded no Earned Reps; it recorded earned = performed, so its smallest completed set
    /// is read as earned, floored onto the grid and held inside the range.
    func testALegacyLogReadsEarnedAsItsSmallestSetOnTheGrid() {
        // 20 earned (the smallest set), performed at or above it: one step up.
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [25, 20, 22], daysAgo: 1)]), 25)
        // 22 floors to 20, and the session reached it: one step up.
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [22, 22, 22], daysAgo: 1)]), 25)
        // 13 floors to 10, below the range, so it reads as 15; "too easy" adds a step.
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [13, 13, 13], daysAgo: 1, difficulty: .tooEasy)]), 20)
        // 14 reads as 15 but never reached it, so it holds there.
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [14, 14, 14], daysAgo: 1)]), 15)
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [6, 6, 6], daysAgo: 1)]), 15)
        // 50 is above a beginner's range, so it holds at the top; an advanced range reaches 50.
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [50, 50, 50], daysAgo: 1)]), 30)
        XCTAssertEqual(earned(repsExercise(), [legacy(reps: [50, 50, 50], daysAgo: 1)], level: .advanced), 50)
    }

    func testEarnedRepsAndTheServedNumberAlwaysSitOnTheGridInsideTheRange() {
        for level in FitnessLevel.allCases {
            for exercise in [repsExercise(), perSideReps(), holdExercise(), perSideHold()] {
                let range = RepGrammar.earnedRange(for: exercise, level: level)
                for value in 0...80 {
                    for difficulty in [nil, PerceivedDifficulty.tooEasy, .tooHard] {
                        let log = TrainingDayFixtures.log(
                            [TrainingDayFixtures.station("ex", pattern: .squat, role: nil, value: value, isHold: exercise.isHold)],
                            completedAt: date(daysAgo: 1),
                            difficulty: difficulty
                        )
                        let target = AdaptiveOverload.target(for: exercise, level: level, recentLogs: [log])
                        XCTAssertEqual(target.earned % RepGrammar.step, 0)
                        XCTAssertTrue(range.contains(target.earned), "\(level) \(value) -> earned \(target.earned)")
                        XCTAssertEqual(target.value % RepGrammar.step, 0)
                        XCTAssertTrue(range.contains(target.value), "\(level) \(value) -> served \(target.value)")
                    }
                }
            }
        }
    }

    // MARK: - The climb

    /// Doing what is prescribed, session after session, climbs one step each time until the top of the
    /// level's range - and the first session at the top is the one that clears the rung.
    func testEachSessionAtEarnedRepsClimbsOneStepToTheTopOfTheRange() {
        let exercise = repsExercise()
        for level in FitnessLevel.allCases {
            let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
            var logs: [WorkoutLog] = []
            var servedSequence: [Int] = []
            for index in 0..<10 {
                XCTAssertEqual(RepGrammar.hasCleared(exercise, in: logs, level: level), servedSequence.contains(top),
                               "\(level): only a session at the top clears the rung")
                let target = AdaptiveOverload.target(for: exercise, level: level, recentLogs: logs)
                servedSequence.append(target.value)
                logs.append(session(value: target.value, earned: target.earned, daysAgo: 20 - index))
            }
            let climb = Array(stride(from: 15, through: top, by: RepGrammar.step))
            XCTAssertEqual(Array(servedSequence.prefix(climb.count)), climb, "\(level)")
            XCTAssertTrue(servedSequence.dropFirst(climb.count).allSatisfy { $0 == top }, "\(level) holds at the top")
            XCTAssertTrue(RepGrammar.hasCleared(exercise, in: logs, level: level), "\(level) clears at the top")
        }
    }

    func testAnUnratedSessionClimbsLikeJustRight() {
        XCTAssertEqual(earned(repsExercise(), [session(value: 20, daysAgo: 1, difficulty: nil)]), 25)
    }

    func testTooEasyAddsAStepAtOnceEvenFromAShortSession() {
        XCTAssertEqual(earned(repsExercise(), [session(value: 20, daysAgo: 1, difficulty: .tooEasy)]), 25)
        XCTAssertEqual(earned(repsExercise(), [session(value: 10, earned: 20, daysAgo: 1, difficulty: .tooEasy)]), 25,
                       "too easy climbs even when a short session served under Earned Reps")
    }

    func testTooHardTakesAStepOff() {
        XCTAssertEqual(earned(repsExercise(), [session(value: 25, daysAgo: 1, difficulty: .tooHard)]), 20)
    }

    func testTooHardAtTheBottomHoldsAndSignalsAChainStepDown() {
        let logs = [session(value: 15, daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(earned(repsExercise(), logs), 15)
        XCTAssertEqual(AdaptiveOverload.floorStepBackDate(for: repsExercise(), level: .beginner, recentLogs: logs), date(daysAgo: 1))

        let holdLogs = [session(value: 20, daysAgo: 1, difficulty: .tooHard, isHold: true)]
        XCTAssertEqual(earned(holdExercise(), holdLogs), 20)
        XCTAssertEqual(AdaptiveOverload.floorStepBackDate(for: holdExercise(), level: .beginner, recentLogs: holdLogs), date(daysAgo: 1))
    }

    func testAStepBackAboveTheBottomDoesNotSignalAChainStepDown() {
        let tooHard = [session(value: 20, daysAgo: 1, difficulty: .tooHard)]
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(), level: .beginner, recentLogs: tooHard))
        let justRight = [session(value: 15, daysAgo: 1)]
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(), level: .beginner, recentLogs: justRight))
    }

    func testARecentSkipStepsBackEvenAfterTooEasy() {
        let logs = [skip(daysAgo: 1), session(value: 20, daysAgo: 3, difficulty: .tooEasy)]
        XCTAssertEqual(earned(repsExercise(), logs), 15)
    }

    func testARecentSkipAtTheBottomSignalsAChainStepDownDatedAtTheSkip() {
        let logs = [skip(daysAgo: 1), session(value: 15, daysAgo: 3)]
        XCTAssertEqual(AdaptiveOverload.floorStepBackDate(for: repsExercise(), level: .beginner, recentLogs: logs), date(daysAgo: 1))
    }

    func testTheClimbStopsAtTheTopOfTheLevelsRange() {
        let atThirty = [session(value: 30, daysAgo: 1, difficulty: .tooEasy)]
        XCTAssertEqual(earned(repsExercise(), atThirty, level: .beginner), 30)
        XCTAssertEqual(earned(repsExercise(), atThirty, level: .intermediate), 30)
        XCTAssertEqual(earned(repsExercise(), atThirty, level: .advanced), 35, "the advanced range runs to 50")
        XCTAssertEqual(earned(repsExercise(), [session(value: 50, daysAgo: 1, difficulty: .tooEasy)], level: .advanced), 50)
    }

    // MARK: - Holds and per-side moves

    func testHoldsClimbInFiveSecondStepsInsideTheirRange() {
        let hold = holdExercise()
        XCTAssertEqual(earned(hold, [session(value: 30, daysAgo: 1, isHold: true)]), 35)
        XCTAssertEqual(earned(hold, [session(value: 30, daysAgo: 1, difficulty: .tooHard, isHold: true)]), 25)
        XCTAssertEqual(earned(hold, [session(value: 60, daysAgo: 1, difficulty: .tooEasy, isHold: true)]), 60)
        XCTAssertEqual(earned(hold, [session(value: 60, daysAgo: 1, difficulty: .tooEasy, isHold: true)], level: .advanced), 65,
                       "an advanced hold runs to 90 seconds")
    }

    func testPerSideMovesClimbInsideTheirOwnRange() {
        let reps = perSideReps()
        XCTAssertEqual(earned(reps, [session(value: 10, daysAgo: 1)]), 15)
        XCTAssertEqual(earned(reps, [session(value: 15, daysAgo: 1, difficulty: .tooEasy)], level: .advanced), 15,
                       "reps per side top out at 15 at every level")
        let atBottom = [session(value: 5, daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(earned(reps, atBottom), 5)
        XCTAssertNotNil(AdaptiveOverload.floorStepBackDate(for: reps, level: .beginner, recentLogs: atBottom))

        // A per-side hold is a hold: the seconds are per side, inside the hold range.
        let sidePlank = perSideHold()
        XCTAssertEqual(served(sidePlank, []), 20)
        XCTAssertEqual(earned(sidePlank, [session(value: 60, daysAgo: 1, difficulty: .tooEasy, isHold: true)]), 60)
    }

    // MARK: - "Couldn't finish" marks

    func testTooHardWithMarksStepsBackOnlyTheMarkedMoves() {
        let logs = [multiLog([("a", 20, true), ("b", 20, false)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(earned(repsExercise(id: "a"), logs), 15, "the marked move steps back")
        XCTAssertEqual(earned(repsExercise(id: "b"), logs), 20, "the unmarked move holds")
    }

    func testAnUnmarkedMoveInAMarkedTooHardSessionDoesNotClimb() {
        let b = repsExercise(id: "b")
        let logs = [multiLog([("a", 20, true), ("b", 20, false)], daysAgo: 1, difficulty: .tooHard)]
            + (0..<3).map { multiLog([("b", 20, nil)], daysAgo: 2 + $0, difficulty: .justRight) }
        XCTAssertEqual(AdaptiveOverload.signal(for: logs[0].exercises[1], in: logs[0]), .hold)
        for rate in [0.5, 1.0, 2.0] {
            XCTAssertEqual(earned(b, logs, progressionRate: rate), 20,
                           "the held session is the newest signal, so older good sessions do not climb it")
        }
    }

    func testTooHardWithNothingMarkedStepsEveryMoveBack() {
        let logs = [multiLog([("a", 20, nil), ("b", 25, nil)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(earned(repsExercise(id: "a"), logs), 15)
        XCTAssertEqual(earned(repsExercise(id: "b"), logs), 20)
    }

    func testAMarkedMoveAtTheBottomSignalsAChainStepDown() {
        let logs = [multiLog([("a", 15, true), ("b", 15, false)], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertNotNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(id: "a"), level: .beginner, recentLogs: logs))
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: repsExercise(id: "b"), level: .beginner, recentLogs: logs),
                     "an unmarked move at the bottom holds rather than stepping down")
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
                      "a log the follow-up never reached counts every worked move")
        XCTAssertEqual(AdaptiveOverload.signal(for: beforeTheFollowUp.exercises[0], in: beforeTheFollowUp), .stepBack,
                       "while its too hard still steps every move back")

        var justRight = multiLog([("a", 15, nil)], daysAgo: 1, difficulty: .justRight)
        XCTAssertTrue(justRight.countsTowardAdvancement(justRight.exercises[0]))
        justRight.exercises[0].role = .practice
        XCTAssertFalse(justRight.countsTowardAdvancement(justRight.exercises[0]), "a Practice station never counts")
        justRight.exercises[0].role = .main
        justRight.exercises[0].skipped = true
        XCTAssertFalse(justRight.countsTowardAdvancement(justRight.exercises[0]), "a skip never counts")
    }

    // MARK: - What is never read as earned

    func testAPracticeStationOfTheSameMoveIsIgnored() {
        let logs = [
            session(value: 10, earned: nil, daysAgo: 1, difficulty: .tooHard, role: .practice),
            session(value: 20, daysAgo: 3),
        ]
        XCTAssertEqual(earned(repsExercise(), logs), 25, "the newer Practice station neither steps back nor resets the move")
    }

    /// A legacy log held by a Return or its Re-entry Ramp logged what the Return served, not what the user
    /// earned, so it is skipped; a held log that records its Earned Reps is read as usual.
    func testALegacyLogHeldByAReturnIsNotReadAsEarned() {
        let capacity = legacy(reps: [25, 25, 25], daysAgo: 10)
        let heldReturn = legacy(reps: [10, 10, 10], daysAgo: 3, wasReturn: true)
        XCTAssertEqual(earned(repsExercise(), [heldReturn, capacity]), 30, "read from the session before the Return")

        let unheld = legacy(reps: [10, 10, 10], daysAgo: 3)
        XCTAssertEqual(earned(repsExercise(), [unheld, capacity]), 15, "the same numbers outside a Return are capacity")

        var recordsEarned = session(value: 10, earned: 25, daysAgo: 3)
        recordsEarned.wasReturn = true
        XCTAssertEqual(earned(repsExercise(), [recordsEarned, capacity]), 25,
                       "a held session that recorded Earned Reps keeps them, without climbing on the held number")
    }

    /// A move the user was stepped down onto opens at the bottom of the range and reads only the sessions
    /// after the step down, never an old clear of the easier rung - and never a cold-start lift.
    func testASteppedDownMoveReadsOnlyTheSessionsAfterTheStepDown() {
        let old = session(value: 30, daysAgo: 6)
        let since = date(daysAgo: 4)
        XCTAssertEqual(
            AdaptiveOverload.earned(for: repsExercise(), level: .beginner, recentLogs: [old], steppedDownSince: since, startingRepMultiplier: 1.30),
            15
        )
        let after = session(value: 15, daysAgo: 2)
        XCTAssertEqual(
            AdaptiveOverload.earned(for: repsExercise(), level: .beginner, recentLogs: [after, old], steppedDownSince: since),
            20
        )
    }

    // MARK: - progressionRate

    func testProgressionRateSetsHowManyQualifyingSessionsAClimbTakes() {
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 1.0), 1)
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 0.5), 2)
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 0.85), 2)
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 1.15), 1)
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 2.0), 1)
        XCTAssertEqual(AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: 0.1), 2, "clamped to the rate rail")
        // Monotone: a faster rate never asks for more sessions.
        var previous = Int.max
        for rate in stride(from: 0.5, through: 2.0, by: 0.05) {
            let sessions = AdaptiveOverload.qualifyingSessionsToClimb(progressionRate: rate)
            XCTAssertLessThanOrEqual(sessions, previous)
            previous = sessions
        }
    }

    /// At a slower pace the climb needs a run of qualifying sessions at one Earned Reps number: a session
    /// that served under Earned Reps breaks the run, and so does a session at a different number.
    func testASlowerPaceClimbsOnlyAfterARunAtOneNumber() {
        let slow = 0.5
        let run = [session(value: 20, daysAgo: 1), session(value: 20, daysAgo: 2)]
        XCTAssertEqual(earned(repsExercise(), run, progressionRate: slow), 25)

        let broken = [session(value: 20, daysAgo: 1), session(value: 10, earned: 20, daysAgo: 2), session(value: 20, daysAgo: 3)]
        XCTAssertEqual(earned(repsExercise(), broken, progressionRate: slow), 20, "a short session breaks the run")

        let afterAClimb = [session(value: 20, daysAgo: 1), session(value: 15, daysAgo: 2)]
        XCTAssertEqual(earned(repsExercise(), afterAClimb, progressionRate: slow), 20, "the run counts only sessions at 20")

        XCTAssertEqual(earned(repsExercise(), [session(value: 20, daysAgo: 1)], progressionRate: 2.0), 25,
                       "a faster pace never climbs later than the neutral one")
    }

    func testTheRateNeverChangesTheStepSizeOrTheBackOff() {
        let tooEasy = [session(value: 15, daysAgo: 1, difficulty: .tooEasy)]
        let tooHard = [session(value: 20, daysAgo: 1, difficulty: .tooHard)]
        for rate in [0.5, 1.0, 2.0] {
            XCTAssertEqual(earned(repsExercise(), tooEasy, progressionRate: rate), 20)
            XCTAssertEqual(earned(repsExercise(), tooHard, progressionRate: rate), 15)
        }
    }

    // MARK: - Return / Re-entry Ramp scale

    /// A Return or ramp session serves at least one step under Earned Reps, scaled and floored onto the
    /// grid, while the Earned Reps it records stay where they are.
    func testReentryScaleHoldsTheServedNumberUnderEarnedReps() {
        let logs = [session(value: 15, daysAgo: 1)] // earns 20
        for (scale, expected) in [(1.0, 20), (0.9, 15), (0.7, 10)] {
            let target = AdaptiveOverload.target(for: repsExercise(), level: .beginner, recentLogs: logs, reentryScale: scale)
            XCTAssertEqual(target.reps, expected, "scale \(scale)")
            XCTAssertEqual(target.earned, 20, "scale \(scale) never moves Earned Reps")
        }
        let deep = [session(value: 35, daysAgo: 1)] // earns 40 at the advanced level
        XCTAssertEqual(served(repsExercise(), deep, level: .advanced, reentryScale: 0.7), 25)
        XCTAssertEqual(served(repsExercise(), deep, level: .advanced, reentryScale: 0.9), 35)
        XCTAssertEqual(served(repsExercise(), [session(value: 25, daysAgo: 1)], reentryScale: 0.99), 25,
                       "any scale under neutral serves at least a step under the 30 earned")
    }

    func testReentryScaleNeverServesBelowTheShortSessionFloor() {
        XCTAssertEqual(served(repsExercise(), [], reentryScale: 0.5), RepGrammar.shortSessionFloor(for: .reps))
        XCTAssertEqual(served(perSideReps(), [], reentryScale: 0.5), RepGrammar.shortSessionFloor(for: .repsPerSide))
        XCTAssertEqual(served(holdExercise(), [], reentryScale: 0.5), RepGrammar.shortSessionFloor(for: .hold))
        XCTAssertEqual(served(repsExercise(), [], reentryScale: 0), RepGrammar.shortSessionFloor(for: .reps))
    }

    // MARK: - Cold-start multiplier

    func testAColdStartMultiplierLiftsTheOpeningNumberOntoTheNearestGridNumber() {
        XCTAssertEqual(served(repsExercise(), [], startingRepMultiplier: 1.0), 15)
        XCTAssertEqual(served(repsExercise(), [], startingRepMultiplier: 1.15), 15, "17.25 lands on 15")
        XCTAssertEqual(served(repsExercise(), [], startingRepMultiplier: 1.30), 20, "19.5 lands on 20")
        XCTAssertEqual(served(holdExercise(), [], startingRepMultiplier: 1.15), 25, "23 seconds lands on 25")
        XCTAssertEqual(served(holdExercise(), [], startingRepMultiplier: 1.30), 25, "26 seconds lands on 25")
        XCTAssertEqual(served(perSideReps(), [], startingRepMultiplier: 1.30), 5, "6.5 a side lands on 5")
        // A larger multiplier never serves less.
        for exercise in [repsExercise(), holdExercise(), perSideReps()] {
            var previous = 0
            for multiplier in stride(from: 1.0, through: 3.0, by: 0.05) {
                let value = served(exercise, [], startingRepMultiplier: multiplier)
                XCTAssertGreaterThanOrEqual(value, previous)
                previous = value
            }
        }
    }

    /// The lifted opening number stays at least one step under the top of the range, so a seeded first
    /// session can never clear the rung, and never drops under the bottom.
    func testAColdStartMultiplierNeverLiftsTheOpeningNumberToTheTop() {
        XCTAssertEqual(served(repsExercise(), [], level: .beginner, startingRepMultiplier: 3.0), 25)
        XCTAssertEqual(served(repsExercise(), [], level: .advanced, startingRepMultiplier: 3.0), 45)
        XCTAssertEqual(served(repsExercise(), [], level: .advanced, startingRepMultiplier: 9.0), 45)
        XCTAssertEqual(served(holdExercise(), [], level: .beginner, startingRepMultiplier: 3.0), 55)
        XCTAssertEqual(served(perSideReps(), [], startingRepMultiplier: 3.0), 10)
        XCTAssertEqual(served(repsExercise(), [], startingRepMultiplier: 0.5), 15, "never under the bottom of the range")
    }

    func testAColdStartMultiplierNeverTouchesAnEarnedNumber() {
        let logs = [session(value: 15, daysAgo: 1)]
        XCTAssertEqual(served(repsExercise(), logs, startingRepMultiplier: 1.30), served(repsExercise(), logs))
        XCTAssertEqual(served(repsExercise(), logs, startingRepMultiplier: 1.30), 20)
    }

    // MARK: - Sets and determinism

    func testEveryTargetRunsFourSets() {
        let twoSets = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("ex", pattern: .squat, value: 20, earned: 20, sets: 2)],
            completedAt: date(daysAgo: 1)
        )
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), level: .beginner, recentLogs: [twoSets]).sets, 4)
        XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), level: .beginner, recentLogs: [legacy(reps: [15, 15, 15], daysAgo: 1)]).sets, 4)
        XCTAssertEqual(AdaptiveOverload.target(for: holdExercise(), level: .advanced, recentLogs: [], reentryScale: 0.7).sets, 4)
    }

    func testTheNewestSessionDecides() {
        let logs = [
            session(value: 25, daysAgo: 1, difficulty: .tooEasy),
            session(value: 15, daysAgo: 8, difficulty: .tooEasy),
        ]
        XCTAssertEqual(earned(repsExercise(), logs), 30)
    }

    func testTargetIsDeterministic() {
        let logs = [legacy(reps: [21, 23, 22], daysAgo: 2, difficulty: .tooEasy)]
        let first = AdaptiveOverload.target(for: repsExercise(), level: .intermediate, recentLogs: logs)
        for _ in 0..<50 {
            XCTAssertEqual(AdaptiveOverload.target(for: repsExercise(), level: .intermediate, recentLogs: logs), first)
        }
    }

    // MARK: - Real bundled library (PRD validation)

    /// The PRD's validation case over the real library: squats rated too hard step back a step; at the
    /// bottom of the range the reps hold and the chain steps down a rung instead.
    func testPRDValidationEasesSquatsMarkedTooHard() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })

        let tooHard = [TrainingDayFixtures.log(
            [TrainingDayFixtures.station(squat.id, pattern: .squat, value: 20, earned: 20)],
            completedAt: date(daysAgo: 1),
            difficulty: .tooHard
        )]
        let target = AdaptiveOverload.target(for: squat, level: .beginner, recentLogs: tooHard)
        XCTAssertEqual(target.sets, 4)
        XCTAssertEqual(target.reps, 15)

        let legacyAtBottom = [legacy(squat.id, reps: [15, 15, 15], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(AdaptiveOverload.target(for: squat, level: .beginner, recentLogs: legacyAtBottom).reps, 15)
        XCTAssertNotNil(AdaptiveOverload.floorStepBackDate(for: squat, level: .beginner, recentLogs: legacyAtBottom))
    }

    /// A fresh user's real squat opens at the bottom of the range, never a heroic constant.
    func testPRDFreshUserGetsTheBottomOfTheRangeOverRealLibrary() async throws {
        let library = try await MockExerciseService().exercises()
        let squat = try XCTUnwrap(library.first { $0.id == "squat_bodyweight" })
        for level in FitnessLevel.allCases {
            let target = AdaptiveOverload.target(for: squat, level: level, recentLogs: [])
            XCTAssertEqual(target.reps, 15)
            XCTAssertEqual(target.sets, 4)
        }
    }

    /// Every catalog movement's opening number sits on the grid inside its range and under the top, at
    /// every level and every Start Seed multiplier, so no first session clears a rung.
    func testEveryCatalogOpeningNumberSitsOnTheGridUnderTheTop() async throws {
        let library = try await MockExerciseService().exercises()
        for exercise in library {
            for level in FitnessLevel.allCases {
                let range = RepGrammar.earnedRange(for: exercise, level: level)
                for multiplier in [1.0, 1.15, 1.30] {
                    let value = served(exercise, [], level: level, startingRepMultiplier: multiplier)
                    XCTAssertEqual(value % RepGrammar.step, 0, "\(exercise.id) x\(multiplier) -> \(value)")
                    XCTAssertTrue(range.contains(value), "\(exercise.id) \(level) x\(multiplier) -> \(value)")
                    XCTAssertLessThan(value, range.upperBound, "\(exercise.id) \(level) x\(multiplier) opens at the top")
                }
            }
        }
    }
}
