import Foundation

enum BlockType: String, Codable, CaseIterable, Identifiable {
    case warmup
    case strength
    case circuit
    case hiit
    case emom
    case amrap
    case cooldown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warmup: "Warm Up"
        case .strength: "Strength"
        case .circuit: "Circuit"
        case .hiit: "HIIT"
        case .emom: "EMOM"
        case .amrap: "AMRAP"
        case .cooldown: "Cool Down"
        }
    }
}
