import SwiftUI

@Observable
final class HomeViewModel {
    var todaysWorkout: Workout?
    var selectedDuration: Int = 15
    var isGenerating = false
    var weeklyStats = WeeklyStats()
    var streakCount = 0
    var showingWorkout = false
    var userName = ""
    var hasWorkoutHistory = false

    struct WeeklyStats {
        var completed = 0
        var goal = 3
        var completedDays: [Bool] = Array(repeating: false, count: 7)
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning"
        case 12..<17: timeGreeting = "Good afternoon"
        case 17..<21: timeGreeting = "Good evening"
        default: timeGreeting = "Hey there"
        }
        return userName.isEmpty ? timeGreeting : "\(timeGreeting), \(userName)"
    }

    var insightText: String {
        let insights = [
            "Consistency is more important than intensity. Even 5 minutes counts!",
            "Your muscles need 48 hours to recover. We balance your workout focus automatically.",
            "Short workouts add up: 15 min/day = 7.5 hours/month of exercise!",
            "Studies show micro-workouts improve energy levels throughout the day.",
            "Your brain releases endorphins within just 5 minutes of exercise.",
            "Bodyweight exercises can be just as effective as weighted ones for building strength.",
            "Taking the stairs instead of the elevator burns about 0.17 calories per step.",
            "Stretching after a workout reduces muscle soreness by up to 25%.",
            "Morning workouts can boost your metabolism for the rest of the day.",
            "Even a 10-minute walk after meals helps regulate blood sugar levels.",
            "Compound exercises like squats work multiple muscle groups, saving you time.",
            "Staying hydrated improves exercise performance by up to 20%.",
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return insights[dayOfYear % insights.count]
    }

    func loadData(services: ServiceContainer?) async {
        guard let services else { return }
        do {
            // Load profile to set default duration
            if let profile = try await services.user.getProfile() {
                selectedDuration = profile.typicalAvailableMinutes
                userName = profile.displayName
            }

            todaysWorkout = try await services.workout.getTodaysWorkout()
            let stats = try await services.user.getGamificationStats()
            weeklyStats.completed = stats.workoutsThisWeek
            weeklyStats.goal = stats.weeklyWorkoutGoal
            streakCount = stats.currentWeeklyStreak
            hasWorkoutHistory = stats.totalWorkoutsCompleted > 0
        } catch {}
    }

    func generateWorkout(services: ServiceContainer?) async {
        guard let services else { return }
        isGenerating = true
        do {
            let profile = try await services.user.getProfile() ?? .empty
            let workout = try await services.workout.generateWorkout(duration: selectedDuration, profile: profile)
            todaysWorkout = workout
        } catch {}
        isGenerating = false
    }

    func regenerateWorkout(services: ServiceContainer?) async {
        todaysWorkout = nil
        await generateWorkout(services: services)
    }
}
