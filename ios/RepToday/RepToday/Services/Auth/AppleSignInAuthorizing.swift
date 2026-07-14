import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// The identity fields a successful Sign in with Apple authorization returns (US-N01).
///
/// `userIdentifier` is the stable, app-scoped `ASAuthorizationAppleIDCredential.user` string that
/// keys the user record; `fullName`/`email` are surfaced only on the very first authorization and
/// are captured opportunistically (the MVP keys purely on the identifier).
struct AppleSignInResult: Sendable, Equatable {
    let userIdentifier: String
    let fullName: PersonNameComponents?
    let email: String?

    init(userIdentifier: String, fullName: PersonNameComponents? = nil, email: String? = nil) {
        self.userIdentifier = userIdentifier
        self.fullName = fullName
        self.email = email
    }
}

/// Failures the auth layer can surface. Every case is non-fatal to the core loop: onboarding
/// swallows them and falls back to a locally-generated identifier, so sign-in never gates the
/// first session.
enum AuthError: Error, Equatable {
    /// The user dismissed the Apple sheet.
    case canceled
    /// The authorization returned a non-Apple-ID credential.
    case invalidCredential
    /// Any other failure (offline, missing entitlement, system error), message attached for logs.
    case failed(String)
}

/// Seam over the Sign in with Apple authorization ceremony.
///
/// The real ceremony (`ASAuthorizationController` + presentation anchor + delegate callbacks) is
/// UIKit- and main-actor-bound and cannot run in a unit test, so it lives behind this boundary.
/// `AppleAuthService` composes it, and tests inject a stub that returns a canned result or throws.
protocol AppleSignInAuthorizing: Sendable {
    func authorize() async throws -> AppleSignInResult
}

/// Production authorizer: drives the real Sign in with Apple sheet and bridges its delegate
/// callbacks into `async`/`await` via a checked continuation. Stateless, so it is `Sendable`.
final class AppleIDSignInAuthorizer: AppleSignInAuthorizing {
    func authorize() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                AppleSignInCoordinator.start(continuation: continuation)
            }
        }
    }
}

/// Retains itself across the async delegate ceremony (an `ASAuthorizationController` does not
/// keep its delegate alive), then releases once it has resumed the continuation exactly once.
@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let continuation: CheckedContinuation<AppleSignInResult, Error>
    private var selfRetain: AppleSignInCoordinator?

    private init(continuation: CheckedContinuation<AppleSignInResult, Error>) {
        self.continuation = continuation
    }

    static func start(continuation: CheckedContinuation<AppleSignInResult, Error>) {
        let coordinator = AppleSignInCoordinator(continuation: continuation)
        coordinator.selfRetain = coordinator

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { selfRetain = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: AuthError.invalidCredential)
            return
        }
        continuation.resume(returning: AppleSignInResult(
            userIdentifier: credential.user,
            fullName: credential.fullName,
            email: credential.email
        ))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { selfRetain = nil }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation.resume(throwing: AuthError.canceled)
        } else {
            continuation.resume(throwing: AuthError.failed(error.localizedDescription))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let window = scene?.keyWindow ?? scene?.windows.first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }
}
