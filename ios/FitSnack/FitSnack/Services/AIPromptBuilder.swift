import Foundation

/// Constructs AI prompts from workout/profile data.
/// PII-sanitized: only sends age, sex, weight, fitness level — never name, email, or userId.
struct AIPromptBuilder {

    // MARK: - Post-Workout Summary Prompt

    /// Builds a prompt for generating a post-workout summary (max ~100 tokens).
    static func postWorkoutPrompt(
        workout: Workout,
        profile: UserProfile,
        recentHistory: [Workout]
    ) -> String {
        let sanitized = sanitizedProfile(profile)
        let exercises = exerciseSummary(workout)
        let muscles = muscleSummary(workout)
        let duration = workout.actualDurationMinutes ?? workout.requestedDurationMinutes
        let rating = workout.userRating.map { "\($0)/5" } ?? "none"
        let difficulty = workout.perceivedDifficulty?.displayName ?? "not rated"
        let last7Days = last7DaysSummary(recentHistory)

        return """
        Generate a brief, encouraging post-workout summary (2-3 sentences, max 100 tokens).

        Workout details:
        - Duration: \(duration) minutes
        - Exercises: \(exercises)
        - Muscle groups: \(muscles)
        - User rating: \(rating)
        - Perceived difficulty: \(difficulty)

        User context:
        \(sanitized)

        Recent activity (last 7 days):
        \(last7Days)

        Focus on what they accomplished and one specific thing to build on next session. Be conversational, not clinical.
        """
    }

    // MARK: - Weekly Report Prompt

    /// Builds a prompt for generating a weekly report (max ~300 tokens).
    static func weeklyReportPrompt(
        workouts: [Workout],
        profile: UserProfile,
        streak: Int,
        xp: Int,
        level: Int
    ) -> String {
        let sanitized = sanitizedProfile(profile)
        let weekSummary = weeklyWorkoutsSummary(workouts)
        let thirtyDayTrend = thirtyDayTrendSummary(workouts)

        return """
        Generate a weekly fitness report (4-6 sentences, max 300 tokens).

        This week's workouts:
        \(weekSummary)

        30-day trends:
        \(thirtyDayTrend)

        Progress:
        - Current streak: \(streak) weeks
        - XP: \(xp) (Level \(level))
        - Weekly goal: \(profile.weeklyWorkoutGoal) workouts

        User context:
        \(sanitized)

        Include: what went well, areas for improvement, and a motivating note about their consistency. Be specific about muscle groups and patterns.
        """
    }

    // MARK: - Next-Workout Preview Prompt

    /// Builds a prompt for generating a next-workout preview (max ~150 tokens).
    static func nextWorkoutPreviewPrompt(
        recentHistory: [Workout],
        profile: UserProfile
    ) -> String {
        let sanitized = sanitizedProfile(profile)
        let staleness = movementPatternStaleness(recentHistory)
        let recentMuscles = recentMuscleGroupSummary(recentHistory)

        return """
        Suggest what tomorrow's workout should focus on (2-3 sentences, max 150 tokens).

        Recent workout history:
        \(recentMuscles)

        Movement pattern staleness (days since last trained):
        \(staleness)

        User context:
        \(sanitized)
        - Primary goal: \(profile.primaryGoal.rawValue)
        - Typical duration: \(profile.typicalAvailableMinutes) minutes

        Explain why this focus makes sense based on recovery and balance. Be brief and actionable.
        """
    }

    // MARK: - PII Sanitization

    /// Returns only non-identifying profile data safe to send to AI.
    static func sanitizedProfile(_ profile: UserProfile) -> String {
        """
        - Age: \(profile.age)
        - Sex: \(profile.sex.rawValue)
        - Weight: \(Int(profile.weightKg)) kg
        - Fitness level: \(profile.fitnessLevel.rawValue)
        - Injuries/limitations: \(profile.injuries.isEmpty ? "none" : profile.injuries)
        """
    }

    // MARK: - Workout Data Helpers

