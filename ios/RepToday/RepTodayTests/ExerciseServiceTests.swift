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
        advancementCriteria: String = "3x12 clean reps",
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
        XCTAssertEqual(all.count, 57, "service should load the full bundled library")
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
        XCTAssertEqual(mobility.count, 12)
        XCTAssertTrue(mobility.allSatisfy { $0.pillar == .mobility })
    }

    func testExercisesByMovementPattern() async throws {
        let service = try MockExerciseService()
        let push = try await service.exercises(for: .push)
        XCTAssertEqual(push.count, 9)
        XCTAssertTrue(push.allSatisfy { $0.movementPattern == .push })
    }

    func testExercisesByPhase() async throws {
        let service = try MockExerciseService()
        // `.strength` is a case of both Pillar and Phase; name the type to pick the phase overload.
        let gated = try await service.exercises(for: Phase.strength)
        XCTAssertEqual(Set(gated.map(\.id)), ["push_one_arm", "squat_pistol", "core_l_sit"])
        let discipline = try await service.exercises(for: Phase.discipline)
        XCTAssertEqual(discipline.count, 54)
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
