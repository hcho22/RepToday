import XCTest
@testable import FitSnack

/// Tests the minimal Ready Screen view model (US-I01).
///
/// The Ready Screen's promise is that today's session is already there on open. These tests verify
/// the view model loads the current user, generates a session at the learned Default Duration
/// against the in-force policy, and degrades gracefully when there is no user.
final class ReadyViewModelTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 760_000_000)

    private func onboardedUser(defaultMinutes: Int = 15) -> User {
        var user = MockPersistence.sampleUser
        user.duration = .seeded(minutes: defaultMinutes)
        return user
    }

    private func makeViewModel(
        user: User?,
        engine: CapturingWorkoutEngine = CapturingWorkoutEngine(),
        policy: SessionPolicy = .seeded(forFitnessLevel: .beginner),
        logs: [WorkoutLog] = []
    ) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: StubPolicyService(policy: policy),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(logs: logs),
            now: { self.fixedDate }
        )
    }

    /// On load the session is generated at the user's Default Duration and exposed, with no error.
    func testLoadGeneratesSessionAtDefaultDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()

        XCTAssertNotNil(vm.workout)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.requestedMinutes, 15)
        XCTAssertEqual(engine.capturedRequestedMinutes, 15)
    }

    /// The in-force policy is threaded into generation (so the cold-start contract reaches the engine).
    func testLoadPassesCurrentPolicyToEngine() async {
        let engine = CapturingWorkoutEngine()
        let seeded = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let vm = makeViewModel(user: onboardedUser(), engine: engine, policy: seeded)

        await vm.load()

        XCTAssertEqual(engine.capturedPolicy, seeded)
        XCTAssertNotNil(engine.capturedPolicy?.coldStartContract)
    }

    /// With no user, the view model surfaces an empty-state message and generates nothing.
    func testLoadWithNoUserSetsError() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: nil, engine: engine)

        await vm.load()

        XCTAssertNil(vm.workout)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(engine.capturedRequestedMinutes, "the engine is never called without a user")
    }

    /// A generated session that lands within ±1 of the request (using the real engine) proves the
    /// screen shows a ~N-minute session, matching the US-I01 validation.
    func testEndToEndGeneratesRequestedLengthSession() async throws {
        let exercises = try MockExerciseService()
        let engine = MockWorkoutEngine(exerciseService: exercises)
        let users = MockUserService(user: onboardedUser(defaultMinutes: 15))
        let vm = ReadyViewModel(
            userService: users,
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()

        let workout = try XCTUnwrap(vm.workout)
        XCTAssertEqual(workout.requestedMinutes, 15)
        XCTAssertFalse(workout.blocks.isEmpty)
        XCTAssertEqual(workout.blocks.first?.category, ExerciseCategory.warmup, "a session always opens with a warm-up")
    }

    // MARK: - Duration chip (US-J01)

    /// The offered chips are the canonical ascending vocabulary (5/10/15/20/30/45/60).
    func testDurationChipsAreCanonicalVocabulary() {
        let vm = makeViewModel(user: onboardedUser())
        XCTAssertEqual(vm.durationChips, [5, 10, 15, 20, 30, 45, 60])
    }

    /// Tapping a chip regenerates the session at the new duration and updates the selection, while
    /// the existing session stays present (Start is never left waiting).
    func testSelectDurationRegeneratesAtNewDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()
        XCTAssertEqual(vm.selectedMinutes, 15)

        await vm.selectDuration(30)

        XCTAssertEqual(vm.selectedMinutes, 30)
        XCTAssertEqual(vm.requestedMinutes, 30)
        XCTAssertEqual(engine.capturedRequestedMinutes, 30)
        XCTAssertNotNil(vm.workout, "the session stays present through a regeneration")
        XCTAssertNil(vm.errorMessage)
    }

    /// Regeneration reuses the cached engine inputs - it never re-fetches the user, so a chip tap
    /// stays on-device and instant.
    func testSelectDurationDoesNotRefetchUser() async {
        let users = CountingUserService(user: onboardedUser())
        let engine = CapturingWorkoutEngine()
        let vm = ReadyViewModel(
            userService: users,
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        await vm.selectDuration(45)

        let userFetches = await users.currentUserCallCount
        XCTAssertEqual(userFetches, 1, "the user is fetched once on load, not per chip tap")
        XCTAssertEqual(engine.generateCallCount, 2, "one generation on load, one per chip tap")
    }

    /// Tapping the already-selected chip is a no-op - no wasted regeneration.
    func testSelectDurationSameValueIsNoOp() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 20), engine: engine)

        await vm.load()
        XCTAssertEqual(engine.generateCallCount, 1)

        await vm.selectDuration(20)

        XCTAssertEqual(engine.generateCallCount, 1, "re-selecting the current duration does not regenerate")
    }

    /// Selecting a duration before any user has loaded is a no-op (nothing to generate against).
    func testSelectDurationWithNoUserIsNoOp() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: nil, engine: engine)

        await vm.load()
        await vm.selectDuration(30)

        XCTAssertNil(engine.capturedRequestedMinutes, "the engine is never called without a user")
    }

    /// A re-appear (load re-fires) preserves an in-session chip choice rather than snapping back to
    /// the learned default, and regenerates at the chosen duration.
    func testReappearPreservesSelectedDuration() async {
        let engine = CapturingWorkoutEngine()
        let vm = makeViewModel(user: onboardedUser(defaultMinutes: 15), engine: engine)

        await vm.load()
        await vm.selectDuration(30)
        XCTAssertEqual(vm.selectedMinutes, 30)

        // Simulate the Today tab re-appearing (its `.task` re-fires).
        await vm.load()

        XCTAssertEqual(vm.selectedMinutes, 30, "a refresh keeps the user's chip choice")
        XCTAssertEqual(engine.capturedRequestedMinutes, 30, "regeneration uses the preserved selection")
    }

    /// A chip-tap regeneration failure reverts the selection to the prior value and keeps the
    /// previously displayed session, so the header and highlighted chip never contradict the screen.
    func testSelectDurationFailureRevertsSelection() async {
        let engine = FlakyWorkoutEngine()
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        let loaded = vm.workout
        XCTAssertNotNil(loaded)
        XCTAssertEqual(vm.selectedMinutes, 15)

        engine.shouldFail = true
        await vm.selectDuration(30)

        XCTAssertEqual(vm.selectedMinutes, 15, "a failed regeneration rolls the selection back")
        XCTAssertEqual(vm.requestedMinutes, 15)
        XCTAssertEqual(vm.workout?.requestedMinutes, loaded?.requestedMinutes, "the previous session stays displayed")
    }

    /// End-to-end (real engine): tapping 30 after a 15-min load produces a ~30-min session, matching
    /// the US-J01 validation.
    func testEndToEndChipRegeneratesToRequestedLength() async throws {
        let exercises = try MockExerciseService()
        let engine = MockWorkoutEngine(exerciseService: exercises)
        let vm = ReadyViewModel(
            userService: MockUserService(user: onboardedUser(defaultMinutes: 15)),
            sessionPolicyService: StubPolicyService(policy: .seeded(forFitnessLevel: .beginner)),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(),
            now: { self.fixedDate }
        )

        await vm.load()
        XCTAssertEqual(vm.workout?.requestedMinutes, 15)

        await vm.selectDuration(30)

        XCTAssertEqual(vm.workout?.requestedMinutes, 30)
        XCTAssertEqual(vm.workout?.blocks.first?.category, ExerciseCategory.warmup)
    }
}

