import Foundation

/// Deletes the user's account (App Store Guideline 5.1.1(v), US-AD03; extended for accounts by US-AU05):
/// the account's server data and its sign-in identity, then everything on the device.
///
/// It is the single orchestration seam behind the Settings "Delete Account" control: the view model
/// (`AccountDeletionViewModel`) owns the confirmation and re-entrancy, and this service owns the
/// teardown. It composes the existing per-store deletes rather than reaching into CoreData itself, so
/// each store stays the one place that knows how its records are cleared and saved.
protocol AccountDeletionServiceProtocol {
    /// Tears the account down in this order, then routes back to onboarding:
    ///
    /// 0. With a linked account and an account backend (US-AU05): stop sync, then delete the
    ///    account's server data and its Clerk user (`accounts:deleteAccount`). This needs a connection
    ///    and runs first, so a failure here changes nothing on the device and nothing on the server
    ///    (the server cancels its own deletion if Clerk fails). Once it succeeds, a persisted marker
    ///    makes a retry skip it - the deleted account's session can no longer reach the server.
    /// 1. Delete every durable record on the device - the `CDUser`/`CDWorkoutLog`/`CDSessionPolicy`
    ///    rows in the Cloud store and the `CDActiveSession`/`CDOutsideActivity` rows in the Local
    ///    store - each saved as it goes, then empty the sync outbox and forget the sync cursor. Then
    ///    delete the Rep Today data kept in the user's iCloud from before accounts
    ///    (`LegacyICloudErasure`); when iCloud cannot take it, the deletion is recorded as owed and
    ///    retried on a later launch, and the rest of the teardown carries on.
    /// 2. Clear the Keychain-held Sign in with Apple identifier from before accounts
    ///    (`AuthServiceProtocol.signOut()`) - non-optional, since the Keychain item survives a
    ///    reinstall - and end the account's session on this device.
    /// 3. On the first successful onboarded teardown, rotate `AppState`'s anonymous analytics
    ///    install identifier, reset account-scoped Coach state, forget the account, then reset routing
    ///    (`isOnboarded` -> false, `selectedTab` -> `.home`). The already-running clients read both
    ///    identifiers per request, so a later account inherits neither linkage, provider safety
    ///    history, nor data-sharing acknowledgement.
    ///
    /// Idempotent: a second call skips the finished server step, finds nothing to delete, the Keychain
    /// clear is a no-op, and the already-rotated identifier stays stable because routing marked the
    /// install as no longer onboarded.
    ///
    /// - Throws: `AccountDeletionError` when the server step cannot run; nothing was deleted then.
    func deleteAccount(appState: AppState) async throws

    /// Erases this phone's Rep Today data and routes back to onboarding - steps 1 to 3 above, with no
    /// server step and no iCloud deletion - so the phone can be set up with another account. The
    /// account itself is not deleted. Offered when the phone's data belongs to a different account
    /// than the one just signed in to (`AccountLinkError`).
    func eraseThisDevice(appState: AppState) async throws
}

/// Why account deletion stopped before deleting anything.
enum AccountDeletionError: Error, Equatable {
    /// The server step needs a connection.
    case needsConnection
    /// The account backend did not accept this device's session; signing in again lets deletion run.
    case needsSignIn
    /// The server refused or failed. Nothing was deleted.
    case serverFailed
}

/// The production account-deletion orchestrator (US-AD03).
///
/// Every dependency is a protocol the running container already holds, and every delete is one the
/// store already implements (US-AD02 added the two bulk deletes), so this type carries no persistence
/// knowledge of its own - it only sequences the teardown and does the final routing.
struct AccountDeletionService: AccountDeletionServiceProtocol {
    private let userService: any UserServiceProtocol
    private let workoutLogService: any WorkoutLogServiceProtocol
    private let sessionPolicyStore: any SessionPolicyStore
    private let activeSessionStore: any ActiveSessionStore
    private let authService: any AuthServiceProtocol
    private let coachAuthenticationCleanup: (@Sendable () async -> Void)?
    /// Logged Outside Activities (US-HO04), kept in the on-device Local store and never synced to
    /// iCloud. Optional so a caller that predates them still composes the teardown.
    private let outsideActivityService: (any OutsideActivityServiceProtocol)?
    private let account: AccountTeardown?
    /// The Rep Today data in the user's iCloud from before accounts, or `nil` where there is none to
    /// reach (tests, previews).
    private let legacyICloud: LegacyICloudErasure?

    /// The account half of deletion (M3, US-AU05): the server step and the sync state on the device.
    struct AccountTeardown {
        /// The account backend, or `nil` when this build has none (nothing was ever uploaded).
        let remote: (any SyncRemote)?
        let auth: any AccountAuthServiceProtocol
        let syncStore: any SyncStore
        let cursorStore: any SyncCursorStore
        var engine: SyncEngine?
        var defaults: UserDefaults = .standard

