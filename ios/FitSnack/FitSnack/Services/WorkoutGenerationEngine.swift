import Foundation

struct WorkoutGenerationEngine {
    let exerciseService: ExerciseServiceProtocol

    func generate(duration: Int, profile: UserProfile) -> Workout {
        let exercises = exerciseService.getAllExercises()
        return generateWorkout(duration: duration, profile: profile, exercises: exercises, recentHistory: [])
    }

    func generateWorkout(duration: Int, profile: UserProfile, exercises: [Exercise], recentHistory: [Workout]) -> Workout {
        let availableEquipment = profile.availableEquipment
        let maxDifficulty = difficultyForLevel(profile.fitnessLevel)
        let injuryKeywords = profile.injuries.lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let filteredExercises = exercises.filter { exercise in
            let equipmentMatch = exercise.equipment.isEmpty ||
                exercise.equipment.contains(where: { availableEquipment.contains($0) }) ||
                availableEquipment.contains(.none)
            let difficultyMatch = exercise.difficulty <= maxDifficulty
            return equipmentMatch && difficultyMatch && !shouldExclude(exercise: exercise, injuries: injuryKeywords)
        }

        // Fallback to bodyweight exercises if filters too restrictive
        let allExercises: [Exercise]
        if filteredExercises.filter({ $0.category == .strength || $0.category == .cardio }).isEmpty {
            allExercises = exercises.filter { exercise in
                let isBodyweight = exercise.equipment.isEmpty || exercise.equipment.contains(.none)
                return isBodyweight && !shouldExclude(exercise: exercise, injuries: injuryKeywords)
            }
        } else {
            allExercises = filteredExercises
        }

        // Build muscle group penalty from recent history
        let recentMuscleGroupCounts = recentHistoryMuscleGroupCounts(recentHistory)

        let warmupExercises = allExercises.filter { $0.category == .warmup }
        let mainExercises = allExercises.filter { $0.category == .strength || $0.category == .cardio }
        let cooldownExercises = allExercises.filter { $0.category == .cooldown }

        var totalSeconds = duration * 60
        var warmup: WorkoutBlock?
        var cooldown: WorkoutBlock?
        var mainBlocks: [WorkoutBlock] = []

        // Warmup: 1-2 min for workouts > 5 min
        if duration > 5, !warmupExercises.isEmpty {
            let warmupTime = min(120, totalSeconds / 5)
            warmup = buildWarmupBlock(from: warmupExercises, timeSeconds: warmupTime)
            totalSeconds -= warmupTime
        }

        // Cooldown: 1 min for workouts > 10 min
        if duration > 10, !cooldownExercises.isEmpty {
            let cooldownTime = 60
            cooldown = buildCooldownBlock(from: cooldownExercises, timeSeconds: cooldownTime)
            totalSeconds -= cooldownTime
        }

        // Main blocks: fill remaining time
        let blockCount = min(4, max(1, duration / 7))
        let timePerBlock = totalSeconds / max(1, blockCount)

        var usedExerciseIds = Set<String>()
        var muscleGroupCounts: [MuscleGroup: Int] = recentMuscleGroupCounts

        for i in 0..<blockCount {
            let targetMuscleGroup = leastUsedMuscleGroup(from: muscleGroupCounts, goal: profile.primaryGoal)
            let candidates = mainExercises
                .filter { !usedExerciseIds.contains($0.id) }
                .sorted { ex1, ex2 in
                    let score1 = muscleGroupScore(ex1, target: targetMuscleGroup)
                    let score2 = muscleGroupScore(ex2, target: targetMuscleGroup)
                    return score1 > score2
                }

            let block = buildMainBlock(
                index: i,
                from: candidates,
                timeSeconds: timePerBlock,
                usedIds: &usedExerciseIds,
                muscleGroupCounts: &muscleGroupCounts
            )
            mainBlocks.append(block)
        }

        let muscleGroupsWorked = buildMuscleGroupMap(mainBlocks: mainBlocks, warmup: warmup)

        return Workout(
            id: UUID().uuidString,
            userId: profile.id,
            createdAt: Date(),
            requestedDurationMinutes: duration,
            warmup: warmup,
            mainBlocks: mainBlocks,
            cooldown: cooldown,
            status: .generated,
            muscleGroupsWorked: muscleGroupsWorked,
            focusAreas: Array(Set(mainBlocks.flatMap { $0.exercises.flatMap { $0.exercise.muscleGroups.primary.map(\.displayName) } }))
        )
    }

    private func difficultyForLevel(_ level: FitnessLevel) -> Int {
        switch level {
        case .beginner: 2
        case .intermediate: 4
        case .advanced: 5
        }
    }

    private func shouldExclude(exercise: Exercise, injuries: [String]) -> Bool {
        guard !injuries.isEmpty else { return false }
        let exerciseText = (exercise.name + " " + exercise.tags.joined(separator: " ") +
            exercise.muscleGroups.primary.map(\.rawValue).joined(separator: " ")).lowercased()
        return injuries.contains { injury in
            exerciseText.contains(injury)
        }
    }

