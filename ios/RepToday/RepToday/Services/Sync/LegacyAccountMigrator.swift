import Foundation

/// Moves the history of a user who onboarded before accounts to their account, once (M3, US-AU04).
///
/// It adds no upload path of its own: it queues every record on the phone in the ordinary sync
/// outbox, and the sync engine uploads them like any other change. So the move inherits the outbox's
/// guarantees - nothing is deleted from the phone or from iCloud, an upload is idempotent by record id,
/// and an interruption at any point leaves the queue to resume on the next sync.
///
/// The stages, each persisted on `AppState` and safe to repeat:
///
/// 1. `importingFromICloud` (after the one-time sign-in): wait, bounded and once per launch, for the
///    iCloud mirror's import (a device with no iCloud account has nothing to wait for), so records that
///    were only in iCloud are on the phone; then queue every record. The
///    entries are dated at the epoch, so a record the account already holds a newer copy of (from
///    another device that moved first) is never replaced by this phone's older one. If iCloud never
///    answered (offline), the queued records still upload, and the next launch waits again and queues
///    again; after `maxImportAttempts` launches it moves on with what the phone has.
/// 2. `uploading`: the iCloud mirror is off from the next launch; the outbox drains.
/// 3. `complete`: the first sync that leaves the outbox empty.
@MainActor
struct LegacyAccountMigrator {
    let appState: AppState
    let store: any SyncStore
    let importer: any LegacyICloudImporting
    let defaults: UserDefaults
    var importTimeout: Duration = .seconds(45)
    var maxImportAttempts = 5

    static let importAttemptsKey = "Sync.legacyImportAttempts"

    /// When the migration's entries are dated: older than any real change.
    static let queuedAt = Date(timeIntervalSince1970: 0)

    /// Queues the phone's history once the iCloud import has settled. Does nothing outside the
    /// `importingFromICloud` stage.
    func prepareUpload() async throws {
        guard appState.account != nil, appState.legacyMigrationStage == .importingFromICloud else { return }
        let outcome = await importer.waitForImport(timeout: importTimeout)
        try await store.enqueueAllRecords(changedAt: Self.queuedAt)
        let attempts = defaults.integer(forKey: Self.importAttemptsKey) + 1
        if outcome != .unconfirmed || attempts >= maxImportAttempts {
            defaults.removeObject(forKey: Self.importAttemptsKey)
            appState.advanceLegacyMigration(to: .uploading)
        } else {
            defaults.set(attempts, forKey: Self.importAttemptsKey)
        }
    }

    /// Marks the move complete once a sync has left nothing waiting.
    func completeIfUploaded(pendingAfterSync: Int) {
        guard appState.legacyMigrationStage == .uploading, pendingAfterSync == 0 else { return }
        appState.advanceLegacyMigration(to: .complete)
    }
}
