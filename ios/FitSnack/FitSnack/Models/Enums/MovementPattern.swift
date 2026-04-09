import Foundation

/// High-level movement focus groups used for day-rotation logic.
enum FocusGroup: String, Codable, CaseIterable, Identifiable {
    case push
    case pull
    case squat
    case hinge
    case core
    case cardio
    case mobility

    var id: String { rawValue }
}

enum MovementPattern: String, Codable, CaseIterable, Identifiable {
    case pushHorizontal = "push_horizontal"
    case pushVertical = "push_vertical"
    case pullVertical = "pull_vertical"
    case pullHorizontal = "pull_horizontal"
    case squat
    case hinge
    case lunge
    case carry
    case coreAntiExtension = "core_anti_extension"
    case coreFlexion = "core_flexion"
    case coreRotation = "core_rotation"
    case coreCompression = "core_compression"
    case cardio
    case mobility
    case primal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushHorizontal: "Push (Horizontal)"
        case .pushVertical: "Push (Vertical)"
        case .pullVertical: "Pull (Vertical)"
        case .pullHorizontal: "Pull (Horizontal)"
        case .squat: "Squat"
        case .hinge: "Hinge"
        case .lunge: "Lunge"
        case .carry: "Carry"
        case .coreAntiExtension: "Core (Anti-Extension)"
        case .coreFlexion: "Core (Flexion)"
        case .coreRotation: "Core (Rotation)"
        case .coreCompression: "Core (Compression)"
        case .cardio: "Cardio"
        case .mobility: "Mobility"
        case .primal: "Primal"
        }
    }

    var focusGroup: FocusGroup {
        switch self {
        case .pushHorizontal, .pushVertical: .push
        case .pullVertical, .pullHorizontal: .pull
        case .squat: .squat
        case .hinge: .hinge
        case .lunge: .hinge
        case .carry: .core
        case .coreAntiExtension, .coreFlexion, .coreRotation, .coreCompression: .core
        case .cardio: .cardio
        case .mobility, .primal: .mobility
        }
    }

    // MARK: - Backward-compatible decoding

    /// Maps old Phase 1 raw values to new granular cases so saved workouts decode correctly.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Try direct match first (new raw values)
        if let pattern = MovementPattern(rawValue: rawValue) {
            self = pattern
            return
        }

        // Map old Phase 1 values to new cases
        switch rawValue {
        case "push": self = .pushHorizontal
        case "pull": self = .pullHorizontal
        case "core": self = .coreFlexion
        case "plank": self = .coreAntiExtension
        case "rotation": self = .coreRotation
        case "carry": self = .carry
        case "lunge": self = .lunge
        case "cardio": self = .cardio
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown MovementPattern raw value: \(rawValue)"
            )
        }
    }
}
