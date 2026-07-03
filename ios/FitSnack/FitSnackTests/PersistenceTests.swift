import CoreData
import XCTest
@testable import FitSnack

/// Tests for the CoreData stack and domain conversions (US-A04).
///
/// Each test runs against a fresh in-memory `MockPersistence` stack, so they are isolated
/// and never touch the device store. The contract under test: a saved `User`/`WorkoutLog`
/// reloads byte-for-byte equal (including nested profile/consistency/exercises and
/// optional fields both present and absent), logs are queryable by date range, and a
/// corrupt record fails loudly rather than silently.
final class PersistenceTests: XCTestCase {

    private var controller: PersistenceController!
    private var context: NSManagedObjectContext { controller.viewContext }

    override func setUp() {
        super.setUp()
        controller = MockPersistence.controller()
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    // Fixed, deterministic fixtures so round-trips are exact and reproducible.
    private let dateA = Date(timeIntervalSinceReferenceDate: 700_000)
    private let dateB = Date(timeIntervalSinceReferenceDate: 1_234_567)
    private let uuidA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let uuidB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let uuidC = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    // MARK: - User save / reload

    func testSaveAndReloadUserPreservesAllFields() throws {
        // Fully populated: premium subscription with both dates, injuries present.
        let user = makeUser(
            subscription: Subscription(tier: .premium, provider: .apple, expiresAt: dateA, trialEndsAt: dateB),
            injuries: ["lower_back", "knees"]
        )

        try insert(user)
        let reloaded = try XCTUnwrap(fetchUser(id: user.id)).toUser()

        XCTAssertEqual(reloaded, user)
    }

    func testSaveAndReloadUserMinimalOptionals() throws {
        // Free subscription with nil dates, empty injuries - exercises the absent-optional path.
        let user = makeUser(
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            injuries: []
        )

        try insert(user)
        let reloaded = try XCTUnwrap(fetchUser(id: user.id)).toUser()

        XCTAssertEqual(reloaded, user)
        XCTAssertNil(reloaded.subscription.expiresAt)
        XCTAssertNil(reloaded.subscription.trialEndsAt)
    }

    /// US-D01 validation test: the v6 `why`/`duration`/`coldStart` fields round-trip
    /// identically through the CoreData layer.
    func testSaveAndReloadUserPreservesV6Fields() throws {
        var user = makeUser(
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            injuries: []
        )
        user.why = User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility)
        user.duration = User.Duration(defaultMinutes: 10, onboardingSeedMinutes: 15, completedDurationEWMA: 11.2)
        user.coldStart = User.ColdStart(sessionsLogged: 0, active: true)

        try insert(user)
        let reloaded = try XCTUnwrap(fetchUser(id: user.id)).toUser()

        XCTAssertEqual(reloaded, user)
        XCTAssertEqual(reloaded.why.statement, "get on the floor with my grandkids")
        XCTAssertEqual(reloaded.why.openingBias, .mobility)
        XCTAssertEqual(reloaded.duration.onboardingSeedMinutes, 15)
        XCTAssertTrue(reloaded.coldStart.active)
    }

    /// A pre-v6 record - one whose `why`/`duration`/`coldStart` columns are nil because it
    /// was written before those fields existed - decodes to the documented defaults rather
    /// than crashing: empty `why`, `duration` seeded from `profile.typicalAvailableMinutes`
    /// (so `defaultMinutes == onboardingSeedMinutes`), and a fresh cold-start.
    func testLegacyUserRecordDecodesV6Defaults() throws {
        let user = makeUser(
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            injuries: []
        )
        // profile.typicalAvailableMinutes in the factory is 15.
        let cd = CDUser(context: context)
        try cd.update(from: user)
        // Simulate a legacy record: clear the additive v6 columns.
        cd.whyData = nil
        cd.durationData = nil
        cd.coldStartData = nil

        let reloaded = try cd.toUser()

        XCTAssertEqual(reloaded.why, .empty)
        XCTAssertEqual(reloaded.duration.defaultMinutes, reloaded.duration.onboardingSeedMinutes)
        XCTAssertEqual(reloaded.duration.defaultMinutes, user.profile.typicalAvailableMinutes)
        XCTAssertNil(reloaded.duration.completedDurationEWMA)
        XCTAssertEqual(reloaded.coldStart, .fresh)
        XCTAssertTrue(reloaded.coldStart.active)
        XCTAssertEqual(reloaded.coldStart.sessionsLogged, 0)
    }

