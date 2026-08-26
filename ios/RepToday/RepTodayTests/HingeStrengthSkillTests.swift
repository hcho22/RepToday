import XCTest
@testable import RepToday

/// US-SP03 - "the missing hinge skill": before this story push/squat/core each had an earned
/// Strength-Phase ladder (a difficulty-4 bridge into a difficulty-5 summit, US-SP02) but hinge had
/// *no* `phase == .strength` skill at all - so a Strength-Phase user had an earned skill for only
/// three of the four foundations. This story authors the full strength hinge ladder on the
/// `hinge_bridge` chain (whose discipline frontier `hinge_long_lever_bridge` already sits at
/// difficulty 4): an **Assisted Nordic Curl** (difficulty 4, `phase == .strength`) bridge into a
/// full **Nordic Curl** (difficulty 5, `phase == .strength`) summit - the canonical advanced,
/// zero-equipment posterior-chain hinge, apartment-friendly with the feet braced under furniture
/// (bracing is not "equipment" in this catalog's sense).
///
/// These tests run over the *real* bundled `Exercises.json` and mirror `MidTierStrengthSkillTests`:
/// the catalog still loads/validates, the touched chain is a clean doubly-linked ladder, and the
/// two new skills are reachable by a Strength-Phase user and not by a discipline user (US-SP01
/// already lifted the effective difficulty cap; this story only gives hinge a skill to reach).
final class HingeStrengthSkillTests: XCTestCase {

    // The hinge_bridge chain's new phase-gated tail: the discipline frontier, the US-SP03 mid-tier
    // bridge, and the difficulty-5 summit, with the clearing value that advances each rung.
    private let chainId = "hinge_bridge"
    private let frontier = (id: "hinge_long_lever_bridge", difficulty: 4, clear: 8)  // "3x8 slow reps per side"
    private let bridge = (id: "hinge_nordic_assisted", difficulty: 4, clear: 6)       // "3x6 clean reps"
    private let summit = (id: "hinge_nordic", difficulty: 5)

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A log in which `exerciseId` was worked (non-skipped) with three rep-based sets each meeting
    /// `value`, enough to clear a `"3x{value}..."` tier.
    private func clearingLog(_ exerciseId: String, value: Int) -> WorkoutLog {
        let sets = (0..<3).map { _ in CompletedSet(reps: value, durationSeconds: nil) }
        return WorkoutLog(
            id: UUID(), workoutId: UUID(),
            completedAt: Date(timeIntervalSince1970: 1_760_000_000),
            requestedMinutes: 20, durationMinutes: 20, shape: .singleFocus, focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [LoggedExercise(
                id: UUID(), exerciseId: exerciseId, pillar: .strength,
                movementPattern: .hinge, completedSets: sets, skipped: false
            )]
        )
    }

