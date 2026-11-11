import XCTest
@testable import RepToday

/// Tests the exercise service that loads and integrity-checks the bundled library (US-B02).
///
/// Two halves: the *query* tests load the real bundled `Exercises.json` through the service
/// and assert each helper answers correctly; the *validation* tests feed deliberately broken
/// libraries to `init(library:)` and assert the exact `ExerciseLibraryError` each rule raises,
/// naming the offending exercise. `ExerciseLibraryTests` remains the gate on the real data's
/// shape; this suite is the gate on the service's loading, caching, querying, and failure behavior.
final class ExerciseServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds an exercise with sensible bodyweight defaults; override only what a test cares about.
    private func makeExercise(
        id: String,
        pillar: Pillar = .strength,
        movementPattern: MovementPattern = .push,
        category: ExerciseCategory = .strength,
        difficulty: Int = 1,
        phase: Phase = .discipline,
        audience: MovementAudience? = .beginner,
        equipment: [Equipment] = [],
        isHold: Bool = false,
        defaultReps: Int? = 10,
        defaultDurationSeconds: Int? = nil,
        estimatedTimePerSetSeconds: Int = 40,
        metValue: Double = 3.0,
        progressionChainId: String = "chain",
        progressionOrder: Int = 0,
        regressionId: String? = nil,
        progressionId: String? = nil,
        advancementCriteria: String = "4 clean sets at the top of your rep range",
        apartmentFriendly: Bool = true
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: movementPattern,
            category: category,
            difficulty: difficulty,
            phase: phase,
            audience: audience,
            equipment: equipment,
            isHold: isHold,
            defaultReps: defaultReps,
            defaultDurationSeconds: defaultDurationSeconds,
            estimatedTimePerSetSeconds: estimatedTimePerSetSeconds,
            metValue: metValue,
            progressionChainId: progressionChainId,
            progressionOrder: progressionOrder,
            regressionId: regressionId,
            progressionId: progressionId,
            advancementCriteria: advancementCriteria,
            apartmentFriendly: apartmentFriendly
        )
    }

    /// A minimal valid two-step chain: `a` (order 0) -> `b` (order 1), links pointing at each other.
    private func validChain() -> [Exercise] {
        [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "b"),
            makeExercise(id: "b", progressionChainId: "c", progressionOrder: 1, regressionId: "a"),
        ]
    }

    // MARK: - Real library loads and answers queries

    func testRealLibraryLoadsAndCaches() async throws {
        let service = try MockExerciseService()
        let all = try await service.exercises()
        XCTAssertEqual(
            all.count, 68,
            "the offered library is the bundled 76 minus the 7 retired primal movements and Prone Y-T-W Raises (version 2)"
        )
        XCTAssertFalse(all.contains(where: MovementAccess.isWithdrawn), "no withdrawn movement is ever served")
    }

    func testExerciseByIdResolves() async throws {
        let service = try MockExerciseService()
        let found = try await service.exercise(id: "push_standard")
        XCTAssertEqual(found?.displayName, "Standard Push-Up")
        let missing = try await service.exercise(id: "does_not_exist")
        XCTAssertNil(missing)
    }

    func testExercisesByPillar() async throws {
        let service = try MockExerciseService()
        // `.mobility` is a case of both Pillar and MovementPattern, so name the type to pick
        // the pillar overload of the shared `exercises(for:)` label.
        let mobility = try await service.exercises(for: Pillar.mobility)
        XCTAssertEqual(mobility.count, 26)
        XCTAssertTrue(mobility.allSatisfy { $0.pillar == .mobility })
    }

    /// The primal pillar is retired (ADR-0014): its movements stay in the file so history resolves, but the
    /// service offers none of them.
    func testRetiredPrimalPillarOffersNothing() async throws {
        let service = try MockExerciseService()
        let primal = try await service.exercises(for: Pillar.primal)
        XCTAssertTrue(primal.isEmpty)
        let locomotion = try await service.exercises(for: .locomotion)
        XCTAssertTrue(locomotion.isEmpty)
        let bearCrawl = try await service.exercise(id: "primal_bear_crawl")
        XCTAssertNil(bearCrawl)
    }

    func testExercisesByMovementPattern() async throws {
        let service = try MockExerciseService()
        let push = try await service.exercises(for: .push)
        XCTAssertEqual(push.count, 10)
        XCTAssertTrue(push.allSatisfy { $0.movementPattern == .push })
    }

    func testExercisesByPhase() async throws {
        let service = try MockExerciseService()
        // `.strength` is a case of both Pillar and Phase; name the type to pick the phase overload.
        let gated = try await service.exercises(for: Phase.strength)
        XCTAssertEqual(Set(gated.map(\.id)), [
            "push_one_arm_assisted", "push_one_arm",
            "squat_pistol_assisted", "squat_pistol",
            "core_one_leg_l_sit", "core_l_sit",
            "hinge_nordic_assisted", "hinge_nordic",
        ])
        let discipline = try await service.exercises(for: Phase.discipline)
        XCTAssertEqual(discipline.count, 60, "68 discipline movements minus the 8 withdrawn (7 retired, 1 version 2)")
    }

    func testExercisesByDifficultyRange() async throws {
        let service = try MockExerciseService()
        let beginnerCap = try await service.exercises(inDifficultyRange: 1...2)
        XCTAssertFalse(beginnerCap.isEmpty)
        XCTAssertTrue(beginnerCap.allSatisfy { (1...2).contains($0.difficulty) })
        // The cap must exclude the difficulty 3+ tiers (incl. the gated 4-5 skills).
        XCTAssertFalse(beginnerCap.contains { $0.id == "push_diamond" }, "difficulty 3 should be excluded")
        XCTAssertFalse(beginnerCap.contains { $0.id == "push_one_arm" }, "difficulty 5 should be excluded")
    }

    func testNextInChainResolvesProgression() async throws {
        let service = try MockExerciseService()
        let next = try await service.nextInChain(after: "push_wall")
        XCTAssertEqual(next?.id, "push_incline", "next up the push_horizontal chain")
    }

    func testNextInChainReturnsNilAtTopOfChain() async throws {
        let service = try MockExerciseService()
        // push_one_arm sits at the top of its chain - no progression beyond it.
        let next = try await service.nextInChain(after: "push_one_arm")
        XCTAssertNil(next)
    }

    /// Reverse Snow Angel is the live top of the postural chain: the rung above it, Prone Y-T-W Raises, is
    /// withdrawn until version 2, so nothing is offered past it.
    func testNextInChainReturnsNilBelowAWithdrawnTail() async throws {
        let service = try MockExerciseService()
        let angel = try await service.exercise(id: "pull_reverse_snow_angel")
        XCTAssertEqual(angel?.progressionId, "pull_ytw", "the file keeps the link to the withdrawn tail")
        let next = try await service.nextInChain(after: "pull_reverse_snow_angel")
        XCTAssertNil(next)
    }

    func testNextInChainReturnsNilForUnknownId() async throws {
        let service = try MockExerciseService()
        let next = try await service.nextInChain(after: "does_not_exist")
        XCTAssertNil(next)
    }

    // MARK: - Validation rules (deliberately broken fixtures)

    func testValidLibraryConstructs() {
        XCTAssertNoThrow(try MockExerciseService(library: validChain()))
    }

    func testDuplicateIdThrows() {
        let library = [
            makeExercise(id: "dup", progressionChainId: "c1", progressionOrder: 0),
            makeExercise(id: "dup", progressionChainId: "c2", progressionOrder: 0),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .duplicateId("dup"))
        }
    }

    func testEquipmentNotEmptyThrows() {
        let library = [
            makeExercise(id: "with_gear", equipment: [.dumbbells], progressionChainId: "c", progressionOrder: 0),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .equipmentNotEmpty(exerciseId: "with_gear"))
        }
    }

    /// The validation test's headline scenario: a dangling `progressionId`.
    func testDanglingProgressionIdThrows() {
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "ghost"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(
                error as? ExerciseLibraryError,
                .unresolvedChainLink(exerciseId: "a", missingId: "ghost", link: "progressionId")
            )
        }
    }

    func testDanglingRegressionIdThrows() {
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, regressionId: "ghost"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(
                error as? ExerciseLibraryError,
                .unresolvedChainLink(exerciseId: "a", missingId: "ghost", link: "regressionId")
            )
        }
    }

    func testNonContiguousChainThrows() {
        // Orders 0 and 2: a gap at 1, so the chain is not contiguous.
        let library = [
            makeExercise(id: "a", progressionChainId: "gap", progressionOrder: 0, progressionId: "b"),
            makeExercise(id: "b", progressionChainId: "gap", progressionOrder: 2, regressionId: "a"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(
                error as? ExerciseLibraryError,
                .chainNotContiguous(chainId: "gap", orders: [0, 2])
            )
        }
    }

    func testMissingAudienceThrows() {
        let library = [makeExercise(id: "a", audience: nil, progressionChainId: "c", progressionOrder: 0)]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .missingAudience(exerciseId: "a"))
        }
    }

    func testChainThatIsNotDoublyLinkedThrows() {
        // `a` points up at `b`, but `b` does not link back down at `a`.
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "b"),
            makeExercise(id: "b", progressionChainId: "c", progressionOrder: 1),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .chainNotDoublyLinked(exerciseId: "a", linkedId: "b"))
        }
    }

    func testProgressionThatSkipsARungThrows() {
        // `a` links straight to `c`, jumping over `b`: reordering a chain must rewire it properly.
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "c"),
            makeExercise(id: "b", progressionChainId: "c", progressionOrder: 1),
            makeExercise(id: "c", progressionChainId: "c", progressionOrder: 2, regressionId: "a"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .chainNotDoublyLinked(exerciseId: "a", linkedId: "c"))
        }
    }

    /// A withdrawn tail at the top of a live chain loads - for either withdrawal, version 2 or retired -
    /// and is never served, so the live rungs stay one contiguous ladder.
    func testWithdrawnTailAtTheTopOfALiveChainLoadsButIsNeverServed() async throws {
        for audience in [MovementAudience.version2, .retired] {
            let library = [
                makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "b"),
                makeExercise(id: "b", progressionChainId: "c", progressionOrder: 1, regressionId: "a", progressionId: "w1"),
                makeExercise(id: "w1", audience: audience, progressionChainId: "c", progressionOrder: 2, regressionId: "b", progressionId: "w2"),
                makeExercise(id: "w2", audience: audience, progressionChainId: "c", progressionOrder: 3, regressionId: "w1"),
            ]
            let service = try MockExerciseService(library: library)
            let offered = try await service.exercises().map(\.id)
            XCTAssertEqual(offered, ["a", "b"], "\(audience)")
            let found = try await service.exercise(id: "w1")
            XCTAssertNil(found, "\(audience)")
            let next = try await service.nextInChain(after: "b")
            XCTAssertNil(next, "\(audience): nothing is offered past the live top")
        }
    }

    /// A withdrawn rung with a live rung above it would leave a hole in a live ladder, so it fails load.
    func testWithdrawnRungBelowALiveOneThrows() {
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "w"),
            makeExercise(id: "w", audience: .version2, progressionChainId: "c", progressionOrder: 1, regressionId: "a", progressionId: "top"),
            makeExercise(id: "top", progressionChainId: "c", progressionOrder: 2, regressionId: "w"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .withdrawnMovementInLiveChain(exerciseId: "a", withdrawnId: "w"))
        }
    }

    /// A withdrawn entry rung under a live one throws too: a live movement never regresses onto a
    /// withdrawn one.
    func testLiveRungAboveAWithdrawnEntryThrows() {
        let library = [
            makeExercise(id: "w", audience: .retired, progressionChainId: "c", progressionOrder: 0, progressionId: "a"),
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 1, regressionId: "w"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .withdrawnMovementInLiveChain(exerciseId: "a", withdrawnId: "w"))
        }
    }

    func testWholeWithdrawnChainLoadsButIsNeverServed() async throws {
        for audience in [MovementAudience.version2, .retired] {
            let library = validChain() + [
                makeExercise(id: "w1", audience: audience, progressionChainId: "w", progressionOrder: 0, progressionId: "w2"),
                makeExercise(id: "w2", audience: audience, progressionChainId: "w", progressionOrder: 1, regressionId: "w1"),
            ]
            let service = try MockExerciseService(library: library)
            let offered = try await service.exercises().map(\.id)
            XCTAssertEqual(offered, ["a", "b"], "\(audience)")
            let found = try await service.exercise(id: "w1")
            XCTAssertNil(found, "\(audience)")
        }
    }

    func testDescriptiveErrorNamesExerciseAndRule() {
        let library = [
            makeExercise(id: "a", progressionChainId: "c", progressionOrder: 0, progressionId: "ghost"),
        ]
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            let message = (error as? ExerciseLibraryError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("a"), "error should name the offending exercise")
            XCTAssertTrue(message.contains("ghost"), "error should name the unresolved link")
            XCTAssertTrue(message.contains("progressionId"), "error should name the broken rule")
        }
    }

    // MARK: - Bundle / decoding failures

    func testResourceMissingThrows() {
        // The test bundle does not ship Exercises.json (it lives in the app target).
        let testBundle = Bundle(for: ExerciseServiceTests.self)
        XCTAssertThrowsError(try MockExerciseService(bundle: testBundle)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .resourceMissing)
        }
    }

    func testDecodingFailedThrows() {
        let garbage = Data("not valid json".utf8)
        XCTAssertThrowsError(try MockExerciseService(data: garbage)) { error in
            guard case .decodingFailed = error as? ExerciseLibraryError else {
                return XCTFail("expected .decodingFailed, got \(error)")
            }
        }
    }
}
