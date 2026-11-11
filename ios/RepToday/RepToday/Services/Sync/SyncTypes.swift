import Foundation

/// The values the local-first sync layer passes between the on-device store, the engine and the
/// account backend (M3, US-AU03, ADR-0016). `convex/sync.ts` is the other end of the wire.

/// What a synced record carries when it is uploaded or pulled.
enum SyncRecordContent: Equatable, Sendable {
    /// The `User` aggregate as JSON, plus its Focus Areas (stored server-side in their own table).
    case profile(payload: String, focusAreas: [String])
    /// The in-force `SessionPolicy` as JSON.
    case sessionPolicy(payload: String)
    /// A `WorkoutLog` as JSON and its completion time.
    case workoutLog(payload: String, completedAt: Date)
    /// An `OutsideActivity` as JSON and its date.
    case outsideActivity(payload: String, date: Date)
    /// The record is gone (a log or an Outside Activity was deleted).
    case deleted
}

/// One outbox entry with the record's current contents, ready to upload.
struct PendingSyncChange: Equatable, Sendable {
    let type: SyncRecordType
    let recordId: String
    /// The outbox entry's revision when it was read. The entry is removed after the upload only if it
    /// still has this revision, so an edit made during the upload is uploaded too.
    let revision: UUID
    /// Sent as `clientUpdatedAt`: the newer change wins on the server.
    let changedAt: Date
    /// `nil` when there is nothing to upload: a profile or policy whose record no longer exists or no
    /// longer decodes. Such an entry is removed without a request.
    let content: SyncRecordContent?
}

/// The outbox entry a successful upload clears.
struct SyncAcknowledgement: Equatable, Sendable {
    let type: SyncRecordType
    let recordId: String
    let revision: UUID
}

/// One record as the account holds it, pulled to this device.
struct RemoteSyncRecord: Equatable, Sendable {
    let type: SyncRecordType
    let recordId: String
    /// When the record was last changed on whichever device wrote it.
    let clientUpdatedAt: Date
    let content: SyncRecordContent
}

/// One page of pulled records.
struct SyncPullPage: Equatable, Sendable {
    let records: [RemoteSyncRecord]
    /// The `since` for the next page.
    let cursor: Int
    let hasMore: Bool
}

/// Why a call to the account backend did not succeed.
enum SyncRemoteError: Error, Equatable {
    /// No signed-in account (or no account backend configured); nothing was sent.
    case notSignedIn
    /// The backend did not accept the session token.
    case unauthenticated
    /// The account is being deleted; nothing more is written to it.
    case accountDeleting
    /// No connection, or the request timed out. Worth retrying later.
    case unreachable
    /// The backend refused the request or failed; `code` is the backend's error code when it sent one.
    case rejected(code: String?, message: String)
    /// The response was not what the account API returns.
    case invalidResponse
}

/// The on-device side of sync: the outbox and the records it names (`CoreDataSyncStore`).
protocol SyncStore: Sendable {
    /// Up to `limit` outbox entries with their records' current contents, oldest change first.
    func pendingChanges(limit: Int) async throws -> [PendingSyncChange]
    /// How many records are waiting to sync.
    func pendingCount() async throws -> Int
    /// Removes the entries an upload settled, unless they changed again since they were read.
    func acknowledge(_ acknowledgements: [SyncAcknowledgement]) async throws
    /// Writes pulled records into the store without queueing them for upload. A record with a local
    /// change still waiting is kept unless the pulled one is newer. Returns how many records changed.
    @discardableResult
    func apply(_ records: [RemoteSyncRecord]) async throws -> Int
    /// Queues every synced record on the device for upload, dated `changedAt` (the migration passes the
    /// epoch, so nothing it uploads replaces newer account data). Returns how many were queued.
    @discardableResult
    func enqueueAllRecords(changedAt: Date) async throws -> Int
    /// Empties the outbox (account deletion).
    func clearOutbox() async throws
    /// Deletes every synced record on the device and the outbox, without queueing anything: the clean
    /// slate an account restore writes onto.
    func eraseSyncedRecords() async throws
}

/// The account backend (`ConvexSyncRemote`).
protocol SyncRemote: Sendable {
    /// Uploads changes that have content. Every change the backend answers for is settled, whatever
    /// the outcome (`applied`, `unchanged`, or `stale` when the account already holds a newer one).
    func push(_ changes: [PendingSyncChange]) async throws
    /// The account's records written after `since`.
    func pull(since: Int, limit: Int) async throws -> SyncPullPage
    /// Deletes the account's server data and its sign-in identity (`accounts:deleteAccount`).
    func deleteAccount() async throws
}

/// Encodes and decodes the domain records that travel as sync payloads.
///
/// Dates go over the wire as milliseconds since the epoch, so the account data is readable server-side,
/// and keys are sorted, so the same record always encodes to the same string - which is what lets the
/// backend recognise a replayed upload as `unchanged`.
enum SyncPayloadCoder {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "payload is not UTF-8"))
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from payload: String) throws -> T {
        try decoder.decode(type, from: Data(payload.utf8))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

extension Date {
    /// Whole milliseconds since the epoch, the wire form of every sync timestamp.
    var syncMilliseconds: Double { (timeIntervalSince1970 * 1000).rounded() }

    init(syncMilliseconds: Double) {
        self.init(timeIntervalSince1970: syncMilliseconds / 1000)
    }
}
