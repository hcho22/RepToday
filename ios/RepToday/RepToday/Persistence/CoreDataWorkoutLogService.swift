import CoreData
import Foundation

/// The CoreData-backed `WorkoutLogServiceProtocol` (US-N02), so completed sessions survive
/// relaunch and sync through CloudKit (the `Cloud` configuration) across the user's devices.
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
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
