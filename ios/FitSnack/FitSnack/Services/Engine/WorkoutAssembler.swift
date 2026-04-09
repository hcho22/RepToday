import Foundation

/// Assembles a Workout from selected exercises, respecting time budgets
/// with overflow/underflow handling.
struct WorkoutAssembler {

    // MARK: - Main Assembly

    /// Assembles a complete Workout from the given exercises and time budget.
    func assemble(
        duration: Int,
        exercises: [Exercise],
        warmupExercises: [Exercise],
        cooldownExercises: [Exercise],
        profile: UserProfile,
        dayTemplate: MovementPatternRotation.DayTemplate
    ) -> Workout {
        var totalSeconds = duration * 60
        var warmup: WorkoutBlock?
        var cooldown: WorkoutBlock?

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

        // Build main blocks from selected exercises
        let mainBlocks = buildMainBlocks(
            exercises: exercises,
            timeSeconds: totalSeconds,
            duration: duration,
            dayTemplate: dayTemplate,
            profile: profile
        )

        let muscleGroupsWorked = buildMuscleGroupMap(mainBlocks: mainBlocks, warmup: warmup)
        let focusAreas = Array(Set(
            mainBlocks.flatMap { $0.exercises.flatMap { $0.exercise.muscleGroups.primary.map(\.displayName) } }
        ))

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
            focusAreas: focusAreas
        )
    }

    // MARK: - Block Builders

    func buildWarmupBlock(from exercises: [Exercise], timeSeconds: Int) -> WorkoutBlock {
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

    func buildCooldownBlock(from exercises: [Exercise], timeSeconds: Int) -> WorkoutBlock {
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

    // MARK: - Main Block Assembly

    func buildMainBlocks(
        exercises: [Exercise],
        timeSeconds: Int,
        duration: Int,
        dayTemplate: MovementPatternRotation.DayTemplate,
        profile: UserProfile
    ) -> [WorkoutBlock] {
        let blockCount = min(4, max(1, duration / 7))
        let timePerBlock = timeSeconds / max(1, blockCount)

        var usedIds = Set<String>()
        var muscleGroupCounts: [MuscleGroup: Int] = [:]
        var blocks: [WorkoutBlock] = []

        for i in 0..<blockCount {
            let targetMuscleGroup = leastUsedMuscleGroup(from: muscleGroupCounts, goal: profile.primaryGoal)
            let candidates = exercises
                .filter { !usedIds.contains($0.id) }
                .sorted { ex1, ex2 in
                    muscleGroupScore(ex1, target: targetMuscleGroup) >
                    muscleGroupScore(ex2, target: targetMuscleGroup)
                }

            let block = buildMainBlock(
                index: i,
                from: candidates,
                timeSeconds: timePerBlock,
                usedIds: &usedIds,
                muscleGroupCounts: &muscleGroupCounts,
                allExercises: exercises
            )
            blocks.append(block)
        }

        return blocks
    }

    private func buildMainBlock(
        index: Int,
        from candidates: [Exercise],
        timeSeconds: Int,
        usedIds: inout Set<String>,
        muscleGroupCounts: inout [MuscleGroup: Int],
        allExercises: [Exercise]
    ) -> WorkoutBlock {
        var selected: [WorkoutExercise] = []
        var remaining = timeSeconds

        for exercise in candidates {
            guard remaining > 30 else { break }

            let sets = calculateSets(for: exercise, availableTime: remaining)
            let totalTime = exercise.estimatedTimePerSetSeconds * sets +
                exercise.restBetweenSetsSeconds * max(0, sets - 1)

            // Overflow handling: skip exercise if it doesn't fit
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

        // Underflow handling: if > 2 minutes remaining, try to add another exercise
        if remaining > 120, selected.count < 4 {
            let extraCandidates = allExercises.filter { !usedIds.contains($0.id) }
            for exercise in extraCandidates {
                let sets = calculateSets(for: exercise, availableTime: remaining)
                let totalTime = exercise.estimatedTimePerSetSeconds * sets +
                    exercise.restBetweenSetsSeconds * max(0, sets - 1)
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
                break
            }
        }

        return WorkoutBlock(
            id: UUID().uuidString,
            name: blockNameForExercises(selected),
            type: .strength,
            exercises: selected,
            restBetweenExercisesSeconds: 30
        )
    }

    // MARK: - Timing Verification

    /// Verifies total assembled time does not exceed the requested duration.
    func verifyTiming(workout: Workout) -> Bool {
        let totalSeconds = workout.allExercises.reduce(0) { $0 + $1.estimatedTotalSeconds }
        return totalSeconds <= workout.requestedDurationMinutes * 60
    }

    // MARK: - Helpers

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

    private func blockNameForExercises(_ exercises: [WorkoutExercise]) -> String {
        let muscles = Set(exercises.flatMap { $0.exercise.muscleGroups.primary })

        let upperMuscles: Set<MuscleGroup> = [.chest, .upperBack, .lowerBack, .shoulders, .biceps, .triceps, .forearms]
        let lowerMuscles: Set<MuscleGroup> = [.quads, .glutes, .hamstrings, .calves, .hipFlexors, .adductors, .abductors]
        let coreMuscles: Set<MuscleGroup> = [.core, .obliques]

        let hasUpper = !muscles.isDisjoint(with: upperMuscles)
        let hasLower = !muscles.isDisjoint(with: lowerMuscles)
        let hasCore = !muscles.isDisjoint(with: coreMuscles)

        switch (hasUpper, hasLower, hasCore) {
        case (true, true, _): return "Full Body"
        case (true, false, true): return "Upper Body & Core"
        case (false, true, true): return "Lower Body & Core"
        case (true, false, false): return "Upper Body"
        case (false, true, false): return "Lower Body"
        case (false, false, true): return "Core"
        default: return "Workout"
        }
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
