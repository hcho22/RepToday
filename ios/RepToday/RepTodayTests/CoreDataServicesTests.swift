import CoreData
import XCTest
@testable import RepToday

/// Tests for the CoreData-backed `UserServiceProtocol`/`WorkoutLogServiceProtocol` and the
/// production `ServiceContainer.live(...)` wiring (US-N02).
///
/// Each test runs against a fresh in-memory `MockPersistence` stack (the single-store,
/// CloudKit-free test path), so they stay isolated and never touch the device store or iCloud.
/// The contract: a saved user/log reloads equal, re-saving overwrites in place (never
/// duplicates), logs are queryable by date range, deletes clear, and the production container
/// composes those CoreData services so a write through one is read back through another.
///
/// The two container tests want that CoreData wiring and nothing else, but building the production
/// container is also what wires the live telemetry transport (US-T04), so they pass
/// `NoOpAnalyticsService` through the factory's sink parameter. That is what keeps them off the
/// network now that US-T07 through US-T12 have added the emission call sites, rather than leaving it to the
/// fact that none exist (FR-13) - a guarantee that covers in-process tests like these ones, not
/// the out-of-process `RepTodayUITests` launches, which US-T06's persisted opt-out flag closes.
final class CoreDataServicesTests: XCTestCase {

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

    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    // MARK: - CoreDataUserService

    func testUserServiceSaveAndReadBack() async throws {
        let service = CoreDataUserService(context: context)
        let before = try await service.currentUser()
        XCTAssertNil(before, "no user before any save")

        let user = makeUser(id: "apple-user-1", score: 70)
        try await service.save(user)

        let reloaded = try await service.currentUser()
        XCTAssertEqual(reloaded, user)
    }

    func testUserServiceSaveOverwritesInPlace() async throws {
        let service = CoreDataUserService(context: context)
        let user = makeUser(id: "apple-user-1", score: 70)
        try await service.save(user)

        var updated = user
        updated.consistency.score = 88.5
        try await service.save(updated)

        // The upsert keys on `id`, so re-saving replaces rather than accumulating.
        let all = try context.fetch(CDUser.fetchRequest())
        XCTAssertEqual(all.count, 1)
        let reloaded = try await service.currentUser()
        XCTAssertEqual(reloaded, updated)
    }

    func testUserServiceDeleteClearsUser() async throws {
        let service = CoreDataUserService(context: context)
        try await service.save(makeUser(id: "apple-user-1", score: 70))

        try await service.deleteCurrentUser()

        let after = try await service.currentUser()
        XCTAssertNil(after)
        XCTAssertTrue(try context.fetch(CDUser.fetchRequest()).isEmpty)
    }

    // MARK: - CoreDataWorkoutLogService

    func testWorkoutLogServiceSaveAndReadBack() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        let before = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(before.isEmpty)

        let log = makeLog(completedAt: base)
        try await service.save(log)