    private func user(level: FitnessLevel, phase: Phase) -> User {
        User(
            id: "u1", displayName: "Test", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: level, primaryGoal: .buildStrength, sitsLong: false,
                injuries: [], typicalAvailableMinutes: 20
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 100, workoutsThisWeek: 3,
                longestChain: 8, totalWorkoutsCompleted: 40, totalMinutesExercised: 600
            )
        )
    }

    // MARK: - Catalog loads / validates with the new hinge skills

    /// The bundled catalog with the two new hinge skills still decodes and passes every load-time
    /// integrity rule (`MockExerciseService.init` throws otherwise), and each new skill is present,
    /// zero-equipment (Zero-Equipment Floor), rep-based, and `phase == .strength`.
    func testCatalogLoadsAndValidatesWithTheNewHingeSkills() async throws {
        _ = try MockExerciseService()  // constructing the service *is* the load-time validation

        let byId = Dictionary(uniqueKeysWithValues: try await library().map { ($0.id, $0) })
        for skill in [bridge.id, summit.id] {
            let ex = try XCTUnwrap(byId[skill], "\(skill) must exist in the catalog")
            XCTAssertEqual(ex.phase, .strength, "\(skill) is a phase-gated skill")
            XCTAssertEqual(ex.movementPattern, .hinge, "\(skill) is a hinge skill")
            XCTAssertEqual(ex.equipment, [], "\(skill) must be zero-equipment (Zero-Equipment Floor)")
            XCTAssertFalse(ex.isHold, "the Nordic-curl ladder is rep-based")
        }
        XCTAssertEqual(byId[bridge.id]?.difficulty, bridge.difficulty)
        XCTAssertEqual(byId[summit.id]?.difficulty, summit.difficulty)
    }

    /// The `hinge_bridge` chain is a contiguous, gap-free, duplicate-free `progressionOrder` sequence
    /// with each rung's `regressionId`/`progressionId` pointing at its exact neighbour (nil at the
    /// ends), and its gated tail is exactly frontier(d4,discipline) -> bridge(d4,strength) ->
    /// summit(d5,strength), adjacent and in order - so `ProgressionChainSelection` walks a clean ladder.
    func testHingeBridgeChainIsContiguousAndCleanlyLinked() async throws {
        let rungs = try await library()
            .filter { $0.progressionChainId == chainId }
            .sorted { $0.progressionOrder < $1.progressionOrder }

        XCTAssertEqual(rungs.map(\.progressionOrder), Array(0..<rungs.count),
                       "\(chainId) orders must be contiguous/gap-free/duplicate-free")
        for (index, rung) in rungs.enumerated() {
            XCTAssertEqual(rung.regressionId, index == 0 ? nil : rungs[index - 1].id,
                           "\(rung.id) regressionId must link to its lower neighbour")
            XCTAssertEqual(rung.progressionId, index == rungs.count - 1 ? nil : rungs[index + 1].id,
                           "\(rung.id) progressionId must link to its higher neighbour")
        }

        let byId = Dictionary(uniqueKeysWithValues: rungs.map { ($0.id, $0) })
        let frontierEx = try XCTUnwrap(byId[frontier.id])
        let bridgeEx = try XCTUnwrap(byId[bridge.id])
        let summitEx = try XCTUnwrap(byId[summit.id])
        XCTAssertEqual(frontierEx.progressionId, bridge.id, "the discipline frontier progresses into the bridge")
        XCTAssertEqual(bridgeEx.progressionId, summit.id, "the bridge progresses into the summit")
        XCTAssertEqual(bridgeEx.progressionOrder, frontierEx.progressionOrder + 1)
        XCTAssertEqual(summitEx.progressionOrder, bridgeEx.progressionOrder + 1)
    }

    // MARK: - Reachable by a Strength-Phase user, not a discipline user (US-SP03 Validation Test)

    /// A Strength-Phase user standing at (and having cleared) the discipline frontier is offered the
    /// difficulty-4 bridge - never a direct jump to the difficulty-5 summit - and then, having cleared
    /// the bridge, is offered the summit. Both skills are eligible under the real Step 4 filter for
    /// this earned user (US-SP01's lifted cap composing with the new catalog).
    func testStrengthUserClimbsTheHingeLadderOneRungAtATime() async throws {
        let library = try await library()
        let user = user(level: .advanced, phase: .strength)
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []).map(\.id))
        let members = library.filter { $0.progressionChainId == chainId }

        XCTAssertTrue(eligibleIds.contains(bridge.id),
                      "the mid-tier \(bridge.id) must be eligible for a Strength-Phase user")
        XCTAssertTrue(eligibleIds.contains(summit.id),
                      "the summit \(summit.id) must be eligible for a Strength-Phase user")

        let fromFrontier = try XCTUnwrap(
            ProgressionChainSelection.selectInChain(
                members, eligibleIds: eligibleIds,
                recentLogs: [clearingLog(frontier.id, value: frontier.clear)]
            ),
            "\(chainId) must resolve a tier"
        )
        XCTAssertEqual(fromFrontier.exercise.id, bridge.id,
                       "advancing hinge from its frontier must surface the mid-tier bridge first")
        XCTAssertTrue(fromFrontier.didAdvance, "clearing the frontier advances one rung")
        XCTAssertLessThan(fromFrontier.exercise.difficulty, summit.difficulty,
                          "the surfaced rung is easier than the difficulty-5 skill (no 4->5 jump)")

        let fromBridge = try XCTUnwrap(
            ProgressionChainSelection.selectInChain(
                members, eligibleIds: eligibleIds,
                recentLogs: [clearingLog(bridge.id, value: bridge.clear)]
            )
        )
        XCTAssertEqual(fromBridge.exercise.id, summit.id,
                       "clearing the mid-tier bridge advances hinge to the difficulty-5 summit")
        XCTAssertEqual(fromBridge.exercise.difficulty, summit.difficulty)
    }

    /// The freshly-advanced bridge must not clear itself on first exposure: with no prior history the
    /// engine doses `hinge_nordic_assisted` off its `defaultReps` (US-CC09 records prescribed=performed),
    /// so if that seed matched the "3x6 clean reps" threshold the user would leap frontier -> bridge ->
    /// summit in two sessions with no dwell on the bridge. Pin that the first prescription sits strictly
    /// below the clearing threshold, so the climb takes multiple sessions ("a rung at a time, no 4->5 jump").
    func testFreshHingeBridgePrescriptionSitsBelowItsClearingThreshold() async throws {
        let library = try await library()
        let bridgeEx = try XCTUnwrap(library.first { $0.id == bridge.id })

        let firstTarget = AdaptiveOverload.target(for: bridgeEx, recentLogs: [])
        let firstReps = try XCTUnwrap(firstTarget.reps, "the bridge is rep-based, so it has a rep target")
        XCTAssertLessThan(firstReps, bridge.clear,
                          "the fresh bridge prescription must sit below its \(bridge.clear)-rep clearing threshold, "
                          + "so a Strength-Phase user must climb across sessions before reaching the summit")
    }

    /// The mirror: a **discipline**-phase user at the same frontier can reach neither new hinge skill
    /// (both are phase-gated), so they stay on the frontier - which is what makes the Strength-Phase
    /// step above a real unlock rather than a no-op. This is the "and none for a discipline user" half
    /// of the story's Validation Test.
    func testDisciplineUserNeverReachesTheHingeStrengthSkills() async throws {
        let library = try await library()
        let disciplineUser = user(level: .advanced, phase: .discipline)
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: disciplineUser, recentLogs: []).map(\.id))

        XCTAssertFalse(eligibleIds.contains(bridge.id), "the phase-gated \(bridge.id) must be hidden from a discipline user")
        XCTAssertFalse(eligibleIds.contains(summit.id), "the phase-gated \(summit.id) must be hidden from a discipline user")

        let members = library.filter { $0.progressionChainId == chainId }
        let chosen = try XCTUnwrap(
            ProgressionChainSelection.selectInChain(
                members, eligibleIds: eligibleIds,
                recentLogs: [clearingLog(frontier.id, value: frontier.clear)]
            )
        )
        XCTAssertEqual(chosen.exercise.id, frontier.id,
                       "a discipline user clears the frontier but the gated skills are out of reach, so they stay put")
        XCTAssertFalse(chosen.didAdvance, "no advancement into a phase-gated rung for a discipline user")
    }

    /// US-SP03 changes no evaluator logic, but the story asks us to pin that `PhaseEvaluator` still
    /// resolves hinge competence as one of the four foundations - so an added hinge skill can never
    /// silently drop hinge out of the Strength-Phase competence gate.
    func testPhaseEvaluatorStillTreatsHingeAsAFoundation() {
        XCTAssertEqual(PhaseEvaluator.foundationalPatterns, [.push, .squat, .hinge, .core])
        XCTAssertTrue(PhaseEvaluator.foundationalPatterns.contains(.hinge),
                      "hinge must remain one of the foundations the Strength Phase gates on")
    }
}
