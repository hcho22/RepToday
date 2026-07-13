import XCTest
@testable import FitSnack

/// Tests the real Sign in with Apple identity service (US-N01).
///
/// The service composes two seams - an `AppleSignInAuthorizing` (the UIKit ceremony) and an
/// `AuthCredentialStore` (persistence). Both are stubbed here, so these tests cover the real
/// composition end to end without a live Apple sheet or the Keychain:
/// - a successful sign-in returns the stable identifier and persists it;
/// - `currentUserIdentifier()` reads back the persisted identifier (offline, no network);
/// - `signOut()` clears it;
/// - a failed authorization propagates and leaves the store untouched (offline-first fallback).
final class AppleAuthServiceTests: XCTestCase {

    // MARK: - Stubs

    private struct StubAuthorizer: AppleSignInAuthorizing {
        let result: Result<AppleSignInResult, AuthError>
        func authorize() async throws -> AppleSignInResult {
            switch result {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

    private func makeService(
        authorizer: StubAuthorizer,
        store: any AuthCredentialStore = InMemoryAuthCredentialStore()
    ) -> AppleAuthService {
        AppleAuthService(authorizer: authorizer, store: store)
    }

    // MARK: - Sign in

    func testSignInReturnsAndPersistsIdentifier() async throws {
        let store = InMemoryAuthCredentialStore()
        let service = makeService(
            authorizer: StubAuthorizer(result: .success(AppleSignInResult(userIdentifier: "apple-001"))),
            store: store
        )

        let returned = try await service.signInWithApple()

        XCTAssertEqual(returned, "apple-001")
        let persisted = try await store.loadIdentifier()
        XCTAssertEqual(persisted, "apple-001", "the signed-in identifier is stored to key the user record")
    }

    func testCurrentUserIdentifierIsNilBeforeSignIn() async throws {
        let service = makeService(
            authorizer: StubAuthorizer(result: .success(AppleSignInResult(userIdentifier: "unused")))
        )
        let current = try await service.currentUserIdentifier()
        XCTAssertNil(current, "a fresh install has no identity until the user signs in")
    }

    func testCurrentUserIdentifierReadsBackPersistedIdentity() async throws {
        let service = makeService(
            authorizer: StubAuthorizer(result: .success(AppleSignInResult(userIdentifier: "apple-777")))
        )

        _ = try await service.signInWithApple()
        let current = try await service.currentUserIdentifier()

        XCTAssertEqual(current, "apple-777", "the persisted identifier is a local read - resolves offline")
    }

    func testSignOutClearsIdentity() async throws {
        let service = makeService(
            authorizer: StubAuthorizer(result: .success(AppleSignInResult(userIdentifier: "apple-abc")))
        )
        _ = try await service.signInWithApple()

        try await service.signOut()

        let current = try await service.currentUserIdentifier()
        XCTAssertNil(current)
    }

    func testSignInFailurePropagatesAndLeavesStoreUntouched() async throws {
        let store = InMemoryAuthCredentialStore()
        let service = makeService(authorizer: StubAuthorizer(result: .failure(.canceled)), store: store)

        do {
            _ = try await service.signInWithApple()
            XCTFail("a canceled authorization should throw")
        } catch let error as AuthError {
            XCTAssertEqual(error, .canceled)
        }

        let persisted = try await store.loadIdentifier()
        XCTAssertNil(persisted, "a failed sign-in never writes an identifier")
    }

    // MARK: - In-memory credential store

    func testInMemoryStoreRoundTrips() async throws {
        let store = InMemoryAuthCredentialStore()
        var loaded = try await store.loadIdentifier()
        XCTAssertNil(loaded)

        try await store.save("id-1")
        loaded = try await store.loadIdentifier()
        XCTAssertEqual(loaded, "id-1")

        try await store.save("id-2")
        loaded = try await store.loadIdentifier()
        XCTAssertEqual(loaded, "id-2", "save overwrites")

        try await store.clear()
        loaded = try await store.loadIdentifier()
        XCTAssertNil(loaded)
    }

    func testInMemoryStoreSeedsWithInitialIdentifier() async throws {
        let store = InMemoryAuthCredentialStore(identifier: "seeded")
        let loaded = try await store.loadIdentifier()
        XCTAssertEqual(loaded, "seeded")
    }
}
