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
/// already lifted the effective difficulty cap; this story only gives hinge a skill to reach). A rung
/// clears the way the rep grammar says (US-TD03): four sets at the top of the user's range, at earned reps.
final class HingeStrengthSkillTests: XCTestCase {

    // The hinge_bridge chain's phase-gated tail: the discipline frontier, the US-SP03 mid-tier bridge,
    // and the difficulty-5 summit.
    private let chainId = "hinge_bridge"
    private let frontier = (id: "hinge_long_lever_bridge", difficulty: 4)
    private let bridge = (id: "hinge_nordic_assisted", difficulty: 4)
    private let summit = (id: "hinge_nordic", difficulty: 5)

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A Training Day log whose main station clears `exercise` for a user at `level`: four sets at the
    /// top of the level's range, prescribed at earned reps that had reached it.
    private func clearingLog(_ exercise: Exercise, level: FitnessLevel, daysAgo: Int = 1) -> WorkoutLog {
        let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
        return TrainingDayFixtures.log(
            [TrainingDayFixtures.station(exercise.id, pattern: .hinge, value: top, earned: top, isHold: exercise.isHold)],
            completedAt: TrainingDayFixtures.date(daysAgo: daysAgo)
        )
    }

    private func exercise(_ id: String, in library: [Exercise]) throws -> Exercise {
        try XCTUnwrap(library.first { $0.id == id }, "\(id) must exist in the catalog")
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
        let level = FitnessLevel.advanced
        let user = TrainingDayFixtures.user(level: level, phase: .strength)
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []).map(\.id))
        let members = library.filter { $0.progressionChainId == chainId }

        XCTAssertTrue(eligibleIds.contains(bridge.id),
                      "the mid-tier \(bridge.id) must be eligible for a Strength-Phase user")
        XCTAssertTrue(eligibleIds.contains(summit.id),
                      "the summit \(summit.id) must be eligible for a Strength-Phase user")

        let fromFrontier = try XCTUnwrap(
            ProgressionChainSelection.selectInChain(
                members, eligibleIds: eligibleIds,
                recentLogs: [clearingLog(try exercise(frontier.id, in: library), level: level)],
                level: level
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
                recentLogs: [clearingLog(try exercise(bridge.id, in: library), level: level)],
                level: level
            )
        )
        XCTAssertEqual(fromBridge.exercise.id, summit.id,
                       "clearing the mid-tier bridge advances hinge to the difficulty-5 summit")
        XCTAssertEqual(fromBridge.exercise.difficulty, summit.difficulty)
    }

    /// The freshly-reached bridge opens at the bottom of the user's range, so it can never clear on
    /// first exposure: each finished session climbs Earned Reps one step, and only a session served at
    /// the top of the range clears it - four sessions for an intermediate (15, 20, 25, 30), eight for an
    /// advanced user whose range runs to 50. A session at the top the user marks "couldn't finish"
    /// never clears it.
    func testFreshHingeBridgeTakesAtLeastFourSessionsToClear() async throws {
        let library = try await library()
        let bridgeEx = try exercise(bridge.id, in: library)
        let members = library.filter { $0.progressionChainId == chainId }
        let eligibleIds = Set(members.map(\.id))

        for (level, expectedSessions) in [(FitnessLevel.intermediate, 4), (.advanced, 8)] {
            let range = RepGrammar.earnedRange(for: bridgeEx, level: level)
            XCTAssertEqual(AdaptiveOverload.target(for: bridgeEx, level: level, recentLogs: []).reps, range.lowerBound,
                           "\(level): the bridge opens at the bottom of the range")

            // The user cleared the frontier, which put them on the bridge.
            var logs = [clearingLog(try exercise(frontier.id, in: library), level: level, daysAgo: 30)]
            var served: [Int] = []
            func selected() throws -> String {
                try XCTUnwrap(ProgressionChainSelection.selectInChain(
                    members, eligibleIds: eligibleIds, recentLogs: logs, level: level
                )).exercise.id
            }
            func session(_ target: OverloadTarget, couldNotFinish: Bool = false) -> WorkoutLog {
                TrainingDayFixtures.log(
                    [TrainingDayFixtures.station(bridge.id, pattern: .hinge, value: target.value, earned: target.earned,
                                                 couldNotFinish: couldNotFinish ? true : nil)],
                    completedAt: TrainingDayFixtures.date(daysAgo: 29 - served.count),
                    difficulty: couldNotFinish ? .tooHard : .justRight
                )
            }

            while try selected() == bridge.id, served.count < 20 {
                let target = AdaptiveOverload.target(for: bridgeEx, level: level, recentLogs: logs)
                if target.value == range.upperBound {
                    XCTAssertEqual(try selected(), bridge.id)
                    let marked = logs + [session(target, couldNotFinish: true)]
                    XCTAssertEqual(
                        try XCTUnwrap(ProgressionChainSelection.selectInChain(
                            members, eligibleIds: eligibleIds, recentLogs: marked, level: level
                        )).exercise.id,
                        bridge.id,
                        "\(level): a session at the top marked couldn't finish never clears it"
                    )
                }
                logs.append(session(target))
                served.append(target.value)
            }

            XCTAssertEqual(try selected(), summit.id, "\(level): the finished session at the top clears the bridge")
            XCTAssertEqual(served.count, expectedSessions, "\(level): served \(served)")
            XCTAssertEqual(served, Array(stride(from: range.lowerBound, through: range.upperBound, by: RepGrammar.step)))
            XCTAssertGreaterThanOrEqual(served.count, 4, "a newly reached move takes at least four sessions")
        }
    }

    /// The mirror: a **discipline**-phase user at the same frontier can reach neither new hinge skill
    /// (both are phase-gated), so they stay on the frontier - which is what makes the Strength-Phase
    /// step above a real unlock rather than a no-op. This is the "and none for a discipline user" half
    /// of the story's Validation Test.
    func testDisciplineUserNeverReachesTheHingeStrengthSkills() async throws {
        let library = try await library()
        let level = FitnessLevel.advanced
        let disciplineUser = TrainingDayFixtures.user(level: level, phase: .discipline)
        let eligibleIds = Set(ExercisePoolFilter.eligiblePool(from: library, user: disciplineUser, recentLogs: []).map(\.id))

        XCTAssertFalse(eligibleIds.contains(bridge.id), "the phase-gated \(bridge.id) must be hidden from a discipline user")
        XCTAssertFalse(eligibleIds.contains(summit.id), "the phase-gated \(summit.id) must be hidden from a discipline user")

        let members = library.filter { $0.progressionChainId == chainId }
        let chosen = try XCTUnwrap(
            ProgressionChainSelection.selectInChain(
                members, eligibleIds: eligibleIds,
                recentLogs: [clearingLog(try exercise(frontier.id, in: library), level: level)],
                level: level
            )
        )
        XCTAssertEqual(chosen.exercise.id, frontier.id,
                       "a discipline user clears the frontier but the gated skills are out of reach, so they stay put")
        XCTAssertFalse(chosen.didAdvance, "no advancement into a phase-gated rung for a discipline user")
    }

    /// US-SP03 changes no evaluator logic, but the story asks us to pin that `PhaseEvaluator` still
    /// resolves hinge competence as one of the four foundations - so an added hinge skill can never
    /// silently drop hinge out of the Strength-Phase competence gate. Since ADR-0006 hinge is the
    /// Hinge side of the Legs foundation, and Legs is cleared only when both its sides are.
    func testPhaseEvaluatorStillTreatsHingeAsAFoundation() {
        XCTAssertEqual(StrengthFoundation.allLines.map(\.pattern), [.push, .pull, .squat, .hinge, .core])
        XCTAssertEqual(StrengthFoundation.legs.lines.map(\.pattern), [.squat, .hinge])
        XCTAssertTrue(StrengthFoundation.foundationPatterns.contains(.hinge),
                      "hinge must remain part of a foundation the Strength Phase gates on")
    }
}
