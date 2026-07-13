import CoreData
import Foundation

/// CoreData mirror of the `User` aggregate (US-A04).
///
/// Scalar identity fields (`id`, `displayName`, `createdAt`, `phaseRaw`) are stored as
/// native attributes so they are queryable; the nested value types (`profile`,
/// `subscription`, `consistency`, and the v6 `why`/`duration`/`coldStart`) are stored as
/// JSON-encoded `Data`. Every attribute is optional because `NSPersistentCloudKitContainer`
/// (US-N02) requires it - `toUser()` re-imposes the domain model's non-optional contract and
/// throws if a required field is missing, except the additive v6 columns, which decode to
/// documented defaults when absent so pre-v6 records still load (US-D01).
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
    // v6 nested fields (US-D01). Nil on a legacy record written before these existed;
    // `toUser()` fills documented defaults rather than throwing so old data still loads.
    @NSManaged var whyData: Data?
    @NSManaged var durationData: Data?
    @NSManaged var coldStartData: Data?
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
        let profile = try decoder.decode(UserProfile.self, from: profileData)

        // v6 nested fields (US-D01) are backward-compatible: a record written before they
        // existed has nil columns and decodes to documented defaults - an empty `why`, a
        // `duration` seeded from the profile's typical availability (so `defaultMinutes ==
        // onboardingSeedMinutes`), and a fresh (`active == true`, `sessionsLogged == 0`)
        // cold-start - rather than failing to load.
        let why = try whyData.map { try decoder.decode(User.Why.self, from: $0) } ?? .empty
        let duration = try durationData.map { try decoder.decode(User.Duration.self, from: $0) }
            ?? .seeded(minutes: profile.typicalAvailableMinutes)
        let coldStart = try coldStartData.map { try decoder.decode(User.ColdStart.self, from: $0) } ?? .fresh

        return User(
            id: id,
            displayName: displayName,
            createdAt: createdAt,
            profile: profile,
            phase: phase,
            subscription: try decoder.decode(Subscription.self, from: subscriptionData),
            consistency: try decoder.decode(Consistency.self, from: consistencyData),
            why: why,
            duration: duration,
            coldStart: coldStart
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
        whyData = try encoder.encode(user.why)
        durationData = try encoder.encode(user.duration)
        coldStartData = try encoder.encode(user.coldStart)
    }
}
