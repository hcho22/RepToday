import CoreData
import Foundation

/// CoreData mirror of the `User` aggregate (US-A04).
///
/// Scalar identity fields (`id`, `displayName`, `createdAt`, `phaseRaw`) are stored as
/// native attributes so they are queryable; the nested value types (`profile`,
/// `subscription`, `consistency`) are stored as JSON-encoded `Data`. Every attribute is
/// optional because `NSPersistentCloudKitContainer` (US-J02) requires it - `toUser()`
/// re-imposes the domain model's non-optional contract and throws if a field is missing.
@objc(CDUser)
final class CDUser: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDUser> {
        NSFetchRequest<CDUser>(entityName: "CDUser")
    }

    @NSManaged var id: String?
    @NSManaged var displayName: String?
    @NSManaged var createdAt: Date?
    @NSManaged var phaseRaw: String?
    @NSManaged var profileData: Data?
    @NSManaged var subscriptionData: Data?
    @NSManaged var consistencyData: Data?
}

// MARK: - Domain conversion

extension CDUser {
    /// Reconstructs the domain `User`, throwing `PersistenceError` if a required field is
    /// missing or an enum raw value is unknown, and rethrowing any JSON decode failure.
    func toUser() throws -> User {
        guard let id else { throw PersistenceError.missingField("CDUser.id") }
        guard let displayName else { throw PersistenceError.missingField("CDUser.displayName") }
        guard let createdAt else { throw PersistenceError.missingField("CDUser.createdAt") }
        guard let phaseRaw else { throw PersistenceError.missingField("CDUser.phaseRaw") }
        guard let phase = Phase(rawValue: phaseRaw) else {
            throw PersistenceError.invalidEnum(field: "CDUser.phaseRaw", value: phaseRaw)
        }
        guard let profileData else { throw PersistenceError.missingField("CDUser.profileData") }
        guard let subscriptionData else { throw PersistenceError.missingField("CDUser.subscriptionData") }
        guard let consistencyData else { throw PersistenceError.missingField("CDUser.consistencyData") }

        let decoder = PersistenceCoder.decoder
        return User(
            id: id,
            displayName: displayName,
            createdAt: createdAt,
            profile: try decoder.decode(UserProfile.self, from: profileData),
            phase: phase,
            subscription: try decoder.decode(Subscription.self, from: subscriptionData),
            consistency: try decoder.decode(Consistency.self, from: consistencyData)
        )
    }

    /// Overwrites every attribute from `user`. Used for both inserts and updates - call it
    /// on a freshly-inserted `CDUser` or on one fetched by `id` to replace its contents.
    func update(from user: User) throws {
        let encoder = PersistenceCoder.encoder
        id = user.id
        displayName = user.displayName
        createdAt = user.createdAt
        phaseRaw = user.phase.rawValue
        profileData = try encoder.encode(user.profile)
        subscriptionData = try encoder.encode(user.subscription)
        consistencyData = try encoder.encode(user.consistency)
    }
}
