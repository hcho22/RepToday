import Foundation

/// The sync store of the in-memory mock container: its records live in mock services, not Core Data,
/// so there is no outbox and nothing to upload. Tests of the sync layer itself use
/// `CoreDataSyncStore` over an in-memory Core Data stack.
struct NoOpSyncStore: SyncStore {
    func pendingChanges(limit: Int) async throws -> [PendingSyncChange] { [] }
    func pendingCount() async throws -> Int { 0 }
    func acknowledge(_ acknowledgements: [SyncAcknowledgement]) async throws {}
    func apply(_ records: [RemoteSyncRecord]) async throws -> Int { 0 }
    func enqueueAllRecords(changedAt: Date) async throws -> Int { 0 }
    func clearOutbox() async throws {}
    func eraseSyncedRecords() async throws {}
}

/// A cursor held in memory, for tests and the mock container.
final class InMemorySyncCursorStore: SyncCursorStore, @unchecked Sendable {
    // Safe: `value` is only touched under `lock`.
    private let lock = NSLock()
    private var value = 0

    init(cursor: Int = 0) {
        value = cursor
    }

    func cursor() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func setCursor(_ cursor: Int) {
        lock.lock()
        defer { lock.unlock() }
        value = cursor
    }

    func reset() {
        setCursor(0)
    }
}
