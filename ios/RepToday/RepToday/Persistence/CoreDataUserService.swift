import CoreData
import Foundation

/// The CoreData-backed `UserServiceProtocol` (US-N02), so the single user aggregate survives
/// relaunch and syncs through CloudKit (the `Cloud` configuration) across the user's devices.
///
/// Rep Today has exactly one local user, keyed by their stable identity (`User.id`, the Sign in
/// with Apple identifier or a local fallback, US-N01). Reads return that record; `save` upserts
/// it in place by `id` so re-saving never accumulates duplicates. Every access happens inside
/// `context.perform`, which serializes onto the context's queue - the running app injects the
/// shared stack's `viewContext`; the app is otherwise unit-tested against `MockUserService`,
/// keeping view-model logic free of CoreData.
final class CoreDataUserService: UserServiceProtocol, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the context happens
    // inside `context.perform`, which serializes onto its queue.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func currentUser() async throws -> User? {
        try await context.perform {
            let request = CDUser.fetchRequest()
            request.fetchLimit = 1
            guard let record = try self.context.fetch(request).first else { return nil }
            return try record.toUser()
        }
    }

    func save(_ user: User) async throws {
        try await context.perform {
            let request = CDUser.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", user.id)
            request.fetchLimit = 1
            let record = try self.context.fetch(request).first ?? CDUser(context: self.context)
            try record.update(from: user)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteCurrentUser() async throws {
        try await context.perform {
            for record in try self.context.fetch(CDUser.fetchRequest()) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
}
