import XCTest
@testable import RepToday

/// US-TD02 / US-TD03: the one owner of the set grammar (`RepGrammar`), Earned Reps (`AdaptiveOverload`),
/// and the guarantee that Padding and Practice never move progression.
final class RepGrammarTests: XCTestCase {

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func exercise(_ id: String) -> Exercise {
        library.first { $0.id == id }!
    }

    private func date(_ daysAgo: Int) -> Date { TrainingDayFixtures.date(daysAgo: daysAgo) }

    // MARK: Grammar

    func testRangesStepsFloorsAndPracticeValuesFollowDecisions9To16() {
        XCTAssertEqual(RepGrammar.setsPerStation, 4)
        XCTAssertEqual(RepGrammar.step, 5)
        XCTAssertEqual(RepGrammar.earnedRange(for: .reps, level: .beginner), 15...30)
        XCTAssertEqual(RepGrammar.earnedRange(for: .reps, level: .intermediate), 15...30)
        XCTAssertEqual(RepGrammar.earnedRange(for: .reps, level: .advanced), 15...50)
        for level in FitnessLevel.allCases {
            XCTAssertEqual(RepGrammar.earnedRange(for: .repsPerSide, level: level), 5...15)
        }
        XCTAssertEqual(RepGrammar.earnedRange(for: .hold, level: .beginner), 20...60)
        XCTAssertEqual(RepGrammar.earnedRange(for: .hold, level: .advanced), 20...90)
        XCTAssertEqual(RepGrammar.shortSessionFloor(for: .reps), 10)
        XCTAssertEqual(RepGrammar.shortSessionFloor(for: .repsPerSide), 5)
        XCTAssertEqual(RepGrammar.practiceValue(for: .reps), 10)
        XCTAssertEqual(RepGrammar.practiceValue(for: .repsPerSide), 5)
        XCTAssertEqual(RepGrammar.practiceValue(for: .hold), 15)
    }

    func testEarnedRepsAreServedFlooredOntoTheGridInsideTheRange() {
        XCTAssertEqual(RepGrammar.served(earned: 13, for: .reps, level: .beginner), 15)
        XCTAssertEqual(RepGrammar.served(earned: 23, for: .reps, level: .beginner), 20)
        XCTAssertEqual(RepGrammar.served(earned: 45, for: .reps, level: .intermediate), 30)
        XCTAssertEqual(RepGrammar.served(earned: 45, for: .reps, level: .advanced), 45)
        XCTAssertEqual(RepGrammar.served(earned: 12, for: .repsPerSide, level: .beginner), 10)
    }

    func testEveryStrengthMovementStatesTheOneAdvancementBar() {
        for exercise in library where exercise.pillar == .strength {
            XCTAssertTrue(
                exercise.advancementCriteria.hasPrefix("4 clean"),
                "\(exercise.id) states \"\(exercise.advancementCriteria)\""
            )
        }
    }

    // MARK: Advancement (decision 15)

