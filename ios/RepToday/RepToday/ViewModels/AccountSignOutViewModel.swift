import Foundation
import Observation

/// Drives the Settings "Sign Out" control (US-SO01): the confirmation, the upload before signing out,
/// the warning when that upload leaves changes behind (decision 14), and the erase.
///
/// The work lives in `AccountSignOutServiceProtocol`; this type owns the presentation and one
/// re-entrancy guard across both steps, so a double tap, or a confirm arriving while an upload or an
/// erase runs, never starts a second one.
@Observable
@MainActor
final class AccountSignOutViewModel {
    /// Where the flow is, for the row's label and its progress.
    enum Phase: Equatable {
        case idle
        /// Uploading what is waiting before signing out.
        case uploading
        /// Erasing the phone's copy of the account.
        case signingOut
    }

    private(set) var phase: Phase = .idle

    /// Whether "Sign out of Rep Today?" is showing. Bound by `SettingsView`.
    var isConfirmationPresented = false

    /// Whether the warning that recent workouts will be lost is showing. Bound by `SettingsView`.
    var isUnsavedWarningPresented = false

    /// Whether the erase failed. Bound by `SettingsView`. The erase is idempotent, so retrying is safe.
    var isFailureAlertPresented = false

    var isBusy: Bool { phase != .idle }

    private let service: any AccountSignOutServiceProtocol
    private let appState: AppState

    init(service: any AccountSignOutServiceProtocol, appState: AppState) {
        self.service = service
        self.appState = appState
    }

    /// The user tapped "Sign Out".
    func signOutTapped() {
        guard !isBusy else { return }
        isConfirmationPresented = true
    }

    /// The user confirmed. Uploads first; signs out at once when everything is saved, and otherwise
    /// asks before losing anything.
    func confirmSignOut() async {
        guard !isBusy else { return }
        phase = .uploading
        let result = await service.uploadPendingChanges(appState: appState)
        phase = .idle
        switch result {
        case .allSaved:
            await signOut()
        case .unsavedChanges:
            isUnsavedWarningPresented = true
        }
    }

    /// "Sign Out Anyway" in the warning, or "Try Again" after a failed erase.
    func signOut() async {
        guard !isBusy else { return }
        phase = .signingOut
        defer { phase = .idle }
        do {
            try await service.signOut(appState: appState)
        } catch {
            // The erase saves each step and routes away only at its end, so a throw leaves the user
            // here, still signed in, with an erase a retry finishes.
            isFailureAlertPresented = true
        }
    }
}
