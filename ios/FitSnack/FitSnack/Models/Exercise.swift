import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let instructions: [String]
    let commonMistakes: [String]

    let muscleGroups: MuscleGroups
    let movementPattern: MovementPattern
    let category: ExerciseCategory
    let difficulty: Int
    let equipment: [Equipment]
    let isUnilateral: Bool

    let defaultReps: Int?
    let defaultDurationSeconds: Int?
    let defaultSets: Int
    let restBetweenSetsSeconds: Int
    let estimatedTimePerSetSeconds: Int

    let regressions: [String]
    let progressions: [String]

    let metValue: Double
    let tags: [String]

    struct MuscleGroups: Codable, Hashable {
        let primary: [MuscleGroup]
        let secondary: [MuscleGroup]
    }
}
