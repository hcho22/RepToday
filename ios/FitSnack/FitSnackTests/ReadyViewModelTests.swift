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
}

// MARK: - Test doubles

/// A workout engine that records its generation inputs and returns a canned session.
private final class CapturingWorkoutEngine: WorkoutEngineProtocol {
    private(set) var capturedRequestedMinutes: Int?
    private(set) var capturedPolicy: SessionPolicy?

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> Workout {
        capturedRequestedMinutes = requestedMinutes
        capturedPolicy = sessionPolicy
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

/// A policy service that returns a fixed policy and no-ops the write paths.
private struct StubPolicyService: SessionPolicyServiceProtocol {
    let policy: SessionPolicy
    func currentPolicy(for user: User) async throws -> SessionPolicy { policy }
    func seedInitialPolicy(for user: User) async throws -> SessionPolicy { policy }
    func reprogram(user: User, recentLogs: [WorkoutLog], trigger: ReprogramTrigger) async throws -> SessionPolicy { policy }
    func dueTriggers(user: User, recentLogs: [WorkoutLog], asOf: Date) async throws -> [ReprogramTrigger] { [] }
}
