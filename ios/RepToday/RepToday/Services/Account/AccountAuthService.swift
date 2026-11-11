import Foundation

/// The signed-in Rep Today account (M3, ADR-0016): the Clerk user the device's data syncs to.
struct AccountIdentity: Codable, Equatable, Sendable {
    /// The Clerk user id. Never shown; it keys nothing on the device.
    let userId: String
    /// The account's primary email address, when the sign-in method shared one.
    let email: String?
    let method: AccountSignInMethod
}

/// How the user signed in (decision 23).
enum AccountSignInMethod: String, Codable, CaseIterable, Sendable {
    case apple
    case google
    case email
}

/// An email sign-in waiting for its one-time code.
struct EmailCodeChallenge: Equatable, Sendable {
    let email: String
}

/// Why signing in did not complete. Every case leaves the device exactly as it was.
enum AccountAuthError: Error, Equatable {
    /// This build has no sign-in configured (no Clerk publishable key).
    case notConfigured
    /// The user closed the Apple, Google or browser sheet.
    case canceled
    /// No connection. Signing in needs one; everything already on the device keeps working.
    case unreachable
    /// The email address was not accepted.
    case invalidEmail
    /// The code was wrong or has expired.
    case invalidCode
    /// Clerk refused or failed for another reason.
    case failed(String)
}

/// Why the device was not linked to the account the user signed in to.
enum AccountLinkError: Error, Equatable {
    /// The device's data belongs to `linked`, a different account. It is never uploaded to, or merged
    /// with, another account; signing in to `linked`, or erasing the device's data, are the ways on.
    case belongsToAnotherAccount(linked: AccountIdentity)
}

/// Signs the user in to their Rep Today account and hands the sync layer a session token
/// (M3, US-AU02/US-AU04).
///
/// The production implementation is `ClerkAccountAuthService`; tests, previews and a Debug build with
/// no Clerk key use `StubAccountAuthService`. Nothing here gates the core loop once the device is
/// linked to an account: whether the app may open is decided by the persisted link on `AppState`, read
/// with no network, and a session that cannot refresh only pauses sync.
protocol AccountAuthServiceProtocol: Sendable {
    /// Whether this build can sign in at all.
    var isConfigured: Bool { get }

    /// The signed-in account, from the session cached on the device.
    func currentIdentity() async -> AccountIdentity?

    /// Runs Sign in with Apple (Apple's own sheet), creating the account if it is new.
    func signInWithApple() async throws -> AccountIdentity

    /// Runs Google sign-in in a browser sheet, creating the account if it is new.
    func signInWithGoogle() async throws -> AccountIdentity

    /// Sends a one-time code to `email`, for a new or an existing account.
    func sendEmailCode(to email: String) async throws -> EmailCodeChallenge

    /// Checks the code and signs in.
    func verifyEmailCode(_ code: String, for challenge: EmailCodeChallenge) async throws -> AccountIdentity

    /// A fresh session token for the account backend, or `nil` when no account is signed in.
    func sessionToken() async throws -> String?

    /// Ends the session on this device. Tolerates a session the server already removed (a deleted
    /// account), so it is safe at the end of account deletion.
    func signOut() async
}

extension AccountAuthServiceProtocol {
    /// A session token for the account backend, only when it was issued to `linkedUserId`, the Clerk
    /// user this device is linked to. A session for any other account - one signed in moments before it
    /// is refused and signed out, or one a failed sign-out left behind - yields no token, so nothing is
    /// pulled from or uploaded to an account this device's data does not belong to. With no linked
    /// account (onboarding's restore, before the device links), any session's token is returned.
    func sessionToken(forLinkedAccount linkedUserId: String?) async throws -> String? {
        guard let token = try await sessionToken() else { return nil }
        guard let linkedUserId else { return token }
        return SessionTokenClaims.subject(of: token) == linkedUserId ? token : nil
    }
}

/// Reads the subject (`sub`, the Clerk user id) a Clerk session token was issued to. The token is a
/// JWT; only its payload is decoded, never verified - the account backend verifies it.
enum SessionTokenClaims {
    static func subject(of token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var payload = segments[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["sub"] as? String
    }
}
