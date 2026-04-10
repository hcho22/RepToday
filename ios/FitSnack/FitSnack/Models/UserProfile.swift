import Foundation

struct UserProfile: Identifiable, Encodable {
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

    // Phase 2 fields
    var streakFreezes: Int = 0
    var lastFreezeReplenishDate: Date? = nil
    var progressionLevels: [String: Int] = [:]
    var exerciseSkipCounts: [String: Int] = [:]
    var exerciseRatings: [String: Int] = [:]
    var preferredWorkoutTimeHour: Int? = nil
    var healthKitWeightSync: Bool = false

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

extension UserProfile: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        age = try container.decode(Int.self, forKey: .age)
        sex = try container.decode(Sex.self, forKey: .sex)
        heightCm = try container.decode(Double.self, forKey: .heightCm)
        weightKg = try container.decode(Double.self, forKey: .weightKg)
        fitnessLevel = try container.decode(FitnessLevel.self, forKey: .fitnessLevel)
        primaryGoal = try container.decode(PrimaryGoal.self, forKey: .primaryGoal)
        injuries = try container.decode(String.self, forKey: .injuries)
        availableEquipment = try container.decode([Equipment].self, forKey: .availableEquipment)
        weeklyWorkoutGoal = try container.decode(Int.self, forKey: .weeklyWorkoutGoal)
        typicalAvailableMinutes = try container.decode(Int.self, forKey: .typicalAvailableMinutes)
        unitSystem = try container.decode(UnitSystem.self, forKey: .unitSystem)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Phase 2 fields — default when absent for backward compatibility
        streakFreezes = try container.decodeIfPresent(Int.self, forKey: .streakFreezes) ?? 0
        lastFreezeReplenishDate = try container.decodeIfPresent(Date.self, forKey: .lastFreezeReplenishDate)
        progressionLevels = try container.decodeIfPresent([String: Int].self, forKey: .progressionLevels) ?? [:]
        exerciseSkipCounts = try container.decodeIfPresent([String: Int].self, forKey: .exerciseSkipCounts) ?? [:]
        exerciseRatings = try container.decodeIfPresent([String: Int].self, forKey: .exerciseRatings) ?? [:]
        preferredWorkoutTimeHour = try container.decodeIfPresent(Int.self, forKey: .preferredWorkoutTimeHour)
        healthKitWeightSync = try container.decodeIfPresent(Bool.self, forKey: .healthKitWeightSync) ?? false
    }
}
