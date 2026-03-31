import Foundation

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case none
    case dumbbells
    case resistanceBands = "resistance_bands"
    case pullUpBar = "pull_up_bar"
    case kettlebell
    case yogaMat = "yoga_mat"
    case jumpRope = "jump_rope"
    case foamRoller = "foam_roller"
    case bench
    case stabilityBall = "stability_ball"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Equipment"
        case .dumbbells: "Dumbbells"
        case .resistanceBands: "Resistance Bands"
        case .pullUpBar: "Pull-Up Bar"
        case .kettlebell: "Kettlebell"
        case .yogaMat: "Yoga Mat"
        case .jumpRope: "Jump Rope"
        case .foamRoller: "Foam Roller"
        case .bench: "Bench"
        case .stabilityBall: "Stability Ball"
        }
    }

    var icon: String {
        switch self {
        case .none: "figure.stand"
        case .dumbbells: "dumbbell.fill"
        case .resistanceBands: "circle.and.line.horizontal"
        case .pullUpBar: "rectangle.and.arrow.up.right.and.arrow.down.left"
        case .kettlebell: "scalemass.fill"
        case .yogaMat: "rectangle.fill"
        case .jumpRope: "arrow.turn.right.up"
        case .foamRoller: "cylinder.fill"
        case .bench: "rectangle.split.3x1.fill"
        case .stabilityBall: "circle.fill"
        }
    }
}
