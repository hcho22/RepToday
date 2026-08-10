import XCTest
@testable import RepToday

/// Tests for the account-deletion teardown (US-AD02 bulk deletes exercised through the test doubles,
/// US-AD03 orchestration) - the App Store 5.1.1(v) deletion path.
///
/// The orchestration is exercised over the in-memory doubles (`MockUserService`,
/// `MockWorkoutLogService`, `InMemorySessionPolicyStore`, `InMemoryActiveSessionStore`,
/// `MockAuthService`) plus a real `AppState` on an isolated `UserDefaults` suite, so it asserts the
/// full sequence - every store cleared, the Keychain seam cleared, and routing reset - without a
/// CoreData stack. The CoreData bulk deletes themselves are covered in `CoreDataServicesTests`.
final class AccountDeletionServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AccountDeletionServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - US-AD02 mock/test-double bulk deletes

    func testMockWorkoutLogServiceDeleteAllLogsClearsHistory() async throws {
        let logs = MockWorkoutLogService(logs: [makeLog(), makeLog(), makeLog()])
        try await logs.deleteAllLogs()
        let remaining = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMockWorkoutLogServiceDeleteAllLogsOnEmptyIsANoOp() async throws {
        let logs = MockWorkoutLogService(logs: [])
        try await logs.deleteAllLogs()
        let remaining = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInMemorySessionPolicyStoreDeleteAllClearsEveryRecord() async throws {
        let store = InMemorySessionPolicyStore(policies: ["preview-user": .default, "other": .default])
        try await store.deleteAll()
        let first = try await store.policy(for: "preview-user")
        let second = try await store.policy(for: "other")
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func testInMemorySessionPolicyStoreDeleteAllOnEmptyIsANoOp() async throws {
        let store = InMemorySessionPolicyStore()
        try await store.deleteAll()
        let cleared = try await store.policy(for: "preview-user")
        XCTAssertNil(cleared)
    }

    func testInMemoryActiveSessionStoreClearAllClearsEveryRecord() async throws {
        let store = InMemoryActiveSessionStore(
            sessions: ["preview-user": resumableState(), "other": resumableState()]
        )
        try await store.clearAll()
        let first = try await store.load(for: "preview-user")
        let second = try await store.load(for: "other")
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func testInMemoryActiveSessionStoreClearAllOnEmptyIsANoOp() async throws {
        let store = InMemoryActiveSessionStore()
        try await store.clearAll()
        let cleared = try await store.load(for: "preview-user")
        XCTAssertNil(cleared)
    }

    // MARK: - US-AD03 orchestration

    func testDeleteAccountClearsEverythingForASignedInUser() async throws {
        let userService = MockUserService(user: MockPersistence.sampleUser)
        let logs = MockWorkoutLogService(logs: [makeLog(), makeLog()])
        let policies = InMemorySessionPolicyStore(policies: ["preview-user": .default])
        let sessions = InMemoryActiveSessionStore(sessions: ["preview-user": resumableState()])
        let auth = MockAuthService(userIdentifier: "apple-user-123")
        let appState = makeAppState(isOnboarded: true, selectedTab: .progress)

        let service = AccountDeletionService(
            userService: userService,
            workoutLogService: logs,
            sessionPolicyStore: policies,
            activeSessionStore: sessions,
            authService: auth
        )
        try await service.deleteAccount(appState: appState)

        // Durable records, both store configurations.
        let user = try await userService.currentUser()
        XCTAssertNil(user, "the user aggregate survived deletion")
        let remainingLogs = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remainingLogs.isEmpty, "logs survived deletion")
        let policy = try await policies.policy(for: "preview-user")
        XCTAssertNil(policy, "the policy survived deletion")
        let session = try await sessions.load(for: "preview-user")
        XCTAssertNil(session, "the active session survived deletion")

        // Keychain identifier (mandatory - it outlives reinstall).
        let identifier = try await auth.currentUserIdentifier()
        XCTAssertNil(identifier, "the Sign in with Apple identifier survived deletion")

        // Routing reset back to onboarding.
        await MainActor.run {
            XCTAssertFalse(appState.isOnboarded, "the app did not route back to onboarding")
            XCTAssertEqual(appState.selectedTab, .home, "the selected tab was not reset")
        }
    }

    /// The local-UUID user who never signed in with Apple: no credential to clear, and the teardown
    /// must still clear everything and route without throwing.
    func testDeleteAccountLocalUUIDUserWithNoCredentialClearsAndRoutes() async throws {
        let userService = MockUserService(user: MockPersistence.sampleUser)
        let logs = MockWorkoutLogService(logs: [makeLog()])
        let policies = InMemorySessionPolicyStore(policies: ["preview-user": .default])
        let sessions = InMemoryActiveSessionStore(sessions: ["preview-user": resumableState()])
        let auth = MockAuthService(userIdentifier: nil) // never signed in with Apple
        let appState = makeAppState(isOnboarded: true, selectedTab: .home)

        let service = AccountDeletionService(
            userService: userService, workoutLogService: logs,
            sessionPolicyStore: policies, activeSessionStore: sessions, authService: auth
        )
        try await service.deleteAccount(appState: appState)

        let user = try await userService.currentUser()
        XCTAssertNil(user)
        let remainingLogs = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remainingLogs.isEmpty)
        let policy = try await policies.policy(for: "preview-user")
        XCTAssertNil(policy)
        let session = try await sessions.load(for: "preview-user")
        XCTAssertNil(session)
        let identifier = try await auth.currentUserIdentifier()
        XCTAssertNil(identifier)
        await MainActor.run { XCTAssertFalse(appState.isOnboarded) }
    }

    /// A second run finds nothing to delete and must be a clean no-op (idempotent).
    func testDeleteAccountIsIdempotent() async throws {
        let userService = MockUserService(user: MockPersistence.sampleUser)
        let logs = MockWorkoutLogService(logs: [makeLog()])
        let policies = InMemorySessionPolicyStore(policies: ["preview-user": .default])
        let sessions = InMemoryActiveSessionStore(sessions: ["preview-user": resumableState()])
        let auth = MockAuthService(userIdentifier: "apple-user-123")
        let appState = makeAppState(isOnboarded: true, selectedTab: .progress)

        let service = AccountDeletionService(
            userService: userService, workoutLogService: logs,
            sessionPolicyStore: policies, activeSessionStore: sessions, authService: auth
        )
        try await service.deleteAccount(appState: appState)
        // Second call: nothing left to clear, must not throw.
        try await service.deleteAccount(appState: appState)

        let user = try await userService.currentUser()
        XCTAssertNil(user)
        let remainingLogs = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remainingLogs.isEmpty)
        await MainActor.run { XCTAssertFalse(appState.isOnboarded) }
    }

    /// The teardown does not depend on there being a user aggregate at all (a never-fully-onboarded
    /// install): logs and the Keychain are still cleared and the app still routes.
    func testDeleteAccountWithNoCurrentUserStillClearsLogsAndRoutes() async throws {
        let userService = MockUserService(user: nil)
        let logs = MockWorkoutLogService(logs: [makeLog(), makeLog()])
        let policies = InMemorySessionPolicyStore()
        let sessions = InMemoryActiveSessionStore()
        let auth = MockAuthService(userIdentifier: "apple-user-123")
        let appState = makeAppState(isOnboarded: true, selectedTab: .home)

        let service = AccountDeletionService(
            userService: userService, workoutLogService: logs,
            sessionPolicyStore: policies, activeSessionStore: sessions, authService: auth
        )
        try await service.deleteAccount(appState: appState)

        let remainingLogs = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remainingLogs.isEmpty)
        let identifier = try await auth.currentUserIdentifier()
        XCTAssertNil(identifier)
        await MainActor.run { XCTAssertFalse(appState.isOnboarded) }
    }

    /// A corrupt or unreadable `CDUser` makes `currentUser()` throw (it decodes JSON). The teardown
    /// must not key any delete off that read: policy and active-session records are still cleared
    /// wholesale, the Keychain is cleared, the app routes, and deletion reports success - so a
    /// corrupt user can never leave residual data behind a "delete account" that says done.
    func testDeleteAccountWithUnreadableUserStillClearsPolicyAndActiveSession() async throws {
        let userService = ThrowingUserService()
        let logs = MockWorkoutLogService(logs: [makeLog(), makeLog()])
        let policies = InMemorySessionPolicyStore(policies: ["preview-user": .default])
        let sessions = InMemoryActiveSessionStore(sessions: ["preview-user": resumableState()])
        let auth = MockAuthService(userIdentifier: "apple-user-123")
        let appState = makeAppState(isOnboarded: true, selectedTab: .progress)

        let service = AccountDeletionService(
            userService: userService, workoutLogService: logs,
            sessionPolicyStore: policies, activeSessionStore: sessions, authService: auth
        )
        try await service.deleteAccount(appState: appState)

        let remainingLogs = try await logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(remainingLogs.isEmpty, "logs survived deletion")
        let policy = try await policies.policy(for: "preview-user")
        XCTAssertNil(policy, "the policy survived a delete that could not read the user")
        let session = try await sessions.load(for: "preview-user")
        XCTAssertNil(session, "the active session survived a delete that could not read the user")
        let identifier = try await auth.currentUserIdentifier()
        XCTAssertNil(identifier, "the Sign in with Apple identifier survived deletion")
        XCTAssertTrue(userService.didDelete, "the user record was not deleted")
        await MainActor.run { XCTAssertFalse(appState.isOnboarded) }
    }

    // MARK: - Factories

    private func makeAppState(isOnboarded: Bool, selectedTab: AppTab) -> AppState {
        let appState = AppState(userDefaults: defaults)
        appState.isOnboarded = isOnboarded
        appState.selectedTab = selectedTab
        return appState
    }

    private func makeLog(id: UUID = UUID()) -> WorkoutLog {
        WorkoutLog(
            id: id, workoutId: UUID(),
            completedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
            requestedMinutes: 15, durationMinutes: 15, wasReturn: false,
            shape: .singleFocus, focusPillar: .strength, perceivedDifficulty: nil, exercises: []
        )
    }

    private func resumableState() -> ActiveSessionState {
        let exercise = Exercise(
            id: "push_up", displayName: "Push-up", pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [],
            isHold: false, defaultReps: 10, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "push_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "3x12", apartmentFriendly: true
        )
        let prescription = PrescribedExercise(
            id: UUID(), exercise: exercise, sets: 3, reps: 12, durationSeconds: nil, restSeconds: 45
        )
        let workout = Workout(
            id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
            shape: .singleFocus, focusPillar: .strength, requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [prescription])]
        )
        return ActiveSessionState(fresh: workout)
    }
}

/// A `UserServiceProtocol` double whose `currentUser()` always throws - modelling a corrupt/unreadable
/// `CDUser` blob that fails to decode on read - while `deleteCurrentUser()` still succeeds (a real
/// delete fetches and removes without decoding). Used to prove the teardown keys nothing off reading
/// the user.
private final class ThrowingUserService: UserServiceProtocol, @unchecked Sendable {
    struct Unreadable: Error {}
    private(set) var didDelete = false

    func currentUser() async throws -> User? { throw Unreadable() }
    func save(_ user: User) async throws {}
    func deleteCurrentUser() async throws { didDelete = true }
}
