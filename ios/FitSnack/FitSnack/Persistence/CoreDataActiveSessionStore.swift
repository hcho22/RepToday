import CoreData
import Foundation

/// The CoreData-backed `ActiveSessionStore` (US-K04), so an abandoned session survives a full
/// relaunch and can be resumed or discarded from the Ready Screen.
///
/// Reads, writes, and clears the one `CDActiveSession` record per user (`userId`-keyed, overwritten
/// in place), on the supplied context. The running app injects the shared stack's context; unlike
/// the user, logs, and policy, an in-progress session lives in the device-local store
/// configuration and is **never** synced through CloudKit (US-N02) - it is transient, device-bound
/// state (absolute wall-clock instants tied to this device's run) with no meaning on another
/// device. The store is otherwise unit-tested directly, and the player and Ready Screen are
/// unit-tested against `InMemoryActiveSessionStore`, keeping their logic free of CoreData.
final class CoreDataActiveSessionStore: ActiveSessionStore, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the context happens
    // inside `context.perform`, which serializes onto its queue.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load(for userId: String) async throws -> ActiveSessionState? {
        try await context.perform {
            let request = CDActiveSession.fetchRequest(userId: userId)
            guard let record = try self.context.fetch(request).first else { return nil }
            return try record.toActiveSessionState()
        }
    }

    func save(_ state: ActiveSessionState, for userId: String) async throws {
        try await context.perform {
            let request = CDActiveSession.fetchRequest(userId: userId)
            let record = try self.context.fetch(request).first ?? CDActiveSession(context: self.context)
            try record.update(from: state, userId: userId)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func clear(for userId: String) async throws {
        try await context.perform {
            let request = CDActiveSession.fetchRequest(userId: userId)
            for record in try self.context.fetch(request) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