// MARK: - Test doubles

/// A workout engine that records its generation inputs and returns a canned session.
private final class CapturingWorkoutEngine: WorkoutEngineProtocol {
    private(set) var capturedRequestedMinutes: Int?
    private(set) var capturedPolicy: SessionPolicy?
    private(set) var generateCallCount = 0

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        capturedRequestedMinutes = requestedMinutes
        capturedPolicy = sessionPolicy
        generateCallCount += 1
        return Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: requestedMinutes,
            wasReturn: false,
            blocks: []
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

/// A workout engine that can be flipped to throw, exercising the failure/revert path.
private final class FlakyWorkoutEngine: WorkoutEngineProtocol {
    var shouldFail = false

    struct GenerationError: Error {}

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        if shouldFail { throw GenerationError() }
        return Workout(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: requestedMinutes,
            wasReturn: false,
            blocks: []
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog]
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}

/// A user service that counts `currentUser()` calls, proving a chip regeneration reuses cached
/// inputs rather than re-fetching.
private actor CountingUserService: UserServiceProtocol {
    private let user: User?
    private(set) var currentUserCallCount = 0

    init(user: User?) { self.user = user }

    func currentUser() async throws -> User? {
        currentUserCallCount += 1
        return user
    }

    func save(_ user: User) async throws {}
    func deleteCurrentUser() async throws {}
}

/// A policy service that returns a fixed policy and no-ops the write paths.
private struct StubPolicyService: SessionPolicyServiceProtocol {
    let policy: SessionPolicy
    func currentPolicy(for user: User) async throws -> SessionPolicy { policy }
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy { policy }
    func reprogram(user: User, recentLogs: [WorkoutLog], trigger: ReprogramTrigger) async throws -> SessionPolicy { policy }
    func dueTriggers(user: User, recentLogs: [WorkoutLog], asOf: Date) async throws -> [ReprogramTrigger] { [] }
}
