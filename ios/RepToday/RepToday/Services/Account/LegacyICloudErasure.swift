import CloudKit
import Foundation

/// Deletes the Rep Today data a user kept in their iCloud before accounts (M3, US-AU05): the zone the
/// Core Data mirror wrote in the private database of `PersistenceController.cloudKitContainerIdentifier`.
protocol LegacyICloudDataDeleting: Sendable {
    /// Deletes the zone. A zone that is already gone counts as deleted.
    ///
    /// - Throws: when iCloud cannot be reached or refuses (no iCloud account, offline); the deletion
    ///   is then still owed.
    func deleteLegacyICloudData() async throws
}

/// The CloudKit deletion of the Core Data mirror's zone.
struct CloudKitLegacyICloudDataDeleter: LegacyICloudDataDeleting {
    /// The zone `NSPersistentCloudKitContainer` mirrors into.
    static let zoneName = "com.apple.coredata.cloudkit.zone"

    let containerIdentifier: String

    func deleteLegacyICloudData() async throws {
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await CKContainer(identifier: containerIdentifier).privateCloudDatabase.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return
        }
    }
}

/// Deletes the legacy iCloud copy as part of account deletion, for migrated and not-yet-migrated users
/// alike, and remembers a deletion iCloud could not take so a later launch retries it. It never throws,
/// so it never holds up the rest of account deletion.
struct LegacyICloudErasure: @unchecked Sendable {
    // Safe: `UserDefaults` is thread-safe and the deleter is `Sendable`.
    let deleter: any LegacyICloudDataDeleting
    var defaults: UserDefaults = .standard

    /// Set while an iCloud deletion is owed.
    static let owedKey = "Account.legacyICloudDeletionOwed"

    /// Whether an iCloud deletion is still owed.
    var isOwed: Bool { defaults.bool(forKey: Self.owedKey) }

    /// Deletes the iCloud copy. It is recorded as owed before trying, so an attempt that fails or is
    /// interrupted is retried by `retryIfOwed`.
    func erase() async {
        defaults.set(true, forKey: Self.owedKey)
        do {
            try await deleter.deleteLegacyICloudData()
            defaults.removeObject(forKey: Self.owedKey)
        } catch {
            return
        }
    }

    /// Retries an owed iCloud deletion. Called at launch.
    func retryIfOwed() async {
        guard isOwed else { return }
        await erase()
    }
}
