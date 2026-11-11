import XCTest
@testable import RepToday

/// The account sign-in panel's behavior (M3, US-AU02/US-AU04) and the Account screen's words, without
/// Clerk: `StubAccountAuthService` scripts each outcome.
@MainActor
final class AccountSignInTests: XCTestCase {

    private final class FinishRecorder {
        var finished: [AccountIdentity] = []
        var failuresLeft = 0
    }

    private func model(
        auth: StubAccountAuthService = StubAccountAuthService(isConfigured: true),
        context: AccountSignInViewModel.Context = .onboarding,
        recorder: FinishRecorder = FinishRecorder()
    ) -> AccountSignInViewModel {
        AccountSignInViewModel(auth: auth, context: context) { identity in
            if recorder.failuresLeft > 0 {
                recorder.failuresLeft -= 1
                throw OnboardingViewModel.CompletionError.accountUnreachable
            }
            recorder.finished.append(identity)
        }
    }

    // MARK: - Email

    func testAnEmailCodeSignsInAndFinishes() async {
        let recorder = FinishRecorder()
        let vm = model(recorder: recorder)
        vm.chooseEmail()
        XCTAssertEqual(vm.phase, .email)
        XCTAssertFalse(vm.canSendCode)
        vm.email = " riley@example.com "
        XCTAssertTrue(vm.canSendCode)

        await vm.sendCode()
        XCTAssertEqual(vm.phase, .code(EmailCodeChallenge(email: "riley@example.com")))
        vm.code = StubAccountAuthService.acceptedCode
        await vm.verifyCode()

        XCTAssertEqual(recorder.finished, [AccountIdentity(userId: "user_stub_email", email: "riley@example.com", method: .email)])
        XCTAssertNil(vm.message)
        XCTAssertNil(vm.activity)
    }

    func testAWrongCodeSaysSoAndStaysOnTheCodeScreen() async {
        let recorder = FinishRecorder()
        let vm = model(recorder: recorder)
        vm.chooseEmail()
        vm.email = "riley@example.com"
        await vm.sendCode()
        vm.code = "000000"
        await vm.verifyCode()
        XCTAssertEqual(vm.message, "That code didn't match. Check the email we sent and try again.")
        XCTAssertEqual(vm.phase, .code(EmailCodeChallenge(email: "riley@example.com")))
        XCTAssertTrue(recorder.finished.isEmpty)
    }

