import XCTest
@testable import RepToday

/// US-SO01/US-SO02: signing out uploads what is waiting first, warns before losing anything it could not
/// upload (decision 14, FR-7), and then leaves the phone holding nothing of the account while the
/// account keeps everything (decision 15, FR-8).
///
/// The service runs over the real Core Data stores, the real device teardown and an in-memory account
/// backend with the server's rules (`FakeAccountServer`), so "erased" means the stores the app reads are
/// empty, not that a double recorded a call.
final class AccountSignOutServiceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AccountSignOutServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private static let identity = AccountIdentity(userId: "user_sign_out", email: "sam@example.com", method: .email)
    private static let today = "2026-11-13"

    private struct Fixture {
        let stack: SyncTestStack
        let server: FakeAccountServer
        let auth: StubAccountAuthService
        let cursor: InMemorySyncCursorStore
        let engine: SyncEngine
        let scheduler: RecordingReminderNotificationScheduler
        let reminders: CoachReminderService
        let todayChoices: DefaultsTodayChoicesStore
        let appState: AppState

        func service(timeout: Duration = AccountSignOutService.defaultUploadTimeout, engine: SyncEngine?? = nil, eraser: AccountDeletionService) -> AccountSignOutService {
            AccountSignOutService(engine: engine ?? self.engine, syncStore: stack.store, eraser: eraser, uploadTimeout: timeout)
        }
    }

    /// A signed-in phone with every kind of account data on it, synced, plus one workout logged since.
    private func makeFixture() async throws -> (Fixture, AccountDeletionService) {
        let stack = SyncTestStack()
        let user = SyncFixtures.user(phase: .strength)
        try await stack.users.save(user)
        try await stack.logs.save(SyncFixtures.log(daysAgo: 1))
        try await stack.activities.save(SyncFixtures.activity(daysAgo: 1))
        try await stack.policies.save(.default, for: user.id)
        try await stack.customWorkouts.save(CustomWorkout(
            id: UUID(), title: "Desk Reset", note: "", steps: [], messageId: nil, proposalId: nil,
            createdAt: SyncFixtures.base, acceptedAt: SyncFixtures.base
        ))
        try await stack.activeSessions.save(ActiveSessionState(fresh: Self.workout()), for: user.id)
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore()
        let engine = stack.engine(server, cursor: cursor)
        try await engine.sync()
        // A workout logged since the last sync, still waiting to upload.
        try await stack.logs.save(SyncFixtures.log(daysAgo: 0))

        let scheduler = RecordingReminderNotificationScheduler(permission: .allowed)
        let reminders = CoachReminderService(defaults: defaults, scheduler: scheduler)
        try await reminders.save(CoachReminder(hour: 7, minute: 30, weekdays: [2, 4], createdAt: SyncFixtures.base))
        let todayChoices = DefaultsTodayChoicesStore(defaults: defaults)
        todayChoices.save(TodayChoices(day: Self.today, rest: .restToday, minutes: 10))

        let auth = StubAccountAuthService(isConfigured: true, identity: Self.identity, token: "session-token")
        let appState = AppState(userDefaults: defaults)
        try appState.linkAccount(Self.identity)
        appState.isOnboarded = true
        appState.selectedTab = .profile
        appState.markCoachDataSharingAcknowledged()
        appState.markStrengthGraduationCelebrated()
        appState.healthWorkoutSuggestionsEnabled = true

        let fixture = Fixture(
            stack: stack, server: server, auth: auth, cursor: cursor, engine: engine, scheduler: scheduler,
            reminders: reminders, todayChoices: todayChoices, appState: appState
        )
        let eraser = AccountDeletionService(
            userService: stack.users,
            workoutLogService: stack.logs,
            sessionPolicyStore: stack.policies,
            activeSessionStore: stack.activeSessions,
            authService: MockAuthService(),
            coachState: CoachDeviceTeardown(customWorkouts: stack.customWorkouts, reminders: reminders, todayChoices: todayChoices),
            outsideActivityService: stack.activities,
            account: AccountDeletionService.AccountTeardown(
                remote: server,
                auth: auth,
                syncStore: stack.store,
                cursorStore: cursor,
                engine: engine,
                defaults: defaults
            )
        )
        return (fixture, eraser)
    }

    // MARK: - Upload first (decision 14)

    func testOnlineUploadSavesTheWaitingWorkoutAndReportsAllSaved() async throws {
        let (fixture, eraser) = try await makeFixture()

        let result = await fixture.service(eraser: eraser).uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .allSaved)
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [])
        let uploadedLogs = await fixture.server.rows(of: .workoutLog)
        XCTAssertEqual(uploadedLogs.count, 2, "the workout logged since the last sync reached the account")
    }

    func testOfflineUploadReportsUnsavedChangesAndChangesNothing() async throws {
        let (fixture, eraser) = try await makeFixture()
        await fixture.server.setOffline(true)

        let result = await fixture.service(eraser: eraser).uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .unsavedChanges)
        try await assertStillSignedInWithEverything(fixture)
    }

    func testAnUploadTheAccountRefusesReportsUnsavedChanges() async throws {
        let (fixture, eraser) = try await makeFixture()
        await fixture.server.failPush(call: 2, with: .rejected(code: nil, message: "Server Error"))

        let result = await fixture.service(eraser: eraser).uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .unsavedChanges)
        try await assertStillSignedInWithEverything(fixture)
    }

    /// The upload is bounded: a connection too slow to finish in time is reported as unsaved rather than
    /// holding the user on a spinner.
    func testAnUploadThatRunsPastTheBoundReportsUnsavedChanges() async throws {
        let (fixture, eraser) = try await makeFixture()
        await fixture.server.delayPushes(by: .seconds(1))
        let started = ContinuousClock.now

        let result = await fixture.service(timeout: .milliseconds(50), eraser: eraser).uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .unsavedChanges)
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(900), "the answer came at the bound, not when the upload ended")
        await fixture.engine.waitForIdle()
    }

    /// A build with no account backend never put anything on an account, so whatever the outbox holds
    /// would be lost.
    func testWithNoAccountBackendAWaitingChangeIsUnsaved() async throws {
        let (fixture, eraser) = try await makeFixture()

        let waiting = await fixture.service(engine: .some(nil), eraser: eraser).uploadPendingChanges(appState: fixture.appState)
        XCTAssertEqual(waiting, .unsavedChanges)

        try await fixture.stack.store.clearOutbox()
        let empty = await fixture.service(engine: .some(nil), eraser: eraser).uploadPendingChanges(appState: fixture.appState)
        XCTAssertEqual(empty, .allSaved)
    }

    /// A user still moving their pre-account history may have records the outbox has not been given yet.
    func testAMoveFromBeforeAccountsStillImportingIsUnsaved() async throws {
        let (fixture, eraser) = try await makeFixture()
        try await fixture.stack.store.clearOutbox()
        defaults.set(LegacyAccountMigrationStage.importingFromICloud.rawValue, forKey: LegacyAccountMigrationStage.defaultsKey)
        let migrating = AppState(userDefaults: defaults)

        let result = await fixture.service(eraser: eraser).uploadPendingChanges(appState: migrating)

        XCTAssertEqual(result, .unsavedChanges)
    }

    // MARK: - A clean phone (decision 15)

    func testSigningOutErasesEveryPartOfTheAccountOnThePhoneAndKeepsTheServersCopy() async throws {
        let (fixture, eraser) = try await makeFixture()
        let service = fixture.service(eraser: eraser)
        let upload = await service.uploadPendingChanges(appState: fixture.appState)
        XCTAssertEqual(upload, .allSaved)
        let serverRowsBefore = await fixture.server.rows
        let installIdBefore = fixture.appState.installId

        try await service.signOut(appState: fixture.appState)

        try await assertNothingOfTheAccountLeft(fixture)
        let serverRowsAfter = await fixture.server.rows
        XCTAssertEqual(serverRowsAfter, serverRowsBefore, "the account's data stays on the server")
        let deletions = await fixture.server.deleteCalls
        XCTAssertEqual(deletions, 0, "signing out deletes no account")
        XCTAssertNotEqual(fixture.appState.installId, installIdBefore, "the anonymous install identifier rotates, as the erase does")
    }

    /// Decision 14's "Sign Out Anyway": the waiting workout is lost on purpose, and nothing of the account
    /// is left behind for the next person.
    func testSigningOutAnywayWhileOfflineStillLeavesNothingBehind() async throws {
        let (fixture, eraser) = try await makeFixture()
        await fixture.server.setOffline(true)
        let service = fixture.service(eraser: eraser)
        let upload = await service.uploadPendingChanges(appState: fixture.appState)
        XCTAssertEqual(upload, .unsavedChanges)

        try await service.signOut(appState: fixture.appState)

        try await assertNothingOfTheAccountLeft(fixture)
        let uploadedLogs = await fixture.server.rows(of: .workoutLog)
        XCTAssertEqual(uploadedLogs.count, 1, "the unsaved workout never reached the account")
    }

    func testASecondSignOutIsANoOp() async throws {
        let (fixture, eraser) = try await makeFixture()
        let service = fixture.service(eraser: eraser)
        try await service.signOut(appState: fixture.appState)
        let installId = fixture.appState.installId

        try await service.signOut(appState: fixture.appState)

        try await assertNothingOfTheAccountLeft(fixture)
        XCTAssertEqual(fixture.appState.installId, installId, "a repeat does not rotate the identifier again")
    }

    /// After signing out, another account links with no "this phone belongs to another account" offer:
    /// the phone is clean.
    func testAnotherAccountLinksAfterSignOutWithoutAnEraseOffer() async throws {
        let (fixture, eraser) = try await makeFixture()
        try await fixture.service(eraser: eraser).signOut(appState: fixture.appState)

        let other = AccountIdentity(userId: "user_someone_else", email: nil, method: .google)
        XCTAssertNoThrow(try fixture.appState.linkAccount(other))
        XCTAssertEqual(fixture.appState.account, other)
        XCTAssertNil(fixture.appState.legacyMigrationStage, "signing in afterwards is not a move from before accounts")
    }

    // MARK: - Assertions

    private func assertStillSignedInWithEverything(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNotNil(user, file: file, line: line)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs.count, 2, file: file, line: line)
        let outbox = try await fixture.stack.outbox()
        XCTAssertFalse(outbox.isEmpty, "the waiting workout is still queued", file: file, line: line)
        XCTAssertEqual(fixture.appState.account, Self.identity, file: file, line: line)
        XCTAssertTrue(fixture.appState.isOnboarded, file: file, line: line)
        let session = await fixture.auth.currentIdentity()
        XCTAssertEqual(session, Self.identity, file: file, line: line)
    }

    /// Every item decision 15 names, and every other piece of the account found on the phone.
    private func assertNothingOfTheAccountLeft(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        // Workouts and the rest of the history.
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [], "workouts", file: file, line: line)
        let activities = try await fixture.stack.activities.activities(from: nil, to: nil)
        XCTAssertEqual(activities, [], "outside activities", file: file, line: line)
        let session = try await fixture.stack.activeSessions.load(for: "local-user")
        XCTAssertNil(session, "the paused session", file: file, line: line)
        // The profile, with its Focus Areas, injury flags and Trainer, and the plan.
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user, "profile", file: file, line: line)
        let policy = try await fixture.stack.policies.policy(for: "local-user")
        XCTAssertNil(policy, "session policy", file: file, line: line)
        // The Coach: Custom Workouts, today's choices, reminders and every notification.
        let customWorkouts = try await fixture.stack.customWorkouts.workouts()
        XCTAssertEqual(customWorkouts, [], "Custom Workouts", file: file, line: line)
        XCTAssertTrue(fixture.todayChoices.choices(on: Self.today).isEmpty, "today's choices", file: file, line: line)
        let reminders = await fixture.reminders.reminders()
        XCTAssertEqual(reminders, [], "reminders", file: file, line: line)
        let pending = await fixture.scheduler.pending
        XCTAssertTrue(pending.isEmpty, "scheduled notifications", file: file, line: line)
        // Sync and sign-in.
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [], "sync outbox", file: file, line: line)
        XCTAssertEqual(fixture.cursor.cursor(), 0, "sync cursor", file: file, line: line)
        let signedIn = await fixture.auth.currentIdentity()
        XCTAssertNil(signedIn, "the account's session", file: file, line: line)
        XCTAssertNil(fixture.appState.account, file: file, line: line)
        // Account-scoped settings, back to a new install's.
        XCTAssertFalse(fixture.appState.hasAcknowledgedCoachDataSharing, "Coach disclosure", file: file, line: line)
        XCTAssertFalse(fixture.appState.hasCelebratedStrengthGraduation, "Strength-Phase celebration", file: file, line: line)
        XCTAssertFalse(fixture.appState.healthWorkoutSuggestionsEnabled, "Apple Health suggestions", file: file, line: line)
        // Back to sign-in.
        XCTAssertFalse(fixture.appState.isOnboarded, file: file, line: line)
        XCTAssertEqual(fixture.appState.selectedTab, .home, file: file, line: line)
        XCTAssertFalse(fixture.appState.isAccountDeletionInProgress, file: file, line: line)
    }

    private static func workout() -> Workout {
        let exercise = Exercise(
            id: "push_up", displayName: "Push-up", pillar: .strength, movementPattern: .push,
            category: .strength, difficulty: 2, phase: .discipline, equipment: [],
            isHold: false, defaultReps: 10, defaultDurationSeconds: nil,
            estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "push_chain",
            progressionOrder: 0, regressionId: nil, progressionId: nil,
            advancementCriteria: "3x12", apartmentFriendly: true
        )
        return Workout(
            id: UUID(), createdAt: SyncFixtures.base, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [
                PrescribedExercise(id: UUID(), exercise: exercise, sets: 3, reps: 12, durationSeconds: nil, restSeconds: 45),
            ])]
        )
    }
}

