import XCTest
@testable import RepToday

/// Tests US-AC01: the derived coach context bundle - the single, auditable definition of what leaves
/// the device for the premium coach. These assert two things the privacy contract turns on: the
/// bundle is built faithfully from the app's *already-computed* values (chain positions, the
/// consistency trend, the earned phase, recent patterns), and its wire encoding contains **only**
/// those non-identifying fields - never raw history and never an identity field.
final class CoachContextBundleTests: XCTestCase {

    // MARK: - Fixtures

    private func exercise(id: String, name: String, pattern: MovementPattern) -> Exercise {
        Exercise(
            id: id,
            displayName: name,
            pillar: .strength,
            movementPattern: pattern,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "\(pattern.rawValue)_chain",
            progressionOrder: 2,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x10 clean reps",
            apartmentFriendly: true
        )
    }

    private func log(daysAgo: Int, patterns: [MovementPattern]) -> WorkoutLog {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400)
        return WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: completedAt,
            requestedMinutes: 15,
            durationMinutes: 15,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: patterns.map { pattern in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "\(pattern.rawValue)_x",
                    pillar: .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: false
                )
            }
        )
    }

    private func trend(_ scores: [Double]) -> [ConsistencyTrendPoint] {
        scores.enumerated().map { index, score in
            ConsistencyTrendPoint(
                weekStart: Date(timeIntervalSince1970: Double(index) * 604_800),
                score: score
            )
        }
    }

    // MARK: - Build faithfulness

    func testBuildsSummaryFromComputedSources() {
        let positions = [
            ChainPositionSummary(
                pattern: .push,
                currentExercise: exercise(id: "push_standard", name: "Standard Push-Up", pattern: .push),
                tier: 3,
                chainLength: 7,
                hasNextTier: true
            ),
            ChainPositionSummary(pattern: .squat, currentExercise: nil, tier: 0, chainLength: 0, hasNextTier: false),
        ]

        let bundle = CoachContextBundle.make(
            phase: .strength,
            requestedMinutes: 20,
            chainPositions: positions,
            consistencyTrend: trend([40, 55, 72]),
            recentLogs: [log(daysAgo: 1, patterns: [.push, .core])]
        )

        XCTAssertEqual(bundle.phase, "strength")
        XCTAssertEqual(bundle.requestedMinutes, 20)
        XCTAssertEqual(bundle.chainPositions.count, 2)

        let push = bundle.chainPositions[0]
        XCTAssertEqual(push.pattern, "push")
        XCTAssertEqual(push.currentExercise, "Standard Push-Up")
        XCTAssertEqual(push.tier, 3)
        XCTAssertEqual(push.chainLength, 7)
        XCTAssertTrue(push.hasNextTier)

        // A never-trained pattern carries no exercise name (not identifying, just "not started").
        XCTAssertNil(bundle.chainPositions[1].currentExercise)

        XCTAssertEqual(bundle.consistency.currentScore, 72)
        XCTAssertEqual(bundle.consistency.direction, .rising)
    }

    // MARK: - Recent patterns: distinct, most-recent-first, capped

    func testRecentPatternsAreDistinctMostRecentFirstAndCapped() {
        let logs = [
            log(daysAgo: 3, patterns: [.hinge, .core]),
            log(daysAgo: 1, patterns: [.push, .push, .squat]), // most recent; dup push collapses
            log(daysAgo: 2, patterns: [.core, .push]),
        ]
        let bundle = CoachContextBundle.make(
            phase: .discipline,
            requestedMinutes: 10,
            chainPositions: [],
            consistencyTrend: trend([50]),
            recentLogs: logs,
            recentPatternLimit: 3
        )
        // Most-recent session first (push, squat), then the next session's new pattern (core); hinge
        // falls off the cap of 3. First occurrence wins, so no duplicate push.
        XCTAssertEqual(bundle.recentPatterns, ["push", "squat", "core"])
    }

    func testRecentPatternsEmptyWhenNoLogs() {
        let bundle = CoachContextBundle.make(
            phase: .discipline,
            requestedMinutes: 5,
            chainPositions: [],
            consistencyTrend: [],
            recentLogs: []
        )
        XCTAssertEqual(bundle.recentPatterns, [])
        XCTAssertEqual(bundle.consistency.currentScore, 0)
        XCTAssertEqual(bundle.consistency.direction, .new)
    }

    // MARK: - Consistency direction

    func testConsistencyDirectionFalling() {
        let bundle = CoachContextBundle.make(
            phase: .discipline, requestedMinutes: 10, chainPositions: [],
            consistencyTrend: trend([80, 60, 45]), recentLogs: []
        )
        XCTAssertEqual(bundle.consistency.currentScore, 45)
        XCTAssertEqual(bundle.consistency.direction, .falling)
    }

    func testConsistencyDirectionSteadyWithinBand() {
        let bundle = CoachContextBundle.make(
            phase: .discipline, requestedMinutes: 10, chainPositions: [],
            consistencyTrend: trend([70, 71, 70.5]), recentLogs: []
        )
        XCTAssertEqual(bundle.consistency.currentScore, 71) // 70.5 rounds to 71 (banker's? .rounded() = 70 or 71)
        XCTAssertEqual(bundle.consistency.direction, .steady)
    }

    func testConsistencyDirectionNewWithSinglePoint() {
        let bundle = CoachContextBundle.make(
            phase: .discipline, requestedMinutes: 10, chainPositions: [],
            consistencyTrend: trend([66]), recentLogs: []
        )
        XCTAssertEqual(bundle.consistency.currentScore, 66)
        XCTAssertEqual(bundle.consistency.direction, .new)
    }

    // MARK: - Wire shape: only non-identifying fields leave the device

    func testEncodedWireCarriesOnlyTheAuditedFields() throws {
        let bundle = CoachContextBundle.make(
            phase: .strength,
            requestedMinutes: 20,
            chainPositions: [
                ChainPositionSummary(
                    pattern: .push,
                    currentExercise: exercise(id: "push_standard", name: "Standard Push-Up", pattern: .push),
                    tier: 3, chainLength: 7, hasNextTier: true
                ),
            ],
            consistencyTrend: trend([40, 72]),
            recentLogs: [log(daysAgo: 1, patterns: [.push])]
        )

        let data = try JSONEncoder().encode(bundle)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            ["phase", "requestedMinutes", "chainPositions", "recentPatterns", "consistency"]
        )

        let chain = try XCTUnwrap((object["chainPositions"] as? [[String: Any]])?.first)
        XCTAssertEqual(
            Set(chain.keys),
            ["pattern", "currentExercise", "tier", "chainLength", "hasNextTier"]
        )
        let consistency = try XCTUnwrap(object["consistency"] as? [String: Any])
        XCTAssertEqual(Set(consistency.keys), ["currentScore", "direction"])

        // No identity field can appear anywhere in the serialized bundle.
        let wire = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in ["installid", "idfa", "identifierforvendor", "appleid", "email", "keychain", "uuid", "\"id\""] {
            XCTAssertFalse(wire.contains(forbidden), "bundle wire must not contain \(forbidden): \(wire)")
        }
    }
}
