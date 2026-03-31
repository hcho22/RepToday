import SwiftUI

@Observable
final class ProgressViewModel {
    var workoutHistory: [Workout] = []
    var monthStats = MonthStats()
    var calendarData: [Date: Int] = [:]
    var personalRecords: [PersonalRecord] = []
    var consistencyScore: Double = 0

    struct MonthStats {
        var totalWorkouts = 0
        var totalMinutes = 0
        var totalCalories = 0
        var avgDuration = 0
    }

    struct PersonalRecord {
        var title: String
        var value: String
        var date: Date?
    }

    var historyItems: [WorkoutHistory] {
        workoutHistory.map { workout in
            WorkoutHistory(
                id: UUID().uuidString,
                workoutId: workout.id,
                date: workout.completedAt ?? workout.createdAt,
                durationMinutes: workout.actualDurationMinutes ?? workout.requestedDurationMinutes,
                exerciseCount: workout.allExercises.count,
                caloriesBurned: Double(workout.actualCalories ?? workout.estimatedCalories ?? 0),
                muscleGroups: Array(Set(workout.allExercises.flatMap { $0.exercise.muscleGroups.primary })),
                rating: workout.userRating
            )
        }
    }

    func loadData(services: ServiceContainer?) async {
        guard let services else { return }
        do {
            workoutHistory = try await services.workout.getHistory()
            let stats = try await services.user.getGamificationStats()
            calculateMonthStats()
            buildCalendarData()
            calculatePRs(longestStreak: stats.longestWeeklyStreak)
            calculateConsistency(weeklyGoal: stats.weeklyWorkoutGoal)
        } catch {}
    }

    private func calculateMonthStats() {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let thisMonth = workoutHistory.filter { $0.completedAt ?? $0.createdAt >= monthStart }
        monthStats.totalWorkouts = thisMonth.count
        monthStats.totalMinutes = thisMonth.reduce(0) { $0 + ($1.actualDurationMinutes ?? $1.requestedDurationMinutes) }
        monthStats.totalCalories = thisMonth.reduce(0) { $0 + ($1.actualCalories ?? $1.estimatedCalories ?? 0) }
        monthStats.avgDuration = thisMonth.isEmpty ? 0 : monthStats.totalMinutes / thisMonth.count
    }

    private func buildCalendarData() {
        let calendar = Calendar.current
        calendarData = [:]
        for workout in workoutHistory {
            let date = calendar.startOfDay(for: workout.completedAt ?? workout.createdAt)
            let minutes = workout.actualDurationMinutes ?? workout.requestedDurationMinutes
            calendarData[date, default: 0] += minutes
        }
    }

    private func calculatePRs(longestStreak: Int) {
        personalRecords = []

        if let longest = workoutHistory.max(by: { ($0.actualDurationMinutes ?? 0) < ($1.actualDurationMinutes ?? 0) }) {
            personalRecords.append(PersonalRecord(
                title: "Longest Workout",
                value: "\(longest.actualDurationMinutes ?? longest.requestedDurationMinutes) min",
                date: longest.completedAt
            ))
        }

        if let highestCal = workoutHistory.max(by: { ($0.actualCalories ?? $0.estimatedCalories ?? 0) < ($1.actualCalories ?? $1.estimatedCalories ?? 0) }) {
            let cal = highestCal.actualCalories ?? highestCal.estimatedCalories ?? 0
            if cal > 0 {
                personalRecords.append(PersonalRecord(
                    title: "Highest Calories",
                    value: "\(cal) cal",
                    date: highestCal.completedAt
                ))
            }
        }

        if longestStreak > 0 {
            personalRecords.append(PersonalRecord(
                title: "Longest Streak",
                value: "\(longestStreak) week\(longestStreak == 1 ? "" : "s")",
                date: nil
            ))
        }

        personalRecords.append(PersonalRecord(
            title: "Total Workouts",
            value: "\(workoutHistory.count)",
            date: nil
        ))
    }

    private func calculateConsistency(weeklyGoal: Int) {
        guard weeklyGoal > 0, !workoutHistory.isEmpty else {
            consistencyScore = 0
            return
        }

        let calendar = Calendar.current
        let dates = workoutHistory.compactMap { $0.completedAt }
        guard let earliest = dates.min() else {
            consistencyScore = 0
            return
        }

        var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: earliest))!
        let now = Date()
        var totalWeeks = 0
        var metGoalWeeks = 0

        while weekStart <= now {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            let workoutsInWeek = dates.filter { $0 >= weekStart && $0 < weekEnd }.count
            totalWeeks += 1
            if workoutsInWeek >= weeklyGoal {
                metGoalWeeks += 1
            }
            weekStart = weekEnd
        }

        consistencyScore = totalWeeks > 0 ? Double(metGoalWeeks) / Double(totalWeeks) : 0
    }
}