/// The account leftovers the one device teardown now clears for Delete Account, the different-account
/// erase and sign-out alike, and the guard that every `UserDefaults` key the app writes is decided.
final class AccountDeviceLeftoverTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AccountDeviceLeftoverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeService(reminders: CoachReminderService? = nil) -> AccountDeletionService {
        AccountDeletionService(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(),
            sessionPolicyStore: InMemorySessionPolicyStore(),
            activeSessionStore: InMemoryActiveSessionStore(),
            authService: MockAuthService(),
            coachState: CoachDeviceTeardown(
                customWorkouts: InMemoryCustomWorkoutService(),
                reminders: reminders ?? CoachReminderService(defaults: defaults, scheduler: RecordingReminderNotificationScheduler()),
                todayChoices: InMemoryTodayChoicesStore()
            )
        )
    }

    private func makeOnboardedAppState() throws -> AppState {
        let appState = AppState(userDefaults: defaults)
        try appState.linkAccount(AccountIdentity(userId: "user_leftovers", email: nil, method: .apple))
        appState.isOnboarded = true
        return appState
    }

    /// Delete Account correction: a Strength Phase one account earned no longer suppresses the next
    /// account's graduation moment.
    func testDeleteAccountForgetsTheStrengthCelebration() async throws {
        let appState = try makeOnboardedAppState()
        appState.markStrengthGraduationCelebrated()

        try await makeService().deleteAccount(appState: appState)

        XCTAssertFalse(appState.hasCelebratedStrengthGraduation)
        XCTAssertFalse(AppState(userDefaults: defaults).hasCelebratedStrengthGraduation, "and it stays forgotten after a relaunch")
    }

    /// The different-account erase gets the same correction, through the same teardown.
    func testEraseThisDeviceForgetsTheStrengthCelebration() async throws {
        let appState = try makeOnboardedAppState()
        appState.markStrengthGraduationCelebrated()

        try await makeService().eraseThisDevice(appState: appState)

        XCTAssertFalse(appState.hasCelebratedStrengthGraduation)
    }

    /// Delete Account correction: the account's unfinished move from before accounts leaves no attempt
    /// count behind.
    func testTheTeardownForgetsTheMovesImportAttempts() async throws {
        defaults.set(3, forKey: LegacyAccountMigrator.importAttemptsKey)
        let appState = try makeOnboardedAppState()

        try await makeService().deleteAccount(appState: appState)

        XCTAssertNil(defaults.object(forKey: LegacyAccountMigrator.importAttemptsKey))
    }

    /// Delete Account correction: every notification Rep Today has pending goes, including one no saved
    /// reminder names any more (a lost or corrupt reminder list).
    func testTheTeardownRemovesNotificationsNoReminderNames() async throws {
        let scheduler = RecordingReminderNotificationScheduler(permission: .allowed)
        try await scheduler.add([ScheduledReminderNotification(
            identifier: "coach.reminder.orphan.2", title: "Rep Today", body: "", weekday: 2, hour: 7, minute: 0
        )])
        let reminders = CoachReminderService(defaults: defaults, scheduler: scheduler)
        try await reminders.save(CoachReminder(hour: 8, minute: 0, weekdays: [3], createdAt: Date()))
        let appState = try makeOnboardedAppState()

        try await makeService(reminders: reminders).deleteAccount(appState: appState)

        let pending = await scheduler.pending
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - No account key left

    /// `UserDefaults` keys that hold the account's data or state. The teardown must leave each as a new
    /// install has it; `testTheTeardownLeavesNoAccountKeyBehind` proves it does.
    private static let accountKeys: [String: Any?] = [
        "AppState.accountUserId": nil,
        "AppState.accountEmail": nil,
        "AppState.accountMethod": nil,
        "AppState.linkedAccountBeingDeleted": nil,
        "AppState.legacyMigrationStage": nil,
        "AppState.healthWorkoutSuggestionsEnabled": false,
        "AppState.dismissedHealthWorkoutIds": [String](),
        "AppState.lastCelebratedPhase": Phase.discipline.rawValue,
        "AppState.hasAcknowledgedCoachDataSharing": nil,
        "AppState.selectedTab": AppTab.home.rawValue,
        "AppState.isOnboarded": false,
        "Coach.todayChoices": nil,
        "Coach.reminders": nil,
        "Sync.pullCursor": nil,
        "Sync.legacyImportAttempts": nil,
        "Account.remoteDeletionCompletedFor": nil,
        "Account.remoteDeletionRequestedFor": nil,
        "Account.remoteDeletionUnderWay": nil,
    ]

    /// Every account key, written as an account would leave it, is back to a new install's value after
    /// the teardown sign-out runs.
    func testTheTeardownLeavesNoAccountKeyBehind() async throws {
        let todayChoices = DefaultsTodayChoicesStore(defaults: defaults)
        todayChoices.save(TodayChoices(day: "2026-11-13", rest: .restToday, minutes: 10))
        let reminders = CoachReminderService(defaults: defaults, scheduler: RecordingReminderNotificationScheduler(permission: .allowed))
        try await reminders.save(CoachReminder(hour: 7, minute: 0, weekdays: [2], createdAt: Date()))
        let cursor = DefaultsSyncCursorStore(defaults: defaults)
        cursor.setCursor(42)
        defaults.set(3, forKey: LegacyAccountMigrator.importAttemptsKey)
        defaults.set(LegacyAccountMigrationStage.complete.rawValue, forKey: LegacyAccountMigrationStage.defaultsKey)
        let appState = try makeOnboardedAppState()
        appState.markLinkedAccountBeingDeleted()
        appState.healthWorkoutSuggestionsEnabled = true
        appState.dismissHealthWorkout(UUID())
        appState.markStrengthGraduationCelebrated()
        appState.markCoachDataSharingAcknowledged()
        appState.selectedTab = .coach
        let service = AccountDeletionService(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(),
            sessionPolicyStore: InMemorySessionPolicyStore(),
            activeSessionStore: InMemoryActiveSessionStore(),
            authService: MockAuthService(),
            coachState: CoachDeviceTeardown(customWorkouts: InMemoryCustomWorkoutService(), reminders: reminders, todayChoices: todayChoices),
            account: AccountDeletionService.AccountTeardown(
                remote: nil, auth: StubAccountAuthService(), syncStore: NoOpSyncStore(), cursorStore: cursor, defaults: defaults
            )
        )
        let written = Set(Self.accountKeys.keys).filter { defaults.object(forKey: $0) != nil }
        XCTAssertGreaterThanOrEqual(written.count, 12, "the fixture writes the account's keys before the teardown")

        try await AccountSignOutService(engine: nil, syncStore: NoOpSyncStore(), eraser: service).signOut(appState: appState)

        for (key, expected) in Self.accountKeys {
            let value = defaults.object(forKey: key)
            switch expected {
            case nil:
                XCTAssertNil(value, key)
            case let flag as Bool:
                XCTAssertEqual(value as? Bool ?? false, flag, key)
            case let text as String:
                XCTAssertEqual(value as? String, text, key)
            case let list as [String]:
                XCTAssertEqual(value as? [String] ?? [], list, key)
            default:
                XCTFail("unhandled expectation for \(key)")
            }
        }
    }
}

