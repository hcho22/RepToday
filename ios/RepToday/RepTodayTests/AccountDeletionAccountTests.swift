import CloudKit
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

    private func makeFixture(legacyICloud: LegacyICloudErasure? = nil, remote: (any SyncRemote)? = nil) async throws -> Fixture {
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
                remote: remote ?? server,
                auth: auth,
                syncStore: stack.store,
                cursorStore: cursor,
                engine: stack.engine(server, cursor: cursor),
                defaults: defaults
            ),
            legacyICloud: legacyICloud
        )
        let appState = try await MainActor.run { () throws -> AppState in
            let state = AppState(userDefaults: defaults)
            try state.linkAccount(Self.identity)
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
        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
        await MainActor.run {
            XCTAssertEqual(fixture.appState.account, Self.identity)
            XCTAssertTrue(fixture.appState.isOnboarded)
            XCTAssertFalse(fixture.appState.isAccountDeletionInProgress, "sync resumes")
        }
    }

    func testNoSessionForTheLinkedAccountAsksForSignInAndChangesNothing() async throws {
        let fixture = try await makeFixture()
        await fixture.server.failDeletion(with: .notSignedIn)
        do {
            try await fixture.service.deleteAccount(appState: fixture.appState)
            XCTFail("with no session the request never leaves the phone")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .needsSignIn)
        }
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNotNil(user)
        XCTAssertNil(defaults.string(forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey))
    }

    // MARK: - Committed once sent

    /// The server committed the deletion and the answer was lost on the way back: the phone wipes
    /// itself as on success and says the deletion is under way.
    func testAResponseLostAfterTheServerCommittedStillWipesThePhone() async throws {
        let fixture = try await makeFixture()
        await fixture.server.loseDeletionResponse()

        try await fixture.service.deleteAccount(appState: fixture.appState)

        try await assertWipedWithDeletionUnderWay(fixture)
    }

    /// An ambiguous answer after the request was sent (the server may have marked the account first)
    /// counts as committed too.
    func testAnAmbiguousAnswerAfterTheRequestWasSentCountsAsCommitted() async throws {
        for error in [SyncRemoteError.rejected(code: nil, message: "Server Error"), .invalidResponse, .noResponse] {
            let fixture = try await makeFixture()
            await fixture.server.failDeletion(with: error)

            try await fixture.service.deleteAccount(appState: fixture.appState)

            try await assertWipedWithDeletionUnderWay(fixture)
        }
    }

    /// The request went out on an earlier attempt and the job has since deleted the Clerk user, so no
    /// session can be had: the retry finishes the deletion on the phone rather than asking for a
    /// sign-in that can never succeed.
    func testARetryAfterTheClerkUserIsGoneFinishesOnThePhone() async throws {
        let fixture = try await makeFixture()
        defaults.set(Self.identity.userId, forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey)
        await fixture.server.failDeletion(with: .notSignedIn)

        try await fixture.service.deleteAccount(appState: fixture.appState)

        try await assertWipedWithDeletionUnderWay(fixture)
    }

    /// A first request that never left the phone is forgotten, so the next attempt online is an
    /// ordinary deletion.
    func testARequestThatNeverLeftThePhoneIsNotTreatedAsSent() async throws {
        let fixture = try await makeFixture()
        await fixture.server.setOffline(true)
        _ = try? await fixture.service.deleteAccount(appState: fixture.appState)
        XCTAssertNil(defaults.string(forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey))

        await fixture.server.setOffline(false)
        try await fixture.service.deleteAccount(appState: fixture.appState)

        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        await MainActor.run { XCTAssertFalse(fixture.appState.showAccountDeletionUnderWay) }
    }

    /// Answers that provably come before the server marks anything delete nothing and say so.
    func testARefusalBeforeTheMarkDeletesNothing() async throws {
        let refusals: [(SyncRemoteError, AccountDeletionError)] = [
            (.unauthenticated, .needsSignIn),
            (.rejected(code: "deletion_unavailable", message: "Account deletion is not configured on this deployment."), .unavailable),
        ]
        for (refusal, expected) in refusals {
            let fixture = try await makeFixture()
            await fixture.server.failDeletion(with: refusal)
            do {
                try await fixture.service.deleteAccount(appState: fixture.appState)
                XCTFail("\(refusal) must not count as a committed deletion")
            } catch {
                XCTAssertEqual(error as? AccountDeletionError, expected)
            }
            try await assertNothingDeleted(fixture)
        }
    }

    /// Offline, the session token cannot be refreshed, so the request is never built: nothing is
    /// deleted and the phone says deletion needs a connection.
    func testAnOfflineSessionTokenFetchDeletesNothing() async throws {
        let offlineRemote = ConvexSyncRemote(client: ConvexHTTPClient(deploymentURL: URL(string: "https://a-b-1.convex.cloud")!) {
            throw URLError(.notConnectedToInternet)
        })
        let fixture = try await makeFixture(remote: offlineRemote)
        do {
            try await fixture.service.deleteAccount(appState: fixture.appState)
            XCTFail("a request that was never built must not count as sent")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .needsConnection)
        }
        try await assertNothingDeleted(fixture)
    }

    // MARK: - A relaunch with the request recorded

    /// The app was closed while the request was out: the next launch sends it again and finishes the
    /// teardown, telling the user once that the deletion is under way.
    func testARelaunchWithTheRequestRecordedFinishesTheDeletion() async throws {
        let fixture = try await makeFixture()
        defaults.set(Self.identity.userId, forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey)

        try await fixture.service.resumeRequestedDeletion(appState: fixture.appState)

        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
        try await assertWipedWithDeletionUnderWay(fixture)

        await MainActor.run { fixture.appState.showAccountDeletionUnderWay = false }
        try await fixture.service.resumeRequestedDeletion(appState: fixture.appState)
        await MainActor.run { XCTAssertFalse(fixture.appState.showAccountDeletionUnderWay, "the message shows once") }
    }

    func testARelaunchWithNoRequestForTheLinkedAccountChangesNothing() async throws {
        for recorded in [nil, "user_someone_else"] {
            let fixture = try await makeFixture()
            defaults.set(recorded, forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey)

            try await fixture.service.resumeRequestedDeletion(appState: fixture.appState)

            let deleteCalls = await fixture.server.deleteCalls
            XCTAssertEqual(deleteCalls, 0)
            let user = try await fixture.stack.users.currentUser()
            XCTAssertNotNil(user)
            await MainActor.run {
                XCTAssertEqual(fixture.appState.account, Self.identity)
                XCTAssertFalse(fixture.appState.showAccountDeletionUnderWay)
            }
        }
    }

    private func assertNothingDeleted(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNotNil(user, file: file, line: line)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs.count, 2, file: file, line: line)
        await MainActor.run {
            XCTAssertEqual(fixture.appState.account, Self.identity, file: file, line: line)
            XCTAssertTrue(fixture.appState.isOnboarded, file: file, line: line)
            XCTAssertFalse(fixture.appState.showAccountDeletionUnderWay, file: file, line: line)
        }
        XCTAssertNil(defaults.string(forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey), file: file, line: line)
    }

    private func assertWipedWithDeletionUnderWay(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user, file: file, line: line)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(logs.isEmpty, file: file, line: line)
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [], file: file, line: line)
        await MainActor.run {
            XCTAssertTrue(fixture.appState.showAccountDeletionUnderWay, file: file, line: line)
            XCTAssertNil(fixture.appState.account, file: file, line: line)
            XCTAssertFalse(fixture.appState.isOnboarded, file: file, line: line)
        }
        XCTAssertNil(defaults.string(forKey: AccountDeletionService.AccountTeardown.remoteDeletionRequestedKey), file: file, line: line)
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
        let appState = try await MainActor.run { () throws -> AppState in
            let state = AppState(userDefaults: defaults)
            try state.linkAccount(Self.identity)
            state.isOnboarded = true
            return state
        }
        try await service.deleteAccount(appState: appState)
        let user = try await stack.users.currentUser()
        XCTAssertNil(user)
        let outbox = try await stack.outbox()
        XCTAssertEqual(outbox, [])
    }

    // MARK: - Clerk not reachable yet

    /// The server committed the deletion but could not reach Clerk: the phone wipes its data exactly as
    /// on success and says the sign-in removal finishes on its own, instead of claiming nothing changed.
    func testAPendingSignInRemovalStillWipesThePhoneAndSaysSo() async throws {
        let fixture = try await makeFixture()
        await fixture.server.answerDeletion(with: .underWay)

        try await fixture.service.deleteAccount(appState: fixture.appState)

        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(logs.isEmpty)
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [])
        await MainActor.run {
            XCTAssertTrue(fixture.appState.showAccountDeletionUnderWay)
            XCTAssertNil(fixture.appState.account)
            XCTAssertFalse(fixture.appState.isOnboarded)
        }
        XCTAssertFalse(defaults.bool(forKey: AccountDeletionService.AccountTeardown.deletionUnderWayKey))
        XCTAssertEqual(
            RootView.deletionNoticeMessage(appleGuidance: false, deletionUnderWay: true),
            "Your Rep Today data is deleted from this phone. Your account is being deleted, and that finishes on its own - there's nothing more you need to do."
        )
    }

    func testACompleteDeletionShowsNoPendingNote() async throws {
        let fixture = try await makeFixture()

        try await fixture.service.deleteAccount(appState: fixture.appState)

        await MainActor.run { XCTAssertFalse(fixture.appState.showAccountDeletionUnderWay) }
    }

    // MARK: - The legacy iCloud copy

    func testDeletionAlsoDeletesTheLegacyICloudCopyAndIsSafeToRepeat() async throws {
        let deleter = SpyLegacyICloudDeleter()
        let erasure = LegacyICloudErasure(deleter: deleter, defaults: defaults)
        let fixture = try await makeFixture(legacyICloud: erasure)

        try await fixture.service.deleteAccount(appState: fixture.appState)
        try await fixture.service.deleteAccount(appState: fixture.appState)

        let calls = await deleter.calls
        XCTAssertEqual(calls, 2, "a repeat asks again, and a zone already gone counts as deleted")
        XCTAssertFalse(erasure.isOwed)
    }

    /// With iCloud unavailable the rest of the deletion still completes; the iCloud deletion is owed
    /// and lands on a later launch's retry.
    func testAnICloudDeletionThatCannotRunIsOwedAndRetriedWithoutBlockingTheRest() async throws {
        let deleter = SpyLegacyICloudDeleter(failuresLeft: 1)
        let erasure = LegacyICloudErasure(deleter: deleter, defaults: defaults)
        let fixture = try await makeFixture(legacyICloud: erasure)

        try await fixture.service.deleteAccount(appState: fixture.appState)

        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        await MainActor.run { XCTAssertFalse(fixture.appState.isOnboarded) }
        XCTAssertTrue(erasure.isOwed, "the iCloud deletion is still owed")

        await erasure.retryIfOwed()
        XCTAssertFalse(erasure.isOwed)
        await erasure.retryIfOwed()
        let calls = await deleter.calls
        XCTAssertEqual(calls, 2, "nothing is retried once it has landed")
    }

    /// Erasing the phone, when its data belongs to another account, deletes neither that account nor
    /// its iCloud copy.
    func testErasingThisDeviceDeletesNoAccountAndNoICloudCopy() async throws {
        let deleter = SpyLegacyICloudDeleter()
        let fixture = try await makeFixture(legacyICloud: LegacyICloudErasure(deleter: deleter, defaults: defaults))

        try await fixture.service.eraseThisDevice(appState: fixture.appState)

        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 0)
        let calls = await deleter.calls
        XCTAssertEqual(calls, 0)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertTrue(logs.isEmpty)
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [])
        await MainActor.run {
            XCTAssertNil(fixture.appState.account)
            XCTAssertFalse(fixture.appState.isOnboarded)
            XCTAssertFalse(fixture.appState.isAccountDeletionInProgress)
        }
    }

    @MainActor
    func testNothingSyncsWhileDeletionIsInProgress() async throws {
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        let appState = AppState(userDefaults: defaults)
        try appState.linkAccount(Self.identity)
        appState.isOnboarded = true
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore()
        let coordinator = AccountSyncCoordinator(
            engine: stack.engine(server, cursor: cursor),
            store: stack.store,
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

/// The CloudKit zone deletion, scripted: fails `failuresLeft` times, then succeeds.
private actor SpyLegacyICloudDeleter: LegacyICloudDataDeleting {
    private(set) var calls = 0
    private var failuresLeft: Int

    init(failuresLeft: Int = 0) {
        self.failuresLeft = failuresLeft
    }

    func deleteLegacyICloudData() async throws {
        calls += 1
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw CKError(.notAuthenticated)
        }
    }
}
