import CoreData
import Foundation

/// The CoreData-backed `SessionPolicyStore` (US-F03), so the deterministic Programmer's last-written
/// policy survives relaunch and offline use (US-D03).
///
/// Reads and writes the one `CDSessionPolicy` record per user (`userId`-keyed, overwritten in place),
/// on the supplied context. The running app injects the shared stack's context; the policy lives in
/// the CloudKit-synced `Cloud` store configuration alongside the user and logs (US-N02), so it backs
/// up and follows the user across devices. The deterministic service is otherwise unit-tested against
/// `InMemorySessionPolicyStore`, keeping its logic free of CoreData.
final class CoreDataSessionPolicyStore: SessionPolicyStore, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the
    // context happens inside `context.perform`, which serializes onto its queue.
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

    func delete(for userId: String) async throws {
        // Account deletion (US-AD02/US-AD03): remove this user's one policy record and save so the
        // CloudKit mirror tombstones it, mirroring `save`'s per-user, in-place shape.
        try await context.perform {
            let request = CDSessionPolicy.fetchRequest(userId: userId)
            for record in try self.context.fetch(request) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteAll() async throws {
        // Account deletion (US-AD02/US-AD03): remove every policy record without a user id, so
        // teardown completes even when the `CDUser` aggregate is unreadable, and save so the CloudKit
        // mirror tombstones it. Deleted object-by-object rather than via `NSBatchDeleteRequest` for the
        // same reason `delete(for:)` is. Single-user, so this is the same one record.
        try await context.perform {
            for record in try self.context.fetch(CDSessionPolicy.fetchRequest()) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
