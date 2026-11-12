import CoreData
import Foundation

/// The kinds of record that sync to the account (M3, US-AU03). The raw value is stored in the outbox.
enum SyncRecordType: String, CaseIterable, Sendable {
    /// The `User` aggregate (`CDUser`), keyed by `User.id`. It carries the Focus Areas.
    case profile
    /// The in-force `SessionPolicy` (`CDSessionPolicy`), keyed by the `User.id` it belongs to.
    case sessionPolicy
    /// One completed session (`CDWorkoutLog`), keyed by `WorkoutLog.id`.
    case workoutLog
    /// One logged Outside Activity (`CDOutsideActivity`), keyed by `OutsideActivity.id`.
    case outsideActivity
    /// One accepted Custom Workout (`CDCustomWorkout`, M4), keyed by `CustomWorkout.id`.
    case customWorkout
}

/// One record waiting to sync: the durable outbox entry of the local-first sync layer (M3, US-AU03),
/// new in model version 3.
///
/// The outbox names *which* record changed, never its contents: the sync engine reads the record as it
/// is when it uploads, so several edits before a sync collapse into one upload of the latest state, and
/// a record that is gone uploads as a deletion. There is at most one entry per record
/// (`recordType` + `recordId`).
///
/// Every store that writes a synced record calls `markChanged` inside the same `context.perform` and
/// the same `save()` as the record itself, so a change and its outbox entry are saved together and an
/// app kill can never leave a saved change without its entry. `revision` is replaced on every change,
/// so an upload removes the entry only if no newer change arrived while it was in flight.
///
/// It lives in the on-device `Local` configuration: it describes this device's pending work and must
/// never mirror to iCloud while the one-time migration still reads it.
@objc(CDSyncChange)
final class CDSyncChange: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDSyncChange> {
        NSFetchRequest<CDSyncChange>(entityName: "CDSyncChange")
    }

    @NSManaged var recordType: String?
    @NSManaged var recordId: String?
    /// When the change was made, sent as the change's `clientUpdatedAt`; the newer change wins on the
    /// server. The migration enqueues records at the epoch so they never replace newer account data.
    @NSManaged var changedAt: Date?
    /// Replaced on every change, so an in-flight upload can tell whether the record changed again.
    @NSManaged var revision: UUID?
}

extension CDSyncChange {
    /// Records that `recordId` changed, coalescing with any entry already waiting for it. Call inside the
    /// writer's `context.perform`, before its `save()`.
    ///
    /// - Parameter changedAt: when the change happened. An entry already waiting keeps the later of the
    ///   two times, so the migration's epoch-dated entries never pull a real edit's time backward.
    static func markChanged(
        _ type: SyncRecordType,
        recordId: String,
        changedAt: Date = Date(),
        in context: NSManagedObjectContext
    ) throws {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "recordType == %@ AND recordId == %@", type.rawValue, recordId)
        request.fetchLimit = 1
        let entry = try context.fetch(request).first ?? CDSyncChange(context: context)
        entry.recordType = type.rawValue
        entry.recordId = recordId
        entry.changedAt = max(entry.changedAt ?? .distantPast, changedAt)
        entry.revision = UUID()
    }
}
