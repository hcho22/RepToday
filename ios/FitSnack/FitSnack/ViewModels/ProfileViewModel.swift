import SwiftUI

@Observable
final class ProfileViewModel {
    var profile: UserProfile?
    var stats = GamificationStats(
        currentWeeklyStreak: 0, longestWeeklyStreak: 0,
        totalWorkoutsCompleted: 0, totalMinutesExercised: 0,
        xp: 0, level: 1, workoutsThisWeek: 0, weeklyWorkoutGoal: 3
    )

    func loadData(services: ServiceContainer?) async {
        guard let services else { return }
        do {
            profile = try await services.user.getProfile()
            stats = try await services.user.getGamificationStats()
            await syncHealthKitWeight(services: services)
        } catch {}
    }

    func syncHealthKitWeight(services: ServiceContainer?) async {
        guard let services, var currentProfile = profile, currentProfile.healthKitWeightSync else { return }
        do {
            if let hkWeight = try await services.healthKit.readLatestWeight(), hkWeight > 0 {
                let roundedWeight = (hkWeight * 10).rounded() / 10
                if abs(roundedWeight - currentProfile.weightKg) > 0.1 {
                    currentProfile.weightKg = roundedWeight
                    currentProfile.updatedAt = Date()
                    try await services.user.updateProfile(currentProfile)
                    profile = currentProfile
                }
            }
        } catch {}
    }

    func updateProfile(_ profile: UserProfile, services: ServiceContainer?) async {
        guard let services else { return }
        do {
            try await services.user.updateProfile(profile)
            self.profile = profile
        } catch {}
    }

    func signOut(services: ServiceContainer?, appState: AppState) {
        services?.auth.signOut()
        appState.isOnboarded = false
    }
}
