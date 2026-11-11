import CoreData
import XCTest
@testable import RepToday

/// US-AU04: a user who onboarded before accounts signs in once on their next launch, and everything on
/// the phone - and in iCloud - moves to the account. Re-running is safe, an interruption at any stage
/// loses and duplicates nothing, and nothing on the phone or in iCloud is ever deleted by it.
@MainActor
final class LegacyAccountMigrationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LegacyAccountMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private static let identity = AccountIdentity(userId: "user_legacy", email: "sam@example.com", method: .apple)

    // MARK: - Who migrates

    func testAnInstallOnboardedBeforeAccountsStartsAwaitingSignIn() {
        defaults.set(true, forKey: AppState.Keys.isOnboarded)
        XCTAssertEqual(LegacyAccountMigrationStage.resolved(in: defaults), .awaitingSignIn)
        let appState = AppState(userDefaults: defaults)
        XCTAssertEqual(appState.legacyMigrationStage, .awaitingSignIn)
        XCTAssertTrue(appState.needsAccountSignIn, "the one-time sign-in is required before anything else")
        XCTAssertEqual(defaults.string(forKey: LegacyAccountMigrationStage.defaultsKey), "awaitingSignIn", "persisted for the store to read")
    }

    func testAFreshInstallAndALinkedUserNeverMigrate() {
        XCTAssertNil(LegacyAccountMigrationStage.resolved(in: defaults), "a fresh install has nothing to move")
        defaults.set(true, forKey: AppState.Keys.isOnboarded)
        defaults.set("user_new", forKey: AppState.Keys.accountUserId)
        XCTAssertNil(LegacyAccountMigrationStage.resolved(in: defaults), "a user who signed in during onboarding has nothing to move")
        let appState = AppState(userDefaults: defaults)
        XCTAssertFalse(appState.needsAccountSignIn)
        XCTAssertEqual(appState.account?.userId, "user_new")
    }

    func testANewUserLinkingDuringOnboardingDoesNotStartAMigration() {
        let appState = AppState(userDefaults: defaults)
        appState.linkAccount(Self.identity)
        appState.isOnboarded = true
        XCTAssertNil(appState.legacyMigrationStage)
        XCTAssertFalse(appState.needsAccountSignIn)
    }

    func testTheICloudMirrorRunsOnlyUntilEverythingIsQueued() {
        XCTAssertTrue(LegacyAccountMigrationStage.awaitingSignIn.mirrorsICloud)
        XCTAssertTrue(LegacyAccountMigrationStage.importingFromICloud.mirrorsICloud)
        XCTAssertFalse(LegacyAccountMigrationStage.uploading.mirrorsICloud)
        XCTAssertFalse(LegacyAccountMigrationStage.complete.mirrorsICloud)
    }

    func testStagesOnlyMoveForward() {
        defaults.set(true, forKey: AppState.Keys.isOnboarded)
        let appState = AppState(userDefaults: defaults)
        appState.linkAccount(Self.identity)
        XCTAssertEqual(appState.legacyMigrationStage, .importingFromICloud)
        appState.advanceLegacyMigration(to: .complete)
        appState.advanceLegacyMigration(to: .uploading)
        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        let relaunched = AppState(userDefaults: defaults)
        XCTAssertEqual(relaunched.legacyMigrationStage, .complete, "the stage survives a relaunch")
        XCTAssertEqual(relaunched.account, Self.identity, "and so does the account, read with no network")
    }

    // MARK: - The move

    func testTheWholeHistoryMovesToTheAccountExactlyOnce() async throws {
        let stack = SyncTestStack()
        let seeded = try await seedLegacyHistory(in: stack)
        let (appState, server, coordinator) = signIn(stack: stack, importer: SettledImporter(.imported))

        await coordinator.syncNow()

        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        XCTAssertEqual(coordinator.status, .upToDate)
        try await assertAccountHolds(seeded, server: server)
        try await assertPhoneUnchanged(seeded, stack: stack)
    }

    func testWithoutAnICloudAnswerThePhoneStillUploadsAndTheNextLaunchFinishes() async throws {
        let stack = SyncTestStack()
        let seeded = try await seedLegacyHistory(in: stack)
        let (appState, server, coordinator) = signIn(stack: stack, importer: SettledImporter(.unconfirmed))

        await coordinator.syncNow()
        XCTAssertEqual(appState.legacyMigrationStage, .importingFromICloud, "iCloud never answered, so the mirror stays on")
        try await assertAccountHolds(seeded, server: server)

        // Next launch: iCloud answers. Everything is queued again and the re-upload changes nothing.
        let writesBefore = await server.appliedWrites
        let relaunch = coordinatorFor(stack: stack, appState: appState, server: server, importer: SettledImporter(.imported))
        await relaunch.syncNow()
        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        let writesAfter = await server.appliedWrites
        XCTAssertEqual(writesAfter, writesBefore, "re-running the migration duplicates nothing")
    }

    func testAnInterruptedUploadResumesWithNothingLostOrDuplicated() async throws {
        let stack = SyncTestStack()
        let seeded = try await seedLegacyHistory(in: stack, logCount: 40)
        let server = FakeAccountServer()
        await server.failPush(call: 2, with: .unreachable)
        let appState = legacyAppState()
        appState.linkAccount(Self.identity)
        let first = coordinatorFor(stack: stack, appState: appState, server: server, importer: SettledImporter(.imported))

        await first.syncNow()
        XCTAssertEqual(appState.legacyMigrationStage, .uploading, "everything was queued before the upload failed")
        XCTAssertEqual(first.status, .waitingForConnection)

        // The app is killed and relaunched: a new coordinator over the same store resumes the queue.
        let relaunch = coordinatorFor(stack: stack, appState: appState, server: server, importer: SettledImporter(.imported))
        await relaunch.syncNow()
        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        try await assertAccountHolds(seeded, server: server)
        try await assertPhoneUnchanged(seeded, stack: stack)
    }

    func testAKillBetweenQueueingAndAdvancingTheStageIsHarmless() async throws {
        let stack = SyncTestStack()
        let seeded = try await seedLegacyHistory(in: stack)
        // The queue was written, but the app died before the stage moved on.
        _ = try await stack.store.enqueueAllRecords(changedAt: LegacyAccountMigrator.queuedAt)
        let (appState, server, coordinator) = signIn(stack: stack, importer: SettledImporter(.imported))

        await coordinator.syncNow()
        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        try await assertAccountHolds(seeded, server: server)
    }

    func testTheMoveNeverOverwritesNewerAccountData() async throws {
        let stack = SyncTestStack()
        let seeded = try await seedLegacyHistory(in: stack)
        let server = FakeAccountServer()
        // Another phone already moved and the user has since renamed themselves there.
        var newer = seeded.user
        newer.displayName = "Sam (renamed on the other phone)"
        await server.seed(.profile, recordId: newer.id, clientUpdatedAt: SyncFixtures.base,
                          content: .profile(payload: try SyncFixtures.payload(newer), focusAreas: []))
        let appState = legacyAppState()
        appState.linkAccount(Self.identity)
        let coordinator = coordinatorFor(stack: stack, appState: appState, server: server, importer: SettledImporter(.imported))

        await coordinator.syncNow()

        let profile = await server.row(.profile, recordId: newer.id)
        guard case .profile(let payload, _)? = profile?.content else { return XCTFail("profile missing") }
        XCTAssertEqual(try SyncPayloadCoder.decode(User.self, from: payload).displayName, newer.displayName,
                       "this phone's older copy never replaces the account's newer one")
        let local = try await stack.users.currentUser()
        XCTAssertEqual(local?.displayName, newer.displayName, "the phone takes the account's newer profile")
        XCTAssertEqual(local?.id, seeded.user.id, "without being rekeyed")
        let logs = await server.rows(of: .workoutLog)
        XCTAssertEqual(logs.count, seeded.logs.count, "the history this phone held still reaches the account")
    }

    func testAfterSeveralUnansweredLaunchesTheMoveFinishesWithWhatThePhoneHolds() async throws {
        let stack = SyncTestStack()
        _ = try await seedLegacyHistory(in: stack)
        let appState = legacyAppState()
        appState.linkAccount(Self.identity)
        let server = FakeAccountServer()
        for launch in 1...5 {
            let coordinator = coordinatorFor(stack: stack, appState: appState, server: server, importer: SettledImporter(.unconfirmed))
            await coordinator.syncNow()
            if launch < 5 {
                XCTAssertEqual(appState.legacyMigrationStage, .importingFromICloud)
            }
        }
        XCTAssertEqual(appState.legacyMigrationStage, .complete, "the iCloud mirror does not stay on forever")
    }

    // MARK: - The store a pre-account build wrote

    /// TestFlight users exist: a store written by model version 2 - the last build before accounts -
    /// opens under version 3 through lightweight migration, keeps every record, and moves completely.
    func testAStoreFromModelVersionTwoOpensAndMovesCompletely() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("m3-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let v2 = try XCTUnwrap(PersistenceController.modelVersion(named: "RepToday 2"))
        XCTAssertNil(v2.entitiesByName["CDSyncChange"])
        let user = SyncFixtures.user(id: "legacy-apple-id")
        let logs = (1...3).map { SyncFixtures.log(daysAgo: $0) }
        let activity = SyncFixtures.activity(daysAgo: 1)
        var policy = SessionPolicy.default
        policy.version = 9
        try writeVersionTwoStore(in: directory, model: v2, user: user, logs: logs, activity: activity, policy: policy)

        let stack = SyncTestStack(persistence: PersistenceController(localOnlyStoresIn: directory))
        let opened = try await stack.users.currentUser()
        XCTAssertEqual(opened, user)
        let openedLogs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(Set(openedLogs.map(\.id)), Set(logs.map(\.id)))
        let outboxBefore = try await stack.outbox()
        XCTAssertEqual(outboxBefore, [], "opening the old store queues nothing by itself")

        let (appState, server, coordinator) = signIn(stack: stack, importer: SettledImporter(.imported))
        await coordinator.syncNow()

        XCTAssertEqual(appState.legacyMigrationStage, .complete)
        let serverLogs = await server.rows(of: .workoutLog)
        XCTAssertEqual(Set(serverLogs.map(\.recordId)), Set(logs.map(\.id.uuidString)))
        let serverActivities = await server.rows(of: .outsideActivity)
        XCTAssertEqual(serverActivities.map(\.recordId), [activity.id.uuidString])
        let serverPolicy = await server.row(.sessionPolicy, recordId: user.id)
        guard case .sessionPolicy(let payload)? = serverPolicy?.content else { return XCTFail("policy missing") }
        XCTAssertEqual(try SyncPayloadCoder.decode(SessionPolicy.self, from: payload), policy)
    }

    // MARK: - Helpers

    private struct SeededHistory {
        let user: User
        let logs: [WorkoutLog]
        let activity: OutsideActivity
        let policy: SessionPolicy
    }

    /// History written the way a pre-account build wrote it: the records exist but nothing is queued.
    private func seedLegacyHistory(in stack: SyncTestStack, logCount: Int = 4) async throws -> SeededHistory {
        let user = SyncFixtures.user(id: "legacy-apple-id", name: "Sam")
        try await stack.users.save(user)
        let logs = (1...logCount).map { SyncFixtures.log(daysAgo: $0) }
        for log in logs { try await stack.logs.save(log) }
        let activity = SyncFixtures.activity(daysAgo: 2)
        try await stack.activities.save(activity)
        var policy = SessionPolicy.default
        policy.version = 3
        try await stack.policies.save(policy, for: user.id)
        try await stack.store.clearOutbox()
        return SeededHistory(user: user, logs: logs, activity: activity, policy: policy)
    }

    private func legacyAppState() -> AppState {
        defaults.set(true, forKey: AppState.Keys.isOnboarded)
        return AppState(userDefaults: defaults)
    }

    private func signIn(stack: SyncTestStack, importer: any LegacyICloudImporting) -> (AppState, FakeAccountServer, AccountSyncCoordinator) {
        let appState = legacyAppState()
        XCTAssertEqual(appState.legacyMigrationStage, .awaitingSignIn)
        appState.linkAccount(Self.identity)
        let server = FakeAccountServer()
        return (appState, server, coordinatorFor(stack: stack, appState: appState, server: server, importer: importer))
    }

    private func coordinatorFor(
        stack: SyncTestStack,
        appState: AppState,
        server: FakeAccountServer,
        importer: any LegacyICloudImporting
    ) -> AccountSyncCoordinator {
        let cursor = InMemorySyncCursorStore()
        return AccountSyncCoordinator(
            engine: stack.engine(server, cursor: cursor, pushBatchSize: 10),
            store: stack.store,
            cursorStore: cursor,
            appState: appState,
            migrator: LegacyAccountMigrator(appState: appState, store: stack.store, importer: importer, defaults: defaults, importTimeout: .milliseconds(10)),
            beginBackgroundWork: { _ in {} },
            onRemoteChangesApplied: {}
        )
    }

    private func assertAccountHolds(_ seeded: SeededHistory, server: FakeAccountServer, file: StaticString = #filePath, line: UInt = #line) async throws {
        let logs = await server.rows(of: .workoutLog)
        XCTAssertEqual(logs.count, seeded.logs.count, "no log lost or duplicated", file: file, line: line)
        XCTAssertEqual(Set(logs.map(\.recordId)), Set(seeded.logs.map(\.id.uuidString)), file: file, line: line)
        let activities = await server.rows(of: .outsideActivity)
        XCTAssertEqual(activities.map(\.recordId), [seeded.activity.id.uuidString], file: file, line: line)
        let profile = await server.row(.profile, recordId: seeded.user.id)
        guard case .profile(let payload, _)? = profile?.content else { return XCTFail("profile missing", file: file, line: line) }
        XCTAssertEqual(try SyncPayloadCoder.decode(User.self, from: payload), seeded.user, file: file, line: line)
        let policy = await server.row(.sessionPolicy, recordId: seeded.user.id)
        guard case .sessionPolicy(let policyPayload)? = policy?.content else { return XCTFail("policy missing", file: file, line: line) }
        XCTAssertEqual(try SyncPayloadCoder.decode(SessionPolicy.self, from: policyPayload), seeded.policy, file: file, line: line)
    }

    private func assertPhoneUnchanged(_ seeded: SeededHistory, stack: SyncTestStack, file: StaticString = #filePath, line: UInt = #line) async throws {
        let user = try await stack.users.currentUser()
        XCTAssertEqual(user, seeded.user, "the device's user is untouched and never rekeyed", file: file, line: line)
        let logs = try await stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(Set(logs.map(\.id)), Set(seeded.logs.map(\.id)), "nothing on the phone is deleted", file: file, line: line)
        let policy = try await stack.policies.policy(for: seeded.user.id)
        XCTAssertEqual(policy, seeded.policy, file: file, line: line)
    }

    /// Writes both stores the way a model-version-2 build did, with persistent history on the Cloud store.
    private func writeVersionTwoStore(
        in directory: URL,
        model: NSManagedObjectModel,
        user: User,
        logs: [WorkoutLog],
        activity: OutsideActivity,
        policy: SessionPolicy
    ) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let cloud = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: "Cloud",
            at: directory.appendingPathComponent("RepToday.sqlite"),
            options: [NSPersistentHistoryTrackingKey: true as NSNumber]
        )
        let local = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: "Local",
            at: directory.appendingPathComponent("RepToday-Local.sqlite")
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        func insert(_ entity: String, into store: NSPersistentStore) -> NSManagedObject {
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            context.assign(object, to: store)
            return object
        }
        let encoder = PersistenceCoder.encoder
        let cdUser = insert("CDUser", into: cloud)
        cdUser.setValue(user.id, forKey: "id")
        cdUser.setValue(user.displayName, forKey: "displayName")
        cdUser.setValue(user.createdAt, forKey: "createdAt")
        cdUser.setValue(user.phase.rawValue, forKey: "phaseRaw")
        cdUser.setValue(try encoder.encode(user.profile), forKey: "profileData")
        cdUser.setValue(try encoder.encode(user.subscription), forKey: "subscriptionData")
        cdUser.setValue(try encoder.encode(user.consistency), forKey: "consistencyData")
        cdUser.setValue(try encoder.encode(user.why), forKey: "whyData")
        cdUser.setValue(try encoder.encode(user.duration), forKey: "durationData")
        cdUser.setValue(try encoder.encode(user.coldStart), forKey: "coldStartData")
        for log in logs {
            let cdLog = insert("CDWorkoutLog", into: cloud)
            cdLog.setValue(log.id, forKey: "id")
            cdLog.setValue(log.workoutId, forKey: "workoutId")
            cdLog.setValue(log.completedAt, forKey: "completedAt")
            cdLog.setValue(log.durationMinutes, forKey: "durationMinutes")
            cdLog.setValue(log.requestedMinutes, forKey: "requestedMinutes")
            cdLog.setValue(log.wasReturn, forKey: "wasReturn")
            cdLog.setValue(log.shape.rawValue, forKey: "shapeRaw")
            cdLog.setValue(log.perceivedDifficulty?.rawValue, forKey: "perceivedDifficultyRaw")
            cdLog.setValue(try encoder.encode(log.exercises), forKey: "exercisesData")
        }
        let cdPolicy = insert("CDSessionPolicy", into: cloud)
        cdPolicy.setValue(user.id, forKey: "userId")
        cdPolicy.setValue(try encoder.encode(policy), forKey: "policyData")
        let cdActivity = insert("CDOutsideActivity", into: local)
        cdActivity.setValue(activity.id, forKey: "id")
        cdActivity.setValue(activity.type.rawValue, forKey: "typeRaw")
        cdActivity.setValue(activity.date, forKey: "date")
        cdActivity.setValue(activity.durationMinutes, forKey: "durationMinutes")
        try context.save()
    }
}

/// An iCloud import that has already settled one way or the other.
private struct SettledImporter: LegacyICloudImporting {
    let outcome: LegacyICloudImportOutcome
    init(_ outcome: LegacyICloudImportOutcome) { self.outcome = outcome }
    func waitForImport(timeout: Duration) async -> LegacyICloudImportOutcome { outcome }
}
