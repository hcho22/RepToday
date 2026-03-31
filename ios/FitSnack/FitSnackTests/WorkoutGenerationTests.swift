import XCTest
@testable import FitSnack

final class WorkoutGenerationTests: XCTestCase {

    // MARK: - Test Helpers

    private struct MockExerciseService: ExerciseServiceProtocol {
        let exercises: [Exercise]
        func getAllExercises() -> [Exercise] { exercises }
        func getExercise(by id: String) -> Exercise? { exercises.first { $0.id == id } }
        func filterExercises(equipment: [Equipment]?, category: ExerciseCategory?, muscleGroup: MuscleGroup?, difficulty: Int?) -> [Exercise] { exercises }
        func searchExercises(query: String) -> [Exercise] { [] }
    }

    private func makeExercise(
        id: String,
        name: String = "Exercise",
        category: ExerciseCategory = .strength,
        primaryMuscles: [MuscleGroup] = [.chest],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: [Equipment] = [.none],
        difficulty: Int = 1,
        defaultReps: Int? = 10,
        defaultDurationSeconds: Int? = nil,
        defaultSets: Int = 3,
        restBetweenSetsSeconds: Int = 30,
        estimatedTimePerSetSeconds: Int = 15,
        tags: [String] = []
    ) -> Exercise {
        Exercise(
            id: id, name: name, displayName: name,
            description: "", instructions: ["Do the exercise"], commonMistakes: [],
            muscleGroups: Exercise.MuscleGroups(primary: primaryMuscles, secondary: secondaryMuscles),
            movementPattern: .push, category: category, difficulty: difficulty,
            equipment: equipment, isUnilateral: false,
            defaultReps: defaultReps, defaultDurationSeconds: defaultDurationSeconds,
            defaultSets: defaultSets, restBetweenSetsSeconds: restBetweenSetsSeconds,
            estimatedTimePerSetSeconds: estimatedTimePerSetSeconds,
            regressions: [], progressions: [],
            metValue: 5.0, tags: tags
        )
    }

    private func makeProfile(
        equipment: [Equipment] = [.none],
        fitnessLevel: FitnessLevel = .beginner,
        injuries: String = ""
    ) -> UserProfile {
        var profile = UserProfile.empty
        profile.availableEquipment = equipment
        profile.fitnessLevel = fitnessLevel
        profile.injuries = injuries
        return profile
    }

    private func makeTestExercises() -> [Exercise] {
        [
            makeExercise(id: "warmup1", name: "Arm Circles", category: .warmup, primaryMuscles: [.shoulders], defaultReps: nil, defaultDurationSeconds: 30, defaultSets: 1, restBetweenSetsSeconds: 10, estimatedTimePerSetSeconds: 30),
            makeExercise(id: "warmup2", name: "March in Place", category: .warmup, primaryMuscles: [.quads], defaultReps: nil, defaultDurationSeconds: 30, defaultSets: 1, restBetweenSetsSeconds: 10, estimatedTimePerSetSeconds: 30),
            makeExercise(id: "s1", name: "Push-up", primaryMuscles: [.chest], secondaryMuscles: [.triceps]),
            makeExercise(id: "s2", name: "Squat", primaryMuscles: [.quads, .glutes]),
            makeExercise(id: "s3", name: "Plank", primaryMuscles: [.core], defaultReps: nil, defaultDurationSeconds: 30),
            makeExercise(id: "s4", name: "Row", primaryMuscles: [.upperBack], equipment: [.dumbbells]),
            makeExercise(id: "s5", name: "Lunge", primaryMuscles: [.quads, .glutes]),
            makeExercise(id: "s6", name: "Shoulder Press", primaryMuscles: [.shoulders], equipment: [.dumbbells]),
            makeExercise(id: "cardio1", name: "Jumping Jacks", category: .cardio, primaryMuscles: [.quads], defaultReps: nil, defaultDurationSeconds: 30, estimatedTimePerSetSeconds: 30),
            makeExercise(id: "cooldown1", name: "Child's Pose", category: .cooldown, primaryMuscles: [.lowerBack], defaultReps: nil, defaultDurationSeconds: 30, defaultSets: 1, restBetweenSetsSeconds: 5, estimatedTimePerSetSeconds: 30),
        ]
    }

    // MARK: - Tests

