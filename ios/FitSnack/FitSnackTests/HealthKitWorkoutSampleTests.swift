import XCTest
@testable import FitSnack

/// Tests the pure HealthKit workout mapping (US-N03): the value type that turns a completed `WorkoutLog`
/// into the workout FitSnack writes to Health. Keeping this HealthKit-free lets the energy estimate, the
/// start/end instants, the activity category, and the idempotency key be verified without a live
/// `HKHealthStore` (which needs the entitlement and a device).
final class HealthKitWorkoutSampleTests: XCTestCase {

    private let completedAt = Date(timeIntervalSinceReferenceDate: 760_000_000)

    // MARK: - Fixtures

    private func makeUser(weightKg: Double = 70) -> User {
        var user = MockPersistence.sampleUser
        user.profile.weightKg = weightKg
        return user
    }

    private func makeLog(
        id: UUID = UUID(),
        durationMinutes: Int = 30,
        focusPillar: Pillar? = nil,
        exercises: [LoggedExercise]
    ) -> WorkoutLog {
        WorkoutLog(
            id: id,
            workoutId: UUID(),
            completedAt: completedAt,
            requestedMinutes: 30,
            durationMinutes: durationMinutes,
            wasReturn: false,
            shape: .blend,
            focusPillar: focusPillar,
            perceivedDifficulty: nil,
            exercises: exercises
        )
    }

    private func worked(_ id: String, pillar: Pillar = .strength, pattern: MovementPattern = .push) -> LoggedExercise {
        LoggedExercise(
            id: UUID(), exerciseId: id, pillar: pillar, movementPattern: pattern,
            completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: false
        )
    }

    // MARK: - Dates & identity

    func testStartIsDerivedFromCompletedAtAndDuration() {
        let log = makeLog(durationMinutes: 20, exercises: [worked("push_up")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: ["push_up": 4])

        XCTAssertEqual(sample.end, completedAt, "the workout ends when the session finished")
        XCTAssertEqual(sample.start, completedAt.addingTimeInterval(-20 * 60), "the workout starts durationMinutes before the finish")
    }

    func testExternalUUIDIsTheLogIdForIdempotency() {
        let id = UUID()
        let log = makeLog(id: id, exercises: [worked("push_up")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: ["push_up": 4])

        XCTAssertEqual(sample.externalUUID, id.uuidString, "the workout carries the log id so a re-write de-duplicates")
    }

    func testZeroDurationIsFlooredAtOneMinute() {
        let log = makeLog(durationMinutes: 0, exercises: [worked("push_up")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: ["push_up": 4])

        XCTAssertEqual(sample.start, completedAt.addingTimeInterval(-60), "a zero-duration log still spans one whole minute")
    }

    // MARK: - Energy (MET x weight x hours)

    func testEnergyUsesMetWeightAndDuration() {
        // MET 6, 70kg, 30 min (0.5h) -> 6 * 70 * 0.5 = 210 kcal.
        let log = makeLog(durationMinutes: 30, exercises: [worked("burpee")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(weightKg: 70), metValuesByExerciseId: ["burpee": 6])

        XCTAssertEqual(sample.energyKilocalories, 210, accuracy: 0.001)
    }

    func testEnergyAveragesWorkedMovementMets() {
        // MET mean of (4, 8) = 6, 70kg, 60 min -> 6 * 70 * 1 = 420 kcal.
        let log = makeLog(durationMinutes: 60, exercises: [worked("a"), worked("b")])
        let sample = HealthKitWorkoutSample.from(
            log: log, user: makeUser(weightKg: 70), metValuesByExerciseId: ["a": 4, "b": 8]
        )

        XCTAssertEqual(sample.energyKilocalories, 420, accuracy: 0.001)
    }

    func testSkippedAndSetlessMovementsAreExcludedFromMet() {
        // Only the worked movement (MET 8) counts; the skipped (MET 100) and set-less (MET 100) drop out,
        // so a movement the user passed on never inflates the estimate. 8 * 70 * 0.5 = 280.
        let skipped = LoggedExercise(
            id: UUID(), exerciseId: "skipped", pillar: .strength, movementPattern: .push,
            completedSets: [CompletedSet(reps: 12, durationSeconds: nil)], skipped: true
        )
        let setless = LoggedExercise(
            id: UUID(), exerciseId: "setless", pillar: .strength, movementPattern: .push,
            completedSets: [], skipped: false
        )
        let log = makeLog(durationMinutes: 30, exercises: [worked("worked"), skipped, setless])
        let sample = HealthKitWorkoutSample.from(
            log: log, user: makeUser(weightKg: 70),
            metValuesByExerciseId: ["worked": 8, "skipped": 100, "setless": 100]
        )

        XCTAssertEqual(sample.energyKilocalories, 280, accuracy: 0.001)
    }

    func testUnresolvedMetsFallBackToDefault() {
        // No MET resolves -> default MET (4), 70kg, 30 min -> 4 * 70 * 0.5 = 140.
        let log = makeLog(durationMinutes: 30, exercises: [worked("unknown")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(weightKg: 70), metValuesByExerciseId: [:])

        XCTAssertEqual(sample.energyKilocalories, HealthKitWorkoutSample.defaultMetValue * 70 * 0.5, accuracy: 0.001)
    }

    func testMissingWeightFallsBackToDefaultWeight() {
        let log = makeLog(durationMinutes: 30, exercises: [worked("a")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(weightKg: 0), metValuesByExerciseId: ["a": 4])

        XCTAssertEqual(sample.energyKilocalories, 4 * HealthKitWorkoutSample.defaultWeightKg * 0.5, accuracy: 0.001)
    }

    func testEnergyIsAlwaysPositive() {
        let log = makeLog(durationMinutes: 1, exercises: [worked("a")])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(weightKg: 0.0001), metValuesByExerciseId: [:])

        XCTAssertGreaterThanOrEqual(sample.energyKilocalories, 1, "energy is floored so a workout never reports a non-positive burn")
    }

    // MARK: - Activity kind

    func testMobilityFocusMapsToFlexibility() {
        let log = makeLog(focusPillar: .mobility, exercises: [worked("stretch", pillar: .mobility)])
        let sample = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: ["stretch": 2])

        XCTAssertEqual(sample.activityKind, .flexibility)
    }

    func testBlendAndStrengthMapToFunctionalStrengthTraining() {
        let blend = makeLog(focusPillar: nil, exercises: [worked("a")])
        let strength = makeLog(focusPillar: .strength, exercises: [worked("a")])

        XCTAssertEqual(
            HealthKitWorkoutSample.from(log: blend, user: makeUser(), metValuesByExerciseId: ["a": 4]).activityKind,
            .functionalStrengthTraining
        )
        XCTAssertEqual(
            HealthKitWorkoutSample.from(log: strength, user: makeUser(), metValuesByExerciseId: ["a": 4]).activityKind,
            .functionalStrengthTraining
        )
    }

    // MARK: - Determinism

    func testDeterministic() {
        let log = makeLog(durationMinutes: 25, exercises: [worked("a"), worked("b")])
        let mets = ["a": 4.0, "b": 7.0]
        let first = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: mets)
        let second = HealthKitWorkoutSample.from(log: log, user: makeUser(), metValuesByExerciseId: mets)

        XCTAssertEqual(first, second)
    }
}
