import XCTest
@testable import FitSnack

final class CalorieCalculatorTests: XCTestCase {
    private let calculator = CalorieCalculator()

    // MARK: - Helper

    private func makeExercise(metValue: Double, estimatedTimePerSet: Int = 15, restBetweenSets: Int = 30) -> Exercise {
        Exercise(
            id: "test-\(metValue)", name: "test", displayName: "Test",
            description: "", instructions: [], commonMistakes: [],
            muscleGroups: Exercise.MuscleGroups(primary: [.chest], secondary: []),
            movementPattern: .pushHorizontal, category: .strength, difficulty: 1,
            equipment: [.none], isUnilateral: false,
            defaultReps: 10, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: restBetweenSets,
            estimatedTimePerSetSeconds: estimatedTimePerSet,
            regressions: [], progressions: [],
            metValue: metValue, tags: []
        )
    }

    private func makeWorkoutExercise(
        metValue: Double,
        sets: Int = 3,
        estimatedTimePerSet: Int = 15,
        restBetweenSets: Int = 30,
        skipped: Bool = false,
        completedSets: [SetLog] = []
    ) -> WorkoutExercise {
        let exercise = makeExercise(metValue: metValue, estimatedTimePerSet: estimatedTimePerSet, restBetweenSets: restBetweenSets)
        return WorkoutExercise(
            id: UUID().uuidString, exerciseId: exercise.id, exercise: exercise,
            sets: sets, reps: 10, durationSeconds: nil,
            restAfterSeconds: restBetweenSets, notes: nil,
            completedSets: completedSets, skipped: skipped
        )
    }

    private func makeWorkout(exercises: [WorkoutExercise]) -> Workout {
        let block = WorkoutBlock(
            id: "block1", name: "Main", type: .strength,
            exercises: exercises, restBetweenExercisesSeconds: 30
        )
        return Workout(
            id: "w1", userId: "u1", createdAt: Date(),
            requestedDurationMinutes: 15,
            mainBlocks: [block],
            status: .completed,
            muscleGroupsWorked: [:], focusAreas: []
        )
    }

    // MARK: - MET calculation matches expected formula output

    func testMETCalculationMatchesFormula() {
        // Exercise: MET 5.0, 3 sets × 15s/set + 30s rest × 2 = 105s total
        let we = makeWorkoutExercise(metValue: 5.0, sets: 3, estimatedTimePerSet: 15, restBetweenSets: 30)
        let workout = makeWorkout(exercises: [we])
        let weightKg = 70.0

        let calories = calculator.calculate(workout: workout, weightKg: weightKg)

        // Expected: MET * weight * durationHours * 1.1 overhead
        // durationHours = 105 / 3600
        // 5.0 * 70 * (105/3600) * 1.1 = 11.229...
        let expected = Int((5.0 * 70.0 * (105.0 / 3600.0) * 1.1).rounded())
        XCTAssertEqual(calories, expected)
    }

    func testEstimateCaloriesMatchesFormula() {
        let calories = calculator.estimateCalories(durationMinutes: 15, averageMET: 5.0, weightKg: 70)
        // 5.0 * 70 * (15/60) * 1.1 = 96.25 → 96
        let expected = Int((5.0 * 70.0 * 0.25 * 1.1).rounded())
        XCTAssertEqual(calories, expected)
    }

    func testMultipleExercisesSumCalories() {
        let we1 = makeWorkoutExercise(metValue: 5.0, sets: 3, estimatedTimePerSet: 15, restBetweenSets: 30)
        let we2 = makeWorkoutExercise(metValue: 8.0, sets: 2, estimatedTimePerSet: 20, restBetweenSets: 20)
        let workout = makeWorkout(exercises: [we1, we2])
        let weightKg = 70.0

        let calories = calculator.calculate(workout: workout, weightKg: weightKg)

        // we1: 5.0 * 70 * (105/3600)
        // we2: 8.0 * 70 * (60/3600) — 2×20 + 20×1 = 60s
        let raw1 = 5.0 * 70.0 * (105.0 / 3600.0)
        let raw2 = 8.0 * 70.0 * (60.0 / 3600.0)
        let expected = max(1, Int(((raw1 + raw2) * 1.1).rounded()))
        XCTAssertEqual(calories, expected)
    }

    // MARK: - Rest periods use lower MET value (1.1x overhead accounts for rest)

    func testRestOverheadApplied() {
        // The calculator applies a 1.1x multiplier to account for rest/transition calories
        let we = makeWorkoutExercise(metValue: 6.0, sets: 2, estimatedTimePerSet: 20, restBetweenSets: 30)
        let workout = makeWorkout(exercises: [we])
        let weightKg = 80.0

        let calories = calculator.calculate(workout: workout, weightKg: weightKg)

        // Without overhead: 6.0 * 80 * (70/3600) = 9.333...
        // With 1.1 overhead: 9.333 * 1.1 = 10.266... → 10
        let rawWithoutOverhead = 6.0 * 80.0 * (70.0 / 3600.0)
        let withOverhead = Int((rawWithoutOverhead * 1.1).rounded())
        XCTAssertEqual(calories, withOverhead)
        // Verify the overhead actually adds calories vs raw
        XCTAssertGreaterThan(Double(calories), rawWithoutOverhead)
    }

    func testEstimateCaloriesIncludesRestOverhead() {
        let withoutOverhead = 5.0 * 70.0 * (10.0 / 60.0) // ~58.33
        let calories = calculator.estimateCalories(durationMinutes: 10, averageMET: 5.0, weightKg: 70)
        XCTAssertGreaterThan(Double(calories), withoutOverhead)
    }

    // MARK: - Zero duration returns minimum calories

    func testZeroDurationReturnsMinimumCalorie() {
        // estimateCalories with 0 minutes → max(1, 0) = 1
        let calories = calculator.estimateCalories(durationMinutes: 0, averageMET: 5.0, weightKg: 70)
        XCTAssertEqual(calories, 1)
    }

    func testAllExercisesSkippedReturnsMinimumCalorie() {
        let we = makeWorkoutExercise(metValue: 5.0, skipped: true)
        let workout = makeWorkout(exercises: [we])
        let calories = calculator.calculate(workout: workout, weightKg: 70)
        XCTAssertEqual(calories, 1)
    }

    func testEmptyWorkoutReturnsMinimumCalorie() {
        let workout = makeWorkout(exercises: [])
        let calories = calculator.calculate(workout: workout, weightKg: 70)
        XCTAssertEqual(calories, 1)
    }

    // MARK: - Uses actual completed set timestamps when available

    func testUsesCompletedSetTimestamps() {
        let start = Date()
        let end = start.addingTimeInterval(120) // 2 minutes between first and last set
        let sets = [
            SetLog(setNumber: 1, completed: true, reps: 10, completedAt: start),
            SetLog(setNumber: 2, completed: true, reps: 10, completedAt: end)
        ]
        let we = makeWorkoutExercise(metValue: 6.0, sets: 2, completedSets: sets)
        let workout = makeWorkout(exercises: [we])
        let weightKg = 70.0

        let calories = calculator.calculate(workout: workout, weightKg: weightKg)

        // durationHours = 120 / 3600
        let expected = max(1, Int((6.0 * 70.0 * (120.0 / 3600.0) * 1.1).rounded()))
        XCTAssertEqual(calories, expected)
    }
}
