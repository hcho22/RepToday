import Foundation

// MARK: - FocusArea

/// A body part the user wants to improve (`CONTEXT.md` "Focus Area", PRD decision 20). Multi-select and
/// optional, asked in onboarding and editable in Settings. It replaces the old, never-read goal list.
///
/// A Focus Area changes emphasis *within* a Training Day and never the Rotation: on its day a focused
/// movement is ordered first among its kind of station, is padded first when the fit has reps to add,
/// and is given the Practice slot first; Abs adds one more Core Sprinkle (`SessionAssembly`). The raw
/// value is the stored form.
enum FocusArea: String, Codable, CaseIterable, Identifiable, Hashable {
    case chest
    case shoulders
    case arms
    case back
    case abs
    case legs
    case glutes

    var id: String { rawValue }

    /// The name onboarding and Settings show.
    var label: String {
        switch self {
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .back: return "Back"
        case .abs: return "Abs"
        case .legs: return "Legs"
        case .glutes: return "Glutes"
        }
    }

    /// One line on what the choice changes, in the user's words.
    var detail: String {
        switch self {
        case .chest: return "Push-ups come first on Push Days."
        case .shoulders: return "Pike push-ups and dips come first on Push Days."
        case .arms: return "Diamond push-ups, dips and rows come first."
        case .back: return "Rows and posture work come first on Pull Days."
        case .abs: return "A second core move on every Training Day."
        case .legs: return "Squats and lunges come first on Legs Days."
        case .glutes: return "Bridges and hinges come first on Legs Days."
        }
    }

    /// The movements behind Arms (decision 20: diamond push-ups, dips and rows). Named one by one
    /// because they sit on ladders other areas own; `FocusAreaTests` pins that each is in the catalog.
    static let armsMovementIds: Set<String> = [
        "push_diamond",
        "push_floor_dips",
        "pull_floor_row",
        "pull_floor_row_single_arm",
    ]

    /// Whether this area covers `exercise` (decision 20): Chest the horizontal push ladder, Shoulders the
    /// vertical push ladder, Arms the diamond push-up, dips and rows, Back both pull ladders, Abs every core
    /// movement, Legs the squat and lunge ladders, Glutes the bridge and hip-hinge ladders.
    func covers(_ exercise: Exercise) -> Bool {
        switch self {
        case .chest: return exercise.progressionChainId == "push_horizontal"
        case .shoulders: return exercise.progressionChainId == "push_vertical"
        case .arms: return Self.armsMovementIds.contains(exercise.id)
        case .back: return ["pull_horizontal", "pull_postural"].contains(exercise.progressionChainId)
        case .abs: return exercise.movementPattern == .core
        case .legs: return ["squat", "lunge"].contains(exercise.progressionChainId)
        case .glutes: return ["hinge_bridge", "hinge_hip"].contains(exercise.progressionChainId)
        }
    }
}

extension Collection where Element == FocusArea {
    /// Whether any of these areas covers `exercise`.
    func covers(_ exercise: Exercise) -> Bool {
        contains { $0.covers(exercise) }
    }

    /// The areas in their canonical order, so a stored or displayed list never depends on tap order.
    var canonicallyOrdered: [FocusArea] {
        FocusArea.allCases.filter { contains($0) }
    }
}
