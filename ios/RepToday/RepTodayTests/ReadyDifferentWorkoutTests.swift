import XCTest
@testable import RepToday

/// The Ready Screen half of **Different workout**: `ReadyViewModel.showDifferentWorkout()` over the real
/// engine and catalog. A press rebuilds today's session in place at the same length with other moves; a
/// length change still works and starts the sequence over; starting a session ends it, so the next load is
/// the default session for the new history; a paused session waiting to be resumed is left alone; and
/// nothing is logged, scored or reported for a workout that is never started. The engine rules every press
/// obeys are pinned in `DifferentWorkoutTests`.
@MainActor
final class ReadyDifferentWorkoutTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 760_000_000)

    private func user(minutes: Int = 20) -> User {
        var user = MockPersistence.sampleUser
        user.duration = .seeded(minutes: minutes)
        user.coldStart = User.ColdStart(sessionsLogged: 0, active: false)
        return user
    }

    private struct Harness {
        let viewModel: ReadyViewModel
        let logService: MockWorkoutLogService
        let store: InMemoryActiveSessionStore
        let analytics: MockAnalyticsService
    }

    private func harness(
        user: User? = nil,
        logs: [WorkoutLog] = [],
        store: InMemoryActiveSessionStore = InMemoryActiveSessionStore()
    ) throws -> Harness {
        let exerciseService = try MockExerciseService()
        let logService = MockWorkoutLogService(logs: logs)
        let analytics = MockAnalyticsService()
        let viewModel = ReadyViewModel(
            userService: MockUserService(user: user ?? self.user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: MockWorkoutEngine(exerciseService: exerciseService, now: { self.fixedDate }),
            workoutLogService: logService,
            activeSessionStore: store,
            analytics: analytics,
            now: { self.fixedDate }
        )
        return Harness(viewModel: viewModel, logService: logService, store: store, analytics: analytics)
    }

    private func moves(_ workout: Workout?) -> Set<String> {
        workout.map(SessionVariation.exerciseIds(in:)) ?? []
    }

    /// The log of `workout` played through at its prescription, completed at the test clock.
    private func completedLog(of workout: Workout) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: workout.id, completedAt: fixedDate,
            requestedMinutes: workout.requestedMinutes, durationMinutes: workout.requestedMinutes,
            wasReturn: false, shape: workout.shape, focusPillar: workout.focusPillar,
            perceivedDifficulty: .justRight,
            exercises: workout.blocks.flatMap(\.exercises).map { prescription in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: prescription.exercise.id,
                    pillar: prescription.exercise.pillar,
                    movementPattern: prescription.exercise.movementPattern,
                    completedSets: Array(
                        repeating: CompletedSet(reps: prescription.reps, durationSeconds: prescription.durationSeconds),
                        count: prescription.sets
                    ),
                    skipped: false
                )
            }
        )
    }

    private func content(_ workout: Workout?) -> [String] {
        (workout?.blocks ?? []).map { block in
            "\(block.category):" + block.exercises.map { "\($0.exercise.id)x\($0.sets)r\($0.reps ?? -1)d\($0.durationSeconds ?? -1)" }
                .joined(separator: ",")
        }
    }

    func testAPressRebuildsTheSessionAtTheSameLengthWithOtherMoves() async throws {
        let h = try harness()
        await h.viewModel.load()
        let original = try XCTUnwrap(h.viewModel.workout)

        await h.viewModel.showDifferentWorkout()

        let different = try XCTUnwrap(h.viewModel.workout)
        XCTAssertEqual(different.requestedMinutes, original.requestedMinutes)
        XCTAssertEqual(h.viewModel.selectedMinutes, 20)
        XCTAssertEqual(different.blocks.map(\.category), original.blocks.map(\.category), "same session shape")
        XCTAssertNotEqual(moves(different), moves(original), "a press brings other moves")
        XCTAssertLessThanOrEqual(abs(SessionAssembly.plannedSeconds(of: different) - 20 * 60), SessionAssembly.toleranceSeconds)
        XCTAssertEqual(h.viewModel.variation.offeredExerciseIds, moves(original))
    }

    func testRepeatedPressesKeepGivingAnotherWorkoutThenComeBackToTheFirst() async throws {
        let h = try harness()
        await h.viewModel.load()
        let first = content(h.viewModel.workout)
        var seen = moves(h.viewModel.workout)

        var cameBack = false
        for _ in 0..<80 {
            await h.viewModel.showDifferentWorkout()
            if content(h.viewModel.workout) == first {
                cameBack = true
                break
            }
            let shown = moves(h.viewModel.workout)
            XCTAssertFalse(shown.isSubset(of: seen), "every press before the cycle shows something new")
            seen.formUnion(shown)
        }
        XCTAssertTrue(cameBack, "the presses cycle back to the first workout instead of running dry")
        XCTAssertNil(h.viewModel.errorMessage)
    }

    func testTheSamePressCountGivesTheSameWorkout() async throws {
        let a = try harness()
        let b = try harness()
        await a.viewModel.load()
        await b.viewModel.load()
        for _ in 0..<3 {
            await a.viewModel.showDifferentWorkout()
            await b.viewModel.showDifferentWorkout()
        }
        XCTAssertEqual(content(a.viewModel.workout), content(b.viewModel.workout))
    }

    func testALengthChangeAfterAPressStillWorksAndStartsOver() async throws {
        let h = try harness()
        await h.viewModel.load()
        await h.viewModel.showDifferentWorkout()

        await h.viewModel.selectDuration(45)

        XCTAssertEqual(h.viewModel.selectedMinutes, 45)
        XCTAssertEqual(h.viewModel.workout?.requestedMinutes, 45)
        XCTAssertEqual(h.viewModel.variation, .none, "a new length starts from its default session")

        let fresh = try harness()
        await fresh.viewModel.load()
        await fresh.viewModel.selectDuration(45)
        XCTAssertEqual(content(h.viewModel.workout), content(fresh.viewModel.workout))

        await h.viewModel.showDifferentWorkout()
        XCTAssertEqual(h.viewModel.workout?.requestedMinutes, 45, "a press at the new length keeps the new length")
        XCTAssertNotEqual(moves(h.viewModel.workout), moves(fresh.viewModel.workout))
    }

    func testAReappearKeepsTheChosenWorkout() async throws {
        let h = try harness()
        await h.viewModel.load()
        await h.viewModel.showDifferentWorkout()
        let chosen = content(h.viewModel.workout)

        await h.viewModel.load()

        XCTAssertEqual(content(h.viewModel.workout), chosen, "returning to the tab does not undo the press")
    }

    func testStartingAPressedWorkoutEndsTheSequenceSoTheNextLoadIsTheDefaultForTheNewHistory() async throws {
        let h = try harness()
        await h.viewModel.load()
        await h.viewModel.showDifferentWorkout()
        let started = try XCTUnwrap(h.viewModel.workout)

        h.viewModel.sessionWillStart()
        let log = completedLog(of: started)
        try await h.logService.save(log)
        await h.viewModel.handlePlayerDismiss(completed: true)
        await h.viewModel.load()

        XCTAssertEqual(h.viewModel.variation, .none, "starting a session ends the Different workout sequence")
        let fresh = try harness(logs: [log])
        await fresh.viewModel.load()
        XCTAssertEqual(
            content(h.viewModel.workout), content(fresh.viewModel.workout),
            "the next Ready Screen shows the default session for the history that now includes the played workout"
        )
    }

    func testAPressLeavesAPausedSessionExactlyAsItIs() async throws {
        let store = InMemoryActiveSessionStore()
        let h = try harness(store: store)
        await h.viewModel.load()
        let paused = ActiveSessionState(fresh: try XCTUnwrap(h.viewModel.workout))
        try await store.save(paused, for: "preview-user")
        await h.viewModel.load()
        XCTAssertNotNil(h.viewModel.resumableSession)

        await h.viewModel.showDifferentWorkout()
        await h.viewModel.showDifferentWorkout()

        XCTAssertEqual(h.viewModel.resumableSession?.workout, paused.workout, "the Resume card still offers the paused session")
        let stored = try await store.load(for: "preview-user")
        XCTAssertEqual(stored?.workout, paused.workout, "the paused session is not overwritten")
    }

    func testAnUnstartedWorkoutLeavesNoLogScoreOrEvent() async throws {
        let h = try harness()
        await h.viewModel.load()
        let scoreBefore = h.viewModel.consistency

        for _ in 0..<4 { await h.viewModel.showDifferentWorkout() }

        let logs = try await h.logService.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(logs.isEmpty, "a press writes no log, so nothing counts toward variety or progression")
        XCTAssertEqual(h.viewModel.consistency, scoreBefore, "the Consistency Score is untouched")
        let events = await h.analytics.recordedEvents
        XCTAssertEqual(events.map(\.name), [.readyScreenShown], "a press reports no event of its own")
    }

    func testAPressBeforeASessionHasLoadedDoesNothing() async throws {
        let h = try harness()

        await h.viewModel.showDifferentWorkout()

        XCTAssertNil(h.viewModel.workout)
        XCTAssertEqual(h.viewModel.variation, .none)
    }

    func testAFailedPressKeepsTheShownSessionAndItsRequest() async throws {
        let engine = FailingAfterFirstEngine(inner: MockWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.fixedDate }))
        let viewModel = ReadyViewModel(
            userService: MockUserService(user: user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: engine,
            workoutLogService: MockWorkoutLogService(logs: []),
            activeSessionStore: InMemoryActiveSessionStore(),
            now: { self.fixedDate }
        )
        await viewModel.load()
        let shown = content(viewModel.workout)

        await viewModel.showDifferentWorkout()

        XCTAssertEqual(content(viewModel.workout), shown)
        XCTAssertEqual(viewModel.variation, .none, "the request rolls back to the one that built the shown session")
    }
}

/// Builds the first session, then throws on every later generation.
private final class FailingAfterFirstEngine: WorkoutEngineProtocol {
    struct Failure: Error {}
    private let inner: any WorkoutEngineProtocol
    private var calls = 0

    init(inner: any WorkoutEngineProtocol) { self.inner = inner }

    func generateWorkout(
        requestedMinutes: Int,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy,
        variation: SessionVariation
    ) async throws -> Workout {
        calls += 1
        guard calls == 1 else { throw Failure() }
        return try await inner.generateWorkout(
            requestedMinutes: requestedMinutes, user: user, recentLogs: recentLogs,
            sessionPolicy: sessionPolicy, variation: variation
        )
    }

    func swapExercise(
        _ prescription: PrescribedExercise,
        in workout: Workout,
        user: User,
        recentLogs: [WorkoutLog],
        sessionPolicy: SessionPolicy
    ) async throws -> SwapOutcome {
        .noAlternative
    }
}
