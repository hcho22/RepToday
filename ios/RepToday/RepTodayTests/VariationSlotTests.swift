import XCTest
@testable import RepToday

/// US-SZ02 (ADR-0018): the Variation slot. A 60-minute Push or Pull Day's fifth main slot takes a
/// Variation of one of the day's current rungs once Trainer art exists for both Trainers, rotating least
/// recently done first; with none eligible it stays empty. A Legs Day's fifth slot is its first ladder's
/// Practice Movement. The shipping catalog carries no Variation, so every case here uses a test-only
/// fixture: a copy of a real rung that declares `variationOf` and sits alone in its own chain.
final class VariationSlotTests: XCTestCase {

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    /// A test-only Variation of `parentId`: the parent's numbers under a new id, alone in its own chain.
    private func variation(_ id: String, of parentId: String, audience: MovementAudience = .beginner) throws -> Exercise {
        var copy = try XCTUnwrap(library.first { $0.id == parentId }, parentId)
        copy.id = id
        copy.displayName = id
        copy.progressionChainId = id
        copy.progressionOrder = 0
        copy.regressionId = nil
        copy.progressionId = nil
        copy.variationOf = parentId
        copy.audience = audience
        return copy
    }

    private func plan(
        _ day: TrainingDay,
        minutes: Int = 60,
        level: FitnessLevel = .beginner,
        injuries: [String] = [],
        library: [Exercise],
        logs: [WorkoutLog] = [],
        hasArt: @escaping (Exercise) -> Bool = { _ in true }
    ) -> SessionPlan {
        var plan = SessionAssembly.planSession(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(level: level, injuries: injuries),
            library: library,
            recentLogs: logs,
            trainingDay: day,
            hasTrainerArt: hasArt,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        return plan
    }

    /// The day's current rung on `ladder` for a fresh beginner, read off the plan with no Variation.
    private func currentRung(_ day: TrainingDay, ladder: String) throws -> String {
        try XCTUnwrap(plan(day, library: library).stations.first { $0.role == .main && $0.exercise.progressionChainId == ladder }?.exercise.id)
    }

    private func variationLog(_ id: String, daysAgo: Int) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station(id, pattern: .push, role: .variation, value: 30)],
            completedAt: TrainingDayFixtures.date(daysAgo: daysAgo)
        )
    }

    // MARK: Eligible path

    func testAnEligibleVariationFillsASixtyMinutePushOrPullDaysFifthSlot() throws {
        for (day, ladder) in [(TrainingDay.push, "push_horizontal"), (.pull, "pull_horizontal")] {
            let parent = try currentRung(day, ladder: ladder)
            let fixture = try variation("test_variation", of: parent)
            let stations = plan(day, library: library + [fixture]).stations
            XCTAssertEqual(stations.map(\.role), [.main, .main, .practice, .practice, .variation, .core, .core], "\(day)")

            let slot = try XCTUnwrap(stations.first { $0.role == .variation }, "\(day)")
            XCTAssertEqual(slot.exercise.id, "test_variation")
            XCTAssertEqual(slot.sets, RepGrammar.setsPerStation)
            XCTAssertNil(slot.earned, "\(day): a Variation records no Earned Reps")
            XCTAssertEqual(slot.value % RepGrammar.step, 0)
            let prescription = slot.materialize(restSeconds: 30)
            XCTAssertEqual(prescription.role, .variation)
            XCTAssertNil(prescription.earnedReps ?? prescription.earnedDurationSeconds)
        }
    }

    /// The Variation runs at its parent's number when both are counted alike, and is padded like a main
    /// station.
    func testAVariationRunsAtItsParentsNumber() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let fixture = try variation("test_variation", of: parent)
        let planned = plan(.push, library: library + [fixture])
        let parentStation = try XCTUnwrap(planned.stations.first { $0.exercise.id == parent })
        let slot = try XCTUnwrap(planned.stations.first { $0.role == .variation })
        XCTAssertEqual(slot.start, parentStation.start)
        XCTAssertEqual(slot.ceiling, RepGrammar.earnedRange(for: fixture, level: .beginner).upperBound)
    }

    // MARK: Empty paths

    func testWithoutArtForBothTrainersTheSlotStaysEmpty() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let fixture = try variation("test_variation", of: parent)
        let lib = library + [fixture]
        let noArt = plan(.push, library: lib, hasArt: { _ in false })
        XCTAssertFalse(noArt.stations.contains { $0.role == .variation })
        XCTAssertEqual(noArt.stations.filter { $0.role == .main || $0.role == .practice }.count, 4)

        // The default asks the app's own asset catalog through the Trainer resolver, which holds no art
        // for the fixture - and does for a real rung.
        XCTAssertFalse(SessionAssembly.hasBundledTrainerArt(fixture))
        XCTAssertTrue(SessionAssembly.hasBundledTrainerArt(try XCTUnwrap(library.first { $0.id == "push_wall" })))
        let bundled = SessionAssembly.planSession(
            requestedMinutes: 60,
            user: TrainingDayFixtures.user(level: .beginner),
            library: lib,
            recentLogs: [],
            trainingDay: .push,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        XCTAssertFalse(bundled.stations.contains { $0.role == .variation })
    }

    func testAVariationOfARungThatIsNotCurrentStaysOut() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let next = try XCTUnwrap(library.first { $0.id == parent }?.progressionId)
        let fixture = try variation("test_variation", of: next)
        XCTAssertFalse(plan(.push, library: library + [fixture]).stations.contains { $0.role == .variation })
    }

    func testOnlyASixtyMinuteSessionHasAVariationSlot() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let lib = library + [try variation("test_variation", of: parent)]
        for minutes in [5, 10, 15, 20, 30, 45] {
            XCTAssertFalse(plan(.push, minutes: minutes, library: lib).stations.contains { $0.role == .variation }, "\(minutes) min")
        }
    }

    /// A Legs Day's fifth slot is its first ladder's Practice Movement, never a Variation (decision 4).
    func testALegsDayNeverTakesAVariation() throws {
        let parent = try currentRung(.legs, ladder: "squat")
        let fixture = try variation("test_variation", of: parent)
        let stations = plan(.legs, library: library + [fixture]).stations
        XCTAssertFalse(stations.contains { $0.role == .variation })
        XCTAssertEqual(stations.filter { $0.role == .main }.count, 4)
        XCTAssertEqual(stations.filter { $0.role == .practice }.count, 1)
    }

    /// A Variation obeys every movement filter like any movement: a withdrawn one and one skipped past the
    /// skip limit stay out.
    func testAVariationObeysWithdrawnAndSkipRules() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let withdrawn = try variation("test_variation", of: parent, audience: .version2)
        XCTAssertFalse(plan(.push, library: library + [withdrawn]).stations.contains { $0.role == .variation })

        let fixture = try variation("test_variation", of: parent)
        let skips = (1...(ExercisePoolFilter.recentSkipThreshold + 1)).map { daysAgo in
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station("test_variation", pattern: .push, role: .variation, skipped: true)],
                completedAt: TrainingDayFixtures.date(daysAgo: daysAgo)
            )
        }
        XCTAssertFalse(plan(.push, library: library + [fixture], logs: skips).stations.contains { $0.role == .variation })
    }

    /// A Variation whose movement an injury rules out stays out with its parent's whole pattern.
    func testAVariationObeysInjuryExclusions() throws {
        let parent = try currentRung(.pull, ladder: "pull_horizontal")
        let fixture = try variation("test_variation", of: parent)
        let contraindicated = InjuryContraindication.contraindicatedPatterns(for: ["shoulder"])
        XCTAssertTrue(contraindicated.contains(.pull))
        let injured = plan(.pull, injuries: ["shoulder"], library: library + [fixture])
        XCTAssertFalse(injured.stations.contains { $0.exercise.id == "test_variation" })
        XCTAssertTrue(injured.stations.allSatisfy { !contraindicated.contains($0.exercise.movementPattern) })
    }

    // MARK: Rotation

    /// Several eligible Variations rotate, least recently done first, the never-done ahead of the done.
    func testVariationsRotateLeastRecentlyDoneFirst() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let lib = library + [try variation("test_variation_a", of: parent), try variation("test_variation_b", of: parent)]
        let pick = { (logs: [WorkoutLog]) in
            self.plan(.push, library: lib, logs: logs).stations.first { $0.role == .variation }?.exercise.id
        }
        XCTAssertEqual(pick([]), "test_variation_a", "never done: the id breaks the tie")
        XCTAssertEqual(pick([variationLog("test_variation_a", daysAgo: 2)]), "test_variation_b")
        XCTAssertEqual(pick([variationLog("test_variation_a", daysAgo: 2), variationLog("test_variation_b", daysAgo: 1)]), "test_variation_a")
        XCTAssertEqual(pick([variationLog("test_variation_a", daysAgo: 1), variationLog("test_variation_b", daysAgo: 3)]), "test_variation_b")
    }

    // MARK: Never advances

    /// A Variation never advances progression, Earned Reps or a Foundation: its log does not count, and a
    /// session logged at the top of the range leaves the parent's Earned Reps and rung where they were.
    func testAVariationNeverAdvancesAnything() throws {
        let station = TrainingDayFixtures.station("test_variation", pattern: .push, role: .variation, value: 30)
        XCTAssertFalse(station.countsForProgression)
        XCTAssertFalse(StationRole.variation.advancesProgression)
        XCTAssertFalse(StationRole.practice.advancesProgression)
        XCTAssertTrue(StationRole.main.advancesProgression)
        XCTAssertTrue(StationRole.core.advancesProgression)

        let parent = try currentRung(.push, ladder: "push_horizontal")
        let fixture = try variation("test_variation", of: parent)
        let lib = library + [fixture]
        let before = plan(.push, library: lib)
        let topSessions = (1...3).map { daysAgo in
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station("test_variation", pattern: .push, role: .variation, value: 30, earned: 30)],
                completedAt: TrainingDayFixtures.date(daysAgo: daysAgo)
            )
        }
        let after = plan(.push, library: lib, logs: topSessions)
        let main = { (plan: SessionPlan) in plan.stations.first { $0.role == .main && $0.exercise.progressionChainId == "push_horizontal" } }
        XCTAssertEqual(main(after)?.exercise.id, parent, "the rung did not move")
        XCTAssertEqual(main(after)?.earned, main(before)?.earned, "the parent's Earned Reps did not move")
        let entry = try XCTUnwrap(lib.first { $0.id == "test_variation" })
        XCTAssertFalse(topSessions.contains { log in log.exercises.contains { RepGrammar.isAdvancementMet(by: $0, in: log, exercise: entry, level: .beginner) } })
    }

    /// A swap never hands a Variation into another slot, where its role could advance it.
    func testASwapNeverOffersAVariation() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let lib = library + [try variation("test_variation", of: parent)]
        let user = TrainingDayFixtures.user(level: .beginner)
        let workout = SessionAssembly.assemble(
            requestedMinutes: 30, user: user, library: lib, recentLogs: [], trainingDay: .push,
            hasTrainerArt: { _ in true }, asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar
        )
        for prescription in workout.blocks.flatMap(\.exercises) {
            if case .substituted(let substitute) = ExerciseSwap.swap(prescription, in: workout, user: user, library: lib, recentLogs: []) {
                XCTAssertNil(substitute.exercise.variationOf, "\(prescription.exercise.id) swapped for a Variation")
            }
        }
    }

    // MARK: The catalog contract

    func testTheShippingCatalogCarriesNoVariation() {
        XCTAssertFalse(library.contains { $0.variationOf != nil })
    }

    func testTheLoaderAcceptsAVariationAndRejectsOneInALadderOrOfABadParent() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let fixture = try variation("test_variation", of: parent)
        // The loader validates the whole file, withdrawn rungs included.
        let url = try XCTUnwrap(Bundle(for: MockExerciseService.self).url(forResource: "Exercises", withExtension: "json"))
        let library = try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        XCTAssertNoThrow(try MockExerciseService(library: library + [fixture]))

        var inLadder = fixture
        inLadder.progressionChainId = "push_horizontal"
        inLadder.progressionOrder = library.filter { $0.progressionChainId == "push_horizontal" }.count
        XCTAssertThrowsError(try MockExerciseService(library: library + [inLadder])) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .variationInLadder(exerciseId: "test_variation"))
        }

        var missingParent = fixture
        missingParent.variationOf = "no_such_rung"
        XCTAssertThrowsError(try MockExerciseService(library: library + [missingParent])) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .variationParentInvalid(exerciseId: "test_variation", parentId: "no_such_rung"))
        }

        var otherPattern = fixture
        otherPattern.variationOf = "squat_bodyweight"
        XCTAssertThrowsError(try MockExerciseService(library: library + [otherPattern])) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .variationParentInvalid(exerciseId: "test_variation", parentId: "squat_bodyweight"))
        }
    }

    /// A Variation decodes from the catalog's JSON shape with its parent link, and the field is optional.
    func testTheVariationFieldDecodes() throws {
        let parent = try currentRung(.push, ladder: "push_horizontal")
        let fixture = try variation("test_variation", of: parent)
        let data = try JSONEncoder().encode(fixture)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"variationOf\":\"\(parent)\""), json)
        XCTAssertEqual(try JSONDecoder().decode(Exercise.self, from: data).variationOf, parent)
        let plain = try JSONEncoder().encode(try XCTUnwrap(library.first { $0.id == parent }))
        XCTAssertNil(try JSONDecoder().decode(Exercise.self, from: plain).variationOf)
    }
}
