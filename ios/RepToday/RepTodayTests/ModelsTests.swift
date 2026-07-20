import XCTest
@testable import RepToday

/// Codable / Equatable round-trip tests for the domain model structs (US-A03).
///
/// Every struct must survive a JSON encode/decode with no data loss, including optional
/// fields both present and absent (nil). These structs are the boundary the engine, the
/// views, and the CoreData layer (US-A04, which stores nested fields as JSON `Data`) all
/// share, so a dropped field or a broken decode would silently corrupt persisted data.
final class ModelsTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Fixed, deterministic values so round-trips are exact and reproducible.
    private let dateA = Date(timeIntervalSinceReferenceDate: 700_000)
    private let dateB = Date(timeIntervalSinceReferenceDate: 1_234_567)
    private let uuidA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let uuidB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let uuidC = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    // MARK: - UserProfile

    func testUserProfileRoundTrip() {
        assertRoundTrip(makeProfile(injuries: ["lower_back", "knees"]))
    }

    func testUserProfileRoundTripEmptyInjuries() {
        assertRoundTrip(makeProfile(injuries: []))
    }

    // MARK: - Subscription (optional dates present and absent)

    func testSubscriptionRoundTripWithDates() {
        let sub = Subscription(tier: .premium, provider: .apple, expiresAt: dateA, trialEndsAt: dateB)
        assertRoundTrip(sub)
    }

    func testSubscriptionRoundTripWithoutDates() {
        let sub = Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        assertRoundTrip(sub)
    }

    /// Locks the persistence contract: nil optionals are omitted from JSON (synthesized
    /// `encodeIfPresent`), not written as `null`. A free user's record carries no date keys.
    func testNilOptionalsAreOmittedFromJSON() throws {
        let sub = Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil)
        let json = String(decoding: try encoder.encode(sub), as: UTF8.self)
        XCTAssertFalse(json.contains("expiresAt"))
        XCTAssertFalse(json.contains("trialEndsAt"))
    }

    // MARK: - Consistency

    func testConsistencyRoundTrip() {
        assertRoundTrip(makeConsistency())
    }

    // MARK: - Why / Duration / ColdStart (v6, US-D01)

    func testWhyRoundTripWithBias() {
        assertRoundTrip(User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility))
    }

    func testWhyRoundTripEmpty() {
        assertRoundTrip(User.Why.empty)
    }

    /// A skipped/absent `openingBias` is omitted from JSON, not written as `null` - the same
    /// `encodeIfPresent` contract the `Subscription` dates rely on.
    func testWhyNilBiasOmittedFromJSON() throws {
        let json = String(decoding: try encoder.encode(User.Why.empty), as: UTF8.self)
        XCTAssertFalse(json.contains("openingBias"))
    }

    func testDurationRoundTripWithEWMA() {
        assertRoundTrip(User.Duration(defaultMinutes: 15, onboardingSeedMinutes: 20, completedDurationEWMA: 12.4))
    }

    func testDurationRoundTripWithoutEWMA() {
        // `seeded` leaves `completedDurationEWMA` nil and `defaultMinutes == onboardingSeedMinutes`.
        let duration = User.Duration.seeded(minutes: 15)
        XCTAssertEqual(duration.defaultMinutes, duration.onboardingSeedMinutes)
        XCTAssertNil(duration.completedDurationEWMA)
        assertRoundTrip(duration)
    }

    func testDurationNilEWMAOmittedFromJSON() throws {
        let json = String(decoding: try encoder.encode(User.Duration.seeded(minutes: 15)), as: UTF8.self)
        XCTAssertFalse(json.contains("completedDurationEWMA"))
    }

    func testColdStartRoundTrip() {
        assertRoundTrip(User.ColdStart(sessionsLogged: 3, active: false))
    }

    /// `fresh` is the documented brand-new/legacy default: cold-start active, nothing logged.
    func testColdStartFreshDefault() {
        XCTAssertEqual(User.ColdStart.fresh, User.ColdStart(sessionsLogged: 0, active: true))
    }

    // MARK: - User (nested optionals present and absent)

    func testUserRoundTripFullyPopulated() {
        let user = makeUser(
            subscription: Subscription(tier: .premium, provider: .apple, expiresAt: dateA, trialEndsAt: dateB),
            injuries: ["shoulder"]
        )
        assertRoundTrip(user)
    }

    func testUserRoundTripMinimalOptionals() {
        let user = makeUser(
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            injuries: []
        )
        assertRoundTrip(user)
    }

    // MARK: - Exercise (optional reps/duration + chain links present and absent)

    func testExerciseRoundTripRepBasedMidChain() {
        // Rep-based, middle of a chain: defaultReps set, both regression and progression present.
        assertRoundTrip(makeExercise(isHold: false, hasRegression: true, hasProgression: true))
    }

    func testExerciseRoundTripHoldChainEnds() {
        // Hold, both ends of a chain: defaultDurationSeconds set, regression and progression nil.
        assertRoundTrip(makeExercise(isHold: true, hasRegression: false, hasProgression: false))
    }

    func testExerciseRoundTripWithAnimationName() {
        // US-O01: the optional animationName survives a round-trip when present.
        var ex = makeExercise(isHold: false, hasRegression: true, hasProgression: true)
        ex.animationName = "push_standard"
        assertRoundTrip(ex)
    }

    func testExerciseDecodesWithoutAnimationName() {
        // US-O01: a pre-O01 record (no animationName key) decodes with animationName == nil,
        // so existing Exercises.json and persisted records are backward-compatible.
        let legacy = """
        {
          "id": "push_standard", "displayName": "Standard Push-Up",
          "pillar": "strength", "movementPattern": "push", "category": "strength",
          "difficulty": 2, "phase": "discipline", "equipment": [], "isHold": false,
          "defaultReps": 10, "estimatedTimePerSetSeconds": 45, "metValue": 3.8,
          "progressionChainId": "push", "progressionOrder": 2,
          "advancementCriteria": "3x15 clean reps", "apartmentFriendly": true
        }
        """.data(using: .utf8)!
        do {
            let decoded = try decoder.decode(Exercise.self, from: legacy)
            XCTAssertNil(decoded.animationName)
            XCTAssertEqual(decoded.id, "push_standard")
        } catch {
            XCTFail("legacy Exercise without animationName should decode: \(error)")
        }
    }

    // MARK: - CompletedSet (each optional independently)

    func testCompletedSetRoundTripReps() {
        assertRoundTrip(CompletedSet(reps: 12, durationSeconds: nil))
    }

    func testCompletedSetRoundTripDuration() {
        assertRoundTrip(CompletedSet(reps: nil, durationSeconds: 45))
    }

    // MARK: - PrescribedExercise (rep-based and hold)

    func testPrescribedExerciseRoundTripReps() {
        let pe = PrescribedExercise(
            id: uuidA,
            exercise: makeExercise(isHold: false, hasRegression: true, hasProgression: true),
            sets: 3, reps: 12, durationSeconds: nil, restSeconds: 60
        )
        assertRoundTrip(pe)
    }

    func testPrescribedExerciseRoundTripHold() {
        let pe = PrescribedExercise(
            id: uuidB,
            exercise: makeExercise(isHold: true, hasRegression: false, hasProgression: false),
            sets: 2, reps: nil, durationSeconds: 45, restSeconds: 30
        )
        assertRoundTrip(pe)
    }

    // MARK: - Workout / WorkoutBlock (focusPillar present and absent)

    func testWorkoutRoundTripSingleFocus() {
        assertRoundTrip(makeWorkout(shape: .singleFocus, focusPillar: .mobility))
    }

    func testWorkoutRoundTripBlendNoFocus() {
        assertRoundTrip(makeWorkout(shape: .blend, focusPillar: nil))
    }

    /// The Return flag (US-E06) round-trips, so a persisted/resumed session preserves the decision.
    func testWorkoutRoundTripReturnFlag() {
        assertRoundTrip(makeWorkout(shape: .singleFocus, focusPillar: .mobility, wasReturn: true))
    }

    // MARK: - WorkoutLog / LoggedExercise (optional feedback present and absent)

    func testWorkoutLogRoundTripWithFeedback() {
        assertRoundTrip(makeWorkoutLog(focusPillar: .strength, difficulty: .tooHard))
    }

    func testWorkoutLogRoundTripWithoutFeedback() {
        assertRoundTrip(makeWorkoutLog(focusPillar: nil, difficulty: nil))
    }

    /// US-D02: the requested-vs-completed durations and the `wasReturn` flag survive a
    /// round-trip. Here the session was requested at 20 min, completed at 15, and served as
    /// a Return - the exact shape the Re-entry Ramp and Default Duration learning read back.
    func testWorkoutLogRoundTripReturnWithDurationGap() {
        let log = makeWorkoutLog(
            focusPillar: .strength, difficulty: .tooHard,
            requestedMinutes: 20, wasReturn: true
        )
        XCTAssertEqual(log.requestedMinutes, 20)
        XCTAssertEqual(log.durationMinutes, 15)
        XCTAssertTrue(log.wasReturn)
        assertRoundTrip(log)
    }

    /// `wasReturn` defaults to `false` when omitted, so an ordinary logged session is never
    /// mistaken for a Return.
    func testWorkoutLogWasReturnDefaultsFalse() {
        let log = WorkoutLog(
            id: uuidA, workoutId: uuidB, completedAt: dateB,
            requestedMinutes: 15, durationMinutes: 15,
            shape: .blend, focusPillar: nil, perceivedDifficulty: nil, exercises: []
        )
        XCTAssertFalse(log.wasReturn)
    }

    // MARK: - Round-trip helper

    /// Encodes then decodes `value` and asserts the result equals the original.
    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(T.self, from: data)
            XCTAssertEqual(decoded, value, "round-trip mismatch for \(T.self)", file: file, line: line)
        } catch {
            XCTFail("round-trip threw for \(T.self): \(error)", file: file, line: line)
        }
    }

    // MARK: - Factories

    private func makeProfile(injuries: [String]) -> UserProfile {
        UserProfile(
            age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
            fitnessLevel: .intermediate, primaryGoal: .stayActive,
            sitsLong: true, injuries: injuries, typicalAvailableMinutes: 15
        )
    }

    private func makeConsistency() -> Consistency {
        Consistency(
            weeklyGoal: 3, score: 82.5, workoutsThisWeek: 2,
            longestChain: 7, totalWorkoutsCompleted: 41, totalMinutesExercised: 615
        )
    }

    private func makeUser(subscription: Subscription, injuries: [String]) -> User {
        User(
            id: "apple-user-abc123",
            displayName: "Riley",
            createdAt: dateA,
            profile: makeProfile(injuries: injuries),
            phase: .discipline,
            subscription: subscription,
            consistency: makeConsistency(),
            why: User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility),
            duration: User.Duration(defaultMinutes: 15, onboardingSeedMinutes: 20, completedDurationEWMA: 12.4),
            coldStart: User.ColdStart(sessionsLogged: 3, active: false)
        )
    }

    private func makeExercise(isHold: Bool, hasRegression: Bool, hasProgression: Bool) -> Exercise {
        Exercise(
            id: "push_standard",
            displayName: "Standard Push-Up",
            pillar: .strength,
            movementPattern: .push,
            category: .strength,
            difficulty: 2,
            phase: .discipline,
            equipment: [],
            isHold: isHold,
            defaultReps: isHold ? nil : 10,
            defaultDurationSeconds: isHold ? 30 : nil,
            estimatedTimePerSetSeconds: 45,
            metValue: 3.8,
            progressionChainId: "push",
            progressionOrder: 2,
            regressionId: hasRegression ? "push_knee" : nil,
            progressionId: hasProgression ? "push_decline" : nil,
            advancementCriteria: "3x15 clean reps",
            apartmentFriendly: true
        )
    }

    private func makeWorkout(shape: SessionShape, focusPillar: Pillar?, wasReturn: Bool = false) -> Workout {
        let warmup = WorkoutBlock(
            id: uuidA, title: "Warm-up", category: .warmup,
            exercises: [PrescribedExercise(
                id: uuidB,
                exercise: makeExercise(isHold: true, hasRegression: false, hasProgression: false),
                sets: 1, reps: nil, durationSeconds: 30, restSeconds: 0
            )]
        )
        let main = WorkoutBlock(
            id: uuidC, title: "Strength", category: .strength,
            exercises: [PrescribedExercise(
                id: uuidA,
                exercise: makeExercise(isHold: false, hasRegression: true, hasProgression: true),
                sets: 3, reps: 10, durationSeconds: nil, restSeconds: 60
            )]
        )
        return Workout(
            id: uuidC, createdAt: dateA, shape: shape,
            focusPillar: focusPillar, requestedMinutes: 15, wasReturn: wasReturn, blocks: [warmup, main]
        )
    }

    private func makeWorkoutLog(
        focusPillar: Pillar?,
        difficulty: PerceivedDifficulty?,
        requestedMinutes: Int = 20,
        wasReturn: Bool = false
    ) -> WorkoutLog {
        WorkoutLog(
            id: uuidA,
            workoutId: uuidB,
            completedAt: dateB,
            requestedMinutes: requestedMinutes,
            durationMinutes: 15,
            wasReturn: wasReturn,
            shape: focusPillar == nil ? .blend : .singleFocus,
            focusPillar: focusPillar,
            perceivedDifficulty: difficulty,
            exercises: [
                LoggedExercise(
                    id: uuidC, exerciseId: "push_standard",
                    pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil),
                                    CompletedSet(reps: 8, durationSeconds: nil)],
                    skipped: false
                ),
                LoggedExercise(
                    id: uuidA, exerciseId: "deep_squat_hold",
                    pillar: .mobility, movementPattern: .mobility,
                    completedSets: [CompletedSet(reps: nil, durationSeconds: 30)],
                    skipped: true
                )
            ]
        )
    }
}
