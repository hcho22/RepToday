import Foundation

struct WorkoutBlock: Codable, Identifiable {
    let id: String
    var name: String
    var type: BlockType
    var exercises: [WorkoutExercise]
    var restBetweenExercisesSeconds: Int
    var rounds: Int?
    var timeLimitSeconds: Int?
}
