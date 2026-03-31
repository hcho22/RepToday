import Foundation

struct CalorieCalculator {
    func calculate(workout: Workout, weightKg: Double) -> Int {
        var totalCalories: Double = 0

        for exercise in workout.allExercises {
            let met = exercise.exercise.metValue
            let durationHours: Double

            if exercise.skipped {
                continue
            }

            if let completedSets = exercise.completedSets.last?.completedAt,
               let firstSet = exercise.completedSets.first?.completedAt {
                durationHours = completedSets.timeIntervalSince(firstSet) / 3600
            } else {
                let totalSeconds = Double(exercise.estimatedTotalSeconds)
                durationHours = totalSeconds / 3600
            }

            // MET * weightKg * durationHours
            totalCalories += met * weightKg * durationHours
        }

        // Add small amount for rest/transitions (10% overhead)
        totalCalories *= 1.1

        return max(1, Int(totalCalories.rounded()))
    }

    func estimateCalories(durationMinutes: Int, averageMET: Double, weightKg: Double) -> Int {
        let durationHours = Double(durationMinutes) / 60.0
        return max(1, Int((averageMET * weightKg * durationHours * 1.1).rounded()))
    }
}
