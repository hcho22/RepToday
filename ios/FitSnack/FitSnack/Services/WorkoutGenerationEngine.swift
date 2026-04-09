import Foundation

/// Facade that orchestrates the modular workout generation pipeline:
/// ExerciseFilter → MovementPatternRotation → ExerciseSelector → WorkoutAssembler.
struct WorkoutGenerationEngine {
    let exerciseService: ExerciseServiceProtocol

    private let filter = ExerciseFilter()
    private let selector = ExerciseSelector()
    private let rotation = MovementPatternRotation()
    private let assembler = WorkoutAssembler()

    // MARK: - Backward-compatible entry point (Phase 1 callers)

    func generate(duration: Int, profile: UserProfile) -> Workout {
        let exercises = exerciseService.getAllExercises()
        return generateWorkout(
            duration: duration,
            profile: profile,
            exercises: exercises,
            recentHistory: []
        )
    }

    // MARK: - Phase 1 compatible entry point with history

    func generateWorkout(
        duration: Int,
        profile: UserProfile,
        exercises: [Exercise],
        recentHistory: [Workout]
    ) -> Workout {
        generate(
            duration: duration,
            profile: profile,
            history: recentHistory,
            progressionLevels: profile.progressionLevels,
            exercisePreferences: ExercisePreferences(
                skipCounts: profile.exerciseSkipCounts,
                ratings: profile.exerciseRatings,
                apartmentFriendly: false
            ),
            exercises: exercises
        )
    }

    // MARK: - Full Phase 2 entry point

    func generate(
        duration: Int,
        profile: UserProfile,
        history: [Workout],
        progressionLevels: [String: Int],
        exercisePreferences: ExercisePreferences,
        exercises: [Exercise]? = nil
    ) -> Workout {
        let allExercises = exercises ?? exerciseService.getAllExercises()

        // Step 1: Filter exercises
        let filtered = filter.filter(
            exercises: allExercises,
            profile: profile,
            preferences: exercisePreferences
        )

        // Step 2: Determine movement pattern rotation
        let stalenessScores = selector.stalenessScores(history: history)
        let template = rotation.selectTemplate(
            stalenessScores: stalenessScores,
            history: history
        )

        // Step 3: Categorize exercises
        let warmupExercises = filtered.filter { $0.category == .warmup }
        let cooldownExercises = filtered.filter { $0.category == .cooldown }
        let mainPool = filtered.filter { $0.category == .strength || $0.category == .cardio }

        // Step 4: Select exercises using staleness, variety, and progression chains
        var usedIds = Set<String>()
        let targetCount = max(3, duration / 3) // More exercises for longer workouts
        let selected = selector.select(
            from: mainPool,
            patterns: template.allPatterns,
            count: targetCount,
            history: history,
            progressionLevels: progressionLevels,
            usedIds: &usedIds
        )

        // If selection didn't yield enough exercises, fall back to muscle-group ordering
        let mainExercises: [Exercise]
        if selected.count >= 2 {
            mainExercises = selected
        } else {
            mainExercises = mainPool
        }

        // Step 5: Assemble workout with timing management
        return assembler.assemble(
            duration: duration,
            exercises: mainExercises,
            warmupExercises: warmupExercises,
            cooldownExercises: cooldownExercises,
            profile: profile,
            dayTemplate: template
        )
    }
}
