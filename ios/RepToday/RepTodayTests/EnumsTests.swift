import XCTest
@testable import RepToday

/// Tests for the canonical domain enums (US-A02).
///
/// These pin every enum's raw value because those raw values are a persistence
/// contract: they are encoded into CoreData / CloudKit, so a rename would silently
/// break already-stored data. The tests fail the moment a documented raw value
/// changes, and prove each enum encodes to / decodes from its exact string.
final class EnumsTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Raw-value stability

    func testPillarRawValues() {
        XCTAssertEqual(Pillar.strength.rawValue, "strength")
        XCTAssertEqual(Pillar.mobility.rawValue, "mobility")
        XCTAssertEqual(Pillar.primal.rawValue, "primal")
        XCTAssertEqual(Pillar.allCases.count, 3)
    }

    func testPhaseRawValues() {
        XCTAssertEqual(Phase.discipline.rawValue, "discipline")
        XCTAssertEqual(Phase.strength.rawValue, "strength")
        XCTAssertEqual(Phase.allCases.count, 2)
    }

    func testMovementPatternRawValues() {
        XCTAssertEqual(MovementPattern.push.rawValue, "push")
        XCTAssertEqual(MovementPattern.squat.rawValue, "squat")
        XCTAssertEqual(MovementPattern.hinge.rawValue, "hinge")
        XCTAssertEqual(MovementPattern.core.rawValue, "core")
        XCTAssertEqual(MovementPattern.pull.rawValue, "pull")
        XCTAssertEqual(MovementPattern.mobility.rawValue, "mobility")
        XCTAssertEqual(MovementPattern.locomotion.rawValue, "locomotion")
        XCTAssertEqual(MovementPattern.allCases.count, 7)
    }

    func testExerciseCategoryRawValues() {
        XCTAssertEqual(ExerciseCategory.strength.rawValue, "strength")
        XCTAssertEqual(ExerciseCategory.mobility.rawValue, "mobility")
        XCTAssertEqual(ExerciseCategory.warmup.rawValue, "warmup")
        XCTAssertEqual(ExerciseCategory.cooldown.rawValue, "cooldown")
        XCTAssertEqual(ExerciseCategory.primal.rawValue, "primal")
        XCTAssertEqual(ExerciseCategory.allCases.count, 5)
    }

    func testEquipmentRawValues() {
        XCTAssertEqual(Equipment.pullUpBar.rawValue, "pull_up_bar")
        XCTAssertEqual(Equipment.resistanceBand.rawValue, "resistance_band")
        XCTAssertEqual(Equipment.dumbbells.rawValue, "dumbbells")
        XCTAssertEqual(Equipment.kettlebell.rawValue, "kettlebell")
        XCTAssertEqual(Equipment.bench.rawValue, "bench")
        XCTAssertEqual(Equipment.allCases.count, 5)
    }

    func testFitnessLevelRawValues() {
        XCTAssertEqual(FitnessLevel.beginner.rawValue, "beginner")
        XCTAssertEqual(FitnessLevel.intermediate.rawValue, "intermediate")
        XCTAssertEqual(FitnessLevel.advanced.rawValue, "advanced")
        XCTAssertEqual(FitnessLevel.allCases.count, 3)
    }

    func testPrimaryGoalRawValues() {
        XCTAssertEqual(PrimaryGoal.stayActive.rawValue, "stay_active")
        XCTAssertEqual(PrimaryGoal.buildStrength.rawValue, "build_strength")
        XCTAssertEqual(PrimaryGoal.increaseEnergy.rawValue, "increase_energy")
        XCTAssertEqual(PrimaryGoal.reduceStress.rawValue, "reduce_stress")
        XCTAssertEqual(PrimaryGoal.loseWeight.rawValue, "lose_weight")
        XCTAssertEqual(PrimaryGoal.allCases.count, 5)
    }

    func testSessionShapeRawValues() {
        XCTAssertEqual(SessionShape.singleFocus.rawValue, "single_focus")
        XCTAssertEqual(SessionShape.blend.rawValue, "blend")
        XCTAssertEqual(SessionShape.allCases.count, 2)
    }

    func testPerceivedDifficultyRawValues() {
        XCTAssertEqual(PerceivedDifficulty.tooEasy.rawValue, "too_easy")
        XCTAssertEqual(PerceivedDifficulty.justRight.rawValue, "just_right")
        XCTAssertEqual(PerceivedDifficulty.tooHard.rawValue, "too_hard")
        XCTAssertEqual(PerceivedDifficulty.allCases.count, 3)
    }

    func testSexRawValues() {
        XCTAssertEqual(Sex.male.rawValue, "male")
        XCTAssertEqual(Sex.female.rawValue, "female")
        XCTAssertEqual(Sex.other.rawValue, "other")
        XCTAssertEqual(Sex.allCases.count, 3)
    }

    func testSubscriptionTierRawValues() {
        XCTAssertEqual(SubscriptionTier.free.rawValue, "free")
        XCTAssertEqual(SubscriptionTier.premium.rawValue, "premium")
        XCTAssertEqual(SubscriptionTier.allCases.count, 2)
    }

    func testSubscriptionProviderRawValues() {
        XCTAssertEqual(SubscriptionProvider.apple.rawValue, "apple")
        XCTAssertEqual(SubscriptionProvider.allCases.count, 1)
    }

    // MARK: - Identifiable

    func testIdentifiableIdMatchesRawValue() {
        XCTAssertEqual(Pillar.mobility.id, "mobility")
        XCTAssertEqual(MovementPattern.locomotion.id, "locomotion")
        XCTAssertEqual(PrimaryGoal.loseWeight.id, "lose_weight")
        XCTAssertEqual(PerceivedDifficulty.tooHard.id, "too_hard")
    }

    // MARK: - Codable round-trips

    /// Encodes every case of every enum and asserts the JSON is exactly the raw-value
    /// string, then decodes it back to the same case. This guarantees the documented
    /// raw values are what actually lands in persisted data.
    func testEveryEnumEncodesToRawValueAndDecodesBack() {
        assertJSONStringRoundTrip(Pillar.allCases)
        assertJSONStringRoundTrip(Phase.allCases)
        assertJSONStringRoundTrip(MovementPattern.allCases)
        assertJSONStringRoundTrip(ExerciseCategory.allCases)
        assertJSONStringRoundTrip(Equipment.allCases)
        assertJSONStringRoundTrip(FitnessLevel.allCases)
        assertJSONStringRoundTrip(PrimaryGoal.allCases)
        assertJSONStringRoundTrip(SessionShape.allCases)
        assertJSONStringRoundTrip(PerceivedDifficulty.allCases)
        assertJSONStringRoundTrip(Sex.allCases)
        assertJSONStringRoundTrip(SubscriptionTier.allCases)
        assertJSONStringRoundTrip(SubscriptionProvider.allCases)
    }

    // MARK: - Helpers

    /// Asserts each value encodes to a JSON string equal to its `rawValue` and decodes
    /// back to the identical case.
    private func assertJSONStringRoundTrip<T>(
        _ values: [T],
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T: Codable & Equatable & RawRepresentable, T.RawValue == String {
        for value in values {
            do {
                let data = try encoder.encode(value)
                let json = String(decoding: data, as: UTF8.self)
                XCTAssertEqual(json, "\"\(value.rawValue)\"", file: file, line: line)

                let decoded = try decoder.decode(T.self, from: data)
                XCTAssertEqual(decoded, value, file: file, line: line)
            } catch {
                XCTFail("Round-trip failed for \(value): \(error)", file: file, line: line)
            }
        }
    }
}
