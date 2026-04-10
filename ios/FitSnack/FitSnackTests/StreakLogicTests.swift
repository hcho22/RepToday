import XCTest
@testable import FitSnack

final class StreakLogicTests: XCTestCase {
    private let calendar = Calendar.current

    // MARK: - Helper

    /// Returns the start of the ISO week containing `date`.
    private func weekStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }

    /// Creates `count` dates spread across the given ISO week (offset from current week).
    /// weekOffset: 0 = current week, -1 = last week, etc.
    private func dates(inWeekOffset offset: Int, count: Int) -> [Date] {
        let currentWeekStart = weekStart(for: Date())
        let targetWeekStart = calendar.date(byAdding: .day, value: offset * 7, to: currentWeekStart)!
        return (0..<count).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: targetWeekStart)
        }
    }

    // MARK: - Tests

    func testEmptyHistoryReturnsZeroStreak() {
        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: [], weeklyGoal: 3)
        XCTAssertEqual(streak, 0, "Empty workout history should return a streak of 0")
    }

    func testStreakIncrementsWhenWeeklyGoalMet() {
        // 3 workouts each in current week, last week, and 2 weeks ago → streak of 3
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 3)
            + dates(inWeekOffset: -2, count: 3)

        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3)
        XCTAssertEqual(streak, 3, "Three consecutive weeks meeting goal should yield streak of 3")
    }

    func testStreakResetsWhenWeeklyGoalMissed() {
        // Current week: 3 workouts (meets goal)
        // Last week: 1 workout (misses goal of 3)
        // Two weeks ago: 3 workouts (meets goal, but unreachable due to gap)
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 1)
            + dates(inWeekOffset: -2, count: 3)

        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3)
        XCTAssertEqual(streak, 1, "Streak should reset at the missed week — only current week counts")
    }

    func testStreakHandlesWeekBoundaries() {
        // Verify the algorithm uses ISO week boundaries, not rolling 7-day windows.
        // Place workouts at the end of last week and start of this week — they should
        // count as two separate weeks, each meeting the goal.
        let currentWeekStart = weekStart(for: Date())
        let lastWeekEnd = calendar.date(byAdding: .day, value: -1, to: currentWeekStart)! // Sunday of last week
        let lastWeekEndMinus1 = calendar.date(byAdding: .day, value: -2, to: currentWeekStart)!

        let thisWeekDates = [
            currentWeekStart,
            calendar.date(byAdding: .day, value: 1, to: currentWeekStart)!,
        ]
        let lastWeekDates = [lastWeekEnd, lastWeekEndMinus1]

        let allDates = thisWeekDates + lastWeekDates
        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 2)
        XCTAssertEqual(streak, 2, "Workouts in two different ISO weeks should count as streak of 2")
    }

    func testFirstWeekCanBeStreakOfOne() {
        // Only the current week has workouts meeting the goal
        let allDates = dates(inWeekOffset: 0, count: 3)
        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3)
        XCTAssertEqual(streak, 1, "A single week meeting the goal should yield a streak of 1")
    }

    // MARK: - Streak Freeze Tests

    func testFreezePreservesStreakOnMissedWeek() {
        // Current week + 2 weeks ago meet goal, last week misses → 1 freeze should bridge the gap
        // Week -3 is empty so it will break the streak (only 1 freeze available)
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 1) // misses goal of 3
            + dates(inWeekOffset: -2, count: 3)

        let result = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3, availableFreezes: 1)
        XCTAssertEqual(result.streak, 3, "Freeze should preserve streak through missed week")
        XCTAssertEqual(result.freezesUsed, 1, "Should consume exactly 1 freeze")
    }

    func testStreakBreaksWhenNoFreezesLeft() {
        // Same scenario but with 0 freezes
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 1)
            + dates(inWeekOffset: -2, count: 3)

        let result = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3, availableFreezes: 0)
        XCTAssertEqual(result.streak, 1, "Without freezes, streak should break at missed week")
        XCTAssertEqual(result.freezesUsed, 0)
    }

    func testMultipleFreezesConsumed() {
        // 2 non-consecutive missed weeks with 2 freezes available
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 1) // miss
            + dates(inWeekOffset: -2, count: 3)
            + dates(inWeekOffset: -3, count: 1) // miss
            + dates(inWeekOffset: -4, count: 3)

        let result = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3, availableFreezes: 2)
        XCTAssertEqual(result.streak, 5, "Two freezes should bridge two missed weeks")
        XCTAssertEqual(result.freezesUsed, 2)
    }

    func testThirdMissedWeekBreaksStreak() {
        // 3 missed weeks but only 2 freezes
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 1) // miss — freeze 1
            + dates(inWeekOffset: -2, count: 1) // miss — freeze 2
            + dates(inWeekOffset: -3, count: 1) // miss — no freeze left
            + dates(inWeekOffset: -4, count: 3)

        let result = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3, availableFreezes: 2)
        XCTAssertEqual(result.streak, 3, "Third missed week should break streak when only 2 freezes available")
        XCTAssertEqual(result.freezesUsed, 2)
    }

    func testOriginalCalculatorUnchangedWithoutFreezes() {
        // The zero-arg overload should still work identically
        let allDates = dates(inWeekOffset: 0, count: 3)
            + dates(inWeekOffset: -1, count: 3)

        let streak = Constants.Streak.calculateWeeklyStreak(workoutDates: allDates, weeklyGoal: 3)
        XCTAssertEqual(streak, 2)
    }

    // MARK: - Streak Freeze Replenish Tests

    func testShouldReplenishWhenNoLastDate() {
        XCTAssertTrue(Constants.StreakFreeze.shouldReplenish(lastReplenishDate: nil))
    }

    func testShouldReplenishOnNewMonth() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        XCTAssertTrue(Constants.StreakFreeze.shouldReplenish(lastReplenishDate: lastMonth))
    }

    func testShouldNotReplenishSameMonth() {
        XCTAssertFalse(Constants.StreakFreeze.shouldReplenish(lastReplenishDate: Date()))
    }

    func testPremiumFreezeCount() {
        XCTAssertEqual(Constants.StreakFreeze.maxFreezes(isPremium: true), 2)
        XCTAssertEqual(Constants.StreakFreeze.maxFreezes(isPremium: false), 0)
    }
}
