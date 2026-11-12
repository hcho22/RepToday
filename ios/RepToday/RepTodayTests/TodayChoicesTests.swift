import XCTest
@testable import RepToday

/// Today's choices (M4, US-CA03): the day-scoped rest, length and swap choices Today's own controls and
/// a confirmed Coach proposal share. Today reads them on every load, so what the Coach applies is what
/// the user sees - and nothing here moves the Rotation, a ladder or the Consistency Score.
@MainActor
final class TodayChoicesTests: XCTestCase {

    private let now = TrainingDayFixtures.asOf
    private var today: String { TodayChoices.dayKey(for: now) }

    private func makeViewModel(logs: [WorkoutLog] = [], choices: InMemoryTodayChoicesStore) throws -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            workoutLogService: MockWorkoutLogService(logs: logs),
            activeSessionStore: InMemoryActiveSessionStore(),
            todayChoicesStore: choices,
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

    // MARK: - The rule

    func testRestingTurnsATrainingDayIntoAChosenRestAndTrainingAnywayTurnsARestDayIntoTraining() {
        let rest = TodayChoices(day: today, rest: .restToday)
        XCTAssertEqual(rest.applied(to: .train(.pull)), .rest(next: .pull, reason: .chosen))
        XCTAssertEqual(rest.applied(to: .rest(next: .push, reason: .cycleComplete)), .rest(next: .push, reason: .cycleComplete))
        let anyway = TodayChoices(day: today, rest: .trainAnyway)
        XCTAssertEqual(anyway.applied(to: .rest(next: .push, reason: .cycleComplete)), .train(.push))
        XCTAssertEqual(anyway.applied(to: .train(.legs)), .train(.legs))
        XCTAssertEqual(TodayChoices.empty(on: today).applied(to: .train(.legs)), .train(.legs))
    }

    func testChoicesBelongToOneDay() {
        let store = InMemoryTodayChoicesStore()
        store.update(on: "2026-11-10") { $0.minutes = 10 }
        XCTAssertEqual(store.choices(on: "2026-11-10").minutes, 10)
        XCTAssertTrue(store.choices(on: "2026-11-11").isEmpty, "a new day starts with no choices")
    }

    func testTheDefaultsStoreSurvivesAndClears() throws {
        let suite = "TodayChoicesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DefaultsTodayChoicesStore(defaults: defaults)
        store.update(on: today) { $0.rest = .restToday; $0.swappedOut = ["push_incline"] }
        XCTAssertEqual(DefaultsTodayChoicesStore(defaults: defaults).choices(on: today).swappedOut, ["push_incline"])
        store.clear()
        XCTAssertTrue(store.choices(on: today).isEmpty)
    }

    // MARK: - Today reads them

    func testAChosenRestShowsTheRestDayAndTrainAnywayTakesItBack() async throws {
        let choices = InMemoryTodayChoicesStore(TodayChoices(day: today, rest: .restToday))
        let vm = try makeViewModel(logs: [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1, hour: 18))], choices: choices)
        await vm.load()
        XCTAssertTrue(vm.showsRestDay)
        XCTAssertEqual(vm.effectivePlan, .rest(next: .pull, reason: .chosen))
        XCTAssertEqual(vm.plan, .train(.pull), "the Rotation itself is untouched: resting skips no group")
        XCTAssertNil(vm.workout)

        await vm.trainAnyway()
        XCTAssertFalse(vm.showsRestDay)
        XCTAssertEqual(vm.workout?.trainingDay, .pull)
        XCTAssertNil(choices.choices(on: today).rest, "taking the rest back clears the choice")
    }

    func testTrainingAnywayOnARestDayIsKeptForTheDay() async throws {
        let choices = InMemoryTodayChoicesStore()
        let vm = try makeViewModel(logs: completedCycle(), choices: choices)
        await vm.load()
        await vm.trainAnyway()
        XCTAssertEqual(choices.choices(on: today).rest, .trainAnyway)

        let reopened = try makeViewModel(logs: completedCycle(), choices: choices)
        await reopened.load()
        XCTAssertFalse(reopened.showsRestDay, "the choice made from Today or the Coach holds for the day")
        XCTAssertEqual(reopened.workout?.trainingDay, .push)
    }

    func testTodaysChosenLengthBuildsTheSession() async throws {
        let choices = InMemoryTodayChoicesStore(TodayChoices(day: today, minutes: 10))
        let vm = try makeViewModel(choices: choices)
        await vm.load()
        XCTAssertEqual(vm.selectedMinutes, 10)
        XCTAssertEqual(vm.workout?.requestedMinutes, 10)

        await vm.selectDuration(30)
        XCTAssertEqual(choices.choices(on: today).minutes, 30, "a chip tap is today's choice too, so the two never disagree")
    }

    func testAMovementSwappedOutTodayIsReplacedByTheEnginesSubstitute() async throws {
        let plain = try makeViewModel(choices: InMemoryTodayChoicesStore())
        await plain.load()
        let original = try XCTUnwrap(plain.workout?.blocks.flatMap(\.exercises).first { $0.role == .main })

        let choices = InMemoryTodayChoicesStore(TodayChoices(day: today, swappedOut: [original.exercise.id]))
        let vm = try makeViewModel(choices: choices)
        await vm.load()
        let ids = vm.workout?.blocks.flatMap(\.exercises).map(\.exercise.id) ?? []
        XCTAssertFalse(ids.contains(original.exercise.id), "the swapped-out movement is gone from today's session")
        XCTAssertEqual(vm.workout?.blocks.flatMap(\.exercises).count, plain.workout?.blocks.flatMap(\.exercises).count,
                       "the slot is kept, with the engine's substitute in it")
    }

    /// The Coach is told about the session on the user's screen: after a swap it names the substitute in
    /// the swapped movement's place, in Today's order, so "the first movement" means the same to both.
    func testTheCoachSeesTodaysSessionWithItsSwapsApplied() async throws {
        let plain = try makeViewModel(choices: InMemoryTodayChoicesStore())
        await plain.load()
        let original = try XCTUnwrap(plain.workout?.blocks.flatMap(\.exercises).first)

        let choices = InMemoryTodayChoicesStore(TodayChoices(day: today, swappedOut: [original.exercise.id]))
        let vm = try makeViewModel(choices: choices)
        await vm.load()
        let onScreen = vm.workout?.blocks.flatMap(\.exercises).map(\.exercise.id) ?? []

        let reader = CoachTodayReader(
            userService: MockUserService(user: TrainingDayFixtures.user()),
            workoutLogService: MockWorkoutLogService(logs: []),
            outsideActivityService: InMemoryOutsideActivityService(),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try MockExerciseService(), now: { self.now }),
            todayChoices: choices,
            now: { self.now }
        )
        let snapshot = await reader.snapshot()
        XCTAssertEqual(snapshot?.movements.map(\.id), Array(onScreen.prefix(16)))
        XCTAssertNotEqual(snapshot?.movements.first?.id, original.exercise.id, "the substitute takes the swapped movement's place")
    }

    func testCompletingASessionClearsTheRestChoice() async throws {
        let choices = InMemoryTodayChoicesStore(TodayChoices(day: today, rest: .trainAnyway))
        let vm = try makeViewModel(logs: completedCycle(), choices: choices)
        await vm.load()
        await vm.handlePlayerDismiss(completed: true)
        XCTAssertNil(choices.choices(on: today).rest, "the plan it was made on has moved")
    }
}