        /// The account whose server data is already deleted, so a retry skips the server step.
        static let remoteDeletionMarkerKey = "Account.remoteDeletionCompletedFor"
    }

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        sessionPolicyStore: any SessionPolicyStore,
        activeSessionStore: any ActiveSessionStore,
        authService: any AuthServiceProtocol,
        coachAuthenticationCleanup: (@Sendable () async -> Void)? = nil,
        outsideActivityService: (any OutsideActivityServiceProtocol)? = nil,
        account: AccountTeardown? = nil,
        legacyICloud: LegacyICloudErasure? = nil
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.sessionPolicyStore = sessionPolicyStore
        self.activeSessionStore = activeSessionStore
        self.authService = authService
        self.coachAuthenticationCleanup = coachAuthenticationCleanup
        self.outsideActivityService = outsideActivityService
        self.account = account
        self.legacyICloud = legacyICloud
    }

    func deleteAccount(appState: AppState) async throws {
        try await withSyncStopped(appState) { linkedAccount in
            try await deleteRemoteAccount(linkedAccount)
            try await eraseDevice(appState: appState, deletesICloud: true)
        }
    }

    func eraseThisDevice(appState: AppState) async throws {
        try await withSyncStopped(appState) { _ in
            await account?.engine?.waitForIdle()
            try await eraseDevice(appState: appState, deletesICloud: false)
        }
    }

    /// Runs `work` with sync stopped (`isAccountDeletionInProgress`), handing it the linked account.
    private func withSyncStopped(_ appState: AppState, _ work: (AccountIdentity?) async throws -> Void) async throws {
        let linkedAccount = await MainActor.run { () -> AccountIdentity? in
            appState.isAccountDeletionInProgress = true
            return appState.account
        }
        do {
            try await work(linkedAccount)
        } catch {
            await MainActor.run { appState.isAccountDeletionInProgress = false }
            throw error
        }
        await MainActor.run { appState.isAccountDeletionInProgress = false }
    }

    /// 0. The server step. Sync has stopped (`isAccountDeletionInProgress`); wait out a cycle that was
    ///    already uploading, so nothing reaches the account after it is deleted.
    private func deleteRemoteAccount(_ linkedAccount: AccountIdentity?) async throws {
        if let account, let linkedAccount, let remote = account.remote,
           account.defaults.string(forKey: AccountTeardown.remoteDeletionMarkerKey) != linkedAccount.userId {
            await account.engine?.waitForIdle()
            do {
                try await remote.deleteAccount()
            } catch let error as SyncRemoteError {
                switch error {
                case .unreachable:
                    throw AccountDeletionError.needsConnection
                case .notSignedIn, .unauthenticated:
                    throw AccountDeletionError.needsSignIn
                case .accountDeleting, .rejected, .invalidResponse:
                    throw AccountDeletionError.serverFailed
                }
            }
            account.defaults.set(linkedAccount.userId, forKey: AccountTeardown.remoteDeletionMarkerKey)
        }
    }

    /// Steps 1 to 3: everything on the device, the legacy iCloud copy when `deletesICloud`, then routing.
    private func eraseDevice(appState: AppState, deletesICloud: Bool) async throws {
        // 1. Durable records across both store configurations, each saved as it goes. Every delete is
        //    wholesale and single-user - the log store carries no
        //    owner column, and the policy and active-session stores clear their one record without a
        //    user id - so teardown never depends on decoding the `CDUser` aggregate. A corrupt or
        //    unreadable user therefore cannot leave the per-user policy or the device-local active
        //    session orphaned behind a "delete account" that reports done.
        try await workoutLogService.deleteAllLogs()
        try await outsideActivityService?.deleteAll()
        try await sessionPolicyStore.deleteAll()
        try await activeSessionStore.clearAll()
        try await userService.deleteCurrentUser()
        // The outbox would otherwise upload the deleted records to the next account signed in here.
        try await account?.syncStore.clearOutbox()
        account?.cursorStore.reset()
        // The Rep Today data in the user's iCloud from before accounts. Never throws: a deletion iCloud
        // cannot take now is owed and retried on a later launch.
        if deletesICloud {
            await legacyICloud?.erase()
        }

        // 2. The Keychain identifier - mandatory, since it outlives a reinstall. A no-op for the
        //    local-UUID user who never signed in with Apple (`SecItemDelete` tolerates "not found").
        try await authService.signOut()
        // The account's session on this device. The server already removed it with the Clerk user;
        // this clears what the device kept.
        await account?.auth.signOut()
        // Unlink the device's Coach key immediately. Remote content-free metadata deletion is
        // bounded best effort and never gates deletion of on-device records or routing.
        await coachAuthenticationCleanup?()

        // 3. Reset routing state on the main actor (it is what SwiftUI observes), which sends the app
        //    back to onboarding. Done last, so a throw in an earlier step leaves the user in place to
        //    retry against an idempotent teardown rather than stranded on a torn-down screen.
        await MainActor.run {
            // `isOnboarded` is also the idempotence marker for the in-memory identities: a second
            // teardown after the app already routed away must not keep minting fresh identifiers.
            if appState.isOnboarded {
                appState.rotateAnalyticsInstallId()
                appState.resetCoachAccountState()
            }
            appState.resetHealthSuggestionState()
            appState.unlinkAccount()
            appState.selectedTab = .home
            appState.isOnboarded = false
        }
        account?.defaults.removeObject(forKey: AccountTeardown.remoteDeletionMarkerKey)
    }
}
