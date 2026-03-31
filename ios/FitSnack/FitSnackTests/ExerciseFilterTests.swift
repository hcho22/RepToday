import XCTest
@testable import FitSnack

final class ExerciseFilterTests: XCTestCase {

    // MARK: - Test Helpers

    /// A testable exercise service that exposes the same filter logic as MockExerciseService
    private final class TestableExerciseService: ExerciseServiceProtocol {
        let exercises: [Exercise]

        init(exercises: [Exercise]) {
            self.exercises = exercises
        }

        func getAllExercises() -> [Exercise] { exercises }

        func getExercise(by id: String) -> Exercise? {
            exercises.first { $0.id == id }
        }

        func filterExercises(equipment: [Equipment]?, category: ExerciseCategory?, muscleGroup: MuscleGroup?, difficulty: Int?) -> [Exercise] {
            exercises.filter { exercise in
                if let equipment {
                    let exerciseEquipment = exercise.equipment.isEmpty ? [Equipment.none] : exercise.equipment
                    guard exerciseEquipment.contains(where: { equipment.contains($0) }) else { return false }
                }
                if let category, exercise.category != category { return false }
                if let muscleGroup {
                    guard exercise.muscleGroups.primary.contains(muscleGroup) ||
                          exercise.muscleGroups.secondary.contains(muscleGroup) else { return false }
                }
                if let difficulty, exercise.difficulty > difficulty { return false }
                return true
            }
        }

        func searchExercises(query: String) -> [Exercise] { [] }
    }

    private func makeExercise(
        id: String,
        name: String = "Exercise",
        category: ExerciseCategory = .strength,
        primaryMuscles: [MuscleGroup] = [.chest],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: [Equipment] = [.none],
        difficulty: Int = 1
    ) -> Exercise {
        Exercise(
            id: id, name: name, displayName: name,
            description: "", instructions: ["Do the exercise"], commonMistakes: [],
            muscleGroups: Exercise.MuscleGroups(primary: primaryMuscles, secondary: secondaryMuscles),
            movementPattern: .push, category: category, difficulty: difficulty,
            equipment: equipment, isUnilateral: false,
            defaultReps: 10, defaultDurationSeconds: nil,
            defaultSets: 3, restBetweenSetsSeconds: 30,
            estimatedTimePerSetSeconds: 15,
            regressions: [], progressions: [],
            metValue: 5.0, tags: []
        )
    }

    private func makeTestExercises() -> [Exercise] {
        [
            makeExercise(id: "1", name: "Push-up", category: .strength, primaryMuscles: [.chest], equipment: [.none], difficulty: 1),
            makeExercise(id: "2", name: "Dumbbell Row", category: .strength, primaryMuscles: [.upperBack], secondaryMuscles: [.biceps], equipment: [.dumbbells], difficulty: 2),
            makeExercise(id: "3", name: "Band Pull-apart", category: .strength, primaryMuscles: [.shoulders], equipment: [.resistanceBands], difficulty: 1),
            makeExercise(id: "4", name: "Squat", category: .strength, primaryMuscles: [.quads, .glutes], equipment: [.none], difficulty: 1),
            makeExercise(id: "5", name: "Jumping Jacks", category: .cardio, primaryMuscles: [.quads], equipment: [.none], difficulty: 1),
            makeExercise(id: "6", name: "Kettlebell Swing", category: .cardio, primaryMuscles: [.glutes, .hamstrings], equipment: [.kettlebell], difficulty: 3),
            makeExercise(id: "7", name: "Plank", category: .strength, primaryMuscles: [.core], equipment: [.none], difficulty: 1),
            makeExercise(id: "8", name: "Child's Pose", category: .cooldown, primaryMuscles: [.lowerBack], equipment: [.yogaMat], difficulty: 1),
        ]
    }

    // MARK: - Tests

    func testFilterBySingleEquipmentType() {
        let service = TestableExerciseService(exercises: makeTestExercises())

        let dumbbellExercises = service.filterExercises(equipment: [.dumbbells], category: nil, muscleGroup: nil, difficulty: nil)
        XCTAssertEqual(dumbbellExercises.count, 1)
        XCTAssertEqual(dumbbellExercises.first?.name, "Dumbbell Row")

        let bandExercises = service.filterExercises(equipment: [.resistanceBands], category: nil, muscleGroup: nil, difficulty: nil)
        XCTAssertEqual(bandExercises.count, 1)
        XCTAssertEqual(bandExercises.first?.name, "Band Pull-apart")

        let kettlebellExercises = service.filterExercises(equipment: [.kettlebell], category: nil, muscleGroup: nil, difficulty: nil)
        XCTAssertEqual(kettlebellExercises.count, 1)
        XCTAssertEqual(kettlebellExercises.first?.name, "Kettlebell Swing")

        // Bodyweight (.none) should match all exercises with .none equipment
        let bodyweightExercises = service.filterExercises(equipment: [.none], category: nil, muscleGroup: nil, difficulty: nil)
        let bodyweightNames = Set(bodyweightExercises.map(\.name))
        XCTAssertTrue(bodyweightNames.contains("Push-up"))
        XCTAssertTrue(bodyweightNames.contains("Squat"))
        XCTAssertTrue(bodyweightNames.contains("Jumping Jacks"))
        XCTAssertTrue(bodyweightNames.contains("Plank"))
        XCTAssertFalse(bodyweightNames.contains("Dumbbell Row"))
    }

