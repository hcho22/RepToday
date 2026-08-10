import XCTest
@testable import RepToday

/// Tests for `AccountDeletionViewModel` (US-AD04 confirmation + re-entrancy, US-AD05 Apple-credential
/// guidance decision). The teardown is stubbed so these assert only the presentation logic: what the
/// confirmation names, that a confirm runs the teardown at most once, and that the post-deletion
/// Apple-ID guidance is armed only in the genuine Sign in with Apple case.
@MainActor
final class AccountDeletionViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AccountDeletionViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - US-AD05: guidance shows only in the Apple-credential case

    func testTappingResolvesAppleCaseAndPresentsConfirmation() async {
        let model = makeModel(
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized
        )
        await model.deleteAccountTapped()
        XCTAssertTrue(model.usedAppleCredential, "a stored, authorized Apple credential must read as used")
        XCTAssertTrue(model.isConfirmationPresented, "the confirmation was not presented")
    }

    func testConfirmingAnAppleAccountArmsTheGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized
        )
        await model.deleteAccountTapped()
        await model.confirmDeletion()
        XCTAssertTrue(appState.showAppleSignOutGuidance, "the Apple-ID guidance was not armed for an Apple account")
    }

    func testLocalUUIDAccountNeitherReadsAsAppleNorArmsGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: nil), // never signed in with Apple
            credentialStatus: .authorized // irrelevant: no stored identifier to query
        )
        await model.deleteAccountTapped()
        XCTAssertFalse(model.usedAppleCredential, "a local-UUID account must not read as an Apple account")
        await model.confirmDeletion()
        XCTAssertFalse(appState.showAppleSignOutGuidance, "the local-UUID case must not surface Apple guidance")
    }

    /// A stored identifier Apple no longer recognizes (`.notFound`) is treated as "no Apple credential
    /// in play", so no guidance - the guidance is for genuinely still-linked accounts.
    func testStoredIdentifierAppleReportsNotFoundShowsNoGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: "stale-apple-id"),
            credentialStatus: .notFound
        )
        await model.deleteAccountTapped()
        XCTAssertFalse(model.usedAppleCredential)
        await model.confirmDeletion()
        XCTAssertFalse(appState.showAppleSignOutGuidance)
    }

    // MARK: - US-AD04: re-entrancy

    /// Confirming twice while the first teardown is still in flight runs it exactly once.
    func testConfirmDeletionRunsTeardownOnceEvenOnDoubleTap() async {
        let spy = SpyAccountDeletionService()
        spy.block = true
        let model = makeModel(service: spy, auth: MockAuthService(userIdentifier: nil))

        let first = Task { await model.confirmDeletion() }
        let second = Task { await model.confirmDeletion() }

        // Let both invocations reach the guard: the first sets `isDeleting` and suspends in the
        // blocked teardown, the second must see the guard and return without a second call.
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(spy.callCount, 1, "the destructive teardown ran more than once on a double-tap")

        spy.release()
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(spy.callCount, 1, "a second teardown ran after the first completed")
    }

    // MARK: - Factories

    private func makeAppState() -> AppState {
        AppState(userDefaults: defaults)
    }

    private func makeModel(
        service: any AccountDeletionServiceProtocol = SpyAccountDeletionService(),
        appState: AppState? = nil,
        auth: MockAuthService = MockAuthService(userIdentifier: nil),
        credentialStatus: AppleCredentialStatus = .authorized
    ) -> AccountDeletionViewModel {
        AccountDeletionViewModel(
            accountDeletionService: service,
            authService: auth,
            appState: appState ?? AppState(userDefaults: defaults),
            credentialStateProvider: StubCredentialStateProvider(status: credentialStatus)
        )
    }
}

/// A stubbed credential-state provider (US-AD05) so the Apple-vs-local decision is tested without
/// AuthenticationServices or a live Apple service.
private struct StubCredentialStateProvider: AppleCredentialStateProviding {
    let status: AppleCredentialStatus
    func credentialStatus(forUserID userID: String) async -> AppleCredentialStatus { status }
}

/// A teardown spy that counts calls and can block mid-teardown, so the re-entrancy guard (US-AD04)
/// is provable: a blocked first call keeps `isDeleting` true while a second call is attempted.
private final class SpyAccountDeletionService: AccountDeletionServiceProtocol, @unchecked Sendable {
    private(set) var callCount = 0
    var block = false
    private var continuation: CheckedContinuation<Void, Never>?

    func deleteAccount(appState: AppState) async throws {
        callCount += 1
        if block {
            await withCheckedContinuation { continuation = $0 }
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
