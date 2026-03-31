import Foundation

enum PrimaryGoal: String, Codable, CaseIterable, Identifiable {
    case loseWeight = "lose_weight"
    case buildMuscle = "build_muscle"
    case stayActive = "stay_active"
    case increaseEnergy = "increase_energy"
    case reduceStress = "reduce_stress"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loseWeight: "Lose Weight"
        case .buildMuscle: "Build Muscle"
        case .stayActive: "Stay Active"
        case .increaseEnergy: "Increase Energy"
        case .reduceStress: "Reduce Stress"
        }
    }

    var icon: String {
        switch self {
        case .loseWeight: "flame.fill"
        case .buildMuscle: "dumbbell.fill"
        case .stayActive: "figure.walk"
        case .increaseEnergy: "bolt.fill"
        case .reduceStress: "leaf.fill"
        }
    }

    var tagline: String {
        switch self {
        case .loseWeight: "Burn calories with high-intensity circuits"
        case .buildMuscle: "Strength-focused exercises to build lean muscle"
        case .stayActive: "Balanced workouts to keep you moving daily"
        case .increaseEnergy: "Energizing routines to power your day"
        case .reduceStress: "Mindful movement to calm body and mind"
        }
    }
}
