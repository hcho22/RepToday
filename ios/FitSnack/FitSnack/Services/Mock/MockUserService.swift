import Foundation
import SwiftData

final class MockUserService: UserServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func getProfile() async throws -> UserProfile? {
        let descriptor = FetchDescriptor<SDUserProfile>()
        return try modelContext.fetch(descriptor).first?.toUserProfile()
    }

    func saveProfile(_ profile: UserProfile) async throws {
        let sdProfile = SDUserProfile(from: profile)
        modelContext.insert(sdProfile)
        try modelContext.save()
    }

    func updateProfile(_ profile: UserProfile) async throws {
        let descriptor = FetchDescriptor<SDUserProfile>(
            predicate: #Predicate { $0.profileId == profile.id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: profile)
            try modelContext.save()
        } else {
            try await saveProfile(profile)
        }
    }

    func deleteProfile() async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        let profiles = try modelContext.fetch(descriptor)
        for profile in profiles {
            modelContext.delete(profile)
        }
        try modelContext.save()
    }

    func getGamificationStats() async throws -> GamificationStats {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else {
            return GamificationStats(
                currentWeeklyStreak: 0, longestWeeklyStreak: 0,
                totalWorkoutsCompleted: 0, totalMinutesExercised: 0,
                xp: 0, level: 1, workoutsThisWeek: 0, weeklyWorkoutGoal: 3
            )
        }

        // Replenish freezes if a new month has started (premium only)
        let isPremium = true // TODO: wire to real subscription state
        if isPremium && Constants.StreakFreeze.shouldReplenish(lastReplenishDate: profile.lastFreezeReplenishDate) {
            profile.streakFreezes = Constants.StreakFreeze.premiumUserFreezes
            profile.lastFreezeReplenishDate = Date()
            try modelContext.save()
        }

        let workoutsThisWeek = try countWorkoutsThisWeek()

        return GamificationStats(
            currentWeeklyStreak: profile.currentWeeklyStreak,
            longestWeeklyStreak: profile.longestWeeklyStreak,
            totalWorkoutsCompleted: profile.totalWorkoutsCompleted,
            totalMinutesExercised: profile.totalMinutesExercised,
            xp: profile.xp,
            level: profile.level,
            workoutsThisWeek: workoutsThisWeek,
            weeklyWorkoutGoal: profile.weeklyWorkoutGoal,
            availableFreezes: profile.streakFreezes,
            isPremium: isPremium
        )
    }

    func addXP(_ amount: Int) async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        profile.xp += amount
        profile.level = Self.levelForXP(profile.xp)
        try modelContext.save()
    }

    func getBadges() async throws -> [Badge] {
        let descriptor = FetchDescriptor<SDUserProfile>()
        return try modelContext.fetch(descriptor).first?.getBadges() ?? Badge.allBadges
    }

    func unlockBadge(_ badgeId: String) async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        var badges = profile.getBadges()
        if let index = badges.firstIndex(where: { $0.id == badgeId && !$0.isUnlocked }) {
            badges[index].isUnlocked = true
            badges[index].unlockedAt = Date()
            profile.setBadges(badges)
            try modelContext.save()
        }
    }

    private func countWorkoutsThisWeek() throws -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }

        let completedStatus = WorkoutStatus.completed.rawValue
        let partialStatus = WorkoutStatus.partial.rawValue
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { ($0.status == completedStatus || $0.status == partialStatus) && $0.completedAt != nil && $0.completedAt! >= weekStart }
        )
        return try modelContext.fetchCount(descriptor)
    }

    func getCachedWeeklyReport(for isoWeek: String) async throws -> String? {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return nil }
        guard profile.cachedWeeklyReportWeek == isoWeek, !profile.cachedWeeklyReport.isEmpty else { return nil }
        return profile.cachedWeeklyReport
    }

    func cacheWeeklyReport(_ report: String, for isoWeek: String) async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        profile.cachedWeeklyReport = report
        profile.cachedWeeklyReportWeek = isoWeek
        try modelContext.save()
    }

    func useStreakFreeze() async throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        guard profile.streakFreezes > 0 else { return }
        profile.streakFreezes -= 1
        try modelContext.save()
    }

    func getAvailableFreezes() async throws -> Int {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return 0 }
        return profile.streakFreezes
    }

    static func levelForXP(_ xp: Int) -> Int {
        let thresholds = [0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500]
        for (index, threshold) in thresholds.enumerated().reversed() {
            if xp >= threshold { return index + 1 }
        }
        return 1
    }
}
