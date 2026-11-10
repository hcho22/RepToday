import XCTest
@testable import RepToday

/// US-SP02 - "fill the cliff": each phase-gated progression chain (push/squat/core) now carries a
/// mid-tier (difficulty 4) `phase == .strength` bridge between its discipline frontier (difficulty 4)
/// and its difficulty-5 summit, so a newly-Strength-Phase user climbs a ladder rather than jumping
/// straight from difficulty 4 to 5.
///
/// These tests run over the *real* bundled `Exercises.json` (not a fixture): the catalog still loads
/// and validates, every touched chain stays a contiguous, cleanly doubly-linked ladder, and a
/// Strength-Phase user advancing a chain from its discipline frontier is offered the difficulty-4
/// bridge *before* the difficulty-5 skill. US-SP01 already lifted the effective difficulty cap, so
/// this is purely the catalog + selection half of the story. A rung clears the way the rep grammar says
/// (US-TD03): four sets at the top of the user's range, at earned reps.
final class MidTierStrengthSkillTests: XCTestCase {

    // MARK: - Fixtures

    /// One gated chain's three-rung, phase-gated tail: the discipline frontier, the US-SP02 mid-tier
    /// bridge, and the difficulty-5 summit.
    private struct GatedChain {
        let chainId: String
        let isHold: Bool
        let frontier: (id: String, difficulty: Int)
        let bridge: (id: String, difficulty: Int)
        let summit: (id: String, difficulty: Int)
    }

    private let gatedChains: [GatedChain] = [
        GatedChain(
            chainId: "push_horizontal", isHold: false,
            frontier: ("push_archer", 4),
            bridge: ("push_one_arm_assisted", 4),
            summit: ("push_one_arm", 5)
        ),
        GatedChain(
            chainId: "squat", isHold: false,
            frontier: ("squat_shrimp", 4),
            bridge: ("squat_pistol_assisted", 4),
            summit: ("squat_pistol", 5)
        ),
        GatedChain(
            chainId: "core_hollow", isHold: true,
            frontier: ("core_tuck_l_sit", 4),
            bridge: ("core_one_leg_l_sit", 4),
            summit: ("core_l_sit", 5)
        ),
    ]

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A Training Day log whose main station clears `exerciseId` for a user at `level`: four sets at the
    /// top of the level's range (reps, reps per side, or hold seconds), at earned reps that had reached it.
    private func clearingLog(_ exerciseId: String, in library: [Exercise], level: FitnessLevel) throws -> WorkoutLog {
        let exercise = try XCTUnwrap(library.first { $0.id == exerciseId }, "\(exerciseId) must exist in the catalog")
        let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
        return TrainingDayFixtures.log(
            [TrainingDayFixtures.station(exercise.id, pattern: exercise.movementPattern, value: top, earned: top, isHold: exercise.isHold)],
            completedAt: TrainingDayFixtures.date(daysAgo: 1)
        )
    }

    /// The same session one step short of the top: worked, but not cleared.
    private func shortLog(_ exerciseId: String, in library: [Exercise], level: FitnessLevel) throws -> WorkoutLog {
        let exercise = try XCTUnwrap(library.first { $0.id == exerciseId })
        let short = RepGrammar.earnedRange(for: exercise, level: level).upperBound - RepGrammar.step
        return TrainingDayFixtures.log(
            [TrainingDayFixtures.station(exercise.id, pattern: exercise.movementPattern, value: short, earned: short, isHold: exercise.isHold)],
            completedAt: TrainingDayFixtures.date(daysAgo: 1)
        )
    }

