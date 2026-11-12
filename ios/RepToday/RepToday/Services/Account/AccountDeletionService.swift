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
    ///    account's server data and its Clerk user (`accounts:deleteAccount`). Before the request is
    ///    sent, the device records that deletion was requested for this account; from then on the
    ///    deletion counts as committed once the server may have marked the account. A first request
    ///    that provably never left the phone (no connection, or no session token could be had) or that
    ///    the server provably refused before marking anything (an unaccepted session, or a deployment
    ///    with deletion unavailable) stops here with nothing deleted. Every other outcome (success, no
    ///    response, a timeout, an unexplained rejection, an invalid response, or any failure on a
    ///    retry of a request already sent) runs the device teardown, and unless the server confirmed
    ///    the deletion complete, `AppState.showAccountDeletionUnderWay` says it is under way and
    ///    finishes on its own. A persisted marker makes a retry after this step skip it, and
    ///    `resumeRequestedDeletion` finishes a deletion the app was closed during.
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
    ///    (`isOnboarded` -> false, `selectedTab` -> `.home`). The already-running telemetry client reads
    ///    the identifier per request, so a later account inherits neither its linkage nor the Coach
    ///    data-sharing acknowledgement. (The Coach's conversation and Custom Workouts live with the
    ///    account, so the server step removes them; Coach reminders are cleared on the device.)
    ///
    /// Idempotent: a second call skips the finished server step, finds nothing to delete, the Keychain
    /// clear is a no-op, and the already-rotated identifier stays stable because routing marked the
    /// install as no longer onboarded.
    ///
    /// - Throws: `AccountDeletionError` when the server step cannot run; nothing was deleted then.
    func deleteAccount(appState: AppState) async throws

    /// Finishes, at launch, a deletion whose request was recorded for the linked account but whose
    /// teardown never completed (the app was closed mid-request): it runs `deleteAccount` again,
    /// which can only end in the device teardown, and shows the being-deleted message once. Does
    /// nothing when no such request is recorded.
    func resumeRequestedDeletion(appState: AppState) async throws

    /// Erases this phone's Rep Today data and routes back to onboarding - steps 1 to 3 above, with no
    /// server step and no iCloud deletion - so the phone can be set up with another account. The
    /// account itself is not deleted. Offered when the phone's data belongs to a different account
    /// than the one just signed in to (`AccountLinkError`).
    func eraseThisDevice(appState: AppState) async throws
}

/// Why account deletion stopped before deleting anything: its request never left the phone.
enum AccountDeletionError: Error, Equatable {
    /// The server step needs a connection.
    case needsConnection
    /// There is no session the server accepts for the linked account; signing in again lets deletion
    /// run.
    case needsSignIn
    /// The server refused before marking anything: deletion is not available on this deployment.
    case unavailable
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
    /// The Coach's on-device state (M4): accepted Custom Workouts, scheduled reminders and today's
    /// choices. Optional so a caller that predates the Coach agent still composes the teardown.
    private let coachState: CoachDeviceTeardown?
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
        /// The account whose deletion request has been sent, recorded before sending: a later attempt
        /// treats every failure as a deletion the server may already have committed.
        static let remoteDeletionRequestedKey = "Account.remoteDeletionRequestedFor"
        /// Set with the marker when the deletion is under way rather than confirmed complete.
        static let deletionUnderWayKey = "Account.remoteDeletionUnderWay"
    }

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        sessionPolicyStore: any SessionPolicyStore,
        activeSessionStore: any ActiveSessionStore,
        authService: any AuthServiceProtocol,
        coachState: CoachDeviceTeardown? = nil,
        outsideActivityService: (any OutsideActivityServiceProtocol)? = nil,
        account: AccountTeardown? = nil,
        legacyICloud: LegacyICloudErasure? = nil
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.sessionPolicyStore = sessionPolicyStore
        self.activeSessionStore = activeSessionStore
        self.authService = authService
        self.coachState = coachState
        self.outsideActivityService = outsideActivityService
        self.account = account
        self.legacyICloud = legacyICloud
    }

    func deleteAccount(appState: AppState) async throws {
        try await withSyncStopped(appState) { linkedAccount in
            let alreadyBeingDeleted = await MainActor.run { appState.isLinkedAccountBeingDeleted }
            try await deleteRemoteAccount(linkedAccount, alreadyBeingDeleted: alreadyBeingDeleted)
            try await eraseDevice(appState: appState, deletesICloud: true)
        }
    }

    func resumeRequestedDeletion(appState: AppState) async throws {
        guard let account else { return }
        let linkedAccount = await MainActor.run { appState.account }
        guard let linkedAccount,
              account.defaults.string(forKey: AccountTeardown.remoteDeletionRequestedKey) == linkedAccount.userId else { return }
        try await deleteAccount(appState: appState)
        await MainActor.run { appState.showAccountDeletionUnderWay = true }
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
    ///    When the account has already answered that it is being deleted, the server has committed the
    ///    deletion, so no request is sent and it counts as under way.
    private func deleteRemoteAccount(_ linkedAccount: AccountIdentity?, alreadyBeingDeleted: Bool) async throws {
        if let account, let linkedAccount, let remote = account.remote,
           account.defaults.string(forKey: AccountTeardown.remoteDeletionMarkerKey) != linkedAccount.userId {
            if alreadyBeingDeleted {
                account.defaults.set(true, forKey: AccountTeardown.deletionUnderWayKey)
                account.defaults.set(linkedAccount.userId, forKey: AccountTeardown.remoteDeletionMarkerKey)
                return
            }
            await account.engine?.waitForIdle()
            let sentBefore = account.defaults.string(forKey: AccountTeardown.remoteDeletionRequestedKey) == linkedAccount.userId
            account.defaults.set(linkedAccount.userId, forKey: AccountTeardown.remoteDeletionRequestedKey)
            let outcome: RemoteAccountDeletion
            do {
                outcome = try await remote.deleteAccount()
            } catch SyncRemoteError.unreachable where !sentBefore {
                account.defaults.removeObject(forKey: AccountTeardown.remoteDeletionRequestedKey)
                throw AccountDeletionError.needsConnection
            } catch SyncRemoteError.notSignedIn where !sentBefore, SyncRemoteError.unauthenticated where !sentBefore {
                account.defaults.removeObject(forKey: AccountTeardown.remoteDeletionRequestedKey)
                throw AccountDeletionError.needsSignIn
            } catch SyncRemoteError.rejected(code: "deletion_unavailable"?, message: _) where !sentBefore {
                account.defaults.removeObject(forKey: AccountTeardown.remoteDeletionRequestedKey)
                throw AccountDeletionError.unavailable
            } catch {
                outcome = .underWay
            }
            account.defaults.set(outcome == .underWay, forKey: AccountTeardown.deletionUnderWayKey)
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
        // The Coach's on-device state: accepted Custom Workouts, the reminders it scheduled (their
        // pending notifications too) and today's choices.
        try await coachState?.erase()

        // 3. Reset routing state on the main actor (it is what SwiftUI observes), which sends the app
        //    back to onboarding. Done last, so a throw in an earlier step leaves the user in place to
        //    retry against an idempotent teardown rather than stranded on a torn-down screen.
        let deletionUnderWay = account?.defaults.bool(forKey: AccountTeardown.deletionUnderWayKey) ?? false
        await MainActor.run {
            if deletionUnderWay {
                appState.showAccountDeletionUnderWay = true
            }
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
        account?.defaults.removeObject(forKey: AccountTeardown.deletionUnderWayKey)
        account?.defaults.removeObject(forKey: AccountTeardown.remoteDeletionRequestedKey)
    }
}