    func testABadAddressIsCaughtBeforeAnyCodeIsSent() async {
        let auth = StubAccountAuthService(isConfigured: true)
        let vm = model(auth: auth)
        vm.chooseEmail()
        vm.email = "not-an-email"
        XCTAssertFalse(vm.canSendCode)
        vm.email = "a@b"
        await vm.sendCode()
        XCTAssertEqual(vm.message, "That email address doesn't look right. Check it and try again.")
        let sent = await auth.sentCodes
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - Failures

    func testOfflineSignInExplainsWhatToDoInEachContext() async {
        let auth = StubAccountAuthService(isConfigured: true)
        await auth.failNext(with: .unreachable)
        let onboarding = model(auth: auth)
        await onboarding.signInWithGoogle()
        XCTAssertEqual(onboarding.message, "Signing in needs a connection. Your answers are kept here - try again when you're online.")
        XCTAssertEqual(onboarding.phase, .choosing)

        await auth.failNext(with: .unreachable)
        let existing = model(auth: auth, context: .existingUser)
        await existing.signInWithGoogle()
        XCTAssertEqual(existing.message, "Signing in needs a connection. Everything on this phone stays as it is - try again when you're online.")
    }

    func testACanceledSheetSaysNothing() async {
        let auth = StubAccountAuthService(isConfigured: true)
        await auth.failNext(with: .canceled)
        let vm = model(auth: auth)
        await vm.signInWithGoogle()
        XCTAssertNil(vm.message)
        XCTAssertEqual(vm.phase, .choosing)

        await auth.failNext(with: .canceled)
        await vm.signInWithApple()
        XCTAssertNil(vm.message)
        XCTAssertNil(vm.activity)
        XCTAssertEqual(vm.phase, .choosing)
    }

    func testABuildWithoutSignInSaysSo() async {
        let vm = AccountSignInViewModel(auth: UnavailableAccountAuthService(), context: .onboarding) { _ in }
        XCTAssertFalse(vm.isConfigured)
        await vm.signInWithGoogle()
        XCTAssertEqual(vm.message, "Sign-in isn't available in this build.")
    }

    // MARK: - Finishing

    func testAFailedFinishRetriesWithoutSigningInAgain() async {
        let auth = StubAccountAuthService(isConfigured: true)
        let recorder = FinishRecorder()
        recorder.failuresLeft = 1
        let vm = model(auth: auth, recorder: recorder)

        await vm.signInWithGoogle()
        guard case .signedIn(let identity) = vm.phase else { return XCTFail("signed in, waiting to finish") }
        XCTAssertEqual(vm.message, "You're signed in, but we couldn't reach your account to save your plan. Check your connection and try again.")
        XCTAssertTrue(recorder.finished.isEmpty)

        await vm.retryFinishing()
        XCTAssertEqual(recorder.finished, [identity])
        XCTAssertNil(vm.message)
    }

    func testASessionAlreadyOnTheDeviceIsOfferedBack() async {
        let existing = AccountIdentity(userId: "user_kept", email: "riley@example.com", method: .apple)
        let auth = StubAccountAuthService(isConfigured: true, identity: existing)
        let vm = model(auth: auth)
        await vm.load()
        XCTAssertEqual(vm.phase, .signedIn(existing))

        await vm.useDifferentAccount()
        XCTAssertEqual(vm.phase, .choosing)
        let signOuts = await auth.signOutCount
        XCTAssertEqual(signOuts, 1)
    }

    func testAppleSignInFinishes() async {
        let recorder = FinishRecorder()
        let vm = model(recorder: recorder)
        await vm.signInWithApple()
        XCTAssertEqual(recorder.finished, [AccountIdentity(userId: "user_stub_apple", email: nil, method: .apple)])
    }

    func testSignedInTextNamesTheAccount() {
        XCTAssertEqual(AccountSignInPanel.signedInText(AccountIdentity(userId: "u", email: "a@example.com", method: .google)), "Signed in as a@example.com")
        XCTAssertEqual(AccountSignInPanel.signedInText(AccountIdentity(userId: "u", email: nil, method: .apple)), "Signed in with Apple")
    }

    // MARK: - The Account screen's words

    func testTheAccountScreenNeverDescribesDataAsLost() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let account = AccountIdentity(userId: "u", email: "riley@example.com", method: .email)
        let statuses: [AccountSyncCoordinator.Status] = [.upToDate, .syncing, .waitingForConnection, .retrying, .needsSignIn, .accountBeingDeleted, .localOnly, .signedOut]
        for status in statuses {
            let presentation = AccountStatusPresentation(account: account, status: status, pendingCount: 3, lastSyncedAt: now, migrationStage: nil, now: now)
            let words = [presentation.headline, presentation.detail ?? ""].joined(separator: " ").lowercased()
            XCTAssertFalse(words.contains("lost") || words.contains("streak"), "\(status): \(words)")
            XCTAssertEqual(presentation.offersSignIn, status == .needsSignIn)
        }
        let waiting = AccountStatusPresentation(account: account, status: .waitingForConnection, pendingCount: 1, lastSyncedAt: nil, migrationStage: nil, now: now)
        XCTAssertEqual(waiting.headline, "1 change will save when you're online.")
        let saved = AccountStatusPresentation(account: account, status: .upToDate, pendingCount: 0, lastSyncedAt: now, migrationStage: nil, now: now)
        XCTAssertEqual(saved.detail, "Last saved just now.")
        XCTAssertEqual(saved.accountLine, "Signed in with email")
        XCTAssertEqual(saved.accountDetail, "riley@example.com")
        let moving = AccountStatusPresentation(account: account, status: .syncing, pendingCount: 12, lastSyncedAt: nil, migrationStage: .uploading, now: now)
        XCTAssertEqual(moving.headline, "Moving your history to your account.")
        XCTAssertEqual(moving.detail, "12 changes to go. You can keep training while it saves.")
    }

