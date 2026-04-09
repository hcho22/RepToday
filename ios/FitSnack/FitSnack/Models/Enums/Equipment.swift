import Foundation

enum Equipment: String, Codable, CaseIterable, Identifiable {
    // Active cases
    case none
    case resistanceBands = "resistance_bands"
    case pullUpBar = "pull_up_bar"
    case bench
    case parallettes
    case rings
    case dipBars = "dip_bars"
    case elevatedSurface = "elevated_surface"
    case wall
    case slidersOrTowel = "sliders_or_towel"
    case anchorPoint = "anchor_point"
    case bandOrStick = "band_or_stick"
    case stepOrStairs = "step_or_stairs"
    case boxOrPlatform = "box_or_platform"

    // Deprecated — kept for backward compatibility with saved profiles
    case dumbbells
    case kettlebell
    case yogaMat = "yoga_mat"
    case jumpRope = "jump_rope"
    case foamRoller = "foam_roller"
    case stabilityBall = "stability_ball"

    var id: String { rawValue }

    /// Whether this case is deprecated and should be hidden from selection UI.
    var isDeprecated: Bool {
        switch self {
        case .dumbbells, .kettlebell, .yogaMat, .jumpRope, .foamRoller, .stabilityBall:
            return true
        default:
            return false
        }
    }

    /// Cases shown in equipment selection UI (excludes deprecated).
    static var selectableCases: [Equipment] {
        allCases.filter { !$0.isDeprecated }
    }

    var displayName: String {
        switch self {
        case .none: "No Equipment"
        case .resistanceBands: "Resistance Bands"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .parallettes: "Parallettes"
        case .rings: "Rings"
        case .dipBars: "Dip Bars"
        case .elevatedSurface: "Elevated Surface"
        case .wall: "Wall"
        case .slidersOrTowel: "Sliders / Towel"
        case .anchorPoint: "Anchor Point"
        case .bandOrStick: "Band / Stick"
        case .stepOrStairs: "Step / Stairs"
        case .boxOrPlatform: "Box / Platform"
        case .dumbbells: "Dumbbells"
        case .kettlebell: "Kettlebell"
        case .yogaMat: "Yoga Mat"
        case .jumpRope: "Jump Rope"
        case .foamRoller: "Foam Roller"
        case .stabilityBall: "Stability Ball"
        }
    }

    var icon: String {
        switch self {
        case .none: "figure.stand"
        case .resistanceBands: "circle.and.line.horizontal"
        case .pullUpBar: "rectangle.and.arrow.up.right.and.arrow.down.left"
        case .bench: "rectangle.split.3x1.fill"
        case .parallettes: "equal"
        case .rings: "circle.circle"
        case .dipBars: "line.3.horizontal"
        case .elevatedSurface: "square.stack"
        case .wall: "rectangle.portrait.fill"
        case .slidersOrTowel: "arrow.left.and.right"
        case .anchorPoint: "paperclip"
        case .bandOrStick: "line.diagonal"
        case .stepOrStairs: "stairs"
        case .boxOrPlatform: "cube.fill"
        case .dumbbells: "dumbbell.fill"
        case .kettlebell: "scalemass.fill"
        case .yogaMat: "rectangle.fill"
        case .jumpRope: "arrow.turn.right.up"
        case .foamRoller: "cylinder.fill"
        case .stabilityBall: "circle.fill"
        }
    }
}