/// US-SO01: the Settings flow - confirm, upload, warn when changes remain, and never run twice at once.
@MainActor
final class AccountSignOutViewModelTests: XCTestCase {
    func testAllSavedSignsOutWithoutAWarning() async {
        let service = SpySignOutService(upload: .allSaved)
        let model = AccountSignOutViewModel(service: service, appState: AppState.preview(isOnboarded: true))

        model.signOutTapped()
        XCTAssertTrue(model.isConfirmationPresented)
        await model.confirmSignOut()

        XCTAssertEqual(service.uploads, 1)
        XCTAssertEqual(service.signOuts, 1)
        XCTAssertFalse(model.isUnsavedWarningPresented)
        XCTAssertEqual(model.phase, .idle)
    }

    func testUnsavedChangesWarnAndSignOutOnlyAnyway() async {
        let service = SpySignOutService(upload: .unsavedChanges)
        let model = AccountSignOutViewModel(service: service, appState: AppState.preview(isOnboarded: true))

        await model.confirmSignOut()

        XCTAssertTrue(model.isUnsavedWarningPresented, "decision 14: changes still waiting are never lost silently")
        XCTAssertEqual(service.signOuts, 0)

        await model.signOut()
        XCTAssertEqual(service.signOuts, 1, "Sign Out Anyway erases")
    }

