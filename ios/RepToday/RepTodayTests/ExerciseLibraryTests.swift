import XCTest
@testable import RepToday

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

    /// The exact count is pinned so an accidental add/drop is caught and has to be made
    /// deliberately. It grew from the original 42 when the Start Seed band (US-O02) needed harder
    /// Discipline-Phase tiers to rotate over - see `testAdvancedStartBandHasRoomToRotate`.
    func testLibrarySizeIsAuthored() {
        XCTAssertEqual(exercises.count, 57, "expected the authored 57-movement library")
    }

    func testIdsAreUnique() {
        XCTAssertEqual(byId.count, exercises.count, "duplicate exercise id in the library")
    }

    // MARK: - Category / pillar coverage (v5 5.1)

    /// Every movement-pattern group from v5 5.1 is represented with the authored counts.
    func testMovementPatternCounts() {
        let counts = Dictionary(grouping: exercises, by: \.movementPattern).mapValues(\.count)
        XCTAssertEqual(counts[.push], 9, "push group")
        XCTAssertEqual(counts[.squat], 8, "squat group")
        XCTAssertEqual(counts[.hinge], 6, "hinge group")
        XCTAssertEqual(counts[.core], 9, "core group")
        XCTAssertEqual(counts[.pull], 6, "pull/postural group")
        XCTAssertEqual(counts[.mobility], 12, "Movement Practice mobility group")
        XCTAssertEqual(counts[.locomotion], 7, "primal group")
    }

    /// All three training pillars carry movements; mobility is co-primary (not a sliver).
    func testPillarCoverage() {
        let counts = Dictionary(grouping: exercises, by: \.pillar).mapValues(\.count)
        XCTAssertEqual(counts[.strength], 38)
        XCTAssertEqual(counts[.mobility], 12)
        XCTAssertEqual(counts[.primal], 7)
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

    /// Difficulty never goes *down* as a chain progresses. Step 5 relies on this silently: its
    /// no-history entry rule scans a chain in `progressionOrder` and takes the first tier the Start
    /// Seed band did not withhold, which is only the gentlest surviving tier when the two orderings
    /// agree. A chain edit that inserted a tier out of difficulty order would quietly make that rule
    /// pick a harder-than-necessary entry with nothing else failing.
    func testChainDifficultyNeverDecreasesAlongTheChain() {
        let chains = Dictionary(grouping: exercises, by: \.progressionChainId)

        for (chainId, members) in chains {
            let chain = members.sorted { $0.progressionOrder < $1.progressionOrder }
            for (lower, higher) in zip(chain, chain.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    lower.difficulty, higher.difficulty,
                    "chain \(chainId) drops from \(lower.id) (difficulty \(lower.difficulty)) to "
                        + "\(higher.id) (difficulty \(higher.difficulty)) as it progresses"
                )
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

    /// Phase gates *skills*, not tiers: the gated movements are the library's summit (difficulty 5),
    /// and every tier beneath a summit is reachable in the Discipline Phase. That is what keeps the
    /// reachable catalog a real 1-4 range rather than topping out at 3 - the Start Seed band
    /// (US-O02) has nothing to band against otherwise.
    func testPhaseMatchesDifficultyIntent() {
        for ex in exercises {
            XCTAssertTrue((1...5).contains(ex.difficulty), "\(ex.id) difficulty out of range")
            if ex.phase == .strength {
                XCTAssertEqual(ex.difficulty, 5, "\(ex.id) gated skill should be the library's summit")
            } else {
                XCTAssertLessThanOrEqual(ex.difficulty, 4, "\(ex.id) discipline movement must stay reachable")
            }
        }
        let disciplineTiers = Set(exercises.filter { $0.phase == .discipline }.map(\.difficulty))
        XCTAssertEqual(disciplineTiers, [1, 2, 3, 4], "every non-summit tier must be reachable")
    }

    // MARK: - Start Seed band coverage (US-O02)

    /// The library's shape half of the Start Seed contract: within the band each fitness level's
    /// cold-start contract opens (`[startingDifficultyFloor, cappedMaxDifficulty]`), every banded
    /// movement pattern must offer at least **two progression chains**.
    ///
    /// Two chains, not two movements, is the number that matters: Step 5 resolves a pattern by
    /// picking one exercise *per chain* and then preferring a candidate the variety window has not
    /// seen, so a pattern with a single in-band chain hands the user the identical movement every
    /// session of the cold-start week however many tiers that one chain carries.
    func testAdvancedStartBandHasRoomToRotate() {
        typealias Contract = SessionPolicy.ColdStartContract

        for level in FitnessLevel.allCases {
            let floor = Contract.startingDifficultyFloor(for: level)
            let cap = Contract.cappedMaxDifficulty(for: level)
            let banded = exercises.filter {
                $0.phase == .discipline
                    && ($0.pillar == .strength || $0.pillar == .primal)
                    && (floor...cap).contains($0.difficulty)
            }
            let patterns = Set(banded.map(\.movementPattern))
            XCTAssertFalse(patterns.isEmpty, "\(level)'s band must reach some training pattern")

            for pattern in patterns {
                let chains = Set(banded.filter { $0.movementPattern == pattern }.map(\.progressionChainId))
                XCTAssertGreaterThanOrEqual(
                    chains.count, 2,
                    "\(level)'s [\(floor), \(cap)] band leaves the \(pattern) pattern only "
                        + "\(chains.count) chain(s), so the variety window has nothing to rotate over"
                )
            }
        }
    }

    /// Every banded pattern spans at least two *tiers* inside a seeded band, so the band is a real
    /// range rather than a single difficulty wearing a `[floor, cap]` label. This is the gate the
    /// `SessionPolicy.ColdStartContract.startingDifficultyFloor` tuning rests on: set a level's floor
    /// to its own cap, or leave a pattern topping out at the floor, and this fails.
    ///
    /// Only the levels that actually band are checked - a beginner's floor is the neutral `1`, so
    /// `ColdStartOverride.startBandedPool` is a no-op for them and the whole catalog beneath the cap
    /// stays eligible.
    func testEveryBandedPatternSpansTwoTiersInsideItsStartBand() {
        typealias Contract = SessionPolicy.ColdStartContract

        for level in FitnessLevel.allCases {
            let floor = Contract.startingDifficultyFloor(for: level)
            let cap = Contract.cappedMaxDifficulty(for: level)
            guard floor > Contract.neutralStartingDifficultyFloor else { continue }

            let banded = exercises.filter {
                $0.phase == .discipline
                    && ($0.pillar == .strength || $0.pillar == .primal)
                    && (floor...cap).contains($0.difficulty)
            }
            for pattern in Set(banded.map(\.movementPattern)) {
                let tiers = Set(banded.filter { $0.movementPattern == pattern }.map(\.difficulty))
                XCTAssertGreaterThanOrEqual(
                    tiers.count, 2,
                    "\(level)'s [\(floor), \(cap)] band collapses the \(pattern) pattern to tier(s) "
                        + "\(tiers.sorted()), so the band is not a real range there"
                )
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

    // MARK: - Demo animations (US-O01)

    /// A movement may only name a demo animation that the app actually ships (US-O01). The player
    /// falls back to its SF Symbol for a missing file rather than blanking, so a broken name is silent
    /// at runtime - this is the gate that makes it loud.
    ///
    /// It is also the enforcement half of `docs/asset-attribution.md`: an animation stays out of the
    /// bundle until it has a cleared license row there, so wiring an `animationName` to an uncleared
    /// asset fails here.
    func testEveryAnimationNameResolvesToABundledFile() {
        let bundle = Bundle(for: AppState.self)
        for ex in exercises {
            guard let name = ex.animationName else { continue }
            XCTAssertNotNil(
                bundle.url(forResource: name, withExtension: "json"),
                "\(ex.id) names the animation \"\(name)\", which the app bundle does not carry - "
                    + "either ship the file (with a cleared row in docs/asset-attribution.md) or drop "
                    + "the animationName"
            )
        }
    }
}
