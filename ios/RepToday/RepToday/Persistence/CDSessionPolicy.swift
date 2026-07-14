import CoreData
import Foundation

/// CoreData mirror of the `SessionPolicy` (US-D03).
///
/// A user has exactly one current policy, keyed by `userId` and overwritten in place, so the
/// last-written policy survives relaunch and offline use. `userId` is a native attribute so a
/// policy is queryable by its owner; the policy itself is stored whole as JSON-encoded `Data`
/// (`policyData`) because it nests a `[Pillar: Double]` map and several optional value types.
/// As with `CDUser`/`CDWorkoutLog`, attributes are optional for CloudKit (US-N02, which will
/// sync this alongside the user and logs) and `toSessionPolicy()` re-imposes the non-optional
/// domain contract, failing loudly rather than substituting a silently-wrong policy.
@objc(CDSessionPolicy)
final class CDSessionPolicy: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDSessionPolicy> {
        NSFetchRequest<CDSessionPolicy>(entityName: "CDSessionPolicy")
    }

    /// The id of the `User` this policy belongs to (the query/identity key).
    @NSManaged var userId: String?
    /// The whole `SessionPolicy`, JSON-encoded.
    @NSManaged var policyData: Data?
}

// MARK: - Domain conversion

extension CDSessionPolicy {
    /// Reconstructs the domain `SessionPolicy`, throwing `PersistenceError` when the stored
    /// blob is missing and rethrowing any JSON decode failure.
    func toSessionPolicy() throws -> SessionPolicy {
        guard let policyData else { throw PersistenceError.missingField("CDSessionPolicy.policyData") }
        return try PersistenceCoder.decoder.decode(SessionPolicy.self, from: policyData)
    }

    /// Overwrites this record from `policy` for `userId` (insert or update). Fetch by `userId`
    /// and call this on the existing record to replace it in place - a user keeps a single
    /// current policy, never a growing history.
    func update(from policy: SessionPolicy, userId: String) throws {
        self.userId = userId
        self.policyData = try PersistenceCoder.encoder.encode(policy)
    }
}

// MARK: - Queries

extension CDSessionPolicy {
    /// The current policy record for `userId`, if one has been written.
    static func fetchRequest(userId: String) -> NSFetchRequest<CDSessionPolicy> {
        let request = NSFetchRequest<CDSessionPolicy>(entityName: "CDSessionPolicy")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        return request
    }
}
