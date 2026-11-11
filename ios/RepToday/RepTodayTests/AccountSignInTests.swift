import AuthenticationServices
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

        vm.beginApple()
        XCTAssertEqual(vm.activity, .apple)
        await vm.handleApple(.failure(ASAuthorizationError(.canceled)))
        XCTAssertNil(vm.message)
        XCTAssertNil(vm.activity)
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

    func testSignedInTextNamesTheAccount() {
        XCTAssertEqual(AccountSignInPanel.signedInText(AccountIdentity(userId: "u", email: "a@b.co", method: .google)), "Signed in as a@b.co")
        XCTAssertEqual(AccountSignInPanel.signedInText(AccountIdentity(userId: "u", email: nil, method: .apple)), "Signed in with Apple")
    }

    // MARK: - The Account screen's words

    func testTheAccountScreenNeverDescribesDataAsLost() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let account = AccountIdentity(userId: "u", email: "riley@example.com", method: .email)
        let statuses: [AccountSyncCoordinator.Status] = [.upToDate, .syncing, .waitingForConnection, .retrying, .needsSignIn, .localOnly, .signedOut]
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
        let moving = AccountStatusPresentation(account: account, status: .syncing, pendingCount: 12, lastSyncedAt: nil, migrationStage: .uploading, now: now)
        XCTAssertEqual(moving.headline, "Moving your history to your account.")
        XCTAssertEqual(moving.detail, "12 changes to go. You can keep training while it saves.")
    }

    func testEveryKindOfSyncFailureMapsToAStatus() {
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.unreachable), .waitingForConnection)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.unauthenticated), .needsSignIn)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.notSignedIn), .needsSignIn)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.accountDeleting), .needsSignIn)
        XCTAssertEqual(AccountSyncCoordinator.status(for: SyncRemoteError.rejected(code: "invalid_change", message: "")), .retrying)
        XCTAssertEqual(AccountSyncCoordinator.status(for: CocoaError(.fileWriteUnknown)), .retrying)
    }

    // MARK: - Linking

    func testSigningInToADifferentAccountUploadsEverythingToIt() async throws {
        let suite = "AccountSignInTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stack = SyncTestStack()
        try await stack.users.save(SyncFixtures.user())
        try await stack.logs.save(SyncFixtures.log(daysAgo: 1))
        let appState = AppState(userDefaults: defaults)
        appState.linkAccount(AccountIdentity(userId: "first", email: nil, method: .email))
        appState.isOnboarded = true
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore(cursor: 17)
        let coordinator = AccountSyncCoordinator(
            engine: stack.engine(server, cursor: cursor),
            store: stack.store,
            cursorStore: cursor,
            appState: appState,
            migrator: LegacyAccountMigrator(appState: appState, store: stack.store, importer: LegacyICloudImportMonitor(settled: .nothingToImport), defaults: defaults),
            beginBackgroundWork: { _ in {} },
            onRemoteChangesApplied: {}
        )
        await coordinator.syncNow()

        coordinator.linkAccount(AccountIdentity(userId: "second", email: nil, method: .email))
        XCTAssertEqual(cursor.cursor(), 0, "a different account is read from its start")
        try await HostedSurface.settle(until: { coordinator.status == .upToDate && appState.account?.userId == "second" }, timeout: 5)
        await coordinator.syncNow()
        XCTAssertEqual(appState.account?.userId, "second")
        XCTAssertNil(appState.legacyMigrationStage, "switching accounts is not a migration")
        let logs = await server.rows(of: .workoutLog)
        XCTAssertEqual(logs.count, 1)
    }
}
