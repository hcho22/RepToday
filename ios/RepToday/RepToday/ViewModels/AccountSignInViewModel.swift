import AuthenticationServices
import Foundation
import Observation

/// Drives the account sign-in panel (M3, decision 23): Apple, Google, or an email code. Shared by
/// onboarding's "Save your plan" step (US-AU02) and the one-time sign-in an existing user meets on
/// their next launch (US-AU04).
///
/// Signing in and finishing are two steps. Once Clerk has signed the user in, the host's `finish`
/// runs (restore or create the plan, link the device); if that fails - say the account cannot be
/// reached - the user is still signed in, and "Try again" retries only the finishing, never the
/// sign-in. A session already on the device (the app closed mid-flow) is offered back as
/// "Continue as ...".
@MainActor
@Observable
final class AccountSignInViewModel {
    enum Phase: Equatable {
        /// Choosing Apple, Google or email.
        case choosing
        /// Typing an email address.
        case email
        /// Typing the code sent to the address.
        case code(EmailCodeChallenge)
        /// Signed in; finishing (or waiting to retry finishing).
        case signedIn(AccountIdentity)
    }

    /// What the panel says while it works.
    enum Activity: Equatable {
        case apple, google, sendingCode, verifyingCode, finishing
    }

    private(set) var phase: Phase = .choosing
    private(set) var activity: Activity?
    /// A calm, user-facing note about the last attempt, or `nil`.
    private(set) var message: String?
    var email = ""
    var code = ""

    /// Whether this build can really sign in. `false` in a Debug build without Clerk, where the panel
    /// says sign-in is simulated.
    let isConfigured: Bool

    private let auth: any AccountAuthServiceProtocol
    private let context: Context
    private let finish: @MainActor (AccountIdentity) async throws -> Void

    /// Where the panel is shown, which only changes how a connection problem is explained.
    enum Context {
        case onboarding
        case existingUser
    }

    init(
        auth: any AccountAuthServiceProtocol,
        context: Context,
        finish: @escaping @MainActor (AccountIdentity) async throws -> Void
    ) {
        self.auth = auth
        self.isConfigured = auth.isConfigured
        self.context = context
        self.finish = finish
    }

    var isWorking: Bool { activity != nil }

    var canSendCode: Bool {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isWorking && address.contains("@") && address.count >= 3
    }

    var canVerifyCode: Bool {
        !isWorking && code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    /// Offers back a session already on the device.
    func load() async {
        guard phase == .choosing, let identity = await auth.currentIdentity() else { return }
        phase = .signedIn(identity)
    }

    // MARK: - Apple

    /// Called by Apple's button before its sheet appears.
    func beginApple() {
        guard !isWorking else { return }
        message = nil
        activity = .apple
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                activity = nil
                message = Self.message(for: AccountAuthError.failed("no identity token"), context: context)
                return
            }
            await signIn(.apple) { try await self.auth.signInWithApple(identityToken: token) }
        case .failure(let error):
            activity = nil
            let canceled = (error as? ASAuthorizationError)?.code == .canceled
            message = canceled ? nil : Self.message(for: AccountAuthError.failed(error.localizedDescription), context: context)
        }
    }

    // MARK: - Google

    func signInWithGoogle() async {
        guard !isWorking else { return }
        message = nil
        await signIn(.google) { try await self.auth.signInWithGoogle() }
    }

    // MARK: - Email

    func chooseEmail() {
        guard !isWorking else { return }
        message = nil
        phase = .email
    }

    func sendCode() async {
        guard canSendCode else { return }
        message = nil
        activity = .sendingCode
        defer { activity = nil }
        do {
            let challenge = try await auth.sendEmailCode(to: email)
            code = ""
            phase = .code(challenge)
        } catch {
            message = Self.message(for: error, context: context)
        }
    }

    func resendCode() async {
        guard case .code(let challenge) = phase, !isWorking else { return }
        email = challenge.email
        await sendCode()
        if message == nil {
            message = "We sent a new code to \(challenge.email)."
        }
    }

    func verifyCode() async {
        guard case .code(let challenge) = phase, canVerifyCode else { return }
        message = nil
        await signIn(.verifyingCode) { try await self.auth.verifyEmailCode(self.code, for: challenge) }
    }

    /// Back to the three choices from the email or code screen.
    func showChoices() {
        guard !isWorking else { return }
        message = nil
        code = ""
        phase = .choosing
    }

    // MARK: - Finishing

    /// Retries the finishing step for the account already signed in.
    func retryFinishing() async {
        guard case .signedIn(let identity) = phase, !isWorking else { return }
        await runFinish(identity)
    }

    /// Signs out of the session on the device and starts over.
    func useDifferentAccount() async {
        guard !isWorking else { return }
        await auth.signOut()
        message = nil
        phase = .choosing
    }

    // MARK: - Steps

    private func signIn(_ activity: Activity, _ attempt: () async throws -> AccountIdentity) async {
        self.activity = activity
        let identity: AccountIdentity
        do {
            identity = try await attempt()
        } catch {
            self.activity = nil
            message = Self.message(for: error, context: context)
            return
        }
        phase = .signedIn(identity)
        await runFinish(identity)
    }

    private func runFinish(_ identity: AccountIdentity) async {
        activity = .finishing
        message = nil
        defer { activity = nil }
        do {
            try await finish(identity)
        } catch {
            message = context == .onboarding
                ? "You're signed in, but we couldn't reach your account to save your plan. Check your connection and try again."
                : "You're signed in, but we couldn't finish setting up. Check your connection and try again."
        }
    }

    /// Identity-framed, never alarming: what happened and what to do, nothing about what was lost
    /// (nothing is).
    static func message(for error: Error, context: Context) -> String? {
        switch error as? AccountAuthError {
        case .canceled:
            return nil
        case .unreachable:
            return context == .onboarding
                ? "Signing in needs a connection. Your answers are kept here - try again when you're online."
                : "Signing in needs a connection. Everything on this phone stays as it is - try again when you're online."
        case .invalidEmail:
            return "That email address doesn't look right. Check it and try again."
        case .invalidCode:
            return "That code didn't match. Check the email we sent and try again."
        case .notConfigured:
            return "Sign-in isn't available in this build."
        case .failed, .none:
            return "We couldn't sign you in. Please try again."
        }
    }
}