    private func strengthUser(level: FitnessLevel = .advanced) -> User {
        User(
            id: "u1", displayName: "Test", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: level, primaryGoal: .buildStrength, sitsLong: false,
                injuries: [], typicalAvailableMinutes: 20
            ),
            phase: .strength,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 100, workoutsThisWeek: 3,
                longestChain: 8, totalWorkoutsCompleted: 40, totalMinutesExercised: 600
            )
        )
    }

    // MARK: - Catalog still loads / validates

    /// The bundled catalog with the three new mid-tier skills still decodes and passes every
    /// load-time integrity rule (`MockExerciseService.init` throws otherwise), and each new skill is
    /// present, zero-equipment, and `phase == .strength`.
    func testCatalogLoadsAndValidatesWithTheNewSkills() async throws {
        // Constructing the service *is* the load-time validation - it throws on the first violation.
        _ = try MockExerciseService()

        let library = try await library()
        let byId = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        for chain in gatedChains {
            let bridge = try XCTUnwrap(byId[chain.bridge.id], "\(chain.bridge.id) must exist in the catalog")
            XCTAssertEqual(bridge.phase, .strength, "\(bridge.id) is a phase-gated skill")
            XCTAssertEqual(bridge.equipment, [], "\(bridge.id) must be zero-equipment (Zero-Equipment Floor)")
            XCTAssertEqual(bridge.difficulty, chain.bridge.difficulty, "\(bridge.id) sits at the authored mid tier")
            XCTAssertEqual(bridge.isHold, chain.isHold, "\(bridge.id) matches its neighbours' hold/rep shape")
        }
    }

    // MARK: - Chain continuity (contiguous, gap-free, duplicate-free, cleanly doubly-linked)

    /// Every touched chain is a contiguous `0..<n` `progressionOrder` sequence with no gaps or
    /// duplicates, and each rung's `regressionId`/`progressionId` points at its exact neighbour
    /// (nil at the ends) - so `ProgressionChainSelection` walks a clean ladder.
    func testTouchedChainsAreContiguousAndCleanlyLinked() async throws {
        let library = try await library()
        let byChain = Dictionary(grouping: library, by: \.progressionChainId)

        for chain in gatedChains {
            let rungs = try XCTUnwrap(byChain[chain.chainId]).sorted { $0.progressionOrder < $1.progressionOrder }

            let orders = rungs.map(\.progressionOrder)
            XCTAssertEqual(orders, Array(0..<rungs.count),
                           "chain \(chain.chainId) orders must be contiguous/gap-free/duplicate-free")

            for (index, rung) in rungs.enumerated() {
                XCTAssertEqual(rung.regressionId, index == 0 ? nil : rungs[index - 1].id,
                               "\(rung.id) regressionId must link to its lower neighbour")
                XCTAssertEqual(rung.progressionId, index == rungs.count - 1 ? nil : rungs[index + 1].id,
                               "\(rung.id) progressionId must link to its higher neighbour")
            }

            // The gated tail is exactly frontier(d4,discipline) -> bridge(d4,strength) -> summit(d5,strength),
            // adjacent and in that order.
            let byId = Dictionary(uniqueKeysWithValues: rungs.map { ($0.id, $0) })
            let frontier = try XCTUnwrap(byId[chain.frontier.id])
            let bridge = try XCTUnwrap(byId[chain.bridge.id])
            let summit = try XCTUnwrap(byId[chain.summit.id])
            XCTAssertEqual(frontier.progressionId, bridge.id, "the discipline frontier progresses into the mid-tier bridge")
            XCTAssertEqual(bridge.progressionId, summit.id, "the mid-tier bridge progresses into the summit")
            XCTAssertEqual(bridge.progressionOrder, frontier.progressionOrder + 1, "the bridge sits directly above the frontier")
            XCTAssertEqual(summit.progressionOrder, bridge.progressionOrder + 1, "the summit sits directly above the bridge")
        }
    }

    // MARK: - The ladder no longer jumps from difficulty 4 to 5 (US-SP02 Validation Test)

    /// For each gated chain, a Strength-Phase user standing at the discipline frontier (worked and
    /// cleared) is offered the **difficulty-4 bridge**, not the difficulty-5 summit - proof the
    /// phase-gated segment climbs one rung at a time. Then, having cleared the bridge, the same user
    /// is offered the difficulty-5 summit. Run over every chain; the push case is the story's own
    /// Validation Test.
    func testStrengthUserStepsThroughTheMidTierBeforeTheDifficultyFiveSkill() async throws {
        let library = try await library()
        let level = FitnessLevel.advanced
        let user = strengthUser(level: level)
        // US-SP01: a strength-phase user's effective cap is the full 1...5 catalog, so both gated
        // skills are eligible. Reusing the real Step 4 filter proves the two halves compose.
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []).map(\.id))

        for chain in gatedChains {
            let members = library.filter { $0.progressionChainId == chain.chainId }

            // Sanity: both gated skills are actually reachable for this earned Strength-Phase user.
            XCTAssertTrue(eligibleIds.contains(chain.bridge.id),
                          "the mid-tier \(chain.bridge.id) must be eligible for a Strength-Phase user")
            XCTAssertTrue(eligibleIds.contains(chain.summit.id),
                          "the summit \(chain.summit.id) must be eligible for a Strength-Phase user")

            // Step 1: standing at (and having cleared) the discipline frontier, the next rung offered
            // is the difficulty-4 bridge - never a direct jump to the difficulty-5 summit.
            // One step short of the top, the frontier holds.
            let short = try shortLog(chain.frontier.id, in: library, level: level)
            XCTAssertEqual(
                ProgressionChainSelection.selectInChain(members, eligibleIds: eligibleIds, recentLogs: [short], level: level)?.exercise.id,
                chain.frontier.id,
                "\(chain.chainId): a session short of the top of the range does not clear the frontier"
            )

            let atFrontier = try clearingLog(chain.frontier.id, in: library, level: level)
            let fromFrontier = try XCTUnwrap(
                ProgressionChainSelection.selectInChain(members, eligibleIds: eligibleIds, recentLogs: [atFrontier], level: level),
                "chain \(chain.chainId) must resolve a tier"
            )
            XCTAssertEqual(fromFrontier.exercise.id, chain.bridge.id,
                           "advancing \(chain.chainId) from its frontier must surface the mid-tier bridge first")
            XCTAssertTrue(fromFrontier.didAdvance, "clearing the frontier advances one rung")
            XCTAssertLessThan(fromFrontier.exercise.difficulty, chain.summit.difficulty,
                              "the surfaced rung is easier than the difficulty-5 skill (no 4->5 jump)")
            XCTAssertNotEqual(fromFrontier.exercise.id, chain.summit.id,
                              "the difficulty-5 skill is not offered before the mid-tier bridge")

            // Step 2: having now cleared the mid-tier bridge, the summit is offered.
            let atBridge = try clearingLog(chain.bridge.id, in: library, level: level)
            let fromBridge = try XCTUnwrap(
                ProgressionChainSelection.selectInChain(members, eligibleIds: eligibleIds, recentLogs: [atBridge], level: level)
            )
            XCTAssertEqual(fromBridge.exercise.id, chain.summit.id,
                           "clearing the mid-tier bridge advances \(chain.chainId) to the difficulty-5 summit")
            XCTAssertEqual(fromBridge.exercise.difficulty, chain.summit.difficulty)
        }
    }

    /// The mirror of the double-gate that motivates the ladder: a **discipline**-phase user at the
    /// same frontier is *not* handed the mid-tier bridge (it is phase-gated), so they stay on the
    /// frontier. This is what makes the Strength-Phase step above a real unlock rather than a no-op.
    func testDisciplineUserNeverReachesTheMidTierBridge() async throws {
        let library = try await library()
        let disciplineUser = User(
            id: "d1", displayName: "Disc", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: .advanced, primaryGoal: .buildStrength, sitsLong: false,
                injuries: [], typicalAvailableMinutes: 20
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 100, workoutsThisWeek: 3,
                longestChain: 8, totalWorkoutsCompleted: 40, totalMinutesExercised: 600
            )
        )
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: disciplineUser, recentLogs: []).map(\.id))

        for chain in gatedChains {
            XCTAssertFalse(eligibleIds.contains(chain.bridge.id),
                           "the phase-gated \(chain.bridge.id) must be hidden from a discipline user")
            let members = library.filter { $0.progressionChainId == chain.chainId }
            let atFrontier = try clearingLog(chain.frontier.id, in: library, level: .advanced)
            let chosen = try XCTUnwrap(
                ProgressionChainSelection.selectInChain(members, eligibleIds: eligibleIds, recentLogs: [atFrontier], level: .advanced)
            )
            XCTAssertEqual(chosen.exercise.id, chain.frontier.id,
                           "a discipline user clears the frontier but the gated bridge is out of reach, so they stay put")
            XCTAssertFalse(chosen.didAdvance, "no advancement into a phase-gated rung for a discipline user")
        }
    }
}
