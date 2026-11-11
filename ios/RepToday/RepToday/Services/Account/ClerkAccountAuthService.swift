import AuthenticationServices
import ClerkKit
import Foundation

/// Sign-in through Clerk (M3, decision 23, ADR-0016): Apple, Google and email codes, using Clerk's
/// official iOS SDK (`ClerkKit`, its core target only - the sign-in screen is Rep Today's own).
///
/// The publishable key comes from the build (`RepTodayClerkPublishableKey` in `Info.plist`, expanded
/// from `REPTODAY_CLERK_PUBLISHABLE_KEY`). It is a public identifier, not a secret; no secret key ever
/// ships in the app. A build without one gets no instance of this type and uses
/// `StubAccountAuthService` instead (`ServiceContainer.live`).
///
/// Clerk keeps the session in the Keychain and refreshes its short-lived session token itself;
/// `sessionToken()` hands the current one to the account backend, which verifies it against the
/// Clerk instance (`convex/auth.config.ts`). Clerk's SDK telemetry is switched off.
final class ClerkAccountAuthService: AccountAuthServiceProtocol, @unchecked Sendable {
    // Safe: the only mutable state is main-actor isolated; `publishableKey` is immutable.
    let isConfigured = true
    private let publishableKey: String

    /// An email sign-in waiting for its code: a sign-in for an existing account, or a sign-up.
    private enum PendingEmailFlow {
        case signIn(SignIn)
        case signUp(SignUp)
    }

    @MainActor private var pendingEmailFlow: PendingEmailFlow?
    @MainActor private var didConfigure = false

    /// The `Info.plist` key carrying the publishable key.
    static let publishableKeyInfoKey = "RepTodayClerkPublishableKey"

    init(publishableKey: String) {
        self.publishableKey = publishableKey
    }

    /// The service for this build, or `nil` when the build carries no usable publishable key (empty, or
    /// the unexpanded build-setting reference).
    static func configured(bundle: Bundle = .main) -> ClerkAccountAuthService? {
        guard let key = bundle.object(forInfoDictionaryKey: publishableKeyInfoKey) as? String,
              let usable = usablePublishableKey(key) else {
            return nil
        }
        return ClerkAccountAuthService(publishableKey: usable)
    }

    /// A Clerk publishable key is `pk_test_...` or `pk_live_...`; anything else is not configuration.
    static func usablePublishableKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_"), key.count > "pk_test_".count else { return nil }
        return key
    }

    /// Configures the shared Clerk instance once, so it restores the cached session at launch.
    @MainActor
    func start() {
        guard !didConfigure else { return }
        didConfigure = true
        Clerk.configure(
            publishableKey: publishableKey,
            options: .init(telemetryEnabled: false, updateRequiredViewEnabled: false)
        )
    }

    // MARK: - AccountAuthServiceProtocol

    @MainActor
    func currentIdentity() async -> AccountIdentity? {
        start()
        guard Clerk.shared.session?.status == .active, let user = Clerk.shared.user else { return nil }
        return Self.identity(of: user, method: nil)
    }

    @MainActor
    func signInWithApple(identityToken: String) async throws -> AccountIdentity {
        start()
        return try await mapped(.apple) {
            try await Clerk.shared.auth.signInWithIdToken(identityToken, provider: .apple)
        }
    }

    @MainActor
    func signInWithGoogle() async throws -> AccountIdentity {
        start()
        return try await mapped(.google) {
            try await Clerk.shared.auth.signInWithOAuth(provider: .google)
        }
    }

    @MainActor
    func sendEmailCode(to email: String) async throws -> EmailCodeChallenge {
        start()
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw AccountAuthError.invalidEmail }
        do {
            let signIn = try await Clerk.shared.auth.signInWithEmailCode(emailAddress: address)
            pendingEmailFlow = .signIn(signIn)
        } catch let error as ClerkAPIError where error.code == "form_identifier_not_found" {
            // No account yet: the same code screen creates one.
            do {
                let signUp = try await Clerk.shared.auth.signUp(emailAddress: address)
                pendingEmailFlow = .signUp(try await signUp.sendEmailCode())
            } catch {
                throw Self.mapped(error)
            }
        } catch {
            throw Self.mapped(error)
        }
        return EmailCodeChallenge(email: address)
    }

    @MainActor
    func verifyEmailCode(_ code: String, for challenge: EmailCodeChallenge) async throws -> AccountIdentity {
        guard let pendingEmailFlow else { throw AccountAuthError.invalidCode }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch pendingEmailFlow {
            case .signIn(let signIn):
                let result = try await signIn.verifyCode(trimmed)
                guard result.status == .complete else { throw AccountAuthError.failed("Sign-in needs another step.") }
            case .signUp(let signUp):
                let result = try await signUp.verifyEmailCode(trimmed)
                guard result.status == .complete else { throw AccountAuthError.failed("Sign-up needs another step.") }
            }
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
        self.pendingEmailFlow = nil
        return try signedInIdentity(method: .email)
    }

    @MainActor
    func sessionToken() async throws -> String? {
        start()
        return try await Clerk.shared.auth.getToken()
    }

    @MainActor
    func signOut() async {
        start()
        pendingEmailFlow = nil
        // A deleted account's session is already gone on the server; the local session is cleared
        // either way.
        try? await Clerk.shared.auth.signOut()
    }

    // MARK: - Mapping

    /// Runs a Clerk flow that creates the account when it is new, then reads the signed-in identity.
    @MainActor
    private func mapped(_ method: AccountSignInMethod, _ flow: () async throws -> TransferFlowResult) async throws -> AccountIdentity {
        do {
            let result: TransferFlowResult
            do {
                result = try await flow()
            } catch let error as ClerkAPIError where error.code == "session_exists" {
                // A session restored after this screen loaded: carry on as that account.
                return try signedInIdentity(method: method)
            }
            switch result {
            case .signIn(let signIn) where signIn.status != .complete:
                throw AccountAuthError.failed("Sign-in needs another step.")
            case .signUp(let signUp) where signUp.status != .complete:
                throw AccountAuthError.failed("Sign-up needs another step.")
            default:
                break
            }
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
        return try signedInIdentity(method: method)
    }

    @MainActor
    private func signedInIdentity(method: AccountSignInMethod) throws -> AccountIdentity {
        guard let user = Clerk.shared.user else {
            throw AccountAuthError.failed("Signed in, but no account came back.")
        }
        return Self.identity(of: user, method: method)
    }

    private static func identity(of user: ClerkKit.User, method: AccountSignInMethod?) -> AccountIdentity {
        let providers = user.externalAccounts.map { $0.provider.lowercased() }
        let resolved = method
            ?? (providers.contains { $0.contains("apple") } ? .apple
                : providers.contains { $0.contains("google") } ? .google
                : .email)
        return AccountIdentity(userId: user.id, email: user.primaryEmailAddress?.emailAddress, method: resolved)
    }

    private static func mapped(_ error: Error) -> AccountAuthError {
        if let error = error as? AccountAuthError {
            return error
        }
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            return .canceled
        }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            return .canceled
        }
        if error is URLError {
            return .unreachable
        }
        if let error = error as? ClerkAPIError {
            switch error.code {
            case "form_code_incorrect", "verification_expired", "verification_failed":
                return .invalidCode
            case "form_param_format_invalid", "form_identifier_not_found":
                return .invalidEmail
            default:
                return .failed(error.longMessage ?? error.message ?? error.code)
            }
        }
        return .failed(error.localizedDescription)
    }
}
