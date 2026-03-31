import Foundation

protocol ExerciseServiceProtocol {
    func getAllExercises() -> [Exercise]
    func getExercise(by id: String) -> Exercise?
    func filterExercises(equipment: [Equipment]?, category: ExerciseCategory?, muscleGroup: MuscleGroup?, difficulty: Int?) -> [Exercise]
    func searchExercises(query: String) -> [Exercise]
}
