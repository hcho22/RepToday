import XCTest
@testable import RepToday

/// US-TD05 / FR-7: a Rest Day never lowers the Consistency Score, and the Recovery flow is not a session.
///
/// Structurally: the Rotation owes one Rest Day per three Training Days, so any seven days of it hold at
/// least five sessions - above the weekly goal of three - and a week with its Rest Day in it still reads
/// as full adherence.
final class RestDayConsistencyTests: XCTestCase {

    private let calendar = TrainingDayFixtures.calendar
    /// Saturday 14 November 2026, evening: the end of a whole week, so no week in the window is partial.
    private let asOf = TrainingDayFixtures.calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 20))!

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .hour, value: -daysAgo * 24 - 2, to: asOf)!
    }

    /// Eight weeks of the Rotation followed exactly: Push, Pull, Legs, Rest, repeated, through today.
    private func followedRotation(withRecovery: Bool) -> [WorkoutLog] {
        var logs: [WorkoutLog] = []
        for daysAgo in (0...55).reversed() {
            let slot = (55 - daysAgo) % 4
            let date = date(daysAgo: daysAgo)
            if slot < 3 {
                logs.append(TrainingDayFixtures.trainingLog(TrainingDay.rotation[slot], completedAt: date))
            } else if withRecovery {
                logs.append(TrainingDayFixtures.recoveryLog(completedAt: date))
            }
        }
        return logs
    }

    func testAnySevenDaysOfTheRotationHoldMoreSessionsThanTheWeeklyGoal() {
        let logs = followedRotation(withRecovery: false)
        for start in 0...48 {
            let window = logs.filter { log in
                let daysAgo = calendar.dateComponents([.day], from: log.completedAt, to: asOf).day ?? 0
                return daysAgo >= start && daysAgo < start + 7
            }
            XCTAssertGreaterThanOrEqual(window.count, 5)
        }
    }

    func testFollowingTheRotationWithItsRestDaysEarnsTheFullScore() {
        let consistency = ConsistencyScore.evaluate(logs: followedRotation(withRecovery: false), weeklyGoal: 3, asOf: asOf, calendar: calendar)
        XCTAssertEqual(consistency.score, 100)
    }

    func testRestDaysNeverLowerTheScoreAgainstTrainingEveryDay() {
        let withRest = ConsistencyScore.evaluate(logs: followedRotation(withRecovery: false), weeklyGoal: 3, asOf: asOf, calendar: calendar)
        let everyDay = (0...55).map { daysAgo in
            TrainingDayFixtures.trainingLog(TrainingDay.rotation[daysAgo % 3], completedAt: date(daysAgo: daysAgo))
        }
        let noRest = ConsistencyScore.evaluate(logs: everyDay, weeklyGoal: 3, asOf: asOf, calendar: calendar)
        XCTAssertGreaterThanOrEqual(withRest.score, noRest.score)
    }

    func testTheRecoveryFlowIsNotCountedAsASession() {
        let plain = ConsistencyScore.evaluate(logs: followedRotation(withRecovery: false), weeklyGoal: 3, asOf: asOf, calendar: calendar)
        let withRecovery = ConsistencyScore.evaluate(logs: followedRotation(withRecovery: true), weeklyGoal: 3, asOf: asOf, calendar: calendar)
        XCTAssertEqual(withRecovery, plain)

        // A Recovery flow alone is no show-up.
        let onlyRecovery = ConsistencyScore.evaluate(
            logs: [TrainingDayFixtures.recoveryLog(completedAt: date(daysAgo: 1))],
            weeklyGoal: 3,
            asOf: asOf,
            calendar: calendar
        )
        XCTAssertEqual(onlyRecovery.totalWorkoutsCompleted, 0)
    }
}
