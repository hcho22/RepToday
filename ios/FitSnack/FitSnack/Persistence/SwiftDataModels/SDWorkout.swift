import Foundation
import SwiftData

@Model
final class SDWorkout {
    @Attribute(.unique) var workoutId: String
    var userId: String
    var createdAt: Date
    var requestedDurationMinutes: Int
    var status: String
    var startedAt: Date?
    var completedAt: Date?
    var actualDurationMinutes: Int?
    var userRating: Int?
    var perceivedDifficulty: String?
    var estimatedCalories: Int?
    var actualCalories: Int?
    var xpEarned: Int
    var workoutDataRaw: Data // JSON-encoded full Workout
    var aiSummary: String? = nil

    init(from workout: Workout) {
        self.workoutId = workout.id
        self.userId = workout.userId
        self.createdAt = workout.createdAt
        self.requestedDurationMinutes = workout.requestedDurationMinutes
        self.status = workout.status.rawValue
        self.startedAt = workout.startedAt
        self.completedAt = workout.completedAt
        self.actualDurationMinutes = workout.actualDurationMinutes
        self.userRating = workout.userRating
        self.perceivedDifficulty = workout.perceivedDifficulty?.rawValue
        self.estimatedCalories = workout.estimatedCalories
        self.actualCalories = workout.actualCalories
        self.xpEarned = workout.xpEarned
        self.workoutDataRaw = (try? JSONEncoder().encode(workout)) ?? Data()
    }

    func toWorkout() -> Workout? {
        try? JSONDecoder().decode(Workout.self, from: workoutDataRaw)
    }

    func update(from workout: Workout) {
        self.status = workout.status.rawValue
        self.startedAt = workout.startedAt
        self.completedAt = workout.completedAt
        self.actualDurationMinutes = workout.actualDurationMinutes
        self.userRating = workout.userRating
        self.perceivedDifficulty = workout.perceivedDifficulty?.rawValue
        self.estimatedCalories = workout.estimatedCalories
        self.actualCalories = workout.actualCalories
        self.xpEarned = workout.xpEarned
        self.workoutDataRaw = (try? JSONEncoder().encode(workout)) ?? Data()
    }
}
