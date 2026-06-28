import XCTest
@testable import FitSnack

/// Validates the bundled exercise library `Resources/Exercises.json` (US-B01).
///
/// The library is hand-authored JSON, so these tests are its integrity gate: they decode
/// the real bundled file (not a fixture) and assert it matches the v5 section 5.1 structure
/// the engine depends on - the right movements per pattern/pillar, contiguous progression
/// chains whose `regressionId`/`progressionId` links all resolve, the Zero-Equipment Floor,
/// strength-phase gating, and the hold-vs-rep field contract.
///
/// The exercise *service* that loads and integrity-checks the library at startup arrives in
/// US-B02; until then these tests own the guarantee that the data on disk is well-formed.
final class ExerciseLibraryTests: XCTestCase {

    private var exercises: [Exercise] = []
    /// `id -> Exercise`, for resolving chain links and asserting uniqueness.
    private var byId: [String: Exercise] = [:]

    override func setUpWithError() throws {
        // Loaded from the app bundle (where the resource is bundled), located via a class
        // that lives in the app module.
        let bundle = Bundle(for: AppState.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "Exercises", withExtension: "json"),
            "Exercises.json is missing from the app bundle"
        )
        let data = try Data(contentsOf: url)
        exercises = try JSONDecoder().decode([Exercise].self, from: data)
        byId = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    // MARK: - Library size and id uniqueness

    /// ~38 movements per v5 5.1; the exact count is pinned so an accidental add/drop is
    /// caught and has to be made deliberately.
    func testLibrarySizeIsAuthored() {
        XCTAssertEqual(exercises.count, 42, "expected the authored 42-movement library")
    }

    func testIdsAreUnique() {
        XCTAssertEqual(byId.count, exercises.count, "duplicate exercise id in the library")
    }

    // MARK: - Category / pillar coverage (v5 5.1)

    /// Every movement-pattern group from v5 5.1 is represented with the authored counts.
    func testMovementPatternCounts() {
        let counts = Dictionary(grouping: exercises, by: \.movementPattern).mapValues(\.count)
        XCTAssertEqual(counts[.push], 8, "push group")
        XCTAssertEqual(counts[.squat], 6, "squat group")
        XCTAssertEqual(counts[.hinge], 4, "hinge group")
        XCTAssertEqual(counts[.core], 6, "core group")
        XCTAssertEqual(counts[.pull], 3, "pull/postural group")
        XCTAssertEqual(counts[.mobility], 12, "Movement Practice mobility group")
        XCTAssertEqual(counts[.locomotion], 3, "primal group")
    }

    /// All three training pillars carry movements; mobility is co-primary (not a sliver).
    func testPillarCoverage() {
        let counts = Dictionary(grouping: exercises, by: \.pillar).mapValues(\.count)
        XCTAssertEqual(counts[.strength], 27)
        XCTAssertEqual(counts[.mobility], 12)
        XCTAssertEqual(counts[.primal], 3)
    }

    /// `Pillar` and `ExerciseCategory` agree for the library: a strength-pillar movement is
    /// a `.strength` exercise, mobility is `.mobility`, primal is `.primal`.
    func testCategoryMatchesPillar() {
        for ex in exercises {
            switch ex.pillar {
            case .strength: XCTAssertEqual(ex.category, .strength, "\(ex.id) category")
            case .mobility: XCTAssertEqual(ex.category, .mobility, "\(ex.id) category")
            case .primal:   XCTAssertEqual(ex.category, .primal, "\(ex.id) category")
            }
        }
    }

    // MARK: - Zero-Equipment Floor

    func testEveryExerciseIsBodyweight() {
        for ex in exercises {
            XCTAssertEqual(ex.equipment, [], "\(ex.id) must be bodyweight (Zero-Equipment Floor)")
        }
    }

    // MARK: - Progression chains

    /// Each chain's `progressionOrder` is a contiguous 0..<n sequence, and every step's
    /// `regressionId`/`progressionId` points to its exact neighbour (nil at the ends).
    func testChainsAreContiguousAndLinked() {
        let chains = Dictionary(grouping: exercises, by: \.progressionChainId)

        for (chainId, members) in chains {
            let chain = members.sorted { $0.progressionOrder < $1.progressionOrder }

            // Contiguous 0,1,2,... with no gaps or duplicates.
            let orders = chain.map(\.progressionOrder)
            XCTAssertEqual(orders, Array(0..<chain.count), "chain \(chainId) orders not contiguous")

            for (index, ex) in chain.enumerated() {
                let expectedRegression = index == 0 ? nil : chain[index - 1].id
                let expectedProgression = index == chain.count - 1 ? nil : chain[index + 1].id
                XCTAssertEqual(ex.regressionId, expectedRegression, "\(ex.id) regressionId link")
                XCTAssertEqual(ex.progressionId, expectedProgression, "\(ex.id) progressionId link")
            }
        }
    }