    func testFourCleanSetsAtTheTopAtEarnedRepsClearARung() {
        let push = exercise("push_standard")
        let cleared = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 30)],
            completedAt: date(1)
        )
        XCTAssertTrue(RepGrammar.hasCleared(push, in: [cleared], level: .beginner))
        // The advanced range runs to 50, so 30 does not clear for an advanced user.
        XCTAssertFalse(RepGrammar.hasCleared(push, in: [cleared], level: .advanced))
    }

    func testPaddingToTheTopNeverClearsARung() {
        let push = exercise("push_standard")
        let padded = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 20)],
            completedAt: date(1)
        )
        XCTAssertFalse(RepGrammar.hasCleared(push, in: [padded], level: .beginner))
    }

    func testTooHardThreeSetsAndPracticeNeverClearARung() {
        let push = exercise("push_standard")
        let tooHard = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 30)],
            completedAt: date(1),
            difficulty: .tooHard
        )
        let threeSets = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 30, sets: 3)],
            completedAt: date(1)
        )
        let practice = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, role: .practice, value: 30, earned: 30)],
            completedAt: date(1)
        )
        for log in [tooHard, threeSets, practice] {
            XCTAssertFalse(RepGrammar.hasCleared(push, in: [log], level: .beginner))
        }
    }

    // MARK: Earned Reps (the M1 planning default)

    func testANewMovementOpensAtTheBottomOfTheRange() {
        XCTAssertEqual(AdaptiveOverload.earned(for: exercise("push_standard"), level: .beginner, recentLogs: []), 15)
        XCTAssertEqual(AdaptiveOverload.earned(for: exercise("push_archer"), level: .advanced, recentLogs: []), 5)
        XCTAssertEqual(AdaptiveOverload.earned(for: exercise("core_forearm_plank"), level: .beginner, recentLogs: []), 20)
    }

    func testEarnedRepsClimbOneStepPerSessionAtOrAboveThem() {
        let push = exercise("push_standard")
        let atEarned = TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 20, earned: 20)], completedAt: date(1))
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [atEarned]), 25)

        // Padding climbs exactly as a set at Earned Reps does: one step, never to the padded number.
        let padded = TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 20)], completedAt: date(1))
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [padded]), 25)

        // A short session below Earned Reps neither climbs nor steps back.
        let short = TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 10, earned: 20)], completedAt: date(1))
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [short]), 20)
    }

    func testTooHardStepsBackAndTheTopOfTheRangeHolds() {
        let push = exercise("push_standard")
        let tooHard = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(push.id, pattern: .push, value: 20, earned: 20)],
            completedAt: date(1),
            difficulty: .tooHard
        )
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [tooHard]), 15)
        let atTop = TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 30, earned: 30)], completedAt: date(1))
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [atTop]), 30)
    }

    func testASlowerPaceTakesMoreQualifyingSessionsToClimb() {
        let push = exercise("push_standard")
        let once = TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 20, earned: 20)], completedAt: date(1))
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: [once], progressionRate: 0.5), 20)
        let twice = [
            TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 20, earned: 20)], completedAt: date(3)),
            once,
        ]
        XCTAssertEqual(AdaptiveOverload.earned(for: push, level: .beginner, recentLogs: twice, progressionRate: 0.5), 25)
    }

    func testAReturnHoldsThePrescriptionNotEarnedReps() {
        let push = exercise("push_standard")
        let logs = [TrainingDayFixtures.log([TrainingDayFixtures.station(push.id, pattern: .push, value: 25, earned: 25)], completedAt: date(1))]
        let held = AdaptiveOverload.target(for: push, level: .beginner, recentLogs: logs, reentryScale: 0.7)
        XCTAssertEqual(held.earned, 30)
        XCTAssertEqual(held.reps, 20)
        XCTAssertEqual(held.sets, 4)
    }

    // MARK: Practice never moves progression (US-TD02)

    func testAPracticeStationNeverMovesARungOrTheRepRamp() {
        // The user is on Standard Push-Up and practices Diamond Push-Up, the next rung, at the very
        // numbers that would clear it.
        let standard = exercise("push_standard")
        let diamond = exercise("push_diamond")
        let session = TrainingDayFixtures.log([
            TrainingDayFixtures.station(standard.id, pattern: .push, value: 20, earned: 20),
            TrainingDayFixtures.station(diamond.id, pattern: .push, role: .practice, value: 30, earned: 30),
        ], completedAt: date(1))

        // The Rep Ramp: Diamond keeps no Earned Reps of its own, Standard climbs one step as usual.
        XCTAssertEqual(AdaptiveOverload.earned(for: diamond, level: .intermediate, recentLogs: [session]), 15)
        XCTAssertEqual(AdaptiveOverload.earned(for: standard, level: .intermediate, recentLogs: [session]), 25)

        // The rung: the chain frontier stays on Standard.
        let chain = library.filter { $0.progressionChainId == standard.progressionChainId }
        let selection = ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: Set(chain.map(\.id)),
            recentLogs: [session],
            level: .intermediate
        )
        XCTAssertEqual(selection?.exercise.id, standard.id)

        // Clearing: Practice never clears the rung it previews.
        XCTAssertFalse(RepGrammar.hasCleared(diamond, in: [session], level: .intermediate))
    }

    func testCompletedSetsAreUnchangedByStationRoles() {
        // US-CC09's guard: a set still records only what it asked for.
        let labels = Mirror(reflecting: CompletedSet(reps: 1, durationSeconds: nil)).children.compactMap(\.label)
        XCTAssertEqual(labels, ["reps", "durationSeconds"])
    }

    func testLogsAndPrescriptionsWrittenBeforeStationRolesStillDecode() throws {
        let legacyLog = """
        {"id":"7E3F6F2E-7C68-4D59-9E7A-0F1B6C0D2A11","exerciseId":"primal_bear_crawl","pillar":"primal",
         "movementPattern":"locomotion","completedSets":[{"reps":10}],"skipped":false}
        """
        let logged = try JSONDecoder().decode(LoggedExercise.self, from: Data(legacyLog.utf8))
        XCTAssertNil(logged.role)
        XCTAssertNil(logged.earnedReps)
        XCTAssertTrue(logged.countsForProgression)
    }
}
