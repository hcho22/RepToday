import Foundation

struct UserProfile: Codable, Identifiable {
    var id: String
    var displayName: String
    var age: Int
    var sex: Sex
    var heightCm: Double
    var weightKg: Double
    var fitnessLevel: FitnessLevel
    var primaryGoal: PrimaryGoal
    var injuries: String
    var availableEquipment: [Equipment]
    var weeklyWorkoutGoal: Int
    var typicalAvailableMinutes: Int
    var unitSystem: UnitSystem
    var createdAt: Date
    var updatedAt: Date

    enum Sex: String, Codable, CaseIterable, Identifiable {
        case male, female, other, preferNotToSay
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .preferNotToSay: return "Prefer not to say"
            default: return rawValue.capitalized
            }
        }
    }

    enum UnitSystem: String, Codable, CaseIterable, Identifiable {
        case metric, imperial
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    static var empty: UserProfile {
        UserProfile(
            id: UUID().uuidString,
            displayName: "",
            age: 30,
            sex: .male,
            heightCm: 170,
            weightKg: 70,
            fitnessLevel: .beginner,
            primaryGoal: .stayActive,
            injuries: "",
            availableEquipment: [.none],
            weeklyWorkoutGoal: 3,
            typicalAvailableMinutes: 15,
            unitSystem: .imperial,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
