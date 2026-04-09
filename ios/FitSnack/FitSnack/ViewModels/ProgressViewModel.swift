import SwiftUI

@Observable
final class ProgressViewModel {
    var workoutHistory: [Workout] = []
    var monthStats = MonthStats()
    var calendarData: [Date: Int] = [:]
    var personalRecords: [PersonalRecord] = []
    var exercisePRs: [PersonalRecord] = []
    var consistencyScore: Double = 0
    var movementPatternFrequency: [FocusGroup: Double] = [:]

    struct MonthStats {
        var totalWorkouts = 0
        var totalMinutes = 0
        var totalCalories = 0
        var avgDuration = 0
    }

    struct PersonalRecord: Identifiable {
        let id = UUID()
        var title: String
        var value: String
        var date: Date?
        var exerciseName: String?
    }

    enum PRType {
        case workout, exercise
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
            calculateExercisePRs()
            calculateConsistency(weeklyGoal: stats.weeklyWorkoutGoal)
            calculateMovementPatternFrequency()
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

        if let mostExercises = workoutHistory.max(by: { $0.allExercises.count < $1.allExercises.count }) {
            let count = mostExercises.allExercises.count
            if count > 0 {
                personalRecords.append(PersonalRecord(
                    title: "Most Exercises",
                    value: "\(count) exercises",
                    date: mostExercises.completedAt
                ))
            }
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

    private func calculateExercisePRs() {
        struct ExerciseBest {
            var exerciseName: String
            var maxReps: Int?
            var maxRepsDate: Date?
            var maxDuration: Int?
            var maxDurationDate: Date?
        }

        var bestByExercise: [String: ExerciseBest] = [:]

        for workout in workoutHistory {
            let workoutDate = workout.completedAt ?? workout.createdAt
            for we in workout.allExercises where !we.skipped {
                let completedSets = we.completedSets.filter { $0.completed }
                guard !completedSets.isEmpty else { continue }

                let exerciseId = we.exerciseId
                var best = bestByExercise[exerciseId] ?? ExerciseBest(exerciseName: we.exercise.displayName)

                if let maxSetReps = completedSets.compactMap({ $0.reps }).max() {
                    if maxSetReps > (best.maxReps ?? 0) {
                        best.maxReps = maxSetReps
                        best.maxRepsDate = workoutDate
                    }
                }

                if let maxSetDuration = completedSets.compactMap({ $0.durationSeconds }).max() {
                    if maxSetDuration > (best.maxDuration ?? 0) {
                        best.maxDuration = maxSetDuration
                        best.maxDurationDate = workoutDate
                    }
                }

                bestByExercise[exerciseId] = best
            }
        }

        var records: [PersonalRecord] = []
        for (_, best) in bestByExercise {
            if let reps = best.maxReps, let date = best.maxRepsDate {
                records.append(PersonalRecord(
                    title: "Max Reps",
                    value: "\(reps) reps",
                    date: date,
                    exerciseName: best.exerciseName
                ))
            }
            if let duration = best.maxDuration, let date = best.maxDurationDate {
                let formatted = duration >= 60 ? "\(duration / 60)m \(duration % 60)s" : "\(duration)s"
                records.append(PersonalRecord(
                    title: "Max Duration",
                    value: formatted,
                    date: date,
                    exerciseName: best.exerciseName
                ))
            }
        }

        exercisePRs = records.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func calculateMovementPatternFrequency() {
        let calendar = Calendar.current
        let now = Date()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return }

        let recentWorkouts = workoutHistory.filter {
            ($0.completedAt ?? $0.createdAt) >= thirtyDaysAgo
        }

        var counts: [FocusGroup: Int] = [:]
        for workout in recentWorkouts {
            for exercise in workout.allExercises {
                let group = exercise.exercise.movementPattern.focusGroup
                counts[group, default: 0] += 1
            }
        }

        let maxCount = counts.values.max() ?? 1
        guard maxCount > 0 else {
            movementPatternFrequency = [:]
            return
        }

        movementPatternFrequency = counts.mapValues { Double($0) / Double(maxCount) }
    }
}
