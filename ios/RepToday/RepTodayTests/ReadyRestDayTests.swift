import XCTest
@testable import RepToday

/// US-TD05: Today follows the Rotation - the next Training Day, or the Rest Day card after a completed
/// Cycle with its Recovery flow and "Train anyway".
@MainActor
final class ReadyRestDayTests: XCTestCase {

    private let now = TrainingDayFixtures.asOf

    private func makeViewModel(
        logs: [WorkoutLog],
        store: any ActiveSessionStore = InMemoryActiveSessionStore(),
        analytics: (any AnalyticsServiceProtocol)? = nil
    ) throws -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            workoutLogService: MockWorkoutLogService(logs: logs),
            activeSessionStore: store,
            analytics: analytics,
            now: { self.now }
        )
    }

    private func completedCycle() -> [WorkoutLog] {
        [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 3, hour: 18)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2, hour: 18)),
            TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 1, hour: 18)),
        ]
    }

    func testTodayShowsTheNextTrainingDay() async throws {
        let vm = try makeViewModel(logs: [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1, hour: 18))])
        await vm.load()
        XCTAssertFalse(vm.showsRestDay)
        XCTAssertEqual(vm.trainingDay, .pull)
        XCTAssertEqual(vm.workout?.trainingDay, .pull)
    }

    func testACompletedCycleShowsTheRestDayAndBuildsNoSession() async throws {
        let vm = try makeViewModel(logs: completedCycle())
        await vm.load()
        XCTAssertTrue(vm.showsRestDay)
        XCTAssertEqual(vm.plan, .rest(next: .push, reason: .cycleComplete))
        XCTAssertNil(vm.workout)
    }

    func testTrainAnywayBuildsTheNextGroupsSession() async throws {
        let vm = try makeViewModel(logs: completedCycle())
        await vm.load()
        await vm.trainAnyway()
        XCTAssertFalse(vm.showsRestDay)
        XCTAssertEqual(vm.workout?.trainingDay, .push)
    }

    func testRecoveryIsAMobilityOnlyFlowThatLeavesTheRestDayInPlace() async throws {
        let vm = try makeViewModel(logs: completedCycle())
        await vm.load()
        let built = await vm.recoveryWorkout()
        let recovery = try XCTUnwrap(built)
        XCTAssertTrue(recovery.blocks.flatMap(\.exercises).allSatisfy { $0.role == .recovery })
        XCTAssertTrue(vm.showsRestDay)
    }

    /// The Rotation replays the whole history, not the engine's 70-day window. Here the window would
    /// begin on a Pull, so a replay from it reads every later Cycle one day out of step and owes a Rest
    /// Day after yesterday's Push; the real Cycles (Push, Pull, Legs, then a rest) put today on Pull.
    func testTheRotationReadsTheWholeHistoryNotTheRecentWindow() async throws {
        // Backward from yesterday: Push, three session-free days, then Legs, Pull, Push, rest repeating,
        // so day 70 (the oldest in the window) is a Pull and day 71 (just outside it) a Push.
        var logs = [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1, hour: 18))]
        let cycle: [TrainingDay?] = [.legs, .pull, .push, nil]
        for daysAgo in 5...100 {
            guard let day = cycle[(daysAgo - 5) % cycle.count] else { continue }
            logs.append(TrainingDayFixtures.trainingLog(day, completedAt: TrainingDayFixtures.date(daysAgo: daysAgo, hour: 18)))
        }
        let window = logs.filter { $0.completedAt >= TrainingDayFixtures.date(daysAgo: 70, hour: 0) }
        XCTAssertEqual(window.min { $0.completedAt < $1.completedAt }?.trainingDay, .pull)
        XCTAssertTrue(TrainingRotation.plan(logs: window, asOf: now, calendar: TrainingDayFixtures.calendar).isRest)

        let vm = try makeViewModel(logs: logs)
        await vm.load()
        XCTAssertEqual(vm.plan, .train(.pull))
        XCTAssertEqual(vm.workout?.trainingDay, .pull)
    }

    /// Starting the Recovery flow overwrites a paused session just as Start does, so that session is
    /// given up: it emits `session_abandoned` and its Resume card clears.
    func testStartingRecoveryOverAPausedSessionAbandonsIt() async throws {
        let paused = SessionAssembly.assemble(
            requestedMinutes: 15,
            user: TrainingDayFixtures.user(),
            library: try await MockExerciseService().exercises(),
            recentLogs: [],
            trainingDay: .push,
            asOf: now,
            calendar: TrainingDayFixtures.calendar
        )
        let slots = paused.blocks.flatMap { block in
            block.exercises.map { ActiveSessionState.Slot(blockTitle: block.title, blockCategory: block.category, prescription: $0) }
        }
        let store = InMemoryActiveSessionStore()
        try await store.save(
            ActiveSessionState(
                workout: paused, slots: slots, currentStepIndex: 0, currentSet: 1,
                completedSets: [:], skippedStepIDs: [], startedAt: now, rest: nil, hold: nil,
                exercisedMinutes: 3
            ),
            for: TrainingDayFixtures.user().id
        )
        let analytics = MockAnalyticsService()
        let vm = try makeViewModel(logs: completedCycle(), store: store, analytics: analytics)
        await vm.load()
        XCTAssertTrue(vm.showsRestDay)
        XCTAssertNotNil(vm.resumableSession)

        let recovery = await vm.recoveryWorkout()

        XCTAssertNotNil(recovery)
        XCTAssertNil(vm.resumableSession)
        let abandoned = (await analytics.recordedEvents).filter { $0.name == .sessionAbandoned }
        XCTAssertEqual(abandoned.count, 1)
        XCTAssertEqual(abandoned.first?.properties["completed_minutes"], .int(3))
    }

    func testTheHeaderReadsTheHonestLength() async throws {
        let vm = try makeViewModel(logs: [])
        await vm.load()
        let workout = try XCTUnwrap(vm.workout)
        XCTAssertEqual(vm.plannedMinutes, Int((Double(SessionAssembly.plannedSeconds(of: workout)) / 60).rounded()))
    }
}
