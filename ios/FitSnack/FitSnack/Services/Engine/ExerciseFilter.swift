import Foundation

/// Filters the full exercise catalog based on user profile, equipment, injuries, and preferences.
struct ExerciseFilter {

    /// Filters exercises according to profile constraints and user preferences.
    ///
    /// Applies in order: equipment → difficulty → injury exclusion → skip-frequency → apartment-friendly.
    /// Then sorts by rating boost (exercises rated 4-5 appear first).
    func filter(
        exercises: [Exercise],
        profile: UserProfile,
        preferences: ExercisePreferences
    ) -> [Exercise] {
        let maxDifficulty = difficultyForLevel(profile.fitnessLevel)
        let injuryKeywords = parseInjuryKeywords(profile.injuries)

        var result = exercises.filter { exercise in
            equipmentMatch(exercise: exercise, available: profile.availableEquipment) &&
            exercise.difficulty <= maxDifficulty &&
            !shouldExclude(exercise: exercise, injuries: injuryKeywords) &&
            !isOverSkipped(exercise: exercise, skipCounts: preferences.skipCounts) &&
            passesApartmentFilter(exercise: exercise, required: preferences.apartmentFriendly)
        }

        // Bodyweight fallback if filters too restrictive (no strength/cardio left)
        let hasMainExercises = result.contains { $0.category == .strength || $0.category == .cardio }
        if !hasMainExercises {
            result = exercises.filter { exercise in
                let isBodyweight = exercise.equipment.isEmpty || exercise.equipment.contains(.none)
                return isBodyweight &&
                    !shouldExclude(exercise: exercise, injuries: injuryKeywords) &&
                    passesApartmentFilter(exercise: exercise, required: preferences.apartmentFriendly)
            }
        }

        // Rating boost: exercises rated 4-5 sort higher
        return result.sorted { ex1, ex2 in
            let r1 = preferences.ratings[ex1.id] ?? 0
            let r2 = preferences.ratings[ex2.id] ?? 0
            let boost1 = r1 >= 4 ? 1 : 0
            let boost2 = r2 >= 4 ? 1 : 0
            return boost1 > boost2
        }
    }

    // MARK: - Individual Filter Predicates

    func equipmentMatch(exercise: Exercise, available: [Equipment]) -> Bool {
        exercise.equipment.isEmpty ||
        exercise.equipment.contains(where: { available.contains($0) }) ||
        available.contains(.none)
    }

    func difficultyForLevel(_ level: FitnessLevel) -> Int {
        switch level {
        case .beginner: 2
        case .intermediate: 3
        case .advanced: 5
        }
    }

    func shouldExclude(exercise: Exercise, injuries: [String]) -> Bool {
        guard !injuries.isEmpty else { return false }
        let exerciseText = (exercise.name + " " + exercise.tags.joined(separator: " ") +
            exercise.muscleGroups.primary.map(\.rawValue).joined(separator: " ")).lowercased()
        return injuries.contains { injury in
            exerciseText.contains(injury)
        }
    }

    func parseInjuryKeywords(_ injuries: String) -> [String] {
        injuries.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Exercises skipped more than 3 times are excluded from selection.
    func isOverSkipped(exercise: Exercise, skipCounts: [String: Int]) -> Bool {
        (skipCounts[exercise.id] ?? 0) > 3
    }

    /// When apartment-friendly mode is on, exclude exercises where `apartmentFriendly == false`.
    func passesApartmentFilter(exercise: Exercise, required: Bool) -> Bool {
        guard required else { return true }
        return exercise.apartmentFriendly != false
    }
}
