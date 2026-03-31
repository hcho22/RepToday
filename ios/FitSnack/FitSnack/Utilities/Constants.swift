import Foundation

enum Constants {
    enum XP {
        static let perMinute = 3
        static let ratingBonus = [1: 0, 2: 5, 3: 10, 4: 15, 5: 25]
        static let weeklyGoalBonus = 50
        static let streakMilestoneBonus = 100

        static func calculate(durationMinutes: Int, rating: Int) -> Int {
            let base = durationMinutes * perMinute
            let bonus = ratingBonus[rating] ?? 0
            return base + bonus
        }
    }

    enum Level {
        static let thresholds = [0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500]

        static func level(for xp: Int) -> Int {
            for (index, threshold) in thresholds.enumerated().reversed() {
                if xp >= threshold { return index + 1 }
            }
            return 1
        }

        static func xpForNextLevel(currentXP: Int) -> (current: Int, needed: Int) {
            let currentLevel = level(for: currentXP)
            guard currentLevel < thresholds.count else {
                return (currentXP, currentXP)
            }
            let currentThreshold = thresholds[currentLevel - 1]
            let nextThreshold = thresholds[min(currentLevel, thresholds.count - 1)]
            return (currentXP - currentThreshold, nextThreshold - currentThreshold)
        }
    }

    enum Badges {
        struct EvaluationContext {
            let totalWorkouts: Int
            let weeklyStreak: Int
            let completedWorkouts: [Workout]
            let equipmentUsed: Set<String>
            let muscleGroupsThisWeek: Set<String>
        }

        static func evaluateUnlocks(context: EvaluationContext) -> [String] {
            var unlocked: [String] = []

            // first_rep: Complete 1 workout
            if context.totalWorkouts >= 1 {
                unlocked.append("first_rep")
            }

            // week_one: Complete workouts on 7 consecutive days
            if hasSevenConsecutiveDays(context.completedWorkouts) {
                unlocked.append("week_one")
            }

            // early_bird: Complete a workout before 7 AM
            if context.completedWorkouts.contains(where: { workout in
                guard let completed = workout.completedAt else { return false }
                return Calendar.current.component(.hour, from: completed) < 7
            }) {
                unlocked.append("early_bird")
            }

            // speed_demon: Complete a 5-minute workout
            if context.completedWorkouts.contains(where: { $0.requestedDurationMinutes <= 5 }) {
                unlocked.append("speed_demon")
            }

            // endurance_king: Complete a 30-minute workout
            if context.completedWorkouts.contains(where: { $0.requestedDurationMinutes >= 30 }) {
                unlocked.append("endurance_king")
            }

            // streak_starter: 2-week streak
            if context.weeklyStreak >= 2 {
                unlocked.append("streak_starter")
            }

            // iron_will: 4-week streak
            if context.weeklyStreak >= 4 {
                unlocked.append("iron_will")
            }

            // centurion: 100 total workouts
            if context.totalWorkouts >= 100 {
                unlocked.append("centurion")
            }

            // variety_pack: 5 different equipment types
            if context.equipmentUsed.count >= 5 {
                unlocked.append("variety_pack")
            }

            // full_body: All major muscle groups in one week
            let majorGroups: Set<String> = ["Chest", "Back", "Shoulders", "Legs", "Core", "Arms"]
            if majorGroups.isSubset(of: context.muscleGroupsThisWeek) {
                unlocked.append("full_body")
            }

            return unlocked
        }

        private static func hasSevenConsecutiveDays(_ workouts: [Workout]) -> Bool {
            let calendar = Calendar.current
            let days = Set(workouts.compactMap { $0.completedAt }.map { calendar.startOfDay(for: $0) })
            let sorted = days.sorted()
            guard sorted.count >= 7 else { return false }

            var consecutive = 1
            for i in 1..<sorted.count {
                if calendar.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day == 1 {
                    consecutive += 1
                    if consecutive >= 7 { return true }
                } else {
                    consecutive = 1
                }
            }
            return false
        }
    }

    enum Streak {
        static func calculateWeeklyStreak(workoutDates: [Date], weeklyGoal: Int) -> Int {
            let calendar = Calendar.current
            var streak = 0
            var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!

            // Go backwards week by week
            while true {
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
                let workoutsInWeek = workoutDates.filter { $0 >= weekStart && $0 < weekEnd }.count

                if workoutsInWeek >= weeklyGoal {
                    streak += 1
                } else {
                    break
                }

                guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: weekStart) else { break }
                weekStart = previousWeek
            }

            return streak
        }
    }
}