    func testUpdatingExistingUserOverwritesInPlace() throws {
        let user = makeUser(
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            injuries: []
        )
        try insert(user)

        // Re-save the same id with a changed score; it must update, not duplicate.
        var updated = user
        updated.consistency.score = 91.5
        updated.phase = .strength
        let existing = try XCTUnwrap(fetchUser(id: user.id))
        try existing.update(from: updated)
        try context.save()

        let all = try context.fetch(CDUser.fetchRequest())
        XCTAssertEqual(all.count, 1, "updating an existing user must not insert a duplicate")
        XCTAssertEqual(try XCTUnwrap(all.first).toUser(), updated)
    }

    // MARK: - WorkoutLog save / reload

    func testSaveAndReloadWorkoutLogWithFeedback() throws {
        let log = makeWorkoutLog(focusPillar: .strength, difficulty: .tooHard, completedAt: dateB)

        try insert(log)
        let reloaded = try XCTUnwrap(fetchAllLogs().first).toWorkoutLog()

        XCTAssertEqual(reloaded, log)
    }

    func testSaveAndReloadWorkoutLogWithoutFeedback() throws {
        // Blend session: nil focusPillar and nil perceivedDifficulty.
        let log = makeWorkoutLog(focusPillar: nil, difficulty: nil, completedAt: dateB)

        try insert(log)
        let reloaded = try XCTUnwrap(fetchAllLogs().first).toWorkoutLog()

        XCTAssertEqual(reloaded, log)
        XCTAssertNil(reloaded.focusPillar)
        XCTAssertNil(reloaded.perceivedDifficulty)
    }

    /// US-D02 validation test: a log requested at 20 min, completed in 12, and served as a
    /// Return round-trips all three fields identically through the CoreData layer.
    func testSaveAndReloadWorkoutLogPreservesV6Fields() throws {
        let log = makeWorkoutLog(
            focusPillar: .strength, difficulty: .tooHard, completedAt: dateB,
            requestedMinutes: 20, durationMinutes: 12, wasReturn: true
        )

        try insert(log)
        let reloaded = try XCTUnwrap(fetchAllLogs().first).toWorkoutLog()

        XCTAssertEqual(reloaded, log)
        XCTAssertEqual(reloaded.requestedMinutes, 20)
        XCTAssertEqual(reloaded.durationMinutes, 12)
        XCTAssertTrue(reloaded.wasReturn)
    }

    /// A pre-v6 log - one whose `requestedMinutes`/`wasReturn` columns are nil because it was
    /// written before those fields existed - decodes to the documented defaults rather than
    /// crashing: `requestedMinutes` falls back to the completed `durationMinutes`, `wasReturn`
    /// to false.
    func testLegacyWorkoutLogRecordDecodesV6Defaults() throws {
        let log = makeWorkoutLog(
            focusPillar: .strength, difficulty: .tooHard, completedAt: dateB,
            requestedMinutes: 20, durationMinutes: 12, wasReturn: true
        )
        let cd = CDWorkoutLog(context: context)
        try cd.update(from: log)
        // Simulate a legacy record: clear the additive v6 columns.
        cd.requestedMinutes = nil
        cd.wasReturn = nil

        let reloaded = try cd.toWorkoutLog()

        XCTAssertEqual(reloaded.requestedMinutes, reloaded.durationMinutes)
        XCTAssertEqual(reloaded.requestedMinutes, 12)
        XCTAssertFalse(reloaded.wasReturn)
    }

    // MARK: - WorkoutLog date-range query

