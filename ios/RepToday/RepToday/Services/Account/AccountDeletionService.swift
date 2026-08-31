import Foundation

/// Erases the user's on-device account so the app satisfies App Store Guideline 5.1.1(v) - an app
/// that offers Sign in with Apple must offer account deletion (US-AD03).
///
/// It is the single orchestration seam behind the Settings "Delete Account" control: the view model
/// (`AccountDeletionViewModel`) owns the confirmation and re-entrancy, and this service owns the
/// teardown. It composes the existing per-store deletes rather than reaching into CoreData itself, so
/// each store stays the one place that knows how its records are cleared and saved.
protocol AccountDeletionServiceProtocol {
    /// Tears the account down in the order US-AD03 fixes, then routes back to onboarding:
    ///
    /// 1. Delete every durable record - the `CDUser`/`CDWorkoutLog`/`CDSessionPolicy` rows in the
    ///    CloudKit-mirrored **Cloud** store and the `CDActiveSession` row in the device-local
    ///    **Local** store - each saved as it goes, so the CloudKit mirror propagates the tombstones.
    /// 2. Clear the Keychain-held Sign in with Apple identifier (`AuthServiceProtocol.signOut()`).
    ///    Non-optional: the Keychain item survives reinstall, so skipping it would resurrect an
    ///    identity the user believed they deleted.
    /// 3. Rotate `AppState`'s anonymous analytics install identifier, then reset routing
    ///    (`isOnboarded` -> false, `selectedTab` -> `.home`). The already-running telemetry service
    ///    reads the identifier per emission, so post-deletion onboarding events cannot be linked to
    ///    the prior install identity.
    ///
    /// Idempotent and safe for the local-UUID user who never signed in with Apple: a second call
    /// finds nothing to delete and the Keychain clear is a no-op.
    func deleteAccount(appState: AppState) async throws
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

    init(
        userService: any UserServiceProtocol,
        workoutLogService: any WorkoutLogServiceProtocol,
        sessionPolicyStore: any SessionPolicyStore,
        activeSessionStore: any ActiveSessionStore,
        authService: any AuthServiceProtocol
    ) {
        self.userService = userService
        self.workoutLogService = workoutLogService
        self.sessionPolicyStore = sessionPolicyStore
        self.activeSessionStore = activeSessionStore
        self.authService = authService
    }

    func deleteAccount(appState: AppState) async throws {
        // 1. Durable records across both store configurations, each saved as it goes so CloudKit
        //    tombstones mirror. Every delete is wholesale and single-user - the log store carries no
        //    owner column, and the policy and active-session stores clear their one record without a
        //    user id - so teardown never depends on decoding the `CDUser` aggregate. A corrupt or
        //    unreadable user therefore cannot leave the per-user policy or the device-local active
        //    session orphaned behind a "delete account" that reports done.
        try await workoutLogService.deleteAllLogs()
        try await sessionPolicyStore.deleteAll()
        try await activeSessionStore.clearAll()
        try await userService.deleteCurrentUser()

        // 2. The Keychain identifier - mandatory, since it outlives a reinstall. A no-op for the
        //    local-UUID user who never signed in with Apple (`SecItemDelete` tolerates "not found").
        try await authService.signOut()

        // 3. Reset routing state on the main actor (it is what SwiftUI observes), which sends the app
        //    back to onboarding. Done last, so a throw in an earlier step leaves the user in place to
        //    retry against an idempotent teardown rather than stranded on a torn-down screen.
        await MainActor.run {
            // `isOnboarded` is also the idempotence marker for the in-memory identity: a second
            // teardown after the app already routed away must not keep minting fresh identifiers.
            if appState.isOnboarded {
                appState.rotateAnalyticsInstallId()
            }
            appState.selectedTab = .home
            appState.isOnboarded = false
        }
    }
}
