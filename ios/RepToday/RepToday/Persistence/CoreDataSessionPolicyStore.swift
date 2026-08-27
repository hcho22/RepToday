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

    func update(
        for userId: String,
        transform: @escaping @Sendable (SessionPolicy) -> SessionPolicy?
    ) async throws -> SessionPolicy? {
        // Atomic: the read, the transform, and the save all run inside a single `context.perform`
        // block, which serializes onto the context queue, so no other writer can interleave between
        // the read and the write (the two-writer safety seam, ADR-0005).
        try await context.perform {
            let request = CDSessionPolicy.fetchRequest(userId: userId)
            let existing = try self.context.fetch(request).first
            let current = try existing?.toSessionPolicy() ?? .default
            guard let next = transform(current) else { return nil }
            let record = existing ?? CDSessionPolicy(context: self.context)
            try record.update(from: next, userId: userId)
            if self.context.hasChanges {
                try self.context.save()
            }
            return next
        }
    }

    func deleteAll() async throws {
        // Account deletion (US-AD02/US-AD03): remove every policy record without a user id, so
        // teardown completes even when the `CDUser` aggregate is unreadable, and save so the CloudKit
        // mirror tombstones it. Deleted object-by-object rather than via `NSBatchDeleteRequest` so the
        // change flows through the view context and CloudKit mirror like `save` does. Single-user, so
        // this is the one stored record.
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
