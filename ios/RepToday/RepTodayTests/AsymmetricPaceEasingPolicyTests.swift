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
/// `progressionRate`, which sets how many qualifying sessions a climb of Earned Reps takes) and asserting
/// the served target moves down on an ease and never up on a raise attempt.
///
/// Coverage mirrors the PRD acceptance criteria:
///   (a) a coach **ease-down** lowers the target the engine serves;
///   (b) a coach **raise attempt** is clamped so the engine serves a target no harder than the
///       engine-earned one - upward pace stays the engine's alone;
///   (c) the **engine** still advances pace normally through its own writer (`PlateauDiagnosis`), and a
///       neutral coach write is a no-op.
final class AsymmetricPaceEasingPolicyTests: XCTestCase {

    // MARK: - Fixtures

    /// A rep-based exercise whose climb is paced by `progressionRate`.
    private func repsExercise(id: String = "ex") -> Exercise {
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
            defaultReps: 10,
            defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40,
            metValue: 4,
            progressionChainId: "chain",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "4 clean sets at the top of your rep range",
            apartmentFriendly: true
        )
    }

    /// One unrated Training Day session that performed its Earned Reps of 20: a qualifying session,
    /// which climbs at once at a pace of 1 or faster and only after a second one at a slower pace.
    private func oneQualifyingSession() -> [WorkoutLog] {
        [TrainingDayFixtures.log(
            [TrainingDayFixtures.station("ex", pattern: .squat, value: 20, earned: 20)],
            completedAt: TrainingDayFixtures.date(daysAgo: 1),
            difficulty: nil
        )]
    }

    /// The reps Step 6 serves for a policy's `progressionRate` over `logs`.
    private func prescribedReps(for policy: SessionPolicy, logs: [WorkoutLog]) -> Int {
        AdaptiveOverload.target(
            for: repsExercise(),
            level: .intermediate,
            recentLogs: logs,
            progressionRate: policy.progressionRate
        ).reps!
    }

    // MARK: - (a) A coach ease-down lowers the served target

    /// A coach ease-down produces a lower `progressionRate`, and the engine then serves a *lower* target
    /// than the engine-earned rate would - the ease genuinely reaches the session.
    func testCoachEaseDownLowersTheServedTarget() {
        let logs = oneQualifyingSession()

        var engineEarned = SessionPolicy.default
        engineEarned.progressionRate = 2.0
        engineEarned.updatedBy = .deterministic

        let eased = engineEarned.easingProgressionRate(towardCoachProposed: 0.5)

        XCTAssertEqual(eased.updatedBy, .llm)
        XCTAssertLessThan(eased.progressionRate, engineEarned.progressionRate)
        XCTAssertEqual(prescribedReps(for: engineEarned, logs: logs), 25, "the engine-earned pace climbs after one session")
        XCTAssertEqual(prescribedReps(for: eased, logs: logs), 20, "the eased pace waits for a second one")
    }

    // MARK: - (b) A coach raise attempt never lifts the served target

    /// A coach attempt to raise pace above the engine-earned rate is clamped to no increase, so the
    /// engine serves a target no harder than the engine-earned one - upward pace remains the engine's.
    func testCoachRaiseAttemptNeverExceedsTheEngineEarnedTarget() {
        let logs = oneQualifyingSession()

        for engineRate in [0.6, 1.2] {
            var engineEarned = SessionPolicy.default
            engineEarned.progressionRate = engineRate
            engineEarned.updatedBy = .deterministic

            // The coach asks for a far higher pace (and one beyond the rail entirely).
            for attempt in [1.8, 2.0, 99.0] {
                let raised = engineEarned.easingProgressionRate(towardCoachProposed: attempt)
                XCTAssertLessThanOrEqual(
                    raised.progressionRate, engineEarned.progressionRate,
                    "attempt \(attempt): a coach write must never raise pace above the engine-earned rate"
                )
                XCTAssertEqual(
                    prescribedReps(for: raised, logs: logs),
                    prescribedReps(for: engineEarned, logs: logs),
                    "engine \(engineRate), attempt \(attempt): a coach raise attempt must not make the engine serve a harder target"
                )
            }
        }
    }

    /// The PRD Validation Test, end-to-end: ease down (takes effect in the served target), then attempt
    /// to raise (does not lift the served target beyond the engine-earned value).
    func testValidationEaseDownAppliesThenRaiseAttemptDoesNot() {
        let logs = oneQualifyingSession()

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
    /// `progressionRate`), and that raised rate serves a target at least as hard - the upward path the
    /// coach can never take - and, from an eased pace, a strictly harder one.
    func testEngineWriterStillRaisesPaceAndTarget() {
        let logs = oneQualifyingSession()

        let advanced = PlateauDiagnosis.reweighted(.default, for: .physicalStall)
        XCTAssertEqual(advanced.updatedBy, .default, "reweighted moves only levers; provenance is the service's job")
        XCTAssertGreaterThan(advanced.progressionRate, SessionPolicy.default.progressionRate)
        XCTAssertGreaterThanOrEqual(
            prescribedReps(for: advanced, logs: logs),
            prescribedReps(for: .default, logs: logs),
            "the engine's own advance must be free to serve a harder target"
        )

        var slow = SessionPolicy.default
        slow.progressionRate = 0.9
        let sped = PlateauDiagnosis.reweighted(slow, for: .physicalStall)
        XCTAssertGreaterThan(
            prescribedReps(for: sped, logs: logs),
            prescribedReps(for: slow, logs: logs),
            "from 0.9 (two sessions a climb) the stall boost reaches one session a climb"
        )
    }

    /// A neutral coach write (proposing the in-force rate) changes the served target not at all.
    func testNeutralCoachWriteIsANoOpOnTheTarget() {
        let logs = oneQualifyingSession()

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
