import SwiftUI

@Observable
final class HomeViewModel {
    var todaysWorkout: Workout?
    var selectedDuration: Int = 15
    var isGenerating = false
    var weeklyStats = WeeklyStats()
    var streakCount = 0
    var availableFreezes = 0
    var isPremium = false
    var showingWorkout = false
    var userName = ""
    var hasWorkoutHistory = false
    var insightText = ""
    var isInsightLoading = false
    var isAIInsight = false
    var showStreakSaver = false

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

    private static let staticTips = [
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

    private static var staticTip: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return staticTips[dayOfYear % staticTips.count]
    }

    private static func currentISOWeek() -> String {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(comps.yearForWeekOfYear ?? 0)-W\(String(format: "%02d", comps.weekOfYear ?? 0))"
    }

    private static var isMondayMorning: Bool {
        let cal = Calendar.current
        let now = Date()
        return cal.component(.weekday, from: now) == 2 && cal.component(.hour, from: now) < 12
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
            availableFreezes = stats.availableFreezes
            isPremium = stats.isPremium
            hasWorkoutHistory = stats.totalWorkoutsCompleted > 0

            // Streak saver: show when it's Sunday and user is 1 workout short of weekly goal
            let isSunday = Calendar.current.component(.weekday, from: Date()) == 1
            showStreakSaver = isSunday && stats.workoutsThisWeek == stats.weeklyWorkoutGoal - 1
        } catch {}

        // Personalized notification timing — recalculate weekly
        await schedulePersonalizedReminder(services: services)

        await loadInsight(services: services)
    }

    func loadInsight(services: ServiceContainer?) async {
        guard let services else {
            insightText = Self.staticTip
            return
        }

        // Premium gating: free users see static tips
        guard services.subscription.isPremium else {
            insightText = Self.staticTip
            isAIInsight = false
            return
        }

        isInsightLoading = true

        do {
            let profile = try await services.user.getProfile() ?? .empty
            let stats = try await services.user.getGamificationStats()
            let history = try await services.workout.getHistory()

            // Priority 1: Monday morning — show weekly report (cached)
            if Self.isMondayMorning {
                let isoWeek = Self.currentISOWeek()
                if let cached = try await services.user.getCachedWeeklyReport(for: isoWeek) {
                    insightText = cached
                    isAIInsight = true
                    isInsightLoading = false
                    return
                }

                let report = try await services.ai.generateWeeklyReport(
                    workouts: history,
                    userProfile: profile,
                    stats: stats
                )
                try await services.user.cacheWeeklyReport(report, for: isoWeek)
                insightText = report
                isAIInsight = true
                isInsightLoading = false
                return
            }

            // Priority 2: Last workout AI summary
            if let lastWorkout = history.first {
                let summary = try await services.ai.generatePostWorkoutSummary(
                    workout: lastWorkout,
                    userProfile: profile,
                    recentHistory: Array(history.prefix(5))
                )
                insightText = summary.text
                isAIInsight = true
                isInsightLoading = false
                return
            }

            // Priority 3: Next workout preview
            let focusAreas = determineTomorrowsFocus(history: history)
            let preview = try await services.ai.generateNextWorkoutPreview(
                userProfile: profile,
                recentHistory: Array(history.prefix(5)),
                tomorrowsFocus: focusAreas
            )
            insightText = preview
            isAIInsight = true
            isInsightLoading = false
            return
        } catch {
            // Fallback: static tips
            insightText = Self.staticTip
            isAIInsight = false
            isInsightLoading = false
        }
    }

    private func determineTomorrowsFocus(history: [Workout]) -> String {
        let recentMuscles = Set(history.prefix(3).flatMap { $0.muscleGroupsWorked.filter { $0.value == "primary" }.keys })
        let allMajor: Set<String> = ["Chest", "Upper Back", "Shoulders", "Quads", "Glutes", "Core"]
        let missing = allMajor.subtracting(recentMuscles)
        return missing.isEmpty ? "full body" : missing.sorted().joined(separator: ", ")
    }

    private func schedulePersonalizedReminder(services: ServiceContainer?) async {
        guard let services else { return }

        // Only recalculate once per ISO week
        let currentWeek = Self.currentISOWeek()
        let lastRecalcWeek = UserDefaults.standard.string(forKey: "lastReminderRecalcWeek") ?? ""
        guard currentWeek != lastRecalcWeek else { return }

        do {
            let history = try await services.workout.getHistory()
            let workoutStartTimes = history.compactMap(\.startedAt)
            try await services.notification.schedulePersonalizedReminder(basedOnHistory: workoutStartTimes)

            // Persist the computed preferred hour on the user profile
            if workoutStartTimes.count >= 5, var profile = try await services.user.getProfile() {
                let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                let recentHours = workoutStartTimes
                    .filter { $0 >= fourteenDaysAgo }
                    .map { Calendar.current.component(.hour, from: $0) }
                if recentHours.count >= 5 {
                    let modeHour = NotificationService.mode(of: recentHours)
                    profile.preferredWorkoutTimeHour = modeHour
                    try await services.user.updateProfile(profile)
                }
            }

            UserDefaults.standard.set(currentWeek, forKey: "lastReminderRecalcWeek")
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

    func startStreakSaver(services: ServiceContainer?) async {
        guard let services else { return }
        isGenerating = true
        do {
            let profile = try await services.user.getProfile() ?? .empty
            let workout = try await services.workout.generateWorkout(duration: 5, profile: profile)
            todaysWorkout = workout
            showStreakSaver = false
            showingWorkout = true
        } catch {}
        isGenerating = false
    }
}
