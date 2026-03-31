import Foundation

struct WorkoutExercise: Codable, Identifiable {
    let id: String
    var exerciseId: String
    var exercise: Exercise
    var sets: Int
    var reps: Int?
    var durationSeconds: Int?
    var restAfterSeconds: Int
    var notes: String?

    var completedSets: [SetLog]
    var skipped: Bool
    var substitutedWith: String?

    var isCompleted: Bool {
        completedSets.count >= sets || skipped
    }

    var estimatedTotalSeconds: Int {
        let setTime = exercise.estimatedTimePerSetSeconds * sets
        let restTime = restAfterSeconds * max(0, sets - 1)
        return setTime + restTime
    }
}
