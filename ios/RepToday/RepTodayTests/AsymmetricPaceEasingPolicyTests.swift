import XCTest
@testable import RepToday

/// US-AC06: **asymmetric pace easing** - the coach can ease `progressionRate` down, but only the
/// deterministic engine ever advances it.
///
/// The enforcement is a single structural seam on the policy model
/// (`SessionPolicy.easingProgressionRate(towardCoachProposed:)`): a coach-sourced (`.llm`) rate write
/// is clamped to `min(clampedProgressionRate(proposed), inForceRate)`, so it can lower pace but never
/// raise it above the engine-earned value. `SessionPolicyTests` pins the clamp arithmetic and the PRD
/// Validation Test at the value level; this suite proves the clamp *takes effect end-to-end* by feeding
/// the produced rate through the engine's Step 6 (`AdaptiveOverload.target`, the sole consumer of
/// `progressionRate`) and asserting the prescribed advancing target moves down on an ease and never up
/// on a raise attempt.
///
/// Coverage mirrors the PRD acceptance criteria:
///   (a) a coach **ease-down** lowers the prescribed advancing target the engine serves;
///   (b) a coach **raise attempt** is clamped so the engine serves a target no harder than the
///       engine-earned one - upward pace stays the engine's alone;
///   (c) the **engine** still advances pace normally through its own writer (`PlateauDiagnosis`), and a
///       neutral coach write is a no-op.
final class AsymmetricPaceEasingPolicyTests: XCTestCase {

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

