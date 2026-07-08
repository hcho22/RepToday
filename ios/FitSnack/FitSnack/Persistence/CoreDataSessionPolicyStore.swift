import CoreData
import Foundation

/// The CoreData-backed `SessionPolicyStore` (US-F03), so the deterministic Programmer's last-written
/// policy survives relaunch and offline use (US-D03).
///
/// Reads and writes the one `CDSessionPolicy` record per user (`userId`-keyed, overwritten in place),
/// on the supplied context. The running app injects the shared stack's context (US-J02 will sync it
/// through CloudKit alongside the user and logs); the deterministic service is otherwise unit-tested
/// against `InMemorySessionPolicyStore`, keeping its logic free of CoreData.
final class CoreDataSessionPolicyStore: SessionPolicyStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func policy(for userId: String) async throws -> SessionPolicy? {
        try await context.perform {
            let request = CDSessionPolicy.fetchRequest(userId: userId)
            guard let record = try self.context.fetch(request).first else { return nil }
            return try record.toSessionPolicy()
        }
    }

    func save(_ policy: SessionPolicy, for userId: String) async throws {
        try await context.perform {
            let request = CDSessionPolicy.fetchRequest(userId: userId)
            let record = try self.context.fetch(request).first ?? CDSessionPolicy(context: self.context)
            try record.update(from: policy, userId: userId)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
