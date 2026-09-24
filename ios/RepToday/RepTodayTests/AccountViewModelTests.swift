import AuthenticationServices
import XCTest
@testable import RepToday

@MainActor
final class AccountViewModelTests: XCTestCase {
    private struct UnusedAuthorizer: AppleSignInAuthorizing {
        func authorize() async throws -> AppleSignInResult {
            XCTFail("Apple's button supplies the authorization; do not start a second ceremony")
            throw AuthError.invalidCredential
        }
    }

    private actor Store: AuthCredentialStore {
        var identifier: String?
        var readFails = false
        var saveFails = false
        var saves = 0
        init(identifier: String? = nil, readFails: Bool = false, saveFails: Bool = false) {
            self.identifier = identifier
            self.readFails = readFails
            self.saveFails = saveFails
        }
        func loadIdentifier() throws -> String? {
            if readFails { throw AuthError.failed("private storage error") }
            return identifier
        }
        func save(_ identifier: String) throws {
            saves += 1
            if saveFails { throw AuthError.failed("private storage error") }
            self.identifier = identifier
        }
        func clear() { identifier = nil }
        func allowReads() { readFails = false }
    }

    private func model(_ store: any AuthCredentialStore) -> AccountViewModel {
        AccountViewModel(authService: AppleAuthService(authorizer: UnusedAuthorizer(), store: store))
    }

    func testSuccessPersistsCredentialAndReloadShowsSignedIn() async throws {
        let store = Store()
        let vm = model(store)
        await vm.load()
        XCTAssertTrue(vm.canSignIn)
        vm.beginSignIn()
        XCTAssertFalse(vm.canSignIn)
        await vm.completeSignIn(.success("synthetic-apple-id"))
        XCTAssertEqual(vm.state, .signedIn)
        XCTAssertFalse(vm.isSigningIn)
        XCTAssertNil(vm.message)
        let saved = try await store.loadIdentifier()
        XCTAssertEqual(saved, "synthetic-apple-id")
        let reloaded = model(store)
        await reloaded.load()
        XCTAssertEqual(reloaded.state, .signedIn)
        XCTAssertFalse(reloaded.canSignIn)
    }

    func testCancelledAndFailedAuthorizationLeaveCredentialEmptyAndAllowRetry() async throws {
        for error in [AuthError.canceled as Error, ASAuthorizationError(.canceled),
                      AuthError.failed("private error"), AuthError.invalidCredential] {
            let store = Store()
            let vm = model(store)
            await vm.load()
            vm.beginSignIn()
            await vm.completeSignIn(.failure(error))
            XCTAssertEqual(vm.state, .signedOut)
            XCTAssertTrue(vm.canSignIn)
            XCTAssertFalse(vm.isSigningIn)
            let saved = try await store.loadIdentifier()
            let saves = await store.saves
            XCTAssertNil(saved)
            XCTAssertEqual(saves, 0)
            let cancelled = (error as? AuthError) == .canceled
                || (error as? ASAuthorizationError)?.code == .canceled
            XCTAssertEqual(vm.message == nil, cancelled)
            XCTAssertFalse(vm.message?.contains("private error") ?? false)
        }
    }

    func testStorageFailureDoesNotClaimSignIn() async throws {
        let store = Store(saveFails: true)
        let vm = model(store)
        await vm.load()
        vm.beginSignIn()
        await vm.completeSignIn(.success("synthetic-apple-id"))
        XCTAssertEqual(vm.state, .signedOut)
        XCTAssertTrue(vm.canSignIn)
        XCTAssertNotNil(vm.message)
        let saved = try await store.loadIdentifier()
        XCTAssertNil(saved)
    }

    func testAlreadySignedInCannotOverwriteCredential() async throws {
        let store = Store(identifier: "original-apple-id")
        let vm = model(store)
        await vm.load()
        vm.beginSignIn()
        await vm.completeSignIn(.success("other-apple-id"))
        XCTAssertEqual(vm.state, .signedIn)
        XCTAssertFalse(vm.canSignIn)
        let saved = try await store.loadIdentifier()
        let saves = await store.saves
        XCTAssertEqual(saved, "original-apple-id")
        XCTAssertEqual(saves, 0)
    }

    func testFailedCredentialReadRequiresStatusRetryBeforeSignIn() async {
        let store = Store(readFails: true)
        let vm = model(store)
        await vm.load()
        XCTAssertEqual(vm.state, .unavailable)
        XCTAssertFalse(vm.canSignIn)
        vm.beginSignIn()
        await vm.completeSignIn(.success("must-not-write"))
        let saves = await store.saves
        XCTAssertEqual(saves, 0)
        await store.allowReads()
        await vm.load()
        XCTAssertTrue(vm.canSignIn)
        XCTAssertNil(vm.message)
    }

    func testEmptyCredentialAndDuplicateCompletionDoNotWrite() async throws {
        let store = Store()
        let vm = model(store)
        await vm.load()
        vm.beginSignIn()
        await vm.completeSignIn(.success(""))
        XCTAssertTrue(vm.canSignIn)
        XCTAssertNotNil(vm.message)
        vm.beginSignIn()
        await vm.completeSignIn(.success("first"))
        await vm.completeSignIn(.success("second"))
        let saved = try await store.loadIdentifier()
        let saves = await store.saves
        XCTAssertEqual(saved, "first")
        XCTAssertEqual(saves, 1)
    }
}
