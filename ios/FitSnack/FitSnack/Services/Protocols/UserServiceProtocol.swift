import Foundation

protocol UserServiceProtocol {
    func getProfile() async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) async throws
    func updateProfile(_ profile: UserProfile) async throws
    func deleteProfile() async throws
    func getGamificationStats() async throws -> GamificationStats
    func addXP(_ amount: Int) async throws
    func getBadges() async throws -> [Badge]
    func unlockBadge(_ badgeId: String) async throws
}

struct GamificationStats: Codable {
    var currentWeeklyStreak: Int
    var longestWeeklyStreak: Int
    var totalWorkoutsCompleted: Int
    var totalMinutesExercised: Int
    var xp: Int
    var level: Int
    var workoutsThisWeek: Int
    var weeklyWorkoutGoal: Int
}
