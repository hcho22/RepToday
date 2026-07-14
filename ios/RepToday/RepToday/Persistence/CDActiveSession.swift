import CoreData
import Foundation

/// CoreData mirror of the in-progress `ActiveSessionState` (US-K04).
///
/// A user has at most one resumable session, keyed by `userId` and overwritten in place, so an
/// abandoned session survives a full relaunch and can be resumed or discarded from the Ready Screen.
/// `userId` is a native attribute so the record is queryable by its owner; the snapshot is stored
/// whole as JSON-encoded `Data` (`stateData`) because it nests the generated `Workout`, the play
/// counters, and the rest-timer instants. As with `CDSessionPolicy`, attributes are optional for
/// CloudKit (US-N02) and `toActiveSessionState()` re-imposes the non-optional domain contract,
/// failing loudly rather than resuming a silently-corrupt session.
@objc(CDActiveSession)
final class CDActiveSession: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDActiveSession> {
        NSFetchRequest<CDActiveSession>(entityName: "CDActiveSession")
    }

    /// The id of the `User` this in-progress session belongs to (the query/identity key).
    @NSManaged var userId: String?
    /// The whole `ActiveSessionState`, JSON-encoded.
    @NSManaged var stateData: Data?
}

// MARK: - Domain conversion

extension CDActiveSession {
    /// Reconstructs the domain `ActiveSessionState`, throwing `PersistenceError` when the stored
    /// blob is missing and rethrowing any JSON decode failure.
    func toActiveSessionState() throws -> ActiveSessionState {
        guard let stateData else { throw PersistenceError.missingField("CDActiveSession.stateData") }
        return try PersistenceCoder.decoder.decode(ActiveSessionState.self, from: stateData)
    }

    /// Overwrites this record from `state` for `userId` (insert or update). Fetch by `userId` and
    /// call this on the existing record to replace it in place - a user keeps a single in-progress
    /// session, never a growing history.
    func update(from state: ActiveSessionState, userId: String) throws {
        self.userId = userId
        self.stateData = try PersistenceCoder.encoder.encode(state)
    }
}

// MARK: - Queries

extension CDActiveSession {
    /// The in-progress session record for `userId`, if one has been written.
    static func fetchRequest(userId: String) -> NSFetchRequest<CDActiveSession> {
        let request = NSFetchRequest<CDActiveSession>(entityName: "CDActiveSession")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        return request
    }
}
