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

    func swapExercise(in workout: Workout, exerciseId: String, reason: String) async throws -> Workout {
        var updated = workout
        let allExercises = exerciseService.getAllExercises()

        for blockIndex in updated.mainBlocks.indices {
            for exIndex in updated.mainBlocks[blockIndex].exercises.indices {
                if updated.mainBlocks[blockIndex].exercises[exIndex].exerciseId == exerciseId {
                    let current = updated.mainBlocks[blockIndex].exercises[exIndex].exercise
                    let usedIds = Set(updated.allExercises.map(\.exerciseId))

                    if let replacement = allExercises.first(where: { ex in
                        !usedIds.contains(ex.id) &&
                        ex.category == current.category &&
                        ex.id != current.id
                    }) {
                        updated.mainBlocks[blockIndex].exercises[exIndex].substitutedWith = replacement.id
                        updated.mainBlocks[blockIndex].exercises[exIndex].exercise = replacement
                        updated.mainBlocks[blockIndex].exercises[exIndex].exerciseId = replacement.id
                    }
                }
            }
        }

        try await saveWorkout(updated)
        return updated
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
