import Foundation

/// Where a user who onboarded before accounts (M3, US-AU04) is in their one-time move to an account.
///
/// Persisted on `AppState` and read once at launch by `PersistenceController`, which keeps the old
/// iCloud mirror running only while it can still matter. A user who onboarded on an account build has
/// no stage at all.
enum LegacyAccountMigrationStage: String, CaseIterable, Sendable {
    /// Onboarded before accounts and not signed in yet. The app asks for the one-time sign-in; the
    /// iCloud mirror keeps importing in the meantime, so anything only in iCloud reaches the phone.
    case awaitingSignIn
    /// Signed in. Waiting (bounded) for the iCloud mirror's import to settle, then every record on
    /// the phone is queued for upload. Re-run on every launch until the import is confirmed.
    case importingFromICloud
    /// Everything is queued; the outbox is uploading to the account. Done when it is empty. The
    /// iCloud mirror is off from here on.
    case uploading
    /// Everything that was on the phone and in iCloud is on the account.
    case complete

    /// Whether the store should still mirror the user's iCloud data at this stage. Only before every
    /// record has been queued; after that the account is where data goes.
    var mirrorsICloud: Bool {
        switch self {
        case .awaitingSignIn, .importingFromICloud:
            return true
        case .uploading, .complete:
            return false
        }
    }

    // MARK: - Persistence

    static let defaultsKey = "AppState.legacyMigrationStage"

    /// The stage for the install `defaults` describes. An install with no stored stage that is
    /// onboarded but not linked to an account predates accounts and starts at `awaitingSignIn`.
    /// This is the one decision `AppState` and `PersistenceController` share, so they can never
    /// disagree about whether the iCloud mirror runs.
    static func resolved(in defaults: UserDefaults) -> LegacyAccountMigrationStage? {
        if let stored = defaults.string(forKey: defaultsKey).flatMap(LegacyAccountMigrationStage.init(rawValue:)) {
            return stored
        }
        let onboarded = defaults.bool(forKey: AppState.Keys.isOnboarded)
        let linked = !(defaults.string(forKey: AppState.Keys.accountUserId) ?? "").isEmpty
        return onboarded && !linked ? .awaitingSignIn : nil
    }
}
