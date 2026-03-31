import Foundation

final class MockExerciseService: ExerciseServiceProtocol {
    private var exercises: [Exercise] = []

    init() {
        loadExercises()
    }

    private func loadExercises() {
        guard let url = Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }
        exercises = (try? JSONDecoder().decode([Exercise].self, from: data)) ?? []
    }

    func getAllExercises() -> [Exercise] {
        exercises
    }

    func getExercise(by id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func filterExercises(equipment: [Equipment]?, category: ExerciseCategory?, muscleGroup: MuscleGroup?, difficulty: Int?) -> [Exercise] {
        exercises.filter { exercise in
            if let equipment {
                let exerciseEquipment = exercise.equipment.isEmpty ? [Equipment.none] : exercise.equipment
                guard exerciseEquipment.contains(where: { equipment.contains($0) }) else { return false }
            }
            if let category, exercise.category != category { return false }
            if let muscleGroup {
                guard exercise.muscleGroups.primary.contains(muscleGroup) ||
                      exercise.muscleGroups.secondary.contains(muscleGroup) else { return false }
            }
            if let difficulty, exercise.difficulty > difficulty { return false }
            return true
        }
    }

    func searchExercises(query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let lowered = query.lowercased()
        return exercises.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.displayName.lowercased().contains(lowered) ||
            $0.tags.contains(where: { $0.lowercased().contains(lowered) })
        }
    }
}
