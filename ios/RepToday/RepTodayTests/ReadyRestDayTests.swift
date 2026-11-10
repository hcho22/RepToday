import XCTest
@testable import RepToday

/// US-TD05: Today follows the Rotation - the next Training Day, or the Rest Day card after a completed
/// Cycle with its Recovery flow and "Train anyway".
@MainActor
final class ReadyRestDayTests: XCTestCase {

    private let now = TrainingDayFixtures.asOf

    private func makeViewModel(logs: [WorkoutLog]) throws -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            workoutLogService: MockWorkoutLogService(logs: logs),
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
        XCTAssertEqual(vm.plan, .rest(next: .push, isEarly: false))
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

    func testTheHeaderReadsTheHonestLength() async throws {
        let vm = try makeViewModel(logs: [])
        await vm.load()
        let workout = try XCTUnwrap(vm.workout)
        XCTAssertEqual(vm.plannedMinutes, Int((Double(SessionAssembly.plannedSeconds(of: workout)) / 60).rounded()))
    }
}
