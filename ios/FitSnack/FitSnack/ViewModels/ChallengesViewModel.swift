import SwiftUI

@Observable
final class ChallengesViewModel {
    var badges: [Badge] = Badge.allBadges
    var currentXP: Int = 0
    var currentLevel: Int = 1
    var xpToNextLevel: Int = 100
    var xpProgress: Double = 0.0

    func loadData(services: ServiceContainer?) async {
        guard let services else { return }
        do {
            let stats = try await services.user.getGamificationStats()
            currentXP = stats.xp
            currentLevel = Constants.Level.level(for: stats.xp)
            let progress = Constants.Level.xpForNextLevel(currentXP: stats.xp)
            xpToNextLevel = progress.needed
            xpProgress = progress.needed > 0 ? Double(progress.current) / Double(progress.needed) : 1.0

            // Evaluate badge unlocks
            let workouts = try await services.workout.getHistory()
            let equipmentUsed = Set(workouts.flatMap { $0.allExercises.flatMap { $0.exercise.equipment.map(\.rawValue) } })
            let calendar = Calendar.current
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let muscleGroupsThisWeek = Set(
                workouts
                    .filter { ($0.completedAt ?? $0.createdAt) >= weekStart }
                    .flatMap { $0.allExercises.flatMap { $0.exercise.muscleGroups.primary.map(\.displayName) } }
            )

            let context = Constants.Badges.EvaluationContext(
                totalWorkouts: stats.totalWorkoutsCompleted,
                weeklyStreak: stats.currentWeeklyStreak,
                completedWorkouts: workouts,
                equipmentUsed: equipmentUsed,
                muscleGroupsThisWeek: muscleGroupsThisWeek
            )
            let unlockedIds = Constants.Badges.evaluateUnlocks(context: context)

            // Merge with stored badges
            var storedBadges = try await services.user.getBadges()
            for id in unlockedIds {
                if let index = storedBadges.firstIndex(where: { $0.id == id && !$0.isUnlocked }) {
                    storedBadges[index].isUnlocked = true
                    storedBadges[index].unlockedAt = Date()
                    try await services.user.unlockBadge(id)
                }
            }
            badges = storedBadges
        } catch {}
    }
}