    /// A rep-based exercise whose advancing bump is scaled by `progressionRate`.
    private func repsExercise(id: String = "ex", defaultReps: Int = 10) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: .strength,
            movementPattern: .squat,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: false,
            defaultReps: defaultReps,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x15 clean reps",
            apartmentFriendly: true
        )
    }

    /// A worked, unrated session (so the ramp signal is the gentlest advancing nudge, which
    /// `progressionRate` paces) that demonstrates capacity of `reps` per set.
    private func repsLog(id: String = "ex", reps: [Int], daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .squat,
                    completedSets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
                    skipped: false
                )
            ]
        )
    }

    /// The engine's prescribed advancing rep target for a policy's `progressionRate` over a
    /// capacity-bearing history - the number Step 6 actually serves.
    private func prescribedReps(for policy: SessionPolicy, logs: [WorkoutLog]) -> Int {
        AdaptiveOverload.target(
            for: repsExercise(),
            recentLogs: logs,
            progressionRate: policy.progressionRate
        ).reps!
    }

    // MARK: - (a) A coach ease-down lowers the served target

    /// A coach ease-down produces a lower `progressionRate`, and the engine then serves a *lower*
    /// advancing target than the engine-earned rate would - the ease genuinely reaches the session.
    func testCoachEaseDownLowersTheServedAdvancingTarget() {
        // A high advancing capacity so the paced bump is visible in whole reps.
        let logs = [repsLog(reps: [30, 30], daysAgo: 1)]

        var engineEarned = SessionPolicy.default
        engineEarned.progressionRate = 2.0
        engineEarned.updatedBy = .deterministic

        let eased = engineEarned.easingProgressionRate(towardCoachProposed: 0.5)

        XCTAssertEqual(eased.updatedBy, .llm)
        XCTAssertLessThan(eased.progressionRate, engineEarned.progressionRate)
        XCTAssertLessThan(
            prescribedReps(for: eased, logs: logs),
            prescribedReps(for: engineEarned, logs: logs),
            "a coach ease-down must make the engine serve a gentler advancing target"
        )
    }

    // MARK: - (b) A coach raise attempt never lifts the served target

    /// A coach attempt to raise pace above the engine-earned rate is clamped to no increase, so the
    /// engine serves a target no harder than the engine-earned one - upward pace remains the engine's.
    func testCoachRaiseAttemptNeverExceedsTheEngineEarnedTarget() {
        let logs = [repsLog(reps: [30, 30], daysAgo: 1)]

        var engineEarned = SessionPolicy.default
        engineEarned.progressionRate = 1.2
        engineEarned.updatedBy = .deterministic

        // The coach asks for a far higher pace (and one beyond the rail entirely).
        for attempt in [1.8, 2.0, 99.0] {
            let raised = engineEarned.easingProgressionRate(towardCoachProposed: attempt)
            XCTAssertLessThanOrEqual(
                raised.progressionRate, engineEarned.progressionRate,
                "attempt \(attempt): a coach write must never raise pace above the engine-earned rate"
            )
            XCTAssertLessThanOrEqual(
                prescribedReps(for: raised, logs: logs),
                prescribedReps(for: engineEarned, logs: logs),
                "attempt \(attempt): a coach raise attempt must not make the engine serve a harder target"
            )
        }
    }

    /// The PRD Validation Test, end-to-end: ease down (takes effect in the served target), then attempt
    /// to raise (does not lift the served target beyond the engine-earned value).
    func testValidationEaseDownAppliesThenRaiseAttemptDoesNot() {
        let logs = [repsLog(reps: [30, 30], daysAgo: 1)]

        var engineEarned = SessionPolicy.default
        engineEarned.progressionRate = 1.5
        engineEarned.updatedBy = .deterministic
        let earnedReps = prescribedReps(for: engineEarned, logs: logs)

        // Ease-down applies.
        let eased = engineEarned.easingProgressionRate(towardCoachProposed: 0.6)
        let easedReps = prescribedReps(for: eased, logs: logs)
        XCTAssertLessThan(easedReps, earnedReps, "the ease-down must take effect on the served target")

        // Raise attempt from the eased policy does not lift pace past engine-earned - and, structurally,
        // does not raise it at all.
        let raiseAttempt = eased.easingProgressionRate(towardCoachProposed: 2.0)
        XCTAssertLessThanOrEqual(
            prescribedReps(for: raiseAttempt, logs: logs), earnedReps,
            "the raise attempt must not push the served target beyond the engine-earned value"
        )
        XCTAssertEqual(
            prescribedReps(for: raiseAttempt, logs: logs), easedReps,
            "the raise attempt leaves the eased target unchanged (no increase)"
        )
    }

    // MARK: - (c) The engine still owns upward pace; neutral coach write is a no-op

    /// The deterministic engine writer still advances pace (its `.physicalStall` re-weight raises
    /// `progressionRate`), and that raised rate serves a *harder* advancing target - the upward path the
    /// coach can never take.
    func testEngineWriterStillRaisesPaceAndTarget() {
        let logs = [repsLog(reps: [30, 30], daysAgo: 1)]

        let advanced = PlateauDiagnosis.reweighted(.default, for: .physicalStall)
        XCTAssertEqual(advanced.updatedBy, .default, "reweighted moves only levers; provenance is the service's job")
        XCTAssertGreaterThan(advanced.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertGreaterThanOrEqual(
            prescribedReps(for: advanced, logs: logs),
            prescribedReps(for: .default, logs: logs),
            "the engine's own advance must be free to serve a harder target"
        )
    }

    /// A neutral coach write (proposing the in-force rate) changes the served target not at all.
    func testNeutralCoachWriteIsANoOpOnTheTarget() {
        let logs = [repsLog(reps: [30, 30], daysAgo: 1)]

        var policy = SessionPolicy.default
        policy.progressionRate = 1.3
        policy.updatedBy = .deterministic

        let neutralCoach = policy.easingProgressionRate(towardCoachProposed: policy.progressionRate)
        XCTAssertEqual(neutralCoach.progressionRate, policy.progressionRate)
        XCTAssertEqual(
            prescribedReps(for: neutralCoach, logs: logs),
            prescribedReps(for: policy, logs: logs),
            "a coach write at the in-force rate serves an identical target"
        )
    }
}
