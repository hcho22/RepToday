import XCTest
@testable import FitSnack

final class ModelCodingTests: XCTestCase {

    // MARK: - Exercise decodes from Exercises.json

    func testExerciseDecodesFromJSON() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "Exercises", withExtension: "json")
                ?? Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return // Skip if bundle doesn't contain exercises in test target
        }
        let exercises = try? JSONDecoder().decode([Exercise].self, from: data)
        XCTAssertNotNil(exercises)
        XCTAssertEqual(exercises?.count, 30)
    }

    func testExerciseDecodedFieldsAreValid() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "Exercises", withExtension: "json")
                ?? Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data),
              let first = exercises.first else {
            return
        }
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertFalse(first.displayName.isEmpty)
        XCTAssertGreaterThan(first.metValue, 0)
        XCTAssertGreaterThan(first.defaultSets, 0)
        XCTAssertFalse(first.muscleGroups.primary.isEmpty)
    }

    // MARK: - UserProfile encode/decode roundtrip

    func testUserProfileRoundtrip() throws {
        var profile = UserProfile.empty
        profile.displayName = "Test User"
        profile.fitnessLevel = .intermediate
        profile.primaryGoal = .buildMuscle
        profile.availableEquipment = [.dumbbells, .resistanceBands]
        profile.weeklyWorkoutGoal = 4
        profile.typicalAvailableMinutes = 20

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.displayName, "Test User")
        XCTAssertEqual(decoded.fitnessLevel, .intermediate)
        XCTAssertEqual(decoded.primaryGoal, .buildMuscle)
        XCTAssertEqual(decoded.availableEquipment, [.dumbbells, .resistanceBands])
        XCTAssertEqual(decoded.weeklyWorkoutGoal, 4)
        XCTAssertEqual(decoded.typicalAvailableMinutes, 20)
    }

    func testUserProfileEmptyRoundtrip() throws {
        let profile = UserProfile.empty
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.fitnessLevel, .beginner)
    }

    // MARK: - Workout encode/decode roundtrip (nested blocks/exercises/setLogs)

    func testWorkoutRoundtripWithNestedData() throws {
        let exercise = Exercise(
            id: "ex1", name: "push_up", displayName: "Push Up",
            description: "A push up", instructions: ["Go down", "Push up"], commonMistakes: ["Sagging hips"],
            muscleGroups: Exercise.MuscleGroups(primary: [.chest], secondary: [.triceps]),
            movementPattern: .push, category: .strength, difficulty: 2,
            equipment: [.none], isUnilateral: false,
            defaultReps: 12, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: 30,
            estimatedTimePerSetSeconds: 20,
            regressions: ["knee_push_up"], progressions: ["diamond_push_up"],
            metValue: 3.8, tags: ["upper body"]
        )

        let setLogs = [
            SetLog(setNumber: 1, completed: true, reps: 12, weight: nil, durationSeconds: nil, completedAt: Date()),
            SetLog(setNumber: 2, completed: true, reps: 10, weight: nil, durationSeconds: nil, completedAt: Date().addingTimeInterval(60)),
        ]

        let workoutExercise = WorkoutExercise(
            id: "we1", exerciseId: "ex1", exercise: exercise,
            sets: 3, reps: 12, durationSeconds: nil,
            restAfterSeconds: 30, notes: "Keep core tight",
            completedSets: setLogs, skipped: false
        )

        let warmupExercise = WorkoutExercise(
            id: "we0", exerciseId: "ex1", exercise: exercise,
            sets: 1, reps: nil, durationSeconds: 30,
            restAfterSeconds: 10, notes: nil,
            completedSets: [], skipped: false
        )

        let warmup = WorkoutBlock(
            id: "warmup1", name: "Warm Up", type: .warmup,
            exercises: [warmupExercise], restBetweenExercisesSeconds: 10
        )

        let mainBlock = WorkoutBlock(
            id: "main1", name: "Strength", type: .strength,
            exercises: [workoutExercise], restBetweenExercisesSeconds: 30
        )

        let workout = Workout(
            id: "w1", userId: "u1", createdAt: Date(),
            requestedDurationMinutes: 15,
            warmup: warmup,
            mainBlocks: [mainBlock],
            cooldown: nil,
            status: .completed,
            startedAt: Date(),
            completedAt: Date().addingTimeInterval(900),
            actualDurationMinutes: 15,
            estimatedCalories: 80,
            actualCalories: 75,
            userRating: 4,
            perceivedDifficulty: .justRight,
            xpEarned: 50,
            muscleGroupsWorked: ["chest": "primary"],
            focusAreas: ["upper body"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(workout)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        // Top-level fields
        XCTAssertEqual(decoded.id, "w1")
        XCTAssertEqual(decoded.userId, "u1")
        XCTAssertEqual(decoded.requestedDurationMinutes, 15)
        XCTAssertEqual(decoded.status, .completed)
        XCTAssertEqual(decoded.actualDurationMinutes, 15)
        XCTAssertEqual(decoded.estimatedCalories, 80)
        XCTAssertEqual(decoded.actualCalories, 75)
        XCTAssertEqual(decoded.userRating, 4)
        XCTAssertEqual(decoded.perceivedDifficulty, .justRight)
        XCTAssertEqual(decoded.xpEarned, 50)
        XCTAssertEqual(decoded.focusAreas, ["upper body"])

        // Warmup block
        XCTAssertNotNil(decoded.warmup)
        XCTAssertEqual(decoded.warmup?.type, .warmup)
        XCTAssertEqual(decoded.warmup?.exercises.count, 1)

        // Main block exercises
        XCTAssertEqual(decoded.mainBlocks.count, 1)
        let decodedExercise = decoded.mainBlocks[0].exercises[0]
        XCTAssertEqual(decodedExercise.exercise.displayName, "Push Up")
        XCTAssertEqual(decodedExercise.exercise.metValue, 3.8)
        XCTAssertEqual(decodedExercise.notes, "Keep core tight")

        // SetLogs
        XCTAssertEqual(decodedExercise.completedSets.count, 2)
        XCTAssertEqual(decodedExercise.completedSets[0].reps, 12)
        XCTAssertEqual(decodedExercise.completedSets[1].reps, 10)
        XCTAssertTrue(decodedExercise.completedSets[0].completed)

        // Cooldown nil
        XCTAssertNil(decoded.cooldown)

        // Computed property still works
        XCTAssertEqual(decoded.allExercises.count, 2) // warmup + main
    }

    func testWorkoutMinimalRoundtrip() throws {
        let workout = Workout(
            id: "w2", userId: "u1", createdAt: Date(),
            requestedDurationMinutes: 5,
            mainBlocks: [],
            status: .generated,
            muscleGroupsWorked: [:], focusAreas: []
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        XCTAssertEqual(decoded.id, "w2")
        XCTAssertEqual(decoded.status, .generated)
        XCTAssertNil(decoded.warmup)
        XCTAssertNil(decoded.cooldown)
        XCTAssertTrue(decoded.mainBlocks.isEmpty)
    }

    // MARK: - Badge encode/decode roundtrip

    func testBadgeRoundtrip() throws {
        var badge = Badge(
            id: "first_rep", name: "First Rep",
            description: "Complete your first workout",
            iconName: "star.fill", isUnlocked: true,
            unlockedAt: Date(), criteria: "Complete 1 workout"
        )

        let data = try JSONEncoder().encode(badge)
        let decoded = try JSONDecoder().decode(Badge.self, from: data)

        XCTAssertEqual(decoded.id, "first_rep")
        XCTAssertEqual(decoded.name, "First Rep")
        XCTAssertEqual(decoded.iconName, "star.fill")
        XCTAssertTrue(decoded.isUnlocked)
        XCTAssertNotNil(decoded.unlockedAt)
        XCTAssertEqual(decoded.criteria, "Complete 1 workout")
    }

    func testBadgeLockedRoundtrip() throws {
        let badge = Badge(
            id: "centurion", name: "Centurion",
            description: "Complete 100 total workouts",
            iconName: "100.circle.fill", isUnlocked: false,
            unlockedAt: nil, criteria: "Accumulate 100 completed workouts"
        )

        let data = try JSONEncoder().encode(badge)
        let decoded = try JSONDecoder().decode(Badge.self, from: data)

        XCTAssertEqual(decoded.id, "centurion")
        XCTAssertFalse(decoded.isUnlocked)
        XCTAssertNil(decoded.unlockedAt)
    }

    func testAllBadgesRoundtrip() throws {
        let badges = Badge.allBadges
        let data = try JSONEncoder().encode(badges)
        let decoded = try JSONDecoder().decode([Badge].self, from: data)

        XCTAssertEqual(decoded.count, 10)
        XCTAssertTrue(decoded.allSatisfy { !$0.isUnlocked })
    }
}
