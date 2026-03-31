import Foundation

enum WorkoutStatus: String, Codable, CaseIterable, Identifiable {
    case generated
    case inProgress = "in_progress"
    case completed
    case cancelled
    case skipped
    case partial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .generated: "Ready"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        case .partial: "Partial"
        }
    }
}