    func testFilterByMuscleGroup() {
        let service = TestableExerciseService(exercises: makeTestExercises())

        // Primary muscle group
        let chestExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: .chest, difficulty: nil)
        XCTAssertEqual(chestExercises.count, 1)
        XCTAssertEqual(chestExercises.first?.name, "Push-up")

        // Secondary muscle group should also match
        let bicepsExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: .biceps, difficulty: nil)
        XCTAssertEqual(bicepsExercises.count, 1)
        XCTAssertEqual(bicepsExercises.first?.name, "Dumbbell Row")

        // Muscle group present in multiple exercises
        let quadExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: .quads, difficulty: nil)
        let quadNames = Set(quadExercises.map(\.name))
        XCTAssertTrue(quadNames.contains("Squat"))
        XCTAssertTrue(quadNames.contains("Jumping Jacks"))
    }

    func testFilterByDifficultyLevel() {
        let service = TestableExerciseService(exercises: makeTestExercises())

        // Difficulty 1: should include only difficulty <= 1
        let easyExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: nil, difficulty: 1)
        XCTAssertTrue(easyExercises.allSatisfy { $0.difficulty <= 1 })
        XCTAssertEqual(easyExercises.count, 6) // All except DB Row (2) and KB Swing (3)

        // Difficulty 2: should include difficulty <= 2
        let mediumExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: nil, difficulty: 2)
        XCTAssertTrue(mediumExercises.allSatisfy { $0.difficulty <= 2 })
        XCTAssertEqual(mediumExercises.count, 7) // All except KB Swing (3)

        // Difficulty 3: should include all
        let hardExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: nil, difficulty: 3)
        XCTAssertEqual(hardExercises.count, 8)
    }

    func testCombinedFilters() {
        let service = TestableExerciseService(exercises: makeTestExercises())

        // Equipment + category: bodyweight strength exercises
        let bodyweightStrength = service.filterExercises(equipment: [.none], category: .strength, muscleGroup: nil, difficulty: nil)
        let names = Set(bodyweightStrength.map(\.name))
        XCTAssertTrue(names.contains("Push-up"))
        XCTAssertTrue(names.contains("Squat"))
        XCTAssertTrue(names.contains("Plank"))
        XCTAssertFalse(names.contains("Jumping Jacks")) // cardio
        XCTAssertFalse(names.contains("Dumbbell Row")) // requires dumbbells

        // Equipment + muscle group: dumbbell exercises targeting back
        let dumbbellBack = service.filterExercises(equipment: [.dumbbells], category: nil, muscleGroup: .upperBack, difficulty: nil)
        XCTAssertEqual(dumbbellBack.count, 1)
        XCTAssertEqual(dumbbellBack.first?.name, "Dumbbell Row")

        // Equipment + difficulty: bodyweight exercises at difficulty 1
        let easyBodyweight = service.filterExercises(equipment: [.none], category: nil, muscleGroup: nil, difficulty: 1)
        XCTAssertTrue(easyBodyweight.allSatisfy { $0.difficulty <= 1 && $0.equipment.contains(.none) })

        // All filters combined: bodyweight + strength + quads + difficulty 1
        let specific = service.filterExercises(equipment: [.none], category: .strength, muscleGroup: .quads, difficulty: 1)
        XCTAssertEqual(specific.count, 1)
        XCTAssertEqual(specific.first?.name, "Squat")
    }

    func testEmptyResultReturnsEmptyArray() {
        let service = TestableExerciseService(exercises: makeTestExercises())

        // Equipment nobody has
        let benchExercises = service.filterExercises(equipment: [.bench], category: nil, muscleGroup: nil, difficulty: nil)
        XCTAssertTrue(benchExercises.isEmpty)

        // Muscle group not present in any exercise
        let calvesExercises = service.filterExercises(equipment: nil, category: nil, muscleGroup: .calves, difficulty: nil)
        XCTAssertTrue(calvesExercises.isEmpty)

        // Impossible combination: kettlebell + cooldown
        let impossible = service.filterExercises(equipment: [.kettlebell], category: .cooldown, muscleGroup: nil, difficulty: nil)
        XCTAssertTrue(impossible.isEmpty)

        // Empty exercise list
        let emptyService = TestableExerciseService(exercises: [])
        let result = emptyService.filterExercises(equipment: nil, category: nil, muscleGroup: nil, difficulty: nil)
        XCTAssertTrue(result.isEmpty)
    }
}
