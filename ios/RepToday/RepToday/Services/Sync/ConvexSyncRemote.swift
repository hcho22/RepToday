import Foundation

/// The account backend over Convex (M3, US-AU03/US-AU05): `sync:push`, `sync:pull` and
/// `accounts:deleteAccount` in `convex/`, reached through `ConvexHTTPClient`.
///
/// This type only maps between the sync engine's values and the wire shapes `convex/sync.ts`
/// validates; it decides nothing.
struct ConvexSyncRemote: SyncRemote {
    let client: ConvexHTTPClient

    // MARK: - push

    func push(_ changes: [PendingSyncChange]) async throws {
        let wire = changes.compactMap(WireChange.init)
        guard !wire.isEmpty else { return }
        let _: PushResult = try await client.call(.mutation, "sync:push", args: PushArgs(changes: wire))
    }

    private struct PushArgs: Encodable, Sendable {
        let changes: [WireChange]
    }

    /// The backend reports one outcome per change; every outcome settles the change, so only the
    /// fact that the batch committed is read.
    private struct PushResult: Decodable {
        let serverSeq: Double
    }

    /// One change as `convex/sync.ts` validates it: optional fields are omitted, never `null`.
    struct WireChange: Encodable, Sendable, Equatable {
        let table: String
        let recordId: String
        let clientUpdatedAt: Double
        var payload: String?
        var focusAreas: [String]?
        var deleted: Bool?
        var completedAt: Double?
        var date: Double?

        init?(_ change: PendingSyncChange) {
            guard let content = change.content else { return nil }
            recordId = change.recordId
            clientUpdatedAt = change.changedAt.syncMilliseconds
            switch (change.type, content) {
            case (.profile, .profile(let payload, let focusAreas)):
                table = "profile"
                self.payload = payload
                self.focusAreas = focusAreas
            case (.sessionPolicy, .sessionPolicy(let payload)):
                table = "sessionPolicy"
                self.payload = payload
            case (.workoutLog, .workoutLog(let payload, let completedAt)):
                table = "workoutLog"
                self.payload = payload
                deleted = false
                self.completedAt = completedAt.syncMilliseconds
            case (.workoutLog, .deleted):
                table = "workoutLog"
                deleted = true
            case (.outsideActivity, .outsideActivity(let payload, let date)):
                table = "outsideActivity"
                self.payload = payload
                deleted = false
                self.date = date.syncMilliseconds
            case (.outsideActivity, .deleted):
                table = "outsideActivity"
                deleted = true
            default:
                // A profile or policy is never deleted through sync, and content always matches its type.
                return nil
            }
        }
    }

    // MARK: - pull

    func pull(since: Int, limit: Int) async throws -> SyncPullPage {
        let page: PullResult = try await client.call(.query, "sync:pull", args: PullArgs(since: Double(since), limit: Double(limit)))
        return SyncPullPage(
            records: page.changes.compactMap(\.record),
            cursor: Int(page.cursor),
            hasMore: page.hasMore
        )
    }

    private struct PullArgs: Encodable, Sendable {
        let since: Double
        let limit: Double
    }

    private struct PullResult: Decodable {
        let changes: [PulledChange]
        let cursor: Double
        let hasMore: Bool
    }

    struct PulledChange: Decodable, Equatable {
        let table: String
        let recordId: String
        let clientUpdatedAt: Double
        let payload: String?
        let focusAreas: [String]?
        let deleted: Bool?
        let completedAt: Double?
        let date: Double?

        /// The record, or `nil` for a table this build does not know (a later build's addition).
        var record: RemoteSyncRecord? {
            let updatedAt = Date(syncMilliseconds: clientUpdatedAt)
            let content: SyncRecordContent
            let type: SyncRecordType
            switch table {
            case "profile":
                guard let payload else { return nil }
                type = .profile
                content = .profile(payload: payload, focusAreas: focusAreas ?? [])
            case "sessionPolicy":
                guard let payload else { return nil }
                type = .sessionPolicy
                content = .sessionPolicy(payload: payload)
            case "workoutLog":
                type = .workoutLog
                if deleted == true {
                    content = .deleted
                } else {
                    guard let payload, let completedAt else { return nil }
                    content = .workoutLog(payload: payload, completedAt: Date(syncMilliseconds: completedAt))
                }
            case "outsideActivity":
                type = .outsideActivity
                if deleted == true {
                    content = .deleted
                } else {
                    guard let payload, let date else { return nil }
                    content = .outsideActivity(payload: payload, date: Date(syncMilliseconds: date))
                }
            default:
                return nil
            }
            return RemoteSyncRecord(type: type, recordId: recordId, clientUpdatedAt: updatedAt, content: content)
        }
    }

    // MARK: - deleteAccount

    func deleteAccount() async throws {
        let _: DeleteResult = try await client.call(.action, "accounts:deleteAccount", args: ConvexNoArguments())
    }

    private struct DeleteResult: Decodable {
        let deleted: Bool
    }
}
