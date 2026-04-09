import Foundation
import SwiftData

final class MockWorkoutService: WorkoutServiceProtocol {
    private let modelContext: ModelContext
    private let exerciseService: ExerciseServiceProtocol

    init(modelContext: ModelContext, exerciseService: ExerciseServiceProtocol) {
        self.modelContext = modelContext
        self.exerciseService = exerciseService
    }

    func generateWorkout(duration: Int, profile: UserProfile) async throws -> Workout {
        let engine = WorkoutGenerationEngine(exerciseService: exerciseService)
        let exercises = exerciseService.getAllExercises()
        let history = try await getHistory()
        let workout = engine.generateWorkout(duration: duration, profile: profile, exercises: exercises, recentHistory: history)
        try await saveWorkout(workout)
        return workout
    }

    func startWorkout(_ workout: Workout) async throws -> Workout {
        var updated = workout
        updated.status = .inProgress
        updated.startedAt = Date()
        try await saveWorkout(updated)
        return updated
    }

    func completeWorkout(_ workout: Workout, rating: Int, difficulty: Workout.PerceivedDifficulty) async throws -> Workout {
        var updated = workout
        if updated.status != .partial {
            updated.status = .completed
        }
        updated.completedAt = updated.completedAt ?? Date()
        updated.userRating = rating
        updated.perceivedDifficulty = difficulty
        if updated.actualDurationMinutes == nil, let startedAt = updated.startedAt {
            updated.actualDurationMinutes = Int(Date().timeIntervalSince(startedAt) / 60)
        }
        let calculator = CalorieCalculator()
        updated.actualCalories = calculator.calculate(workout: updated, weightKg: 70)

        // Calculate XP: partial workouts use actual duration, completed use requested
        let minutes = updated.status == .partial
            ? (updated.actualDurationMinutes ?? 0)
            : (updated.actualDurationMinutes ?? updated.requestedDurationMinutes)
        updated.xpEarned = Constants.XP.calculate(durationMinutes: minutes, rating: rating)

        try await saveWorkout(updated)
        return updated
    }

    func cancelWorkout(_ workout: Workout) async throws -> Workout {
        var updated = workout
        updated.status = .cancelled
        try await saveWorkout(updated)
        return updated
    }

    func swapExercise(in workout: Workout, exerciseId: String, reason: SwapReason) async throws -> Workout {
        var updated = workout
        let allExercises = exerciseService.getAllExercises()
        let usedIds = Set(updated.allExercises.map(\.exerciseId))

        for blockIndex in updated.mainBlocks.indices {
            for exIndex in updated.mainBlocks[blockIndex].exercises.indices {
                guard updated.mainBlocks[blockIndex].exercises[exIndex].exerciseId == exerciseId else {
                    continue
                }

                let current = updated.mainBlocks[blockIndex].exercises[exIndex].exercise
                let candidates = allExercises.filter { !usedIds.contains($0.id) && $0.id != current.id }

                if let replacement = findReplacement(for: current, reason: reason, candidates: candidates) {
                    updated.mainBlocks[blockIndex].exercises[exIndex].substitutedWith = replacement.id
                    updated.mainBlocks[blockIndex].exercises[exIndex].exercise = replacement
                    updated.mainBlocks[blockIndex].exercises[exIndex].exerciseId = replacement.id
                    updated.mainBlocks[blockIndex].exercises[exIndex].sets = replacement.defaultSets
                    updated.mainBlocks[blockIndex].exercises[exIndex].reps = replacement.defaultReps
                    updated.mainBlocks[blockIndex].exercises[exIndex].durationSeconds = replacement.defaultDurationSeconds
                    updated.mainBlocks[blockIndex].exercises[exIndex].restAfterSeconds = replacement.restBetweenSetsSeconds
                }

                if reason == .dontLikeIt {
                    try incrementSkipCount(for: current.id)
                }
            }
        }

        // Recalculate estimated calories after swap
        let weightKg = try fetchUserWeightKg()
        let calculator = CalorieCalculator()
        updated.estimatedCalories = calculator.calculate(workout: updated, weightKg: weightKg)

        try await saveWorkout(updated)
        return updated
    }

    // MARK: - Swap Helpers

    private func findReplacement(for current: Exercise, reason: SwapReason, candidates: [Exercise]) -> Exercise? {
        switch reason {
        case .tooHard:
            return findRegression(for: current, candidates: candidates)
        case .tooEasy:
            return findProgression(for: current, candidates: candidates)
        case .noEquipment:
            return findEquipmentAlternative(for: current, candidates: candidates)
        case .itHurts:
            return findPainSafeAlternative(for: current, candidates: candidates)
        case .dontLikeIt:
            return findPatternAlternative(for: current, candidates: candidates)
        }
    }

