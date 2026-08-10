import Foundation
import Observation

/// Drives the Settings "Delete Account" control (US-AD01/US-AD04/US-AD05): it resolves whether the
/// account used Sign in with Apple, presents the confirmation, runs the US-AD03 teardown exactly once,
/// and arms the post-deletion Apple-ID guidance.
///
/// The teardown itself lives in `AccountDeletionServiceProtocol`; this type owns only the presentation
/// and the re-entrancy guard, so a double-tap (or a confirm arriving while a delete is in flight)
/// cannot run the destructive teardown twice.
@Observable
@MainActor
final class AccountDeletionViewModel {
    /// Whether the destructive confirmation alert is showing (US-AD04). Bound by `SettingsView`.
    var isConfirmationPresented = false

    /// Whether the account being deleted signed in with Apple (US-AD05). Drives both the confirmation
    /// copy - which names the Apple link only in this case - and whether the post-deletion guidance is
    /// armed. Resolved when the row is tapped, before the alert is shown.
    private(set) var usedAppleCredential = false

    /// Re-entrancy guard (US-AD04): the teardown runs at most once, even if `confirmDeletion()` is
    /// invoked again while the first run is still in flight.
    private(set) var isDeleting = false

    /// Whether the teardown failed and the failure alert should show. Bound by `SettingsView`. Set when
    /// `deleteAccount(appState:)` throws, so the user is told deletion did not complete rather than being
    /// left with a silently dismissed confirmation. The teardown is idempotent, so retrying is safe.
    var isFailureAlertPresented = false

    private let accountDeletionService: any AccountDeletionServiceProtocol
    private let authService: any AuthServiceProtocol
    private let credentialStateProvider: any AppleCredentialStateProviding
    private let appState: AppState

    init(
        accountDeletionService: any AccountDeletionServiceProtocol,
        authService: any AuthServiceProtocol,
        appState: AppState,
        credentialStateProvider: any AppleCredentialStateProviding = LiveAppleCredentialStateProvider()
    ) {
        self.accountDeletionService = accountDeletionService
        self.authService = authService
        self.appState = appState
        self.credentialStateProvider = credentialStateProvider
    }

    /// The user tapped the destructive "Delete Account" row. Resolve the Apple-credential case first
    /// (so the confirmation can name exactly what is destroyed), then present the confirmation.
    func deleteAccountTapped() async {
        usedAppleCredential = await resolveUsedAppleCredential()
        isConfirmationPresented = true
    }

    /// The user confirmed. Run the US-AD03 teardown once, then - only for an Apple account and only on
    /// success - arm the guidance `RootView` surfaces over the onboarding screen the teardown routes to.
    func confirmDeletion() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await accountDeletionService.deleteAccount(appState: appState)
            // `deleteAccount` has already routed to onboarding (isOnboarded == false). Setting this
            // now re-renders `RootView` - which survives that transition - with the guidance alert.
            if usedAppleCredential {
                appState.showAppleSignOutGuidance = true
            }
        } catch {
            // The teardown is idempotent and saves each step as it goes, and the routing reset is its
            // last step - so a throw leaves the user on Settings still onboarded, with a consistent,
            // retryable state rather than half-signed-out. Surface an honest failure alert so the user
            // knows deletion did not complete and can retry, instead of a silently dismissed
            // confirmation that looks like nothing happened.
            isFailureAlertPresented = true
        }
    }

    /// Was Sign in with Apple used? True only when a stored Apple identifier exists **and** Apple still
    /// has a record of the pairing (US-AD05): the local-UUID user (no stored identifier) and a pairing
    /// Apple reports as `.notFound` both resolve to `false`, so the guidance shows only in the genuine
    /// Apple-credential case.
    private func resolveUsedAppleCredential() async -> Bool {
        guard let appleUserId = try? await authService.currentUserIdentifier(),
              !appleUserId.isEmpty else {
            return false
        }
        let status = await credentialStateProvider.credentialStatus(forUserID: appleUserId)
        return status != .notFound
    }
}
