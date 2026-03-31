import XCTest
@testable import FitSnack

final class FitSnackTests: XCTestCase {
    func testEnumsCaseIterable() {
        XCTAssertEqual(FitnessLevel.allCases.count, 3)
        XCTAssertEqual(PrimaryGoal.allCases.count, 5)
        XCTAssertEqual(Equipment.allCases.count, 10)
        XCTAssertEqual(MuscleGroup.allCases.count, 16)
        XCTAssertEqual(MovementPattern.allCases.count, 10)
        XCTAssertEqual(WorkoutStatus.allCases.count, 6)
        XCTAssertEqual(ExerciseCategory.allCases.count, 5)
        XCTAssertEqual(BlockType.allCases.count, 7)
    }
}

final class LevelTests: XCTestCase {
    func testLevelCalculation() {
        XCTAssertEqual(Constants.Level.level(for: 0), 1)
        XCTAssertEqual(Constants.Level.level(for: 100), 2)
        XCTAssertEqual(Constants.Level.level(for: 300), 3)
        XCTAssertEqual(Constants.Level.level(for: 5500), 11)
    }

    func testXPForNextLevel() {
        let result = Constants.Level.xpForNextLevel(currentXP: 150)
        XCTAssertEqual(result.current, 50) // 150 - 100 (level 2 threshold)
        XCTAssertEqual(result.needed, 200) // 300 - 100
    }
}