    /// Cancel on the warning is the alert dismissing: nothing more runs and the user stays signed in.
    func testCancelOnTheWarningChangesNothing() async {
        let service = SpySignOutService(upload: .unsavedChanges)
        let appState = AppState.preview(isOnboarded: true)
        let model = AccountSignOutViewModel(service: service, appState: appState)

        await model.confirmSignOut()
        model.isUnsavedWarningPresented = false

        XCTAssertEqual(service.signOuts, 0)
        XCTAssertTrue(appState.isOnboarded)
        XCTAssertEqual(model.phase, .idle)
    }

    func testAConfirmWhileTheUploadRunsStartsNothingMore() async {
        let service = SpySignOutService(upload: .allSaved, holdsUpload: true)
        let model = AccountSignOutViewModel(service: service, appState: AppState.preview(isOnboarded: true))

        let first = Task { await model.confirmSignOut() }
        while model.phase != .uploading { await Task.yield() }
        XCTAssertTrue(model.isBusy)
        await model.confirmSignOut()
        await model.signOut()
        model.signOutTapped()
        XCTAssertFalse(model.isConfirmationPresented, "the row takes no second tap while it works")
        service.releaseUpload()
        await first.value

        XCTAssertEqual(service.uploads, 1)
        XCTAssertEqual(service.signOuts, 1)
    }

