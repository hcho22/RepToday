import Foundation
import SwiftData

@Model
final class SDUserProfile {
    @Attribute(.unique) var profileId: String
    var displayName: String
    var age: Int
    var sex: String
    var heightCm: Double
    var weightKg: Double
    var fitnessLevel: String
    var primaryGoal: String
    var injuries: String
    var availableEquipmentRaw: String // JSON-encoded [Equipment]
    var weeklyWorkoutGoal: Int
    var typicalAvailableMinutes: Int
    var unitSystem: String
    var createdAt: Date
    var updatedAt: Date

    // Gamification
    var currentWeeklyStreak: Int
    var longestWeeklyStreak: Int
    var totalWorkoutsCompleted: Int
    var totalMinutesExercised: Int
    var xp: Int
    var level: Int
    var badgesRaw: String // JSON-encoded [Badge]

    init(from profile: UserProfile) {
        self.profileId = profile.id
        self.displayName = profile.displayName
        self.age = profile.age
        self.sex = profile.sex.rawValue
        self.heightCm = profile.heightCm
        self.weightKg = profile.weightKg
        self.fitnessLevel = profile.fitnessLevel.rawValue
        self.primaryGoal = profile.primaryGoal.rawValue
        self.injuries = profile.injuries
        self.availableEquipmentRaw = (try? JSONEncoder().encode(profile.availableEquipment).base64EncodedString()) ?? "[]"
        self.weeklyWorkoutGoal = profile.weeklyWorkoutGoal
        self.typicalAvailableMinutes = profile.typicalAvailableMinutes
        self.unitSystem = profile.unitSystem.rawValue
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
        self.currentWeeklyStreak = 0
        self.longestWeeklyStreak = 0
        self.totalWorkoutsCompleted = 0
        self.totalMinutesExercised = 0
        self.xp = 0
        self.level = 1
        self.badgesRaw = (try? JSONEncoder().encode(Badge.allBadges).base64EncodedString()) ?? "[]"
    }

    func toUserProfile() -> UserProfile {
        let equipment: [Equipment] = {
            guard let data = Data(base64Encoded: availableEquipmentRaw) else { return [.none] }
            return (try? JSONDecoder().decode([Equipment].self, from: data)) ?? [.none]
        }()

        return UserProfile(
            id: profileId,
            displayName: displayName,
            age: age,
            sex: UserProfile.Sex(rawValue: sex) ?? .other,
            heightCm: heightCm,
            weightKg: weightKg,
            fitnessLevel: FitnessLevel(rawValue: fitnessLevel) ?? .beginner,
            primaryGoal: PrimaryGoal(rawValue: primaryGoal) ?? .stayActive,
            injuries: injuries,
            availableEquipment: equipment,
            weeklyWorkoutGoal: weeklyWorkoutGoal,
            typicalAvailableMinutes: typicalAvailableMinutes,
            unitSystem: UserProfile.UnitSystem(rawValue: unitSystem) ?? .imperial,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from profile: UserProfile) {
        self.displayName = profile.displayName
        self.age = profile.age
        self.sex = profile.sex.rawValue
        self.heightCm = profile.heightCm
        self.weightKg = profile.weightKg
        self.fitnessLevel = profile.fitnessLevel.rawValue
        self.primaryGoal = profile.primaryGoal.rawValue
        self.injuries = profile.injuries
        self.availableEquipmentRaw = (try? JSONEncoder().encode(profile.availableEquipment).base64EncodedString()) ?? "[]"
        self.weeklyWorkoutGoal = profile.weeklyWorkoutGoal
        self.typicalAvailableMinutes = profile.typicalAvailableMinutes
        self.unitSystem = profile.unitSystem.rawValue
        self.updatedAt = Date()
    }

    func getBadges() -> [Badge] {
        guard let data = Data(base64Encoded: badgesRaw) else { return Badge.allBadges }
        return (try? JSONDecoder().decode([Badge].self, from: data)) ?? Badge.allBadges
    }

    func setBadges(_ badges: [Badge]) {
        self.badgesRaw = (try? JSONEncoder().encode(badges).base64EncodedString()) ?? "[]"
    }
}
