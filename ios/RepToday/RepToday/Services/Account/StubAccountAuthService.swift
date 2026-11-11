import Foundation

/// A sign-in service with no Clerk behind it: every sign-in succeeds on the device and no session
/// token exists, so nothing ever syncs.
///
/// Used by the mock container (tests and previews), by XCUITests (`-RepTodayAccountStub YES`), and by
/// a Debug build that carries no Clerk publishable key, so those builds can still finish onboarding.
/// A Release build never uses it: with no key it gets `UnavailableAccountAuthService`, and the
/// archive script refuses to build one (`tools/archive-release.sh`).
///
/// Tests can script the next failure (`failNext(with:)`) and read what was asked of it.
actor StubAccountAuthService: AccountAuthServiceProtocol {
    /// `false`: the sign-in screen says sign-in is simulated in this build.
    nonisolated let isConfigured: Bool
    private var identity: AccountIdentity?
    private var token: String?
    private var nextError: AccountAuthError?
    private(set) var signOutCount = 0
    private(set) var sentCodes: [String] = []

    /// The code a test or a person types on the simulated email screen. Any other code is refused.
    static let acceptedCode = "424242"

    init(isConfigured: Bool = false, identity: AccountIdentity? = nil, token: String? = nil) {
        self.isConfigured = isConfigured
        self.identity = identity
        self.token = token
    }

    /// Makes the next sign-in call fail with `error`.
    func failNext(with error: AccountAuthError) {
        nextError = error
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func currentIdentity() async -> AccountIdentity? { identity }

    func signInWithApple(identityToken: String) async throws -> AccountIdentity {
        try signIn(.apple, email: nil)
    }

    func signInWithGoogle() async throws -> AccountIdentity {
        try signIn(.google, email: "you@example.com")
    }

    func sendEmailCode(to email: String) async throws -> EmailCodeChallenge {
        try throwScripted()
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), address.contains(".") else { throw AccountAuthError.invalidEmail }
        sentCodes.append(address)
        return EmailCodeChallenge(email: address)
    }

    func verifyEmailCode(_ code: String, for challenge: EmailCodeChallenge) async throws -> AccountIdentity {
        try throwScripted()
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == Self.acceptedCode else { throw AccountAuthError.invalidCode }
        return try signIn(.email, email: challenge.email)
    }

    func sessionToken() async throws -> String? { identity == nil ? nil : token }

    func signOut() async {
        signOutCount += 1
        identity = nil
    }

    private func signIn(_ method: AccountSignInMethod, email: String?) throws -> AccountIdentity {
        try throwScripted()
        let signedIn = AccountIdentity(userId: "user_stub_\(method.rawValue)", email: email, method: method)
        identity = signedIn
        return signedIn
    }

    private func throwScripted() throws {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
    }
}

/// A Release build with no Clerk publishable key: sign-in is unavailable, and says so. Nothing can be
/// faked into an account in a build that could ship.
struct UnavailableAccountAuthService: AccountAuthServiceProtocol {
    let isConfigured = false
    func currentIdentity() async -> AccountIdentity? { nil }
    func signInWithApple(identityToken: String) async throws -> AccountIdentity { throw AccountAuthError.notConfigured }
    func signInWithGoogle() async throws -> AccountIdentity { throw AccountAuthError.notConfigured }
    func sendEmailCode(to email: String) async throws -> EmailCodeChallenge { throw AccountAuthError.notConfigured }
    func verifyEmailCode(_ code: String, for challenge: EmailCodeChallenge) async throws -> AccountIdentity {
        throw AccountAuthError.notConfigured
    }
    func sessionToken() async throws -> String? { nil }
    func signOut() async {}
}