    func testEveryKindOfSyncFailureMapsToAStatus() {
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.unreachable), .waitingForConnection)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.unauthenticated), .needsSignIn)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.notSignedIn), .needsSignIn)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.accountDeleting), .accountBeingDeleted)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.noResponse), .waitingForConnection)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.rejected(code: "invalid_change", message: "")), .retrying)
        XCTAssertEqual(AccountSyncCoordinator.status(for: CocoaError(.fileWriteUnknown)), .retrying)
    }

    // MARK: - Linking

    /// The phone's data belongs to the account it is linked to: linking a different account is refused,
    /// and nothing is re-queued, re-read or uploaded for it.
    func testLinkingADifferentAccountIsRefusedAndUploadsNothing() async throws {
        let fixture = try await linkedFixture()
        await fixture.coordinator.syncNow()
        let pushesBefore = await fixture.server.pushCalls

        XCTAssertThrowsError(try fixture.coordinator.linkAccount(Self.otherAccount)) { error in
            XCTAssertEqual(error as? AccountLinkError, .belongsToAnotherAccount(linked: Self.originalAccount))
        }
        await fixture.coordinator.syncNow()

        XCTAssertEqual(fixture.appState.account, Self.originalAccount)
        XCTAssertEqual(fixture.cursor.cursor(), 17, "the linked account's cursor is untouched")
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [], "nothing is queued for the other account")
        let pushesAfter = await fixture.server.pushCalls
        XCTAssertEqual(pushesAfter, pushesBefore)
        let pushed = await fixture.server.pushedChanges
        XCTAssertEqual(pushed, 2, "only the original upload of the profile and the log")
    }

    /// Signing in to another account from the Account screen is refused, signs that session out, and
    /// signing back in to the original account carries on as before.
    func testSigningInToAnotherAccountOffersSigningBackInToTheOriginal() async throws {
        let fixture = try await linkedFixture()
        let auth = StubAccountAuthService(isConfigured: true)
        let vm = AccountSignInViewModel(auth: auth, context: .existingUser, eraseThisDevice: {}) { identity in
            try fixture.coordinator.linkAccount(identity)
        }

        await vm.signInWithGoogle()

        XCTAssertEqual(vm.phase, .belongsToAnotherAccount(attempted: Self.otherAccount))
        let session = await auth.currentIdentity()
        XCTAssertNil(session, "the other account's session is signed out, so sync cannot use it")
        XCTAssertEqual(fixture.appState.account, Self.originalAccount)
        XCTAssertTrue(vm.canEraseThisDevice)

        vm.showChoices()
        await vm.signInWithApple()

        XCTAssertEqual(vm.phase, .signedIn(Self.originalAccount))
        XCTAssertNil(vm.message)
        XCTAssertEqual(fixture.appState.account, Self.originalAccount)
    }

    /// An account deleted from another device: this phone's old history must not upload into the new
    /// account the same Apple ID now signs in to. The phone refuses, then erases its data on request
    /// (the account itself is not deleted again) and starts over, after which the new account links.
    func testAnAccountDeletedElsewhereIsErasedHereBeforeAnotherAccountLinks() async throws {
        let fixture = try await linkedFixture()
        try await fixture.stack.logs.save(SyncFixtures.log(daysAgo: 0))
        await fixture.server.failPush(call: 1, with: .accountDeleting)
        await fixture.coordinator.syncNow()
        XCTAssertEqual(fixture.coordinator.status, .accountBeingDeleted)

        let service = AccountDeletionService(
            userService: fixture.stack.users,
            workoutLogService: fixture.stack.logs,
            sessionPolicyStore: fixture.stack.policies,
            activeSessionStore: fixture.stack.activeSessions,
            authService: MockAuthService(),
            outsideActivityService: fixture.stack.activities,
            account: AccountDeletionService.AccountTeardown(
                remote: fixture.server,
                auth: StubAccountAuthService(isConfigured: true),
                syncStore: fixture.stack.store,
                cursorStore: fixture.cursor,
                defaults: fixture.defaults
            )
        )
        let auth = StubAccountAuthService(isConfigured: true)
        let vm = AccountSignInViewModel(
            auth: auth,
            context: .existingUser,
            eraseThisDevice: { try await service.eraseThisDevice(appState: fixture.appState) }
        ) { identity in
            try fixture.coordinator.linkAccount(identity)
        }
        await vm.signInWithGoogle()
        XCTAssertEqual(vm.phase, .belongsToAnotherAccount(attempted: Self.otherAccount))

        vm.requestErase()
        XCTAssertTrue(vm.isEraseConfirmationPresented)
        await vm.confirmErase()

        XCTAssertNil(vm.message)
        let user = try await fixture.stack.users.currentUser()
        XCTAssertNil(user)
        let logs = try await fixture.stack.logs.workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [])
        let outbox = try await fixture.stack.outbox()
        XCTAssertEqual(outbox, [])
        XCTAssertNil(fixture.appState.account)
        XCTAssertFalse(fixture.appState.isOnboarded, "the phone starts setting up again")
        let deletions = await fixture.server.deleteCalls
        XCTAssertEqual(deletions, 0, "erasing the phone deletes no account")

        XCTAssertNoThrow(try fixture.coordinator.linkAccount(Self.otherAccount))
        XCTAssertEqual(fixture.appState.account, Self.otherAccount)
    }

    func testTheOtherAccountScreenNamesWhoSignedInAndOffersErasingOnlyWhereItCan() {
        let withErase = AccountSignInPanel.anotherAccountText(Self.otherAccount, canErase: true)
        XCTAssertTrue(withErase.hasPrefix("You signed in as you@example.com."))
        XCTAssertTrue(withErase.contains("erase this phone's Rep Today data"))
        let withoutErase = AccountSignInPanel.anotherAccountText(Self.originalAccount, canErase: false)
        XCTAssertTrue(withoutErase.hasPrefix("You signed in to a different account."))
        XCTAssertFalse(withoutErase.contains("erase"))
    }

    /// Signing in at "Save your plan" to an account whose deletion is still pending says exactly that,
    /// not that the account cannot be reached, and saves nothing.
    func testSigningInToAnAccountStillBeingDeletedSaysSo() async throws {
        let stack = SyncTestStack()
        let server = FakeAccountServer()
        await server.failPull(call: 1, with: .accountDeleting)
        let onboarding = OnboardingViewModel(
            userService: stack.users,
            sessionPolicyService: DeterministicSessionPolicyService(store: stack.policies, exerciseService: try MockExerciseService(), userService: stack.users),
            accountRestorer: stack.engine(server)
        )
        let vm = AccountSignInViewModel(auth: StubAccountAuthService(isConfigured: true), context: .onboarding) { identity in
            _ = try await onboarding.completeSignIn(as: identity)
        }

        await vm.signInWithApple()

        XCTAssertEqual(vm.message, AccountSignInViewModel.accountBeingDeletedMessage)
        XCTAssertEqual(vm.message, "This account is still being deleted. Try again later, or use a different sign-in.")
        XCTAssertEqual(vm.phase, .signedIn(Self.originalAccount), "Continue tries again later; a different sign-in is offered beside it")
        let user = try await stack.users.currentUser()
        XCTAssertNil(user)
    }

    func testAPhoneLinkedToAnAccountBeingDeletedIsOfferedErasingNotSigningIn() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let presentation = AccountStatusPresentation(account: Self.originalAccount, status: .accountBeingDeleted, pendingCount: 0, lastSyncedAt: nil, migrationStage: nil, now: now)
        XCTAssertFalse(presentation.offersSignIn)
        XCTAssertTrue(presentation.offersErase)
        XCTAssertEqual(presentation.headline, "This account is being deleted.")
        XCTAssertEqual(presentation.detail, "That finishes on its own. This phone keeps its plan and sessions until you erase them. Erasing them lets you set up with another account, starting fresh on this phone.")
        for status in [AccountSyncCoordinator.Status.upToDate, .syncing, .waitingForConnection, .retrying, .needsSignIn, .localOnly, .signedOut] {
            let other = AccountStatusPresentation(account: Self.originalAccount, status: status, pendingCount: 0, lastSyncedAt: nil, migrationStage: nil, now: now)
            XCTAssertFalse(other.offersErase, "\(status)")
        }
    }

    /// Once the account answers that it is being deleted, the phone stays in that state - across a
    /// relaunch, and after the deletion finishes and the account can no longer answer - so it never
    /// invites a sign-in that could only be refused.
    func testAnAccountBeingDeletedStaysSoAndNeverInvitesASignIn() async throws {
        let fixture = try await linkedFixture()
        await fixture.server.failPush(call: 1, with: .accountDeleting)
        await fixture.coordinator.syncNow()
        XCTAssertEqual(fixture.coordinator.status, .accountBeingDeleted)
        XCTAssertTrue(fixture.appState.isLinkedAccountBeingDeleted)

        let relaunched = AccountSyncCoordinator(
            engine: fixture.stack.engine(fixture.server, cursor: fixture.cursor),
            store: fixture.stack.store,
            appState: fixture.appState,
            migrator: LegacyAccountMigrator(appState: fixture.appState, store: fixture.stack.store, importer: LegacyICloudImportMonitor(settled: .nothingToImport), defaults: fixture.defaults),
            beginBackgroundWork: { _ in {} },
            onRemoteChangesApplied: {}
        )
        XCTAssertEqual(relaunched.status, .accountBeingDeleted)
        await fixture.server.failPush(call: 2, with: .unauthenticated)
        await relaunched.syncNow()
        XCTAssertEqual(relaunched.status, .accountBeingDeleted)
        let pushes = await fixture.server.pushCalls
        XCTAssertEqual(pushes, 1, "nothing more is sent to an account being deleted")
    }

    // MARK: - Fixtures

    private static let originalAccount = AccountIdentity(userId: "user_stub_apple", email: nil, method: .apple)
    private static let otherAccount = AccountIdentity(userId: "user_stub_google", email: "you@example.com", method: .google)

    private struct LinkedFixture {
        let stack: SyncTestStack
        let server: FakeAccountServer
        let cursor: InMemorySyncCursorStore
        let appState: AppState
        let coordinator: AccountSyncCoordinator
        let defaults: UserDefaults
    }

    /// A phone linked to `originalAccount`, holding a profile and a log.
    private func linkedFixture() async throws -> LinkedFixture {
        let suite = "AccountSignInTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        try await stack.logs.save(SyncFixtures.log(daysAgo: 1))
        let appState = AppState(userDefaults: defaults)
        try appState.linkAccount(Self.originalAccount)
        appState.isOnboarded = true
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore(cursor: 17)
        let coordinator = AccountSyncCoordinator(
            engine: stack.engine(server, cursor: cursor),
            store: stack.store,
            appState: appState,
            migrator: LegacyAccountMigrator(appState: appState, store: stack.store, importer: LegacyICloudImportMonitor(settled: .nothingToImport), defaults: defaults),
            beginBackgroundWork: { _ in {} },
            onRemoteChangesApplied: {}
        )
        return LinkedFixture(stack: stack, server: server, cursor: cursor, appState: appState, coordinator: coordinator, defaults: defaults)
    }
}