    func testAFailedEraseSaysSoAndCanBeRetried() async {
        let service = SpySignOutService(upload: .allSaved, failsSignOut: true)
        let model = AccountSignOutViewModel(service: service, appState: AppState.preview(isOnboarded: true))

        await model.confirmSignOut()
        XCTAssertTrue(model.isFailureAlertPresented)
        XCTAssertEqual(model.phase, .idle)

        service.failsSignOut = false
        await model.signOut()
        XCTAssertEqual(service.signOuts, 2)
    }

    func testTheRowSaysWhatItIsDoing() {
        XCTAssertNil(SettingsView.signOutProgress(.idle))
        XCTAssertEqual(SettingsView.signOutProgress(.uploading), "Saving your workouts\u{2026}")
        XCTAssertEqual(SettingsView.signOutProgress(.signingOut), "Signing out\u{2026}")
    }
}

@MainActor
private final class SpySignOutService: AccountSignOutServiceProtocol {
    private let upload: SignOutUploadResult
    private let holdsUpload: Bool
    var failsSignOut: Bool
    private(set) var uploads = 0
    private(set) var signOuts = 0
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    struct Failure: Error {}

    init(upload: SignOutUploadResult, holdsUpload: Bool = false, failsSignOut: Bool = false) {
        self.upload = upload
        self.holdsUpload = holdsUpload
        self.failsSignOut = failsSignOut
    }

    func releaseUpload() {
        released = true
        held?.resume()
        held = nil
    }

    func uploadPendingChanges(appState: AppState) async -> SignOutUploadResult {
        uploads += 1
        if holdsUpload && !released {
            await withCheckedContinuation { held = $0 }
        }
        return upload
    }

    func signOut(appState: AppState) async throws {
        signOuts += 1
        if failsSignOut { throw Failure() }
    }
}
