import Foundation

/// The real Sign in with Apple identity service (US-N01).
///
/// It composes two seams: an `AppleSignInAuthorizing` (the UIKit-bound authorization ceremony) and
/// an `AuthCredentialStore` (where the resulting identifier is persisted). Because both concurrency
/// and persistence live in those seams, the service itself is a stateless, `Sendable` composition -
/// unit-testable end to end with an in-memory store and a stubbed authorizer.
///
/// The identifier keys the user record, but sign-in is never a gate: `currentUserIdentifier()` reads
/// only local storage (no network, no iCloud account), so the core loop works fully offline whether
/// or not the user has ever signed in.
struct AppleAuthService: AuthServiceProtocol {
    private let authorizer: any AppleSignInAuthorizing
    private let store: any AuthCredentialStore

    init(authorizer: any AppleSignInAuthorizing, store: any AuthCredentialStore) {
        self.authorizer = authorizer
        self.store = store
    }

    /// The persisted identifier, or `nil` if the user has not signed in. A pure local read - it never
    /// calls Apple, so it resolves instantly and offline.
    func currentUserIdentifier() async throws -> String? {
        try await store.loadIdentifier()
    }

    /// Runs the Sign in with Apple ceremony, persists the returned stable identifier, and hands it
    /// back so the caller can key the user record by it.
    func signInWithApple() async throws -> String {
        let result = try await authorizer.authorize()
        try await store.save(result.userIdentifier)
        return result.userIdentifier
    }

    func signOut() async throws {
        try await store.clear()
    }
}

extension AppleAuthService {
    /// Production wiring: the real Sign in with Apple sheet backed by a Keychain-persisted
    /// identifier (survives reinstall, encrypted at rest, never leaves the device). Ready to be
    /// swapped into the production `ServiceContainer` when it lands (US-N02); `mock()` keeps
    /// `MockAuthService` so tests and previews stay Keychain-free and deterministic.
    static func live() -> AppleAuthService {
        AppleAuthService(
            authorizer: AppleIDSignInAuthorizer(),
            store: KeychainAuthCredentialStore()
        )
    }
}