    /// No dangling references: every non-nil chain link resolves to a real exercise.
    func testChainLinksResolve() {
        for ex in exercises {
            if let regression = ex.regressionId {
                XCTAssertNotNil(byId[regression], "\(ex.id) regressionId '\(regression)' is orphaned")
            }
            if let progression = ex.progressionId {
                XCTAssertNotNil(byId[progression], "\(ex.id) progressionId '\(progression)' is orphaned")
            }
        }
    }

    /// Every strength and primal movement sits in a real chain (one with room to regress or
    /// progress) - never a lone movement with no path up or down.
    func testStrengthAndPrimalMovementsHaveChainRoom() {
        let chainSizes = Dictionary(grouping: exercises, by: \.progressionChainId).mapValues(\.count)
        for ex in exercises where ex.pillar == .strength || ex.pillar == .primal {
            XCTAssertGreaterThanOrEqual(chainSizes[ex.progressionChainId] ?? 0, 2,
                                        "\(ex.id) should belong to a multi-step progression chain")
            XCTAssertTrue(ex.regressionId != nil || ex.progressionId != nil,
                          "\(ex.id) has neither a regression nor a progression")
        }
    }

    // MARK: - Phase gating

    /// The Strength-Phase-only skills are tagged `phase: strength`; everything else is
    /// `discipline`. At MVP launch the phase filter hides the gated skills from every user.
    func testStrengthPhaseSkillsAreTagged() {
        let gated = Set(exercises.filter { $0.phase == .strength }.map(\.id))
        XCTAssertEqual(gated, ["push_one_arm", "squat_pistol", "core_l_sit"])
    }

    /// Phase tracks difficulty intent: gated skills are the hard tiers (4-5), discipline
    /// movements stay accessible (<= 3) so a beginner/intermediate cap always leaves a pool.
    func testPhaseMatchesDifficultyIntent() {
        for ex in exercises {
            XCTAssertTrue((1...5).contains(ex.difficulty), "\(ex.id) difficulty out of range")
            if ex.phase == .strength {
                XCTAssertGreaterThanOrEqual(ex.difficulty, 4, "\(ex.id) gated skill should be a hard tier")
            } else {
                XCTAssertLessThanOrEqual(ex.difficulty, 3, "\(ex.id) discipline movement should stay accessible")
            }
        }
    }

    // MARK: - Hold vs rep contract

    /// Holds carry a duration and no rep count; rep-based movements carry reps and no
    /// duration. The engine's timing/overload steps rely on exactly one being present.
    func testHoldAndRepFieldsAreConsistent() {
        for ex in exercises {
            if ex.isHold {
                XCTAssertNotNil(ex.defaultDurationSeconds, "\(ex.id) hold needs defaultDurationSeconds")
                XCTAssertNil(ex.defaultReps, "\(ex.id) hold must not carry defaultReps")
            } else {
                XCTAssertNotNil(ex.defaultReps, "\(ex.id) rep-based needs defaultReps")
                XCTAssertNil(ex.defaultDurationSeconds, "\(ex.id) rep-based must not carry defaultDurationSeconds")
            }
        }
    }

    // MARK: - Per-movement realism

    /// Every movement is apartment-friendly with a positive MET and per-set time estimate,
    /// so HealthKit energy and the timing-fit step always have real numbers to work with.
    func testEveryExerciseHasRealisticMetadata() {
        for ex in exercises {
            XCTAssertTrue(ex.apartmentFriendly, "\(ex.id) must be apartment-friendly")
            XCTAssertGreaterThan(ex.metValue, 0, "\(ex.id) metValue must be positive")
            XCTAssertGreaterThan(ex.estimatedTimePerSetSeconds, 0, "\(ex.id) estimatedTimePerSetSeconds must be positive")
            XCTAssertFalse(ex.displayName.isEmpty, "\(ex.id) needs a display name")
            XCTAssertFalse(ex.advancementCriteria.isEmpty, "\(ex.id) needs advancement criteria")
        }
    }
}