        let reloaded = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(reloaded, [log])
    }

    func testWorkoutLogServiceSaveOverwritesInPlaceById() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        let log = makeLog(completedAt: base)
        try await service.save(log)

        // Re-saving the same id (e.g. the US-L02 rating update) overwrites, never duplicates.
        var rated = log
        rated.perceivedDifficulty = .tooHard
        try await service.save(rated)

        let all = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.perceivedDifficulty, .tooHard)
    }

    func testWorkoutLogServiceDateRangeQueryIsHalfOpenAndSorted() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        // Four logs across 10 days, saved out of order.
        for offset in [10.0, 0.0, 2.0, 1.0] {
            try await service.save(makeLog(completedAt: base + offset * day, id: UUID()))
        }

        // [base + 0.5d, base + 3d): captures the day+1 and day+2 logs only, oldest first.
        let results = try await service.workoutLogs(from: base + day / 2, to: base + 3 * day)
        XCTAssertEqual(results.map(\.completedAt), [base + day, base + 2 * day])
    }

    func testWorkoutLogServiceDeleteById() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        let keep = makeLog(completedAt: base, id: UUID())
        let drop = makeLog(completedAt: base + day, id: UUID())
        try await service.save(keep)
        try await service.save(drop)

        try await service.deleteLog(id: drop.id)

        let remaining = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(remaining.map(\.id), [keep.id])
    }

    // MARK: - US-AD02 bulk deletes (account deletion)

    func testWorkoutLogServiceDeleteAllLogsClearsWholeHistory() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        for offset in [0.0, 1.0, 2.0] {
            try await service.save(makeLog(completedAt: base + offset * day, id: UUID()))
        }

        // The single-user app has no owner column, so account deletion clears everything.
        try await service.deleteAllLogs(for: "apple-user-1")

        let remaining = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(try context.fetch(CDWorkoutLog.fetchRequest()).isEmpty)
    }

    func testWorkoutLogServiceDeleteAllLogsOnEmptyHistoryIsANoOp() async throws {
        let service = CoreDataWorkoutLogService(context: context)
        // No logs saved: deleting must not throw and must leave the store empty.
        try await service.deleteAllLogs(for: "apple-user-1")
        let remaining = try await service.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSessionPolicyStoreDeleteClearsThePolicy() async throws {
        let store = CoreDataSessionPolicyStore(context: context)
        try await store.save(.default, for: "apple-user-1")
        let stored = try await store.policy(for: "apple-user-1")
        XCTAssertNotNil(stored)

        try await store.delete(for: "apple-user-1")

        let cleared = try await store.policy(for: "apple-user-1")
        XCTAssertNil(cleared)
        XCTAssertTrue(try context.fetch(CDSessionPolicy.fetchRequest()).isEmpty)
    }

    func testSessionPolicyStoreDeleteWithNoStoredPolicyIsANoOp() async throws {
        let store = CoreDataSessionPolicyStore(context: context)
        // Nothing stored for this user: deleting must not throw.
        try await store.delete(for: "apple-user-1")
        let cleared = try await store.policy(for: "apple-user-1")
        XCTAssertNil(cleared)
    }

    func testSessionPolicyStoreDeleteAllClearsEveryRecord() async throws {
        let store = CoreDataSessionPolicyStore(context: context)
        try await store.save(.default, for: "apple-user-1")
        let stored = try await store.policy(for: "apple-user-1")
        XCTAssertNotNil(stored)

        // Account deletion clears the policy wholesale, with no user id to key it off.
        try await store.deleteAll()

        let cleared = try await store.policy(for: "apple-user-1")
        XCTAssertNil(cleared)
        XCTAssertTrue(try context.fetch(CDSessionPolicy.fetchRequest()).isEmpty)
    }

    func testSessionPolicyStoreDeleteAllOnEmptyStoreIsANoOp() async throws {
        let store = CoreDataSessionPolicyStore(context: context)
        // Nothing stored: deleting wholesale must not throw and leaves the store empty.
        try await store.deleteAll()
        XCTAssertTrue(try context.fetch(CDSessionPolicy.fetchRequest()).isEmpty)
    }

    // MARK: - Production container wiring

    /// The production container composes the CoreData-backed services over one shared context, so
    /// a user and log written through it read back through it - proving `live(...)` wires the
    /// same on-device (and synced) history everyone reads.
    func testLiveContainerComposesCoreDataServices() async throws {
        let services = ServiceContainer.live(
            context: context,
            installId: "test-install",
            analyticsService: NoOpAnalyticsService()
        )

        let user = makeUser(id: "apple-user-1", score: 70)
        try await services.userService.save(user)
        let reloadedUser = try await services.userService.currentUser()
        XCTAssertEqual(reloadedUser, user)

        let log = makeLog(completedAt: base)
        try await services.workoutLogService.save(log)
        let reloadedLogs = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(reloadedLogs, [log])

        // The policy service returns the always-valid default until a policy is written, and a
        // fresh user has no due triggers - the CoreData policy store composes like the in-memory one.
        let policy = try await services.sessionPolicyService.currentPolicy(for: user)
        XCTAssertEqual(policy, .default)
        let triggers = try await services.sessionPolicyService.dueTriggers(user: user, recentLogs: [], asOf: base)
        XCTAssertTrue(triggers.isEmpty)
    }

    /// The completion recorder wired into the production container writes a durable log through
    /// the CoreData log service (the US-L01 loop, now cross-launch persistent, US-N02).
    func testLiveContainerCompletionRecorderWritesDurableLog() async throws {
        // The completion recorder now emits `week_active` (US-T11), whose persisted emit-once set lives
        // in `.standard` on the production path; restore it so this test does not leak the key.
        restoreAfterTest(SessionCompletionService.weekActiveEmittedWeeksKey)
        let services = ServiceContainer.live(
            context: context,
            installId: "test-install",
            analyticsService: NoOpAnalyticsService()
        )
        let user = makeUser(id: "apple-user-1", score: 70)
        try await services.userService.save(user)

        let log = makeLog(completedAt: base)
        try await services.sessionCompletionService.recordCompletedSession(log, user: user, recentLogs: [])

        let reloaded = try await services.workoutLogService.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(reloaded.map(\.id), [log.id])
    }

    // MARK: - Factories

    private func makeUser(id: String, score: Double) -> User {
        User(
            id: id,
            displayName: "Riley",
            createdAt: base,
            profile: UserProfile(
                age: 34, sex: .female, heightCm: 168.5, weightKg: 62.0,
                fitnessLevel: .intermediate, primaryGoal: .stayActive,
                sitsLong: true, injuries: [], typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: score, workoutsThisWeek: 2,
                longestChain: 4, totalWorkoutsCompleted: 20, totalMinutesExercised: 300
            ),
            why: User.Why(statement: "move more", openingBias: nil),
            duration: User.Duration(defaultMinutes: 15, onboardingSeedMinutes: 15, completedDurationEWMA: nil),
            coldStart: .fresh
        )
    }

    private func makeLog(completedAt: Date, id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!) -> WorkoutLog {
        WorkoutLog(
            id: id,
            workoutId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            completedAt: completedAt,
            requestedMinutes: 15,
            durationMinutes: 15,
            wasReturn: false,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    exerciseId: "push_standard",
                    pillar: .strength, movementPattern: .push,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: false
                )
            ]
        )
    }
}
