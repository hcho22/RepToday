import CoreData
import Foundation

/// The CoreData-backed `OutsideActivityServiceProtocol` (US-HO04): logged Outside Activities survive
/// relaunch in the on-device `Local` store, which never mirrors to iCloud. Every save and delete also
/// records the change in the sync outbox (`CDSyncChange`), so activities reach the user's account
/// (M3, US-AU03).
///
/// Queried by `date` range and saved by `id` as an upsert, so editing an activity overwrites it in
/// place. Every access happens inside `context.perform`, exactly as `CoreDataWorkoutLogService` does.
final class CoreDataOutsideActivityService: OutsideActivityServiceProtocol, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the context happens
    // inside `context.perform`, which serializes onto its queue.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func activities(from startDate: Date?, to endDate: Date?) async throws -> [OutsideActivity] {
        try await context.perform {
            let request = CDOutsideActivity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            var predicates: [NSPredicate] = []
            if let startDate {
                predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
            }
            if let endDate {
                predicates.append(NSPredicate(format: "date < %@", endDate as NSDate))
            }
            request.predicate = predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return try self.context.fetch(request).map { try $0.toOutsideActivity() }
        }
    }

    func save(_ activity: OutsideActivity) async throws {
        try await context.perform {
            let request = CDOutsideActivity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", activity.id as CVarArg)
            request.fetchLimit = 1
            let record = try self.context.fetch(request).first ?? CDOutsideActivity(context: self.context)
            record.update(from: activity)
            try CDSyncChange.markChanged(.outsideActivity, recordId: activity.id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func delete(id: UUID) async throws {
        try await context.perform {
            let request = CDOutsideActivity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for record in try self.context.fetch(request) {
                self.context.delete(record)
            }
            // A record that is gone uploads as a deletion.
            try CDSyncChange.markChanged(.outsideActivity, recordId: id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteAll() async throws {
        // Object by object rather than a batch delete, so the deletions flow through the view context
        // and every observer sees them. Account deletion only: it records nothing in the sync outbox,
        // because deletion removes the account's server data itself.
        try await context.perform {
            for record in try self.context.fetch(CDOutsideActivity.fetchRequest()) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