    private func buildWarmupBlock(from exercises: [Exercise], timeSeconds: Int) -> WorkoutBlock {
        var selected: [WorkoutExercise] = []
        var remaining = timeSeconds

        for exercise in exercises.shuffled().prefix(3) {
            guard remaining > 0 else { break }
            let duration = min(remaining, exercise.defaultDurationSeconds ?? 30)
            selected.append(WorkoutExercise(
                id: UUID().uuidString,
                exerciseId: exercise.id,
                exercise: exercise,
                sets: 1,
                reps: nil,
                durationSeconds: duration,
                restAfterSeconds: 10,
                notes: exercise.instructions.first,
                completedSets: [],
                skipped: false
            ))
            remaining -= duration + 10
        }

        return WorkoutBlock(
            id: UUID().uuidString,
            name: "Warm Up",
            type: .warmup,
            exercises: selected,
            restBetweenExercisesSeconds: 10
        )
    }

    private func buildCooldownBlock(from exercises: [Exercise], timeSeconds: Int) -> WorkoutBlock {
        var selected: [WorkoutExercise] = []
        var remaining = timeSeconds

        for exercise in exercises.shuffled().prefix(2) {
            guard remaining > 0 else { break }
            let duration = min(remaining, exercise.defaultDurationSeconds ?? 30)
            selected.append(WorkoutExercise(
                id: UUID().uuidString,
                exerciseId: exercise.id,
                exercise: exercise,
                sets: 1,
                reps: nil,
                durationSeconds: duration,
                restAfterSeconds: 5,
                notes: exercise.instructions.first,
                completedSets: [],
                skipped: false
            ))
            remaining -= duration + 5
        }

        return WorkoutBlock(
            id: UUID().uuidString,
            name: "Cool Down",
            type: .cooldown,
            exercises: selected,
            restBetweenExercisesSeconds: 5
        )
    }

    private func buildMainBlock(
        index: Int,
        from candidates: [Exercise],
        timeSeconds: Int,
        usedIds: inout Set<String>,
        muscleGroupCounts: inout [MuscleGroup: Int]
    ) -> WorkoutBlock {
        var selected: [WorkoutExercise] = []
        var remaining = timeSeconds

        for exercise in candidates {
            guard remaining > 30 else { break }

            let sets = calculateSets(for: exercise, availableTime: remaining)
            let totalTime = exercise.estimatedTimePerSetSeconds * sets + exercise.restBetweenSetsSeconds * max(0, sets - 1)

            guard totalTime <= remaining else { continue }

            selected.append(WorkoutExercise(
                id: UUID().uuidString,
                exerciseId: exercise.id,
                exercise: exercise,
                sets: sets,
                reps: exercise.defaultReps,
                durationSeconds: exercise.defaultDurationSeconds,
                restAfterSeconds: exercise.restBetweenSetsSeconds,
                notes: exercise.instructions.first,
                completedSets: [],
                skipped: false
            ))

            usedIds.insert(exercise.id)
            for mg in exercise.muscleGroups.primary {
                muscleGroupCounts[mg, default: 0] += 1
            }
            remaining -= totalTime

            if selected.count >= 3 { break }
        }

        let blockNames = ["Upper Body", "Lower Body", "Core & Cardio", "Full Body"]
        return WorkoutBlock(
            id: UUID().uuidString,
            name: blockNames[index % blockNames.count],
            type: .strength,
            exercises: selected,
            restBetweenExercisesSeconds: 30
        )
    }

    private func calculateSets(for exercise: Exercise, availableTime: Int) -> Int {
        let timePerSet = exercise.estimatedTimePerSetSeconds + exercise.restBetweenSetsSeconds
        let maxSets = max(1, availableTime / max(1, timePerSet))
        return min(exercise.defaultSets, maxSets)
    }

    private func leastUsedMuscleGroup(from counts: [MuscleGroup: Int], goal: PrimaryGoal) -> MuscleGroup? {
        let priorities: [MuscleGroup] = switch goal {
        case .buildMuscle: [.chest, .upperBack, .shoulders, .quads, .glutes]
        case .loseWeight: [.quads, .glutes, .core, .chest, .upperBack]
        case .stayActive: [.core, .quads, .shoulders, .glutes, .chest]
        case .increaseEnergy: [.core, .quads, .glutes, .shoulders, .chest]
        case .reduceStress: [.core, .shoulders, .hipFlexors, .glutes, .quads]
        }

        return priorities.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    private func muscleGroupScore(_ exercise: Exercise, target: MuscleGroup?) -> Int {
        guard let target else { return 0 }
        if exercise.muscleGroups.primary.contains(target) { return 2 }
        if exercise.muscleGroups.secondary.contains(target) { return 1 }
        return 0
    }

    private func recentHistoryMuscleGroupCounts(_ history: [Workout]) -> [MuscleGroup: Int] {
        var counts: [MuscleGroup: Int] = [:]
        // Consider last 3 workouts for balancing
        for workout in history.prefix(3) {
            let allBlocks = workout.mainBlocks + [workout.warmup].compactMap { $0 }
            for block in allBlocks {
                for exercise in block.exercises {
                    for mg in exercise.exercise.muscleGroups.primary {
                        counts[mg, default: 0] += 1
                    }
                }
            }
        }
        return counts
    }

    private func buildMuscleGroupMap(mainBlocks: [WorkoutBlock], warmup: WorkoutBlock?) -> [String: String] {
        var map: [String: String] = [:]
        let allBlocks = mainBlocks + [warmup].compactMap { $0 }
        for block in allBlocks {
            for exercise in block.exercises {
                for mg in exercise.exercise.muscleGroups.primary {
                    map[mg.rawValue] = "primary"
                }
                for mg in exercise.exercise.muscleGroups.secondary {
                    if map[mg.rawValue] == nil {
                        map[mg.rawValue] = "secondary"
                    }
                }
            }
        }
        return map
    }
}
