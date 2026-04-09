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
        XCTAssertEqual(exercises?.count, 142)
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

    // MARK: - US-A03: Expanded Exercise model fields

    func testExerciseNewFieldsDefaultWhenAbsentInJSON() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "Exercises", withExtension: "json")
                ?? Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data) else {
            return
        }
        // Original 30 exercises lack Phase 2 fields — verify they default correctly
        let originalIDs: Set<String> = [
            "push_up", "diamond_push_up", "pike_push_up", "dips_on_chair", "incline_push_up",
            "superman", "bodyweight_squat", "reverse_lunge", "glute_bridge", "step_up",
            "calf_raise", "lateral_lunge", "plank", "dead_bug", "bicycle_crunch",
            "mountain_climber", "hollow_hold", "dumbbell_shoulder_press", "dumbbell_row",
            "dumbbell_curl", "dumbbell_lateral_raise", "goblet_squat", "dumbbell_rdl",
            "dumbbell_split_squat", "arm_circles", "leg_swings", "cat_cow", "childs_pose",
            "standing_quad_stretch", "seated_hamstring_stretch"
        ]
        let originals = exercises.filter { originalIDs.contains($0.id) }
        XCTAssertEqual(originals.count, 30)
        for exercise in originals {
            XCTAssertNil(exercise.progressionChainId)
            XCTAssertNil(exercise.progressionOrder)
            XCTAssertNil(exercise.advancementCriteria)
            XCTAssertNil(exercise.athleteSource)
            XCTAssertEqual(exercise.apartmentFriendly, true, "\(exercise.id) should default apartmentFriendly to true")
        }
    }

    func testExerciseWithNewFieldsRoundtrip() throws {
        let exercise = Exercise(
            id: "prog1", name: "pike_push_up", displayName: "Pike Push-Up",
            description: "Shoulder-dominant push-up", instructions: ["Hinge at hips"], commonMistakes: ["Rounding back"],
            muscleGroups: Exercise.MuscleGroups(primary: [.shoulders], secondary: [.triceps]),
            movementPattern: .pushHorizontal, category: .strength, difficulty: 3,
            equipment: [.none], isUnilateral: false,
            defaultReps: 10, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: 60,
            estimatedTimePerSetSeconds: 25,
            regressions: ["push_up"], progressions: ["handstand_push_up"],
            metValue: 4.0, tags: ["upper body"],
            progressionChainId: "chain_vertical_push",
            progressionOrder: 3,
            advancementCriteria: "3x12 clean reps",
            athleteSource: ["heria", "israetel"],
            apartmentFriendly: false
        )

        let data = try JSONEncoder().encode(exercise)
        let decoded = try JSONDecoder().decode(Exercise.self, from: data)

        XCTAssertEqual(decoded.progressionChainId, "chain_vertical_push")
        XCTAssertEqual(decoded.progressionOrder, 3)
        XCTAssertEqual(decoded.advancementCriteria, "3x12 clean reps")
        XCTAssertEqual(decoded.athleteSource, ["heria", "israetel"])
        XCTAssertEqual(decoded.apartmentFriendly, false)
    }

    func testExerciseMemberwiseInitDefaultsNewFields() {
        let exercise = Exercise(
            id: "ex1", name: "push_up", displayName: "Push Up",
            description: "A push up", instructions: ["Go down"], commonMistakes: ["Sagging"],
            muscleGroups: Exercise.MuscleGroups(primary: [.chest], secondary: [.triceps]),
            movementPattern: .pushHorizontal, category: .strength, difficulty: 2,
            equipment: [.none], isUnilateral: false,
            defaultReps: 12, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: 30,
            estimatedTimePerSetSeconds: 20,
            regressions: [], progressions: [],
            metValue: 3.8, tags: []
        )
        XCTAssertNil(exercise.progressionChainId)
        XCTAssertNil(exercise.progressionOrder)
        XCTAssertNil(exercise.advancementCriteria)
        XCTAssertNil(exercise.athleteSource)
        XCTAssertNil(exercise.apartmentFriendly)
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
            movementPattern: .pushHorizontal, category: .strength, difficulty: 2,
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

    // MARK: - MuscleGroup encode/decode roundtrip

    func testMuscleGroupRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for muscleGroup in MuscleGroup.allCases {
            let data = try encoder.encode(muscleGroup)
            let decoded = try decoder.decode(MuscleGroup.self, from: data)
            XCTAssertEqual(decoded, muscleGroup, "Round-trip failed for \(muscleGroup)")
        }
    }

    func testNewMuscleGroupRawValues() throws {
        XCTAssertEqual(MuscleGroup.wrists.rawValue, "wrists")
        XCTAssertEqual(MuscleGroup.rotatorCuff.rawValue, "rotator_cuff")
        XCTAssertEqual(MuscleGroup.traps.rawValue, "traps")
        XCTAssertEqual(MuscleGroup.erectors.rawValue, "erectors")
    }

    func testNewMuscleGroupDisplayNames() {
        XCTAssertEqual(MuscleGroup.wrists.displayName, "Wrists")
        XCTAssertEqual(MuscleGroup.rotatorCuff.displayName, "Rotator Cuff")
        XCTAssertEqual(MuscleGroup.traps.displayName, "Traps")
        XCTAssertEqual(MuscleGroup.erectors.displayName, "Erectors")
    }

    func testAllBadgesRoundtrip() throws {
        let badges = Badge.allBadges
        let data = try JSONEncoder().encode(badges)
        let decoded = try JSONDecoder().decode([Badge].self, from: data)

        XCTAssertEqual(decoded.count, 10)
        XCTAssertTrue(decoded.allSatisfy { !$0.isUnlocked })
    }

    // MARK: - US-A07: WorkoutTemplate model and JSON

    func testWorkoutTemplatesDecodeFromJSON() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "WorkoutTemplates", withExtension: "json")
                ?? Bundle.main.url(forResource: "WorkoutTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("WorkoutTemplates.json not found in bundle")
            return
        }
        let templates = try? JSONDecoder().decode([WorkoutTemplate].self, from: data)
        XCTAssertNotNil(templates)
        XCTAssertEqual(templates?.count, 6, "Should have exactly 6 workout templates")
    }

    func testWorkoutTemplatesDurationCoverage() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "WorkoutTemplates", withExtension: "json")
                ?? Bundle.main.url(forResource: "WorkoutTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) else {
            return
        }
        let durations = Set(templates.map(\.durationMinutes))
        XCTAssertEqual(durations, [5, 10, 15, 20, 25, 30], "Should cover all 6 duration tiers")
    }

    func testWorkoutTemplatesTimingBudgets() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "WorkoutTemplates", withExtension: "json")
                ?? Bundle.main.url(forResource: "WorkoutTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) else {
            XCTFail("WorkoutTemplates.json not found")
            return
        }
        let tolerance = 30
        for template in templates {
            let targetSeconds = template.durationMinutes * 60
            let estimated = template.estimatedTotalSeconds
            XCTAssertLessThanOrEqual(
                estimated, targetSeconds + tolerance,
                "\(template.name) (\(template.durationMinutes)min): estimated \(estimated)s exceeds \(targetSeconds + tolerance)s"
            )
        }
    }

    func testWorkoutTemplateWarmupCooldownConsistency() {
        guard let url = Bundle(for: type(of: self)).url(forResource: "WorkoutTemplates", withExtension: "json")
                ?? Bundle.main.url(forResource: "WorkoutTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) else {
            return
        }
        for template in templates {
            XCTAssertGreaterThanOrEqual(template.warmupTimeSeconds, 0,
                "\(template.name) warmup should be non-negative")
            XCTAssertGreaterThanOrEqual(template.cooldownTimeSeconds, 0,
                "\(template.name) cooldown should be non-negative")
            if template.durationMinutes <= 10 {
                XCTAssertEqual(template.cooldownTimeSeconds, 0,
                    "\(template.name) (\(template.durationMinutes)min) should have no cooldown")
            }
        }
    }

    func testWorkoutTemplateRoundtrip() throws {
        let block = WorkoutTemplate.BlockDefinition(
            type: .strength, exerciseCount: 2, sets: 3,
            workSeconds: 25, restBetweenSetsSeconds: 45,
            restBetweenExercisesSeconds: 15, rounds: nil, patternCount: 1
        )
        let template = WorkoutTemplate(
            id: "test_template", durationMinutes: 15, name: "Test",
            warmupTimeSeconds: 60, cooldownTimeSeconds: 30,
            blockDefinitions: [block]
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: data)

        XCTAssertEqual(decoded.id, "test_template")
        XCTAssertEqual(decoded.durationMinutes, 15)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.warmupTimeSeconds, 60)
        XCTAssertEqual(decoded.cooldownTimeSeconds, 30)
        XCTAssertEqual(decoded.blockDefinitions.count, 1)
        XCTAssertEqual(decoded.blockDefinitions[0].type, .strength)
        XCTAssertEqual(decoded.blockDefinitions[0].exerciseCount, 2)
        XCTAssertEqual(decoded.blockDefinitions[0].sets, 3)
        XCTAssertEqual(decoded.blockDefinitions[0].workSeconds, 25)
        XCTAssertNil(decoded.blockDefinitions[0].rounds)
        XCTAssertEqual(decoded.blockDefinitions[0].patternCount, 1)
    }

    // MARK: - US-A08: SDUserProfile Phase 2 fields

    func testSDUserProfilePhase2DefaultsFromEmptyProfile() {
        let profile = UserProfile.empty
        let sd = SDUserProfile(from: profile)

        XCTAssertEqual(sd.streakFreezes, 0)
        XCTAssertNil(sd.lastFreezeReplenishDate)
        XCTAssertTrue(sd.getProgressionLevels().isEmpty)
        XCTAssertTrue(sd.getExerciseSkipCounts().isEmpty)
        XCTAssertTrue(sd.getExerciseRatings().isEmpty)
        XCTAssertNil(sd.preferredWorkoutTimeHour)
    }

    func testSDUserProfilePhase2RoundtripViaUserProfile() {
        var profile = UserProfile.empty
        profile.streakFreezes = 2
        profile.lastFreezeReplenishDate = Date(timeIntervalSince1970: 1_700_000_000)
        profile.progressionLevels = ["chain_push": 3, "chain_pull": 1]
        profile.exerciseSkipCounts = ["burpee": 5]
        profile.exerciseRatings = ["push_up": 4, "squat": 5]
        profile.preferredWorkoutTimeHour = 7

        let sd = SDUserProfile(from: profile)
        let restored = sd.toUserProfile()

        XCTAssertEqual(restored.streakFreezes, 2)
        XCTAssertEqual(restored.lastFreezeReplenishDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(restored.progressionLevels, ["chain_push": 3, "chain_pull": 1])
        XCTAssertEqual(restored.exerciseSkipCounts, ["burpee": 5])
        XCTAssertEqual(restored.exerciseRatings, ["push_up": 4, "squat": 5])
        XCTAssertEqual(restored.preferredWorkoutTimeHour, 7)
    }

    func testSDUserProfileUpdateFromSyncsPhase2Fields() {
        let sd = SDUserProfile(from: .empty)
        XCTAssertEqual(sd.streakFreezes, 0)

        var updated = UserProfile.empty
        updated.streakFreezes = 3
        updated.progressionLevels = ["chain_vertical": 2]
        updated.preferredWorkoutTimeHour = 18

        sd.update(from: updated)

        XCTAssertEqual(sd.streakFreezes, 3)
        XCTAssertEqual(sd.getProgressionLevels(), ["chain_vertical": 2])
        XCTAssertEqual(sd.preferredWorkoutTimeHour, 18)
    }

    func testSDUserProfileDictionaryHelpers() {
        let sd = SDUserProfile(from: .empty)

        // Initially empty
        XCTAssertTrue(sd.getProgressionLevels().isEmpty)
        XCTAssertTrue(sd.getExerciseSkipCounts().isEmpty)
        XCTAssertTrue(sd.getExerciseRatings().isEmpty)

        // Set and retrieve
        sd.setProgressionLevels(["a": 1, "b": 2])
        XCTAssertEqual(sd.getProgressionLevels(), ["a": 1, "b": 2])

        sd.setExerciseSkipCounts(["burpee": 4])
        XCTAssertEqual(sd.getExerciseSkipCounts(), ["burpee": 4])

        sd.setExerciseRatings(["squat": 5])
        XCTAssertEqual(sd.getExerciseRatings(), ["squat": 5])

        // Overwrite
        sd.setProgressionLevels([:])
        XCTAssertTrue(sd.getProgressionLevels().isEmpty)
    }

    func testUserProfilePhase2BackwardCompatibleDecoding() throws {
        // Simulate Phase 1 JSON without Phase 2 fields
        let phase1JSON: [String: Any] = [
            "id": "test-id",
            "displayName": "Test",
            "age": 30,
            "sex": "male",
            "heightCm": 170.0,
            "weightKg": 70.0,
            "fitnessLevel": "beginner",
            "primaryGoal": "stay_active",
            "injuries": "",
            "availableEquipment": ["none"],
            "weeklyWorkoutGoal": 3,
            "typicalAvailableMinutes": 15,
            "unitSystem": "imperial",
            "createdAt": 0.0,
            "updatedAt": 0.0
        ]
        let data = try JSONSerialization.data(withJSONObject: phase1JSON)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.streakFreezes, 0)
        XCTAssertNil(decoded.lastFreezeReplenishDate)
        XCTAssertTrue(decoded.progressionLevels.isEmpty)
        XCTAssertTrue(decoded.exerciseSkipCounts.isEmpty)
        XCTAssertTrue(decoded.exerciseRatings.isEmpty)
        XCTAssertNil(decoded.preferredWorkoutTimeHour)
    }

    func testUserProfilePhase2FieldsEncodeDecodeRoundtrip() throws {
        var profile = UserProfile.empty
        profile.streakFreezes = 1
        profile.progressionLevels = ["chain_push": 2]
        profile.exerciseRatings = ["push_up": 5]
        profile.preferredWorkoutTimeHour = 6

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.streakFreezes, 1)
        XCTAssertEqual(decoded.progressionLevels, ["chain_push": 2])
        XCTAssertEqual(decoded.exerciseRatings, ["push_up": 5])
        XCTAssertEqual(decoded.preferredWorkoutTimeHour, 6)
    }
}