    /// "Too Hard" — prefer lower progressionOrder in same chain, fall back to lower difficulty same pattern
    private func findRegression(for current: Exercise, candidates: [Exercise]) -> Exercise? {
        // Try same progression chain first, pick highest order below current
        if let chainId = current.progressionChainId, let currentOrder = current.progressionOrder {
            let chainRegressions = candidates
                .filter { $0.progressionChainId == chainId && ($0.progressionOrder ?? Int.max) < currentOrder }
                .sorted { ($0.progressionOrder ?? 0) > ($1.progressionOrder ?? 0) }
            if let match = chainRegressions.first { return match }
        }

        // Fall back: same movement pattern, lower difficulty
        let patternRegressions = candidates
            .filter { $0.movementPattern == current.movementPattern && $0.difficulty < current.difficulty }
            .sorted { $0.difficulty > $1.difficulty } // closest difficulty below
        if let match = patternRegressions.first { return match }

        // Last resort: same movement pattern, any difficulty
        return candidates.first { $0.movementPattern == current.movementPattern }
    }

    /// "Too Easy" — prefer higher progressionOrder in same chain, fall back to higher difficulty same pattern
    private func findProgression(for current: Exercise, candidates: [Exercise]) -> Exercise? {
        // Try same progression chain first, pick lowest order above current
        if let chainId = current.progressionChainId, let currentOrder = current.progressionOrder {
            let chainProgressions = candidates
                .filter { $0.progressionChainId == chainId && ($0.progressionOrder ?? 0) > currentOrder }
                .sorted { ($0.progressionOrder ?? Int.max) < ($1.progressionOrder ?? Int.max) }
            if let match = chainProgressions.first { return match }
        }

        // Fall back: same movement pattern, higher difficulty
        let patternProgressions = candidates
            .filter { $0.movementPattern == current.movementPattern && $0.difficulty > current.difficulty }
            .sorted { $0.difficulty < $1.difficulty } // closest difficulty above
        if let match = patternProgressions.first { return match }

        // Last resort: same movement pattern, any difficulty
        return candidates.first { $0.movementPattern == current.movementPattern }
    }

    /// "No Equipment" — pick exercise matching movement pattern with only equipment the user has
    private func findEquipmentAlternative(for current: Exercise, candidates: [Exercise]) -> Exercise? {
        let userEquipment: Set<Equipment>
        if let profile = try? fetchUserProfile() {
            userEquipment = Set(profile.availableEquipment)
        } else {
            userEquipment = [.none]
        }

        // Same movement pattern, user has the required equipment
        let patternMatches = candidates
            .filter { $0.movementPattern == current.movementPattern && Set($0.equipment).isSubset(of: userEquipment) }
            .sorted { $0.difficulty < $1.difficulty }
        if let match = patternMatches.first { return match }

        // Any movement pattern, same category, user has equipment
        let categoryMatches = candidates
            .filter { $0.category == current.category && Set($0.equipment).isSubset(of: userEquipment) }
            .sorted { $0.difficulty < $1.difficulty }
        return categoryMatches.first
    }

    /// "It Hurts" — exclude exercises sharing the same primary muscle groups
    private func findPainSafeAlternative(for current: Exercise, candidates: [Exercise]) -> Exercise? {
        let painMuscles = Set(current.muscleGroups.primary)

        // Same movement pattern but different primary muscles
        let safePattern = candidates
            .filter { $0.movementPattern == current.movementPattern && Set($0.muscleGroups.primary).isDisjoint(with: painMuscles) }
        if let match = safePattern.first { return match }

        // Any exercise in same category with no overlapping primary muscles
        let safeCategory = candidates
            .filter { $0.category == current.category && Set($0.muscleGroups.primary).isDisjoint(with: painMuscles) }
        return safeCategory.first
    }

    /// "Don't Like It" — pick different exercise same movement pattern
    private func findPatternAlternative(for current: Exercise, candidates: [Exercise]) -> Exercise? {
        let patternMatches = candidates
            .filter { $0.movementPattern == current.movementPattern }
            .sorted { $0.difficulty < $1.difficulty }
        if let match = patternMatches.first { return match }

        // Fall back to same category
        return candidates.first { $0.category == current.category }
    }

    // MARK: - Persistence Helpers

    private func fetchUserProfile() throws -> UserProfile? {
        let descriptor = FetchDescriptor<SDUserProfile>()
        return try modelContext.fetch(descriptor).first?.toUserProfile()
    }

    private func fetchUserWeightKg() throws -> Double {
        (try fetchUserProfile())?.weightKg ?? 70.0
    }

    private func incrementSkipCount(for exerciseId: String) throws {
        let descriptor = FetchDescriptor<SDUserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        var counts = profile.getExerciseSkipCounts()
        counts[exerciseId, default: 0] += 1
        profile.setExerciseSkipCounts(counts)
        try modelContext.save()
    }

    func getHistory() async throws -> [Workout] {
        let completedStatus = WorkoutStatus.completed.rawValue
        let partialStatus = WorkoutStatus.partial.rawValue
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { $0.status == completedStatus || $0.status == partialStatus },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { $0.toWorkout() }
    }

    func getTodaysWorkout() async throws -> Workout? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { $0.createdAt >= startOfDay },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first?.toWorkout()
    }

    func saveWorkout(_ workout: Workout) async throws {
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { $0.workoutId == workout.id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: workout)
        } else {
            modelContext.insert(SDWorkout(from: workout))
        }
        try modelContext.save()
    }
}
