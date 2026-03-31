import Foundation

struct Workout: Codable, Identifiable {
    let id: String
    var userId: String
    var createdAt: Date
    var requestedDurationMinutes: Int

    var warmup: WorkoutBlock?
    var mainBlocks: [WorkoutBlock]
    var cooldown: WorkoutBlock?

    var status: WorkoutStatus
    var startedAt: Date?
    var completedAt: Date?
    var actualDurationMinutes: Int?

    var estimatedCalories: Int?
    var actualCalories: Int?
    var userRating: Int?
    var perceivedDifficulty: PerceivedDifficulty?
    var xpEarned: Int = 0

    var muscleGroupsWorked: [String: String]
    var focusAreas: [String]

    enum PerceivedDifficulty: String, Codable, CaseIterable, Identifiable {
        case tooEasy = "too_easy"
        case justRight = "just_right"
        case tooHard = "too_hard"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .tooEasy: "Too Easy"
            case .justRight: "Just Right"
            case .tooHard: "Too Hard"
            }
        }
        var emoji: String {
            switch self {
            case .tooEasy: "😴"
            case .justRight: "👌"
            case .tooHard: "🥵"
            }
        }
    }

    var allExercises: [WorkoutExercise] {
        var exercises: [WorkoutExercise] = []
        if let warmup { exercises += warmup.exercises }
        for block in mainBlocks { exercises += block.exercises }
        if let cooldown { exercises += cooldown.exercises }
        return exercises
    }

    var totalExerciseCount: Int { allExercises.count }
}
