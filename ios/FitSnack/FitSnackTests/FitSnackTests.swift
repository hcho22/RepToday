import XCTest
@testable import FitSnack

final class FitSnackTests: XCTestCase {
    func testEnumsCaseIterable() {
        XCTAssertEqual(FitnessLevel.allCases.count, 3)
        XCTAssertEqual(PrimaryGoal.allCases.count, 5)
        XCTAssertEqual(Equipment.allCases.count, 20)
        XCTAssertEqual(MuscleGroup.allCases.count, 20)
        XCTAssertEqual(MovementPattern.allCases.count, 15)
        XCTAssertEqual(WorkoutStatus.allCases.count, 6)
        XCTAssertEqual(ExerciseCategory.allCases.count, 5)
        XCTAssertEqual(BlockType.allCases.count, 7)
    }
}

final class MovementPatternTests: XCTestCase {

    // MARK: - Display names

    func testDisplayNames() {
        XCTAssertEqual(MovementPattern.pushHorizontal.displayName, "Push (Horizontal)")
        XCTAssertEqual(MovementPattern.pushVertical.displayName, "Push (Vertical)")
        XCTAssertEqual(MovementPattern.pullVertical.displayName, "Pull (Vertical)")
        XCTAssertEqual(MovementPattern.pullHorizontal.displayName, "Pull (Horizontal)")
        XCTAssertEqual(MovementPattern.coreAntiExtension.displayName, "Core (Anti-Extension)")
        XCTAssertEqual(MovementPattern.coreFlexion.displayName, "Core (Flexion)")
        XCTAssertEqual(MovementPattern.coreRotation.displayName, "Core (Rotation)")
        XCTAssertEqual(MovementPattern.coreCompression.displayName, "Core (Compression)")
        XCTAssertEqual(MovementPattern.primal.displayName, "Primal")
    }

    // MARK: - Focus group mapping

    func testFocusGroups() {
        XCTAssertEqual(MovementPattern.pushHorizontal.focusGroup, .push)
        XCTAssertEqual(MovementPattern.pushVertical.focusGroup, .push)
        XCTAssertEqual(MovementPattern.pullVertical.focusGroup, .pull)
        XCTAssertEqual(MovementPattern.pullHorizontal.focusGroup, .pull)
        XCTAssertEqual(MovementPattern.squat.focusGroup, .squat)
        XCTAssertEqual(MovementPattern.hinge.focusGroup, .hinge)
        XCTAssertEqual(MovementPattern.lunge.focusGroup, .hinge)
        XCTAssertEqual(MovementPattern.carry.focusGroup, .core)
        XCTAssertEqual(MovementPattern.coreAntiExtension.focusGroup, .core)
        XCTAssertEqual(MovementPattern.coreFlexion.focusGroup, .core)
        XCTAssertEqual(MovementPattern.coreRotation.focusGroup, .core)
        XCTAssertEqual(MovementPattern.coreCompression.focusGroup, .core)
        XCTAssertEqual(MovementPattern.cardio.focusGroup, .cardio)
        XCTAssertEqual(MovementPattern.mobility.focusGroup, .mobility)
        XCTAssertEqual(MovementPattern.primal.focusGroup, .mobility)
    }

    // MARK: - Backward-compatible decoding of old Phase 1 raw values

    func testDecodesOldPushValue() throws {
        let json = Data(#""push""#.utf8)
        let decoded = try JSONDecoder().decode(MovementPattern.self, from: json)
        XCTAssertEqual(decoded, .pushHorizontal)
    }

    func testDecodesOldPullValue() throws {
        let json = Data(#""pull""#.utf8)
        let decoded = try JSONDecoder().decode(MovementPattern.self, from: json)
        XCTAssertEqual(decoded, .pullHorizontal)
    }

    func testDecodesOldCoreValue() throws {
        let json = Data(#""core""#.utf8)
        let decoded = try JSONDecoder().decode(MovementPattern.self, from: json)
        XCTAssertEqual(decoded, .coreFlexion)
    }

    func testDecodesOldPlankValue() throws {
        let json = Data(#""plank""#.utf8)
        let decoded = try JSONDecoder().decode(MovementPattern.self, from: json)
        XCTAssertEqual(decoded, .coreAntiExtension)
    }

    func testDecodesOldRotationValue() throws {
        let json = Data(#""rotation""#.utf8)
        let decoded = try JSONDecoder().decode(MovementPattern.self, from: json)
        XCTAssertEqual(decoded, .coreRotation)
    }

    func testDecodesNewRawValues() throws {
        let decoder = JSONDecoder()
        for pattern in MovementPattern.allCases {
            let json = Data("\"\(pattern.rawValue)\"".utf8)
            let decoded = try decoder.decode(MovementPattern.self, from: json)
            XCTAssertEqual(decoded, pattern, "Round-trip failed for \(pattern)")
        }
    }

    func testDecodesUnknownValueThrows() {
        let json = Data(#""unknown_pattern""#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MovementPattern.self, from: json))
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
