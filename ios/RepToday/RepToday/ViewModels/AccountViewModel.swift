import AuthenticationServices
import Observation

/// Optional authentication for an already-onboarded user. This owns only the local Apple
/// credential, never the User aggregate or its ID. CloudKit uses the device's iCloud account;
/// StoreKit supplies Premium independently. There is no backend account merge or data rekey here.
@MainActor
@Observable
final class AccountViewModel {
    enum State: Equatable { case loading, signedOut, signedIn, unavailable }

    private(set) var state: State = .loading
    private(set) var isSigningIn = false
    private(set) var message: String?
    private var isSavingCredential = false
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol) {
        self.authService = authService
    }

    var canSignIn: Bool { state == .signedOut && !isSigningIn }

    func load() async {
        guard !isSigningIn else { return }
        state = .loading
        message = nil
        do {
            state = try await authService.currentUserIdentifier() == nil ? .signedOut : .signedIn
        } catch {
            // Do not offer to overwrite a credential whose local read failed.
            state = .unavailable
            message = "We couldn't check your sign-in status. Please try again."
        }
    }

    /// Called synchronously by Apple's button before it presents its authorization sheet.
    func beginSignIn() {
        guard canSignIn else { return }
        isSigningIn = true
        message = nil
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        await completeSignIn(result.flatMap { authorization in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return .failure(AuthError.invalidCredential)
            }
            return .success(credential.user)
        })
    }

    /// The result seam keeps cancellation and storage failure testable without Apple's sheet.
    func completeSignIn(_ result: Result<String, Error>) async {
        guard isSigningIn, !isSavingCredential else { return }
        isSavingCredential = true
        defer {
            isSavingCredential = false
            isSigningIn = false
        }
        do {
            let identifier = try result.get()
            guard !identifier.isEmpty else { throw AuthError.invalidCredential }
            try await authService.completeSignIn(identifier: identifier)
            state = .signedIn
        } catch {
            let cancelled = (error as? AuthError) == .canceled
                || (error as? ASAuthorizationError)?.code == .canceled
            if !cancelled {
                message = "We couldn't sign you in. Please try again. Your workouts and history are unchanged."
            }
        }
    }
}
