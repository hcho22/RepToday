import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case flexibility
    case warmup
    case cooldown

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