    func testQueryWorkoutLogsByDateRange() throws {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: 600_000_000)
        // Four logs spread across 10 days, inserted out of chronological order.
        let logs = [
            makeWorkoutLog(focusPillar: .mobility, difficulty: nil, completedAt: base + 10 * day, id: uuidA),
            makeWorkoutLog(focusPillar: .strength, difficulty: nil, completedAt: base, id: uuidB),
            makeWorkoutLog(focusPillar: .strength, difficulty: nil, completedAt: base + 2 * day, id: uuidC),
            makeWorkoutLog(focusPillar: .mobility, difficulty: nil, completedAt: base + day,
                           id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        ]
        for log in logs { try insert(log, save: false) }
        try context.save()

        // Half-open window [base + 0.5d, base + 3d): should capture the day+1 and day+2 logs only.
        let request = CDWorkoutLog.fetchRequest(from: base + day / 2, to: base + 3 * day)
        let results = try context.fetch(request).map { try $0.toWorkoutLog() }

        XCTAssertEqual(results.count, 2)
        // Sorted oldest-first by completedAt.
        XCTAssertEqual(results.map(\.completedAt), [base + day, base + 2 * day])
    }

    // MARK: - Loud failure on corrupt records

    func testToUserThrowsWhenRequiredFieldMissing() throws {
        // A bare, unpopulated managed object stands in for a corrupt record.
        let bare = CDUser(context: context)

        XCTAssertThrowsError(try bare.toUser()) { error in
            XCTAssertEqual(error as? PersistenceError, .missingField("CDUser.id"))
        }
    }

    func testToWorkoutLogThrowsOnInvalidEnumRawValue() throws {
        let log = makeWorkoutLog(focusPillar: .strength, difficulty: nil, completedAt: dateB)
        let cd = CDWorkoutLog(context: context)
        try cd.update(from: log)
        cd.shapeRaw = "bogus_shape" // simulate a value written by an incompatible future build

        XCTAssertThrowsError(try cd.toWorkoutLog()) { error in
            XCTAssertEqual(error as? PersistenceError,
                           .invalidEnum(field: "CDWorkoutLog.shapeRaw", value: "bogus_shape"))
        }
    }

    // MARK: - Insert / fetch helpers

    private func insert(_ user: User) throws {
        try CDUser(context: context).update(from: user)
        try context.save()
    }

    private func insert(_ log: WorkoutLog, save: Bool = true) throws {
        try CDWorkoutLog(context: context).update(from: log)
        if save { try context.save() }
    }

    private func fetchUser(id: String) throws -> CDUser? {
        let request = CDUser.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        return try context.fetch(request).first
    }

    private func fetchAllLogs() throws -> [CDWorkoutLog] {
        try context.fetch(CDWorkoutLog.fetchRequest())
    }

    // MARK: - Factories

    private func makeUser(subscription: Subscription, injuries: [String]) -> User {
        User(
            id: "apple-user-abc123",
            displayName: "Riley",
            createdAt: dateA,
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: true, injuries: injuries, typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: subscription,
            consistency: Consistency(
                weeklyGoal: 3, score: 82.5, workoutsThisWeek: 2,
                longestChain: 7, totalWorkoutsCompleted: 41, totalMinutesExercised: 615
            ),
            why: User.Why(statement: "get on the floor with my grandkids", openingBias: .mobility),
            duration: User.Duration(defaultMinutes: 15, onboardingSeedMinutes: 20, completedDurationEWMA: 12.4),
            coldStart: User.ColdStart(sessionsLogged: 3, active: false)
        )
    }

    private func makeWorkoutLog(
        focusPillar: Pillar?,
        difficulty: PerceivedDifficulty?,
        completedAt: Date,
        id: UUID? = nil,
        requestedMinutes: Int = 20,
        durationMinutes: Int = 15,
        wasReturn: Bool = false
    ) -> WorkoutLog {
        WorkoutLog(
            id: id ?? uuidA,
            workoutId: uuidB,
            completedAt: completedAt,
            requestedMinutes: requestedMinutes,
            durationMinutes: durationMinutes,
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
