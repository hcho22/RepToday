import Foundation

protocol WorkoutServiceProtocol {
    func generateWorkout(duration: Int, profile: UserProfile) async throws -> Workout
    func startWorkout(_ workout: Workout) async throws -> Workout
    func completeWorkout(_ workout: Workout, rating: Int, difficulty: Workout.PerceivedDifficulty) async throws -> Workout
    func cancelWorkout(_ workout: Workout) async throws -> Workout
    func swapExercise(in workout: Workout, exerciseId: String, reason: String) async throws -> Workout
    func getHistory() async throws -> [Workout]
    func getTodaysWorkout() async throws -> Workout?
    func saveWorkout(_ workout: Workout) async throws
}
