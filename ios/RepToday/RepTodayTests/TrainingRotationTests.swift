import XCTest
@testable import RepToday

/// US-TD04 / US-TD05: the pure, date-injected Push -> Pull -> Legs Rotation (ADR-0012).
final class TrainingRotationTests: XCTestCase {

    private let calendar = TrainingDayFixtures.calendar
    private var asOf: Date { TrainingDayFixtures.asOf }

    private func plan(_ logs: [WorkoutLog], activities: [OutsideActivity] = []) -> TrainingPlan {
        TrainingRotation.plan(logs: logs, activities: activities, asOf: asOf, calendar: calendar)
    }

    private func day(_ day: TrainingDay, daysAgo: Int, hour: Int = 9) -> WorkoutLog {
        TrainingDayFixtures.trainingLog(day, completedAt: TrainingDayFixtures.date(daysAgo: daysAgo, hour: hour))
    }

    // MARK: Order and advancement

    func testAFreshUserStartsAtPush() {
        XCTAssertEqual(plan([]), .train(.push))
    }

    func testExistingUsersLogsCarryNoTrainingDaySoTheyStartAtPush() {
        let legacy = TrainingDayFixtures.legacyLog(completedAt: TrainingDayFixtures.date(daysAgo: 1))
        XCTAssertNil(legacy.trainingDay)
        XCTAssertEqual(plan([legacy]), .train(.push))
    }

    func testTheRotationRunsPushPullLegsInAFixedOrder() {
        XCTAssertEqual(plan([day(.push, daysAgo: 1)]), .train(.pull))
        XCTAssertEqual(plan([day(.push, daysAgo: 2), day(.pull, daysAgo: 1)]), .train(.legs))
    }

    func testAMissedDayNeverSkipsAGroup() {
        XCTAssertEqual(plan([day(.push, daysAgo: 6)]), .train(.pull))
    }

    func testASessionCompletedEarlierTodayMovesTodaysNextGroupOn() {
        let morning = TrainingDayFixtures.trainingLog(.push, completedAt: calendar.date(byAdding: .hour, value: -3, to: asOf)!)
        XCTAssertEqual(plan([morning]), .train(.pull))
    }

    // MARK: Rest Day

    func testCompletingACycleOwesARestDayTodayAndTomorrow() {
        let cycle = [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)]
        let legsToday = TrainingDayFixtures.trainingLog(.legs, completedAt: calendar.date(byAdding: .hour, value: -1, to: asOf)!)
        XCTAssertEqual(plan(cycle + [legsToday]), .rest(next: .push, reason: .cycleComplete))
        XCTAssertEqual(plan([day(.push, daysAgo: 3), day(.pull, daysAgo: 2), day(.legs, daysAgo: 1)]), .rest(next: .push, reason: .cycleComplete))
    }

    func testAnySessionFreeDayAfterLegsHonorsTheRest() {
        let logs = [day(.push, daysAgo: 5), day(.pull, daysAgo: 4), day(.legs, daysAgo: 3)]
        XCTAssertEqual(plan(logs), .train(.push))
    }

    func testTrainAnywayForfeitsTheRestAndTheNextCycleCarriesOn() {
        // Legs two days ago, then a Push session on the Rest Day itself: the rest is forfeited.
        let logs = [day(.push, daysAgo: 4), day(.pull, daysAgo: 3), day(.legs, daysAgo: 2), day(.push, daysAgo: 1)]
        XCTAssertEqual(plan(logs), .train(.pull))
    }

    func testARecoveryFlowNeitherMovesTheRotationNorBreaksTheRest() {
        let recovery = TrainingDayFixtures.recoveryLog(completedAt: calendar.date(byAdding: .hour, value: -1, to: asOf)!)
        XCTAssertTrue(recovery.isRecovery)
        XCTAssertNil(recovery.trainingDay)
        let logs = [day(.push, daysAgo: 3), day(.pull, daysAgo: 2), day(.legs, daysAgo: 1), recovery]
        XCTAssertEqual(plan(logs), .rest(next: .push, reason: .cycleComplete))
        // The day of the Recovery flow was session-free, so the next day the Cycle starts over.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: asOf)!
        XCTAssertEqual(TrainingRotation.plan(logs: logs, asOf: tomorrow, calendar: calendar), .train(.push))
    }

    // MARK: Outside Activities (decision 21)

    func testAnOutsideActivitySwapsItsGroupBehindTheNextOne() {
        let swim = OutsideActivity(type: .swim, date: TrainingDayFixtures.date(daysAgo: 1))
        XCTAssertEqual(plan([day(.push, daysAgo: 2)], activities: [swim]), .train(.legs))
        // An activity two days ago has already had its day off.
        let oldSwim = OutsideActivity(type: .swim, date: TrainingDayFixtures.date(daysAgo: 2))
        XCTAssertEqual(plan([day(.push, daysAgo: 3)], activities: [oldSwim]), .train(.pull))
    }

    func testAnOutsideActivityOnTheLastGroupBringsTheRestDayForwardAndTheCycleOwesNoOther() {
        let run = OutsideActivity(type: .run, date: TrainingDayFixtures.date(daysAgo: 1))
        let cycle = [day(.push, daysAgo: 3), day(.pull, daysAgo: 2)]
        XCTAssertEqual(plan(cycle, activities: [run]), .rest(next: .legs, reason: .early))

        // The early rest is taken today (no session), Legs tomorrow closes the Cycle, and the day after
        // starts the next one with no second rest.
        let legsTomorrow = TrainingDayFixtures.trainingLog(.legs, completedAt: calendar.date(byAdding: .day, value: 1, to: asOf)!)
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: asOf)!
        XCTAssertEqual(
            TrainingRotation.plan(logs: cycle + [legsTomorrow], activities: [run], asOf: dayAfter, calendar: calendar),
            .train(.push)
        )
    }

    func testAnOutsideActivityThatWorksNoGroupChangesNothing() {
        let yoga = OutsideActivity(type: .other, date: TrainingDayFixtures.date(daysAgo: 1))
        XCTAssertEqual(plan([day(.push, daysAgo: 2)], activities: [yoga]), .train(.pull))
    }

    // MARK: Core Sprinkle

    func testTheCoreSprinkleRotatesFromCycleToCycle() async throws {
        let library = try await MockExerciseService().exercises()
        let ladders = SessionAssembly.coreLadders
        let first = TrainingRotation.coreLadderOrder(canonical: ladders, library: library, logs: [], asOf: asOf, calendar: calendar)
        XCTAssertEqual(first.first, "core_plank")

        // A Cycle that worked the plank ladder hands the next Cycle a different lead ladder, and the
        // lead holds for every day of a Cycle.
        let plankCycle = [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 5), core: "core_forearm_plank"),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 4), core: "core_forearm_plank"),
            TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 3), core: "core_forearm_plank"),
        ]
        let next = TrainingRotation.coreLadderOrder(canonical: ladders, library: library, logs: plankCycle, asOf: asOf, calendar: calendar)
        XCTAssertNotEqual(next.first, "core_plank")

        let midCycle = plankCycle + [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1), core: "core_bird_dog"),
        ]
        let sameCycle = TrainingRotation.coreLadderOrder(canonical: ladders, library: library, logs: midCycle, asOf: asOf, calendar: calendar)
        XCTAssertEqual(sameCycle.first, next.first)
    }
}
