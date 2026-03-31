import Foundation

struct WorkoutHistory: Codable, Identifiable {
    let id: String
    let workoutId: String
    let date: Date
    let durationMinutes: Int
    let exerciseCount: Int
    let caloriesBurned: Double
    let muscleGroups: [MuscleGroup]
    let rating: Int?
}
