import XCTest
@testable import RepToday

/// US-AU05: deleting the account removes its server data and its Clerk user (`accounts:deleteAccount`)
/// and then everything on the device, in that order. A failure before the server step completes
/// changes nothing anywhere; a repeat after it completes skips it; and nothing is uploaded once
/// deletion has started.
final class AccountDeletionAccountTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AccountDeletionAccountTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private static let identity = AccountIdentity(userId: "user_delete_me", email: "sam@example.com", method: .google)

    private struct Fixture {
        let stack: SyncTestStack
        let server: FakeAccountServer
        let auth: StubAccountAuthService
        let cursor: InMemorySyncCursorStore
        let service: AccountDeletionService
        let appState: AppState
    }

    private func makeFixture() async throws -> Fixture {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        try await stack.users.save(user)
        try await stack.logs.save(SyncFixtures.log(daysAgo: 1))
        try await stack.activities.save(SyncFixtures.activity(daysAgo: 1))
        try await stack.policies.save(.default, for: user.id)
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore()
        try await stack.engine(server, cursor: cursor).sync()
        // A change made since the last sync, still waiting.
        try await stack.logs.save(SyncFixtures.log(daysAgo: 0))
        cursor.setCursor(42)

        let auth = StubAccountAuthService(isConfigured: true, identity: Self.identity, token: "session-token")
        let service = AccountDeletionService(
            userService: stack.users,
            workoutLogService: stack.logs,
            sessionPolicyStore: stack.policies,
            activeSessionStore: stack.activeSessions,
            authService: MockAuthService(),
            outsideActivityService: stack.activities,
            account: AccountDeletionService.AccountTeardown(
                remote: server,
                auth: auth,
                syncStore: stack.store,
                cursorStore: cursor,
                engine: stack.engine(server, cursor: cursor),
                defaults: defaults
            )
        )
        let appState = await MainActor.run { () -> AppState in
            let state = AppState(userDefaults: defaults)
            state.linkAccount(Self.identity)
            state.isOnboarded = true
            return state
        }
        return Fixture(stack: stack, server: server, auth: auth, cursor: cursor, service: service, appState: appState)
    }

    func testDeletesTheAccountOnTheServerThenEverythingOnTheDevice() async throws {
        let fixture = try await makeFixture()

        try await fixture.service.deleteAccount(appState: fixture.appState)

        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
        let serverRows = await fixture.server.rows
        XCTAssertTrue(serverRows.isEmpty, "the account's server data is gone")
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(logs.isEmpty)
        let activities = try await fixture.stack.activities.activities(from: nil, to: nil)
        XCTAssertTrue(activities.isEmpty)
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [], "nothing waits to upload to whichever account signs in next")
        XCTAssertEqual(fixture.cursor.cursor(), 0)
        let signOuts = await fixture.auth.signOutCount
        XCTAssertEqual(signOuts, 1, "the session on the device is ended")
        await MainActor.run {
            XCTAssertNil(fixture.appState.account)
            XCTAssertNil(fixture.appState.legacyMigrationStage)
            XCTAssertFalse(fixture.appState.isOnboarded)
            XCTAssertFalse(fixture.appState.isAccountDeletionInProgress)
        }
        XCTAssertNil(defaults.string(forKey: AccountDeletionService.AccountTeardown.remoteDeletionMarkerKey))
    }

    func testOfflineDeletionChangesNothingAndSaysItNeedsAConnection() async throws {
        let fixture = try await makeFixture()
        await fixture.server.setOffline(true)

        do {
            try await fixture.service.deleteAccount(appState: fixture.appState)
            XCTFail("deletion needs a connection")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .needsConnection)
        }

        let user = try await fixture.stack.users.currentUser()
        XCTAssertNotNil(user, "nothing on the device was deleted")
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs.count, 2)
        let outbox = try await fixture.stack.outbox()
        XCTAssertFalse(outbox.isEmpty, "the waiting change is still queued")
        let serverRows = await fixture.server.rows
        XCTAssertFalse(serverRows.isEmpty, "nothing on the server was deleted")
        await MainActor.run {
            XCTAssertEqual(fixture.appState.account, Self.identity)
            XCTAssertTrue(fixture.appState.isOnboarded)
            XCTAssertFalse(fixture.appState.isAccountDeletionInProgress, "sync resumes")
        }
    }

    func testARejectedSessionAsksForSignInAndChangesNothing() async throws {
        let fixture = try await makeFixture()
        await fixture.server.failDeletion(with: .unauthenticated)
        do {
            try await fixture.service.deleteAccount(appState: fixture.appState)
            XCTFail("an unaccepted session cannot delete")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .needsSignIn)
        }
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNotNil(user)
    }

    func testARepeatAfterTheServerStepSkipsItAndFinishesOnTheDevice() async throws {
        let fixture = try await makeFixture()
        // The server step finished on an earlier attempt, which then stopped before the device teardown.
        defaults.set(Self.identity.userId, forKey: AccountDeletionService.AccountTeardown.remoteDeletionMarkerKey)
        await fixture.server.failDeletion(with: .unauthenticated)

        try await fixture.service.deleteAccount(appState: fixture.appState)

        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 0, "a deleted account's session cannot reach the server again, and need not")
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        await MainActor.run { XCTAssertFalse(fixture.appState.isOnboarded) }
    }

    func testDeletingTwiceIsSafe() async throws {
        let fixture = try await makeFixture()
        try await fixture.service.deleteAccount(appState: fixture.appState)
        try await fixture.service.deleteAccount(appState: fixture.appState)
        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1, "the second run has no account to delete on the server")
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
    }

    func testABuildWithNoAccountBackendDeletesOnTheDeviceOnly() async throws {
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        let service = AccountDeletionService(
            userService: stack.users,
            workoutLogService: stack.logs,
            sessionPolicyStore: stack.policies,
            activeSessionStore: stack.activeSessions,
            authService: MockAuthService(),
            outsideActivityService: stack.activities,
            account: AccountDeletionService.AccountTeardown(
                remote: nil,
                auth: StubAccountAuthService(),
                syncStore: stack.store,
                cursorStore: InMemorySyncCursorStore(),
                defaults: defaults
            )
        )
        let appState = await MainActor.run { () -> AppState in
            let state = AppState(userDefaults: defaults)
            state.linkAccount(Self.identity)
            state.isOnboarded = true
            return state
        }
        try await service.deleteAccount(appState: appState)
        let user = try await stack.users.currentUser()
        XCTAssertNil(user)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
    }

    @MainActor
    func testNothingSyncsWhileDeletionIsInProgress() async throws {
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        let appState = AppState(userDefaults: defaults)
        appState.linkAccount(Self.identity)
        appState.isOnboarded = true
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore()
        let coordinator = AccountSyncCoordinator(
            engine: stack.engine(server, cursor: cursor),
            store: stack.store,
            cursorStore: cursor,
            appState: appState,
            migrator: LegacyAccountMigrator(appState: appState, store: stack.store, importer: LegacyICloudImportMonitor(settled: .nothingToImport), defaults: defaults),
            beginBackgroundWork: { _ in {} },
            onRemoteChangesApplied: {}
        )
        appState.isAccountDeletionInProgress = true
        await coordinator.syncNow()
        let pushes = await server.pushCalls
        XCTAssertEqual(pushes, 0)
        appState.isAccountDeletionInProgress = false
        await coordinator.syncNow()
        let pushesAfter = await server.pushCalls
        XCTAssertEqual(pushesAfter, 1)
    }
}
