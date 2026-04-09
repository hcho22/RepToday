import Foundation

enum SwapReason: String, Codable, CaseIterable, Identifiable {
    case tooHard = "too_hard"
    case tooEasy = "too_easy"
    case noEquipment = "no_equipment"
    case itHurts = "it_hurts"
    case dontLikeIt = "dont_like_it"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tooHard: "Too Hard"
        case .tooEasy: "Too Easy"
        case .noEquipment: "No Equipment"
        case .itHurts: "It Hurts"
        case .dontLikeIt: "Don't Like It"
        }
    }

    var icon: String {
        switch self {
        case .tooHard: "arrow.down.circle"
        case .tooEasy: "arrow.up.circle"
        case .noEquipment: "wrench.and.screwdriver"
        case .itHurts: "bandage"
        case .dontLikeIt: "hand.thumbsdown"
        }
    }
}
