import Foundation

enum FitnessLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    var description: String {
        switch self {
        case .beginner: "New to exercise or returning after a long break"
        case .intermediate: "Exercise regularly, comfortable with most movements"
        case .advanced: "Experienced athlete, looking for challenging workouts"
        }
    }

    var icon: String {
        switch self {
        case .beginner: "figure.walk"
        case .intermediate: "figure.run"
        case .advanced: "figure.highintensity.intervaltraining"
        }
    }
}
