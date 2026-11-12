import CoreData
import Foundation

/// The CoreData-backed `WorkoutLogServiceProtocol` (US-N02), so completed sessions survive
/// relaunch. Every save and delete also records the change in the sync outbox (`CDSyncChange`), in
/// the same save, so it reaches the user's account (M3, US-AU03).
///
/// Logs are queried by `completedAt` range - the window the engine's staleness steps, the
/// Consistency Score, and the Progress tab all read - and saved by `id` as an upsert so
/// re-saving a log (e.g. the US-L02 perceived-difficulty update) overwrites in place rather than
/// duplicating. Every access happens inside `context.perform`, which serializes onto the
/// context's queue; the running app injects the shared stack's `viewContext`, and the app is
/// otherwise unit-tested against `MockWorkoutLogService`, keeping view-model and service logic
/// free of CoreData.
final class CoreDataWorkoutLogService: WorkoutLogServiceProtocol, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the context happens
    // inside `context.perform`, which serializes onto its queue.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func workoutLogs(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutLog] {
        try await context.perform {
            let request = CDWorkoutLog.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: true)]
            // Build a half-open [start, end) predicate matching whichever bounds were supplied,
            // consistent with `MockWorkoutLogService` and `CDWorkoutLog.fetchRequest(from:to:)`.
            var predicates: [NSPredicate] = []
            if let startDate {
                predicates.append(NSPredicate(format: "completedAt >= %@", startDate as NSDate))
            }
            if let endDate {
                predicates.append(NSPredicate(format: "completedAt < %@", endDate as NSDate))
            }
            request.predicate = predicates.isEmpty
                ? nil
                : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return try self.context.fetch(request).map { try $0.toWorkoutLog() }
        }
    }

    func save(_ log: WorkoutLog) async throws {
        try await context.perform {
            let request = CDWorkoutLog.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", log.id as CVarArg)
            request.fetchLimit = 1
            let record = try self.context.fetch(request).first ?? CDWorkoutLog(context: self.context)
            try record.update(from: log)
            try CDSyncChange.markChanged(.workoutLog, recordId: log.id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteLog(id: UUID) async throws {
        try await context.perform {
            let request = CDWorkoutLog.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for record in try self.context.fetch(request) {
                self.context.delete(record)
            }
            // A record that is gone uploads as a deletion.
            try CDSyncChange.markChanged(.workoutLog, recordId: id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteAllLogs() async throws {
        // Rep Today has one local user and `CDWorkoutLog` carries no owner column (US-A04), so the
        // whole history is this user's history: account deletion (US-AD02/US-AD03) clears every
        // record. Deleted object-by-object rather than via `NSBatchDeleteRequest` so the change
        // flows through the view context the same way `deleteLog(id:)` does. It records nothing in
        // the sync outbox: account deletion removes the account's server data itself.
        try await context.perform {
            for record in try self.context.fetch(CDWorkoutLog.fetchRequest()) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
