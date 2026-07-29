import XCTest
@testable import RepToday

/// Tests the cold-start handoff (US-G04): the pure `ColdStartHandoff` module that retires the Step 0
/// cold-start overrides once a user has logged enough sessions for the engine to drive itself.
///
/// Coverage mirrors the PRD acceptance criteria at the unit level: `sessionsLogged` increments on each
/// completed session; `active` flips off exactly at the handoff threshold and stays off; the
/// `coldStartContract` is cleared from the policy once cold-start is inactive; and Step 0
/// (`ColdStartOverride`) is a no-op afterward, so a warmed-up user runs the plain US-E03 pipeline.
final class ColdStartHandoffTests: XCTestCase {

    // MARK: - Fixtures

    private func user(sessionsLogged: Int, active: Bool) -> User {
        User(
            id: "u",
            displayName: "Test",
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            profile: UserProfile(
                age: 35,
                sex: .male,
                heightCm: 178,
                weightKg: 80,
                fitnessLevel: .beginner,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 0,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            ),
            coldStart: User.ColdStart(sessionsLogged: sessionsLogged, active: active)
        )
    }

    // MARK: - sessionsLogged increment

    func testAdvanceIncrementsSessionsLogged() {
        let advanced = ColdStartHandoff.advanced(User.ColdStart(sessionsLogged: 2, active: true), band: .unbanded)
        XCTAssertEqual(advanced.sessionsLogged, 3)
        XCTAssertTrue(advanced.active, "Below the threshold, cold-start stays active.")
    }

    func testFreshUserAdvancesFromZero() {
        let advanced = ColdStartHandoff.advanced(User.ColdStart.fresh, band: .unbanded)
        XCTAssertEqual(advanced.sessionsLogged, 1)
        XCTAssertTrue(advanced.active)
    }

    // MARK: - The flip at the threshold

