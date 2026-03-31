import Foundation

enum MovementPattern: String, Codable, CaseIterable, Identifiable {
    case push
    case pull
    case squat
    case hinge
    case lunge
    case carry
    case rotation
    case core
    case plank
    case cardio

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