    func testGeneratedDurationMatchesRequested() {
        let exercises = makeTestExercises()
        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))
        let profile = makeProfile()

        for duration in [5, 10, 15, 20, 30] {
            let workout = engine.generate(duration: duration, profile: profile)
            XCTAssertEqual(workout.requestedDurationMinutes, duration, "Requested duration should match")

            // Calculate total allocated time from all blocks
            let totalSeconds = allBlocksTime(workout)
            let requestedSeconds = duration * 60
            // The total exercise time should be within roughly the duration budget
            // (exercises fit within the allocated time, which itself is ≤ requested)
            XCTAssertLessThanOrEqual(totalSeconds, requestedSeconds, "Total time should not exceed requested duration for \(duration) min")
        }
    }

    func testWarmupIncludedWhenDurationGreaterThanFive() {
        let exercises = makeTestExercises()
        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))
        let profile = makeProfile()

        let shortWorkout = engine.generate(duration: 5, profile: profile)
        XCTAssertNil(shortWorkout.warmup, "5-min workout should not have warmup")

        let mediumWorkout = engine.generate(duration: 10, profile: profile)
        XCTAssertNotNil(mediumWorkout.warmup, "10-min workout should have warmup")
        XCTAssertEqual(mediumWorkout.warmup?.type, .warmup)

        let longWorkout = engine.generate(duration: 20, profile: profile)
        XCTAssertNotNil(longWorkout.warmup, "20-min workout should have warmup")
    }

    func testExercisesRespectEquipmentFilter() {
        let exercises = makeTestExercises()
        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))

        // Profile with only dumbbells — should only get exercises that use dumbbells or no equipment
        let dumbbellProfile = makeProfile(equipment: [.dumbbells])
        let workout = engine.generate(duration: 15, profile: dumbbellProfile)

        let mainExercises = workout.mainBlocks.flatMap(\.exercises)
        for we in mainExercises {
            let matchesEquipment = we.exercise.equipment.isEmpty ||
                we.exercise.equipment.contains(.dumbbells) ||
                we.exercise.equipment.contains(.none)
            XCTAssertTrue(matchesEquipment, "Exercise \(we.exercise.name) should match available equipment but requires \(we.exercise.equipment)")
        }

        // Verify exercises requiring other equipment (e.g., resistance bands) are excluded
        let hasBandsOnly = mainExercises.contains { we in
            we.exercise.equipment.contains(.resistanceBands) &&
            !we.exercise.equipment.contains(.dumbbells) &&
            !we.exercise.equipment.contains(.none)
        }
        XCTAssertFalse(hasBandsOnly, "Should not include exercises requiring equipment the user doesn't have")
    }

    func testExercisesBalanceMuscleGroups() {
        let exercises = makeTestExercises()
        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))
        let profile = makeProfile()

        let workout = engine.generate(duration: 20, profile: profile)

        // Check that consecutive main blocks don't repeat the same primary muscle group
        let blocks = workout.mainBlocks
        guard blocks.count >= 2 else { return }

        for i in 1..<blocks.count {
            let prevMuscles = Set(blocks[i - 1].exercises.flatMap { $0.exercise.muscleGroups.primary })
            let currMuscles = Set(blocks[i].exercises.flatMap { $0.exercise.muscleGroups.primary })
            // At least some variety — they shouldn't be identical sets
            if !prevMuscles.isEmpty && !currMuscles.isEmpty {
                let overlap = prevMuscles.intersection(currMuscles)
                XCTAssertTrue(overlap.count < prevMuscles.count || overlap.count < currMuscles.count,
                    "Consecutive blocks should have some muscle group variety")
            }
        }
    }

    func testInjuryKeywordsFilterMatchingExercises() {
        let exercises = makeTestExercises()
        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))

        // "chest" injury should exclude push-ups (which target chest)
        let profile = makeProfile(injuries: "chest")
        let workout = engine.generate(duration: 15, profile: profile)

        let allWorkoutExercises = workout.allExercises
        for we in allWorkoutExercises {
            let exerciseText = (we.exercise.name + " " + we.exercise.tags.joined(separator: " ") +
                we.exercise.muscleGroups.primary.map(\.rawValue).joined(separator: " ")).lowercased()
            XCTAssertFalse(exerciseText.contains("chest"),
                "Exercise \(we.exercise.name) should be excluded due to chest injury")
        }
    }

    func testFallbackToBodyweightWhenFiltersTooRestrictive() {
        // Create exercises where all strength/cardio require dumbbells
        let exercises = [
            makeExercise(id: "w1", name: "Arm Circles", category: .warmup, primaryMuscles: [.shoulders], defaultReps: nil, defaultDurationSeconds: 30, defaultSets: 1, restBetweenSetsSeconds: 10, estimatedTimePerSetSeconds: 30),
            makeExercise(id: "d1", name: "DB Press", primaryMuscles: [.chest], equipment: [.dumbbells]),
            makeExercise(id: "d2", name: "DB Row", primaryMuscles: [.upperBack], equipment: [.dumbbells]),
            makeExercise(id: "d3", name: "DB Curl", primaryMuscles: [.biceps], equipment: [.dumbbells]),
            // One bodyweight fallback
            makeExercise(id: "bw1", name: "Bodyweight Squat", primaryMuscles: [.quads], equipment: [.none]),
            makeExercise(id: "bw2", name: "Plank Hold", primaryMuscles: [.core], equipment: [.none]),
        ]

        let engine = WorkoutGenerationEngine(exerciseService: MockExerciseService(exercises: exercises))

        // Profile has resistance bands — no match for dumbbells, so filtered main exercises would be empty
        let profile = makeProfile(equipment: [.resistanceBands])
        let workout = engine.generate(duration: 10, profile: profile)

        // Should still generate a workout (fallback to bodyweight)
        let mainExercises = workout.mainBlocks.flatMap(\.exercises)
        XCTAssertFalse(mainExercises.isEmpty, "Should fallback to bodyweight exercises when filters are too restrictive")

        for we in mainExercises {
            let isBodyweight = we.exercise.equipment.isEmpty || we.exercise.equipment.contains(.none)
            XCTAssertTrue(isBodyweight, "Fallback exercises should be bodyweight")
        }
    }

    // MARK: - Helpers

    private func allBlocksTime(_ workout: Workout) -> Int {
        var total = 0
        if let warmup = workout.warmup {
            total += blockTime(warmup)
        }
        for block in workout.mainBlocks {
            total += blockTime(block)
        }
        if let cooldown = workout.cooldown {
            total += blockTime(cooldown)
        }
        return total
    }

    private func blockTime(_ block: WorkoutBlock) -> Int {
        block.exercises.reduce(0) { acc, we in
            let setTime = we.exercise.estimatedTimePerSetSeconds * we.sets
            let restTime = we.restAfterSeconds * max(0, we.sets - 1)
            return acc + setTime + restTime
        }
    }
}
