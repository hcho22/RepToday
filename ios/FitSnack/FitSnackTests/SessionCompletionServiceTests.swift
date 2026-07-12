import XCTest
@testable import FitSnack

/// Tests the post-session recorder (US-L01): the seam the player calls when a session completes.
///
/// It must durably write the `WorkoutLog`, refresh the forgiving Consistency Score onto the user
/// (US-H01), and drive the cold-start handoff (US-G04) - advancing the user's cold-start state and
/// clearing the now-inert policy contract once cold-start retires. These tests drive it with in-memory
/// stores and a fixed clock so every effect is observable and deterministic.
final class SessionCompletionServiceTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 760_000_000)

    // MARK: - Fixtures

    private func makeUser(sessionsLogged: Int = 0, active: Bool = true, weeklyGoal: Int = 3) -> User {
        var user = MockPersistence.sampleUser
        user.id = "u1"
        user.coldStart = User.ColdStart(sessionsLogged: sessionsLogged, active: active)
        user.consistency = Consistency(
            weeklyGoal: weeklyGoal, score: 0, workoutsThisWeek: 0,
            longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
        )
        return user
    }

    private func makeLog(durationMinutes: Int = 14, requestedMinutes: Int = 20, wasReturn: Bool = false) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: now,
            requestedMinutes: requestedMinutes,
            durationMinutes: durationMinutes,
            wasReturn: wasReturn,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: "push_up", pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: false
                )
            ]
        )
    }

    private func makeService(
        logService: MockWorkoutLogService,
        userService: MockUserService,
        store: InMemorySessionPolicyStore
    ) -> SessionCompletionService {
        SessionCompletionService(
            workoutLogService: logService,
            userService: userService,
            consistencyService: ConsistencyScoreService(now: { self.now }),
            policyStore: store
        )
    }

    // MARK: - Log write

    /// The completed session is written to the log service verbatim - the durable record (US-L01).
    func testRecordWritesLog() async throws {
        let logService = MockWorkoutLogService()
        let service = makeService(logService: logService, userService: MockUserService(user: makeUser()), store: InMemorySessionPolicyStore())
        let log = makeLog(durationMinutes: 14, requestedMinutes: 20)

        try await service.recordCompletedSession(log, user: makeUser(), recentLogs: [])

        let saved = try await logService.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.requestedMinutes, 20)
        XCTAssertEqual(saved.first?.durationMinutes, 14, "the completed - not requested - duration is recorded")
    }

    // MARK: - Consistency refresh (US-H01)

    /// The forgiving Consistency Score is refreshed onto the user aggregate over the full persisted
    /// history (which now includes the just-saved log), counting the new session exactly once.
    func testRecordRefreshesConsistency() async throws {
        let userService = MockUserService(user: makeUser())
        let service = makeService(logService: MockWorkoutLogService(), userService: userService, store: InMemorySessionPolicyStore())

        try await service.recordCompletedSession(makeLog(), user: makeUser(), recentLogs: [])

        let saved = try await userService.currentUser()
        XCTAssertEqual(saved?.consistency.totalWorkoutsCompleted, 1, "the new session counts exactly once")
        XCTAssertGreaterThan(saved?.consistency.score ?? 0, 0, "showing up moves the score off zero")
    }

    // MARK: - Cold-start handoff (US-G04)

    /// Recording a completed session advances the user's cold-start counter.
    func testRecordAdvancesColdStart() async throws {
        let userService = MockUserService(user: makeUser(sessionsLogged: 1, active: true))
        let service = makeService(logService: MockWorkoutLogService(), userService: userService, store: InMemorySessionPolicyStore())

        try await service.recordCompletedSession(makeLog(), user: makeUser(sessionsLogged: 1, active: true), recentLogs: [])

        let saved = try await userService.currentUser()
        XCTAssertEqual(saved?.coldStart.sessionsLogged, 2)
        XCTAssertTrue(saved?.coldStart.active ?? false, "still in the cold-start window below the threshold")
    }

    /// The session that reaches the handoff threshold retires cold-start on the user *and* clears the
    /// now-inert cold-start contract from the stored policy (US-G04), so the engine runs the plain
    /// pipeline from the next open.
    func testRecordRetiresColdStartAndReconcilesPolicy() async throws {
        let store = InMemorySessionPolicyStore()
        try await store.save(.seeded(forFitnessLevel: .beginner), for: "u1")
        // One below the threshold (5), so this completed session flips cold-start off.
        let user = makeUser(sessionsLogged: ColdStartHandoff.handoffThreshold - 1, active: true)
        let userService = MockUserService(user: user)
        let service = makeService(logService: MockWorkoutLogService(), userService: userService, store: store)

        try await service.recordCompletedSession(makeLog(), user: user, recentLogs: [])

        let savedUser = try await userService.currentUser()
        XCTAssertEqual(savedUser?.coldStart.sessionsLogged, ColdStartHandoff.handoffThreshold)
        XCTAssertFalse(savedUser?.coldStart.active ?? true, "cold-start retires at the threshold")

        let savedPolicy = try await store.policy(for: "u1")
        XCTAssertNil(savedPolicy?.coldStartContract, "the retired contract is cleared from the stored policy")
    }

    /// While cold-start is still active, the policy is left untouched (the handoff is a no-op on it),
    /// so the contract that drives the First-Week overrides survives.
    func testRecordKeepsContractWhileColdStartActive() async throws {
        let store = InMemorySessionPolicyStore()
        try await store.save(.seeded(forFitnessLevel: .beginner), for: "u1")
        let user = makeUser(sessionsLogged: 1, active: true)
        let service = makeService(logService: MockWorkoutLogService(), userService: MockUserService(user: user), store: store)

        try await service.recordCompletedSession(makeLog(), user: user, recentLogs: [])

        let savedPolicy = try await store.policy(for: "u1")
        XCTAssertNotNil(savedPolicy?.coldStartContract, "an active cold-start keeps its contract")
    }

    // MARK: - Freshest-user read (second-writer safety)

    /// The user aggregate has a second writer - the on-open reprogram (US-J02/US-F03) can persist a
    /// learned `user.duration` between the Ready-Screen snapshot and session completion. The recorder
    /// must read-modify-write from the *freshest* persisted user, not the stale snapshot, so that
    /// learned duration survives rather than being clobbered.
    func testRecordPreservesDurationWrittenAfterSnapshot() async throws {
        let snapshot = makeUser()
        // The reprogram persisted a shorter learned default after the snapshot was captured.
        var fresher = snapshot
        fresher.duration = User.Duration(defaultMinutes: 10, onboardingSeedMinutes: 20, completedDurationEWMA: 11)
        let userService = MockUserService(user: fresher)
        let service = makeService(logService: MockWorkoutLogService(), userService: userService, store: InMemorySessionPolicyStore())

        try await service.recordCompletedSession(makeLog(), user: snapshot, recentLogs: [])

        let saved = try await userService.currentUser()
        XCTAssertEqual(saved?.duration.defaultMinutes, 10, "the learned duration written after the snapshot is preserved, not clobbered")
        XCTAssertEqual(saved?.duration.completedDurationEWMA, 11)
    }

    // MARK: - Perceived-difficulty rating (US-L02)

    /// The rating is written onto the existing log by its stable id (an upsert, not a second record),
    /// and it does not re-run the cold-start handoff - the counter the completion write already advanced
    /// stays put, so a rating given afterward never double-advances cold-start.
    func testRecordPerceivedDifficultyUpdatesLogInPlace() async throws {
        let logService = MockWorkoutLogService()
        let userService = MockUserService(user: makeUser(sessionsLogged: 1, active: true))
        let service = makeService(logService: logService, userService: userService, store: InMemorySessionPolicyStore())
        let log = makeLog()

        try await service.recordCompletedSession(log, user: makeUser(sessionsLogged: 1, active: true), recentLogs: [])
        try await service.recordPerceivedDifficulty(.tooHard, forLog: log)

        let saved = try await logService.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(saved.count, 1, "the rating updates the same record rather than writing a second log")
        XCTAssertEqual(saved.first?.id, log.id)
        XCTAssertEqual(saved.first?.perceivedDifficulty, .tooHard)

        let savedUser = try await userService.currentUser()
        XCTAssertEqual(savedUser?.coldStart.sessionsLogged, 2, "rating does not re-advance the cold-start counter")
    }

    /// A user already warmed up (cold-start inactive) advances no counter and the policy stays put.
    func testRecordNoOpColdStartWhenAlreadyRetired() async throws {
        let store = InMemorySessionPolicyStore()
        try await store.save(.default, for: "u1")
        let user = makeUser(sessionsLogged: ColdStartHandoff.handoffThreshold, active: false)
        let userService = MockUserService(user: user)
        let service = makeService(logService: MockWorkoutLogService(), userService: userService, store: store)

        try await service.recordCompletedSession(makeLog(), user: user, recentLogs: [])

        let savedUser = try await userService.currentUser()
        XCTAssertEqual(savedUser?.coldStart.sessionsLogged, ColdStartHandoff.handoffThreshold, "frozen once retired")
        XCTAssertFalse(savedUser?.coldStart.active ?? true)
    }
}
