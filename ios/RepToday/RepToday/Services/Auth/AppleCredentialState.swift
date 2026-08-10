import Foundation
import AuthenticationServices

/// The current relationship between this install and its Sign in with Apple credential, as reported
/// by `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)` (US-AD05).
///
/// A framework-free mirror of `ASAuthorizationAppleIDProvider.CredentialState`, so the account-deletion
/// view model can decide whether to surface the "also stop using your Apple ID" guidance without any
/// test that exercises that decision having to import AuthenticationServices or reach a live Apple
/// service.
enum AppleCredentialStatus: Equatable {
    /// The credential is still valid for this install - Sign in with Apple was used and remains linked.
    case authorized
    /// The user revoked the credential (e.g. from Settings) - it was used, and detaching is done.
    case revoked
    /// Apple has no record of this app/user pairing - treated as "no Apple credential in play".
    case notFound
    /// The credential was transferred to another team - still a used Apple credential.
    case transferred
    /// An unrecognized state (a future `@unknown` case) - treated conservatively as "was used".
    case unknown
}

/// Resolves the Sign in with Apple credential state for a stored user id (US-AD05).
///
/// A one-method seam so the deletion flow's Apple-vs-local-UUID decision is unit-testable with a stub,
/// while the app uses the real `ASAuthorizationAppleIDProvider`. `Sendable` because the view model may
/// resolve it from a `Task`.
protocol AppleCredentialStateProviding: Sendable {
    func credentialStatus(forUserID userID: String) async -> AppleCredentialStatus
}

/// The production provider: asks `ASAuthorizationAppleIDProvider` for the credential state and bridges
/// its completion handler into `async` (US-AD05). Read-only - it queries the current state and never
/// revokes a token, matching the captain's Option (a): on-device guidance, no backend.
struct LiveAppleCredentialStateProvider: AppleCredentialStateProviding {
    func credentialStatus(forUserID userID: String) async -> AppleCredentialStatus {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                switch state {
                case .authorized: continuation.resume(returning: .authorized)
                case .revoked: continuation.resume(returning: .revoked)
                case .notFound: continuation.resume(returning: .notFound)
                case .transferred: continuation.resume(returning: .transferred)
                @unknown default: continuation.resume(returning: .unknown)
                }
            }
        }
    }
}
