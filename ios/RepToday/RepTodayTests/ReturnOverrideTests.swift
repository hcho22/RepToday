import XCTest
@testable import RepToday

/// Tests the Return override and the Re-entry Ramp (US-E06): the pure `ReturnOverride` module that
/// makes discipline override optimization after a gap.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: a Return is detected once the gap
/// since the last completed session crosses the threshold; a Return leads with strength (US-005) while
/// keeping the comeback gentle via the capped eligible difficulty and eased volume floor regardless of
/// staleness; and the Re-entry Ramp's volume scale starts at the gentle floor and climbs back to
/// neutral as the counter decrements. The end-to-end behavior over the real pipeline lives in
/// `SessionAssemblyTests`, and the Step 6 volume hold in `AdaptiveOverloadTests`.
final class ReturnOverrideTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A minimal completed session `daysAgo`; the contents don't matter for gap detection.
    private func log(daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    private func exercise(id: String, difficulty: Int) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: .strength,
            movementPattern: .squat,
            category: .strength,
            difficulty: difficulty,
            phase: .discipline,
            equipment: [],
            isHold: false,
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "chain",
            progressionOrder: difficulty,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x15",
            apartmentFriendly: true
        )
    }

    // MARK: - Return detection

    func testGapAtOrAboveThresholdIsReturn() {
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: [log(daysAgo: 7)], asOf: asOf, calendar: calendar),
                      "a gap exactly at the threshold is a Return")
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: [log(daysAgo: 10)], asOf: asOf, calendar: calendar),
                      "a longer gap is a Return")
    }

    func testGapBelowThresholdIsNotReturn() {
        XCTAssertFalse(ReturnOverride.isReturn(recentLogs: [log(daysAgo: 6)], asOf: asOf, calendar: calendar),
                       "a gap under the threshold is a normal session")
        XCTAssertFalse(ReturnOverride.isReturn(recentLogs: [log(daysAgo: 1)], asOf: asOf, calendar: calendar),
                       "yesterday's session is not a Return")
    }

    func testNoHistoryIsNotReturn() {
        XCTAssertFalse(ReturnOverride.isReturn(recentLogs: [], asOf: asOf, calendar: calendar),
                       "a fresh user with no history is never returning")
        XCTAssertNil(ReturnOverride.daysSinceLastSession(recentLogs: [], asOf: asOf, calendar: calendar))
    }

    func testDaysSinceLastSessionUsesMostRecent() {
        // The most recent session (2 days ago) defines the gap, not the oldest (20 days ago).
        let logs = [log(daysAgo: 20), log(daysAgo: 2), log(daysAgo: 15)]
        XCTAssertEqual(ReturnOverride.daysSinceLastSession(recentLogs: logs, asOf: asOf, calendar: calendar), 2)
        XCTAssertFalse(ReturnOverride.isReturn(recentLogs: logs, asOf: asOf, calendar: calendar),
                       "a recent session among older ones is not a Return")
    }

    // MARK: - Difficulty cap

    func testReturnPoolCapsDifficulty() {
        let pool = [
            exercise(id: "easy", difficulty: 1),
            exercise(id: "cap", difficulty: 2),
            exercise(id: "hard", difficulty: 4),
        ]
        let capped = ReturnOverride.returnPool(pool, isReturn: true)
        XCTAssertTrue(capped.allSatisfy { $0.difficulty <= ReturnOverride.returnMaxDifficulty })
        XCTAssertFalse(capped.contains { $0.id == "hard" }, "an over-cap movement is dropped on a Return")

        // Not a Return: the pool is untouched.
        XCTAssertEqual(ReturnOverride.returnPool(pool, isReturn: false).count, pool.count)
    }

    /// The cap must never empty the pool - it returns the uncapped pool rather than break generation.
    func testReturnPoolNeverEmptiesThePool() {
        let onlyHard = [exercise(id: "hard", difficulty: 5)]
        XCTAssertEqual(
            ReturnOverride.returnPool(onlyHard, isReturn: true).count, 1,
            "when nothing meets the cap the uncapped pool is returned rather than an empty one"
        )
    }

    // MARK: - Strength lead is structural (US-M01)

    // The Return no longer carries a pillar-lead override: since US-M01 the strength lead is structural
    // in `SessionAssembly` (every session builds a leading strength block), so `ReturnOverride.overridePlan`
    // was removed. The Return's contribution is the two gentleness rails - the difficulty cap (`returnPool`,
    // above) and the volume floor (`reentryScale`, below). The end-to-end proof that a Return leads
    // strength lives in `SessionAssemblyTests.testReturnLeadsWithStrength`.

    // MARK: - Re-entry Ramp scale

    /// A Return serves the gentle volume floor.
    func testReturnUsesFloorScale() {
        XCTAssertEqual(ReturnOverride.reentryScale(isReturn: true, reentry: nil), ReturnOverride.reentryFloorScale)
        // Even with a ramp present, a fresh Return takes precedence and serves the floor.
        XCTAssertEqual(
            ReturnOverride.reentryScale(isReturn: true, reentry: .init(rampSessionsRemaining: 1)),
            ReturnOverride.reentryFloorScale
        )
    }

    /// The ramp climbs from the floor back to neutral as the counter decrements.
    func testRampScaleClimbsAsRemainingDecrements() {
        let three = ReturnOverride.rampScale(remaining: 3)
        let two = ReturnOverride.rampScale(remaining: 2)
        let one = ReturnOverride.rampScale(remaining: 1)
        let zero = ReturnOverride.rampScale(remaining: 0)

        XCTAssertEqual(three, ReturnOverride.reentryFloorScale, accuracy: 0.0001, "the ramp starts at the floor")
        XCTAssertEqual(zero, 1.0, accuracy: 0.0001, "the ramp ends at neutral")
        XCTAssertLessThan(three, two)
        XCTAssertLessThan(two, one)
        XCTAssertLessThan(one, zero)
    }

    func testReentryScaleUsesRampWhenActiveAndNotReturn() {
        let scale = ReturnOverride.reentryScale(isReturn: false, reentry: .init(rampSessionsRemaining: 2))
        XCTAssertEqual(scale, ReturnOverride.rampScale(remaining: 2), accuracy: 0.0001)
        XCTAssertLessThan(scale, 1.0, "an active ramp still holds volume below normal")
    }

    func testReentryScaleNeutralWithNoRampOrReturn() {
        XCTAssertEqual(ReturnOverride.reentryScale(isReturn: false, reentry: nil), AdaptiveOverload.neutralReentryScale)
        XCTAssertEqual(
            ReturnOverride.reentryScale(isReturn: false, reentry: .init(rampSessionsRemaining: 0)),
            AdaptiveOverload.neutralReentryScale, "an exhausted ramp is neutral"
        )
    }

    func testRampScaleClampsOutOfRange() {
        XCTAssertEqual(ReturnOverride.rampScale(remaining: 99), ReturnOverride.reentryFloorScale, accuracy: 0.0001,
                       "an over-range counter never over-eases past the floor")
        XCTAssertEqual(ReturnOverride.rampScale(remaining: -5), 1.0, accuracy: 0.0001,
                       "a negative counter is neutral")
    }
}
