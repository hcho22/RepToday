import Foundation

final class MockAIService: AIServiceProtocol {

    func generatePostWorkoutSummary(
        workout: Workout,
        userProfile: UserProfile,
        recentHistory: [Workout]
    ) async throws -> AITextResponse {
        let duration = workout.actualDurationMinutes ?? workout.requestedDurationMinutes
        let exerciseCount = workout.totalExerciseCount
        let focusArea = workout.focusAreas.first ?? "full body"

        let primaryMuscles = workout.muscleGroupsWorked
            .filter { $0.value == "primary" }
            .keys
            .sorted()
            .joined(separator: ", ")
        let muscleText = primaryMuscles.isEmpty ? "multiple muscle groups" : primaryMuscles

        let text = "Great \(duration)-minute \(focusArea) session! You completed \(exerciseCount) exercises targeting \(muscleText). Keep up the momentum, \(userProfile.displayName)!"
        return AITextResponse(text: text, isFallback: true)
    }

    func generateWeeklyReport(
        workouts: [Workout],
        userProfile: UserProfile,
        stats: GamificationStats
    ) async throws -> String {
        let count = workouts.count
        let totalMinutes = workouts.reduce(0) { $0 + ($1.actualDurationMinutes ?? $1.requestedDurationMinutes) }
        let goalProgress = "\(stats.workoutsThisWeek)/\(stats.weeklyWorkoutGoal)"
        let streakText = stats.currentWeeklyStreak > 0
            ? "You're on a \(stats.currentWeeklyStreak)-week streak!"
            : "Start a new streak this week!"

        return "This week you completed \(count) workouts totaling \(totalMinutes) minutes. Goal progress: \(goalProgress). \(streakText)"
    }

    func generateNextWorkoutPreview(
        userProfile: UserProfile,
        recentHistory: [Workout],
        tomorrowsFocus: String
    ) async throws -> String {
        let workedMuscles = recentMuscleGroups(from: recentHistory)
        let allMajor: Set<String> = ["Chest", "Upper Back", "Shoulders", "Quads", "Glutes", "Core"]
        let missing = allMajor.subtracting(workedMuscles).sorted()
        let muscleText = missing.isEmpty ? "all major groups" : missing.joined(separator: ", ")

        let daysSinceLast = daysSinceLastWorkout(history: recentHistory)
        let daysText = daysSinceLast.map { "\($0) days" } ?? "a while"

        return "Tomorrow's focus: \(tomorrowsFocus) because you haven't worked \(muscleText) in \(daysText)."
    }

    // MARK: - Helpers

    private func recentMuscleGroups(from history: [Workout]) -> Set<String> {
        var muscles = Set<String>()
        for workout in history.prefix(3) {
            for (muscle, role) in workout.muscleGroupsWorked where role == "primary" {
                muscles.insert(muscle)
            }
        }
        return muscles
    }

    private func daysSinceLastWorkout(history: [Workout]) -> Int? {
        guard let last = history.first else { return nil }
        let date = last.completedAt ?? last.createdAt
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }
}