    func testActiveFlipsOffAtThreshold() {
        // The validation-test setup: a user one session shy of the handoff.
        let before = User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold - 1, active: true)
        let after = ColdStartHandoff.advanced(before, band: .unbanded)
        XCTAssertEqual(after.sessionsLogged, ColdStartHandoff.handoffThreshold)
        XCTAssertFalse(after.active, "Cold-start retires the moment sessionsLogged reaches the threshold.")
    }

    func testActiveStaysOnJustBeforeThreshold() {
        let after = ColdStartHandoff.advanced(
            User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold - 2, active: true),
            band: .unbanded
        )
        XCTAssertEqual(after.sessionsLogged, ColdStartHandoff.handoffThreshold - 1)
        XCTAssertTrue(after.active, "One session before the threshold, cold-start is still active.")
    }

    func testRetirementIsOneWayAndFrozen() {
        // Once inactive, further completed sessions are a no-op - the state never re-activates.
        let retired = User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold, active: false)
        let after = ColdStartHandoff.advanced(retired, band: .unbanded)
        XCTAssertEqual(after, retired, "A retired cold-start state is frozen.")
    }

    func testStepThroughFullColdStartWindow() {
        var state = User.ColdStart.fresh
        for expected in 1...ColdStartHandoff.handoffThreshold {
            state = ColdStartHandoff.advanced(state, band: .unbanded)
            XCTAssertEqual(state.sessionsLogged, expected)
            XCTAssertEqual(
                state.active,
                expected < ColdStartHandoff.handoffThreshold,
                "active is true until the count reaches the threshold, false at and after it."
            )
        }
    }

    // MARK: - Contract cleared from the policy

    func testContractClearedWhenColdStartInactive() {
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        XCTAssertNotNil(policy.coldStartContract)

        let reconciled = ColdStartHandoff.reconciled(
            policy,
            with: User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold, active: false)
        )
        XCTAssertNil(reconciled.coldStartContract, "An inactive cold-start clears the contract.")
    }

    func testContractRetainedWhileColdStartActive() {
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let reconciled = ColdStartHandoff.reconciled(
            policy,
            with: User.ColdStart(sessionsLogged: 2, active: true)
        )
        XCTAssertEqual(reconciled, policy, "While active, the policy is untouched.")
    }

    func testReconcileMovesNoOtherLever() {
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)
        let reconciled = ColdStartHandoff.reconciled(
            policy,
            with: User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold, active: false)
        )
        // Clearing the contract yields exactly the neutral default's shape - no version/lever churn.
        XCTAssertEqual(reconciled, SessionPolicy.default)
    }

    func testReconcileIsNoOpWhenNoContractPresent() {
        let reconciled = ColdStartHandoff.reconciled(
            SessionPolicy.default,
            with: User.ColdStart(sessionsLogged: ColdStartHandoff.handoffThreshold, active: false)
        )
        XCTAssertEqual(reconciled, SessionPolicy.default)
    }

    // MARK: - Combined handoff

    func testAfterCompletedSessionFlipsAndClearsTogether() {
        // Validation test: a cold-start user at sessionsLogged == 4 completes a fifth session.
        let before = user(sessionsLogged: ColdStartHandoff.handoffThreshold - 1, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)

        let outcome = ColdStartHandoff.afterCompletedSession(user: before, sessionPolicy: policy, recentLogs: [])

        XCTAssertEqual(outcome.user.coldStart.sessionsLogged, ColdStartHandoff.handoffThreshold)
        XCTAssertFalse(outcome.user.coldStart.active, "The fifth session retires cold-start.")
        XCTAssertNil(outcome.sessionPolicy.coldStartContract, "The contract is cleared in the same step.")
    }

    func testAfterCompletedSessionKeepsColdStartMidWindow() {
        let before = user(sessionsLogged: 1, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .intermediate)

        let outcome = ColdStartHandoff.afterCompletedSession(user: before, sessionPolicy: policy, recentLogs: [])

        XCTAssertEqual(outcome.user.coldStart.sessionsLogged, 2)
        XCTAssertTrue(outcome.user.coldStart.active)
        XCTAssertNotNil(outcome.sessionPolicy.coldStartContract, "Mid-window, the contract stays.")
        XCTAssertNil(
            outcome.user.coldStart.bandFloorAtHandoff,
            "Mid-window there is no handoff yet, so nothing is recorded."
        )
    }

    // MARK: - Recording the band that ran (US-O02)

    /// The retiring session records the Start Seed floor the week actually ran at, and only that
    /// session does. Step 5 reads this back long after the cold-start logs have aged out of the
    /// engine's bounded window, so it is the one durable record of what was ever on offer.
    func testHandoffRecordsTheBandFloorTheWeekRanAt() {
        let policy = SessionPolicy.seeded(forFitnessLevel: .advanced)

        var state = User.ColdStart.fresh
        for logged in 1..<ColdStartHandoff.handoffThreshold {
            state = ColdStartHandoff.advanced(state, band: ColdStartHandoff.BandRecord(aim: 3, floor: 3))
            XCTAssertEqual(state.sessionsLogged, logged)
            XCTAssertNil(state.bandFloorAtHandoff, "Only the retiring session records the band.")
        }

        let outcome = ColdStartHandoff.afterCompletedSession(
            user: user(sessionsLogged: state.sessionsLogged, active: true),
            sessionPolicy: policy,
            recentLogs: []
        )
        XCTAssertFalse(outcome.user.coldStart.active)
        XCTAssertEqual(
            outcome.user.coldStart.bandFloorAtHandoff,
            SessionPolicy.ColdStartContract.startingDifficultyFloor(for: .advanced)
        )
    }

    /// A handoff with no cold-start contract in play records the neutral floor - "no band ran" - so a
    /// band is never asserted over a user who never had one.
    func testHandoffWithoutAContractRecordsNoBand() {
        let outcome = ColdStartHandoff.afterCompletedSession(
            user: user(sessionsLogged: ColdStartHandoff.handoffThreshold - 1, active: true),
            sessionPolicy: .default,
            recentLogs: []
        )
        XCTAssertEqual(
            outcome.user.coldStart.bandFloorAtHandoff,
            SessionPolicy.ColdStartContract.neutralStartingDifficultyFloor
        )
    }

    func testAfterCompletedSessionCarriesOtherUserFieldsThrough() {
        let before = user(sessionsLogged: 0, active: true)
        let outcome = ColdStartHandoff.afterCompletedSession(
            user: before,
            sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .beginner),
            recentLogs: []
        )
        XCTAssertEqual(outcome.user.id, before.id)
        XCTAssertEqual(outcome.user.profile, before.profile)
        XCTAssertEqual(outcome.user.consistency, before.consistency)
    }

    // MARK: - Step 0 becomes a no-op after the handoff

    func testStep0IsNoOpAfterHandoff() {
        // After the handoff, both the flag and the contract have retired, so Step 0 does nothing.
        let before = user(sessionsLogged: ColdStartHandoff.handoffThreshold - 1, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let outcome = ColdStartHandoff.afterCompletedSession(user: before, sessionPolicy: policy, recentLogs: [])

        XCTAssertFalse(
            ColdStartOverride.isActive(user: outcome.user, sessionPolicy: outcome.sessionPolicy),
            "A handed-off user is no longer in the cold-start window."
        )

        // The two Step 0 overrides return their inputs untouched.
        let pool = [
            Exercise(
                id: "hard", displayName: "Hard", pillar: .strength, movementPattern: .push,
                category: .strength, difficulty: 5, phase: .discipline, equipment: [],
                isHold: false, defaultReps: 10, defaultDurationSeconds: nil,
                estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "c",
                progressionOrder: 5, regressionId: nil, progressionId: nil,
                advancementCriteria: "3x15", apartmentFriendly: true
            )
        ]
        let capped = ColdStartOverride.cappedPool(pool, user: outcome.user, sessionPolicy: outcome.sessionPolicy)
        XCTAssertEqual(capped, pool, "With cold-start retired, the difficulty cap no longer applies.")

        let plan = ColdStartOverride.overridePlan(
            .single(.strength),
            template: .singleFocus,
            user: outcome.user,
            sessionPolicy: outcome.sessionPolicy
        )
        XCTAssertEqual(plan, .single(.strength), "First-Week Contrast no longer forces the lead pillar.")
    }

    // MARK: - Determinism

    func testDeterministic() {
        let before = user(sessionsLogged: 3, active: true)
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let a = ColdStartHandoff.afterCompletedSession(user: before, sessionPolicy: policy, recentLogs: [])
        let b = ColdStartHandoff.afterCompletedSession(user: before, sessionPolicy: policy, recentLogs: [])
        XCTAssertEqual(a, b)
    }
}
