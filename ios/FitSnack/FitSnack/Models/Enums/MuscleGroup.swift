import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest
    case upperBack = "upper_back"
    case lowerBack = "lower_back"
    case shoulders
    case biceps
    case triceps
    case forearms
    case core
    case obliques
    case quads
    case hamstrings
    case glutes
    case calves
    case hipFlexors = "hip_flexors"
    case adductors
    case abductors
    case wrists
    case rotatorCuff = "rotator_cuff"
    case traps
    case erectors

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .upperBack: "Upper Back"
        case .lowerBack: "Lower Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .core: "Core"
        case .obliques: "Obliques"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .hipFlexors: "Hip Flexors"
        case .adductors: "Adductors"
        case .abductors: "Abductors"
        case .wrists: "Wrists"
        case .rotatorCuff: "Rotator Cuff"
        case .traps: "Traps"
        case .erectors: "Erectors"
        }
    }
}