    static func exerciseSummary(_ workout: Workout) -> String {
        let names = workout.allExercises.map { ex in
            let reps = ex.reps.map { "\($0) reps" } ?? "\(ex.durationSeconds ?? 0)s"
            return "\(ex.exercise.displayName) (\(ex.sets)x\(reps))"
        }
        return names.joined(separator: ", ")
    }

    static func muscleSummary(_ workout: Workout) -> String {
        let primary = workout.muscleGroupsWorked
            .filter { $0.value == "primary" }
            .keys.sorted()
        let secondary = workout.muscleGroupsWorked
            .filter { $0.value == "secondary" }
            .keys.sorted()

        var parts: [String] = []
        if !primary.isEmpty { parts.append("Primary: \(primary.joined(separator: ", "))") }
        if !secondary.isEmpty { parts.append("Secondary: \(secondary.joined(separator: ", "))") }
        return parts.isEmpty ? "full body" : parts.joined(separator: "; ")
    }

    static func last7DaysSummary(_ history: [Workout]) -> String {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = history.filter { ($0.completedAt ?? $0.createdAt) >= sevenDaysAgo }

        if recent.isEmpty { return "No workouts in the last 7 days." }

        let totalMinutes = recent.reduce(0) { $0 + ($1.actualDurationMinutes ?? $1.requestedDurationMinutes) }
        let musclesHit = Set(recent.flatMap { $0.muscleGroupsWorked.filter { $0.value == "primary" }.keys })

        return "\(recent.count) workouts, \(totalMinutes) total minutes, muscles trained: \(musclesHit.sorted().joined(separator: ", "))"
    }

    static func weeklyWorkoutsSummary(_ workouts: [Workout]) -> String {
        if workouts.isEmpty { return "No workouts this week." }

        return workouts.enumerated().map { index, w in
            let duration = w.actualDurationMinutes ?? w.requestedDurationMinutes
            let focus = w.focusAreas.first ?? "general"
            let rating = w.userRating.map { "\($0)/5" } ?? "unrated"
            return "\(index + 1). \(duration)min \(focus) — rating: \(rating)"
        }.joined(separator: "\n")
    }

    static func thirtyDayTrendSummary(_ workouts: [Workout]) -> String {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = workouts.filter { ($0.completedAt ?? $0.createdAt) >= thirtyDaysAgo }

        if recent.isEmpty { return "No workouts in the last 30 days." }

        let totalMinutes = recent.reduce(0) { $0 + ($1.actualDurationMinutes ?? $1.requestedDurationMinutes) }
        let avgRating: String = {
            let rated = recent.compactMap(\.userRating)
            guard !rated.isEmpty else { return "N/A" }
            let avg = Double(rated.reduce(0, +)) / Double(rated.count)
            return String(format: "%.1f/5", avg)
        }()

        return "\(recent.count) workouts over 30 days, \(totalMinutes) total minutes, avg rating: \(avgRating)"
    }

    static func movementPatternStaleness(_ history: [Workout]) -> String {
        var lastSeen: [String: Date] = [:]
        for workout in history {
            for exercise in workout.allExercises {
                let pattern = exercise.exercise.movementPattern.rawValue
                let date = workout.completedAt ?? workout.createdAt
                if lastSeen[pattern] == nil || date > lastSeen[pattern]! {
                    lastSeen[pattern] = date
                }
            }
        }

        if lastSeen.isEmpty { return "No prior workout data." }

        let now = Date()
        return lastSeen
            .sorted { $0.key < $1.key }
            .map { pattern, date in
                let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
                return "\(pattern): \(days) days ago"
            }
            .joined(separator: ", ")
    }

    static func recentMuscleGroupSummary(_ history: [Workout]) -> String {
        let recent = Array(history.prefix(5))
        if recent.isEmpty { return "No recent workouts." }

        return recent.enumerated().map { index, w in
            let focus = w.focusAreas.joined(separator: ", ")
            let duration = w.actualDurationMinutes ?? w.requestedDurationMinutes
            let daysAgo: String = {
                let date = w.completedAt ?? w.createdAt
                let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                return days == 0 ? "today" : "\(days)d ago"
            }()
            return "\(index + 1). \(focus) (\(duration)min, \(daysAgo))"
        }.joined(separator: "\n")
    }
}
