import Foundation

struct Badge: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    var isUnlocked: Bool
    var unlockedAt: Date?
    let criteria: String

    static let allBadges: [Badge] = [
        Badge(id: "first_rep", name: "First Rep", description: "Complete your first workout", iconName: "star.fill", isUnlocked: false, criteria: "Complete 1 workout"),
        Badge(id: "week_one", name: "Week One", description: "Complete workouts for a full week", iconName: "calendar", isUnlocked: false, criteria: "Complete workouts on 7 consecutive days"),
        Badge(id: "early_bird", name: "Early Bird", description: "Complete a workout before 7 AM", iconName: "sunrise.fill", isUnlocked: false, criteria: "Finish a workout before 7:00 AM"),
        Badge(id: "speed_demon", name: "Speed Demon", description: "Complete a 5-minute workout", iconName: "bolt.fill", isUnlocked: false, criteria: "Complete a workout with 5-minute duration"),
        Badge(id: "endurance_king", name: "Endurance King", description: "Complete a 30-minute workout", iconName: "crown.fill", isUnlocked: false, criteria: "Complete a workout with 30-minute duration"),
        Badge(id: "streak_starter", name: "Streak Starter", description: "Achieve a 2-week streak", iconName: "flame.fill", isUnlocked: false, criteria: "Maintain a 2-week workout streak"),
        Badge(id: "iron_will", name: "Iron Will", description: "Achieve a 4-week streak", iconName: "shield.fill", isUnlocked: false, criteria: "Maintain a 4-week workout streak"),
        Badge(id: "centurion", name: "Centurion", description: "Complete 100 total workouts", iconName: "100.circle.fill", isUnlocked: false, criteria: "Accumulate 100 completed workouts"),
        Badge(id: "variety_pack", name: "Variety Pack", description: "Use 5 different equipment types", iconName: "tray.full.fill", isUnlocked: false, criteria: "Use at least 5 different equipment types across workouts"),
        Badge(id: "full_body", name: "Full Body", description: "Hit all major muscle groups in one week", iconName: "figure.strengthtraining.traditional", isUnlocked: false, criteria: "Target all major muscle groups within a single week"),
    ]
}
