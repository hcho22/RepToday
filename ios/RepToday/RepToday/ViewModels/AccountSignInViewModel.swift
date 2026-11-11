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
///
/// When the device's data belongs to a different account than the one just signed in to, finishing is
/// refused (`AccountLinkError`): that session is signed out, and the panel offers signing in to the
/// original account or, where the host allows it, erasing this phone's data first.
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
        /// Signed in to `attempted`, but this phone's data belongs to another account. The attempted
        /// session has been signed out.
        case belongsToAnotherAccount(attempted: AccountIdentity)
    }

    /// What the panel says while it works.
    enum Activity: Equatable {
        case apple, google, sendingCode, verifyingCode, finishing, erasing
    }

    private(set) var phase: Phase = .choosing
    private(set) var activity: Activity?
    /// A calm, user-facing note about the last attempt, or `nil`.
    private(set) var message: String?
    var email = ""
    var code = ""
    /// Whether the confirmation for erasing this phone's data is showing. Bound by the panel.
    var isEraseConfirmationPresented = false

    /// Whether this build can really sign in. `false` in a Debug build without Clerk, where the panel
    /// says sign-in is simulated.
    let isConfigured: Bool

    private let auth: any AccountAuthServiceProtocol
    private let context: Context
    private let eraseThisDevice: (@MainActor () async throws -> Void)?
    private let finish: @MainActor (AccountIdentity) async throws -> Void

    /// Where the panel is shown, which only changes how a connection problem is explained.
    enum Context {
        case onboarding
        case existingUser
    }

    /// - Parameter eraseThisDevice: erases this phone's Rep Today data, offered when the data belongs
    ///   to another account; `nil` where that cannot happen.
    init(
        auth: any AccountAuthServiceProtocol,
        context: Context,
        eraseThisDevice: (@MainActor () async throws -> Void)? = nil,
        finish: @escaping @MainActor (AccountIdentity) async throws -> Void
    ) {
        self.auth = auth
        self.isConfigured = auth.isConfigured
        self.context = context
        self.eraseThisDevice = eraseThisDevice
        self.finish = finish
    }

    /// Whether erasing this phone's data is offered.
    var canEraseThisDevice: Bool { eraseThisDevice != nil }

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

    func signInWithApple() async {
        guard !isWorking else { return }
        message = nil
        await signIn(.apple) { try await self.auth.signInWithApple() }
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

    // MARK: - Another account's phone

    /// Asks to confirm erasing this phone's data, after signing in to another account was refused.
    func requestErase() {
        guard case .belongsToAnotherAccount = phase, canEraseThisDevice, !isWorking else { return }
        isEraseConfirmationPresented = true
    }

    /// Erases this phone's Rep Today data; the host then starts setting up again.
    func confirmErase() async {
        guard case .belongsToAnotherAccount = phase, let eraseThisDevice, !isWorking else { return }
        message = nil
        activity = .erasing
        defer { activity = nil }
        do {
            try await eraseThisDevice()
        } catch {
            message = "We couldn't erase this phone's data. Please try again."
        }
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
        } catch SyncRemoteError.accountDeleting {
            message = Self.accountBeingDeletedMessage
        } catch AccountLinkError.belongsToAnotherAccount {
            // This session must not stay signed in: sync would upload this phone's data with its token.
            await auth.signOut()
            phase = .belongsToAnotherAccount(attempted: identity)
        } catch {
            message = context == .onboarding
                ? "You're signed in, but we couldn't reach your account to save your plan. Check your connection and try again."
                : "You're signed in, but we couldn't finish setting up. Check your connection and try again."
        }
    }

    /// The account just signed in to is still being deleted, so it can only be refused until that
    /// finishes.
    static let accountBeingDeletedMessage = "This account is still being deleted. Try again later, or use a different sign-in."

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
