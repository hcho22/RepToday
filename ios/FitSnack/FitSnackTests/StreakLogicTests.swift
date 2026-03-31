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
}
