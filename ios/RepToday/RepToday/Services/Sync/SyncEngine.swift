import Foundation

/// Where the device last read the account's changes up to (`sync:pull`'s cursor), kept per account.
protocol SyncCursorStore: Sendable {
    func cursor() -> Int
    func setCursor(_ cursor: Int)
    func reset()
}

/// The cursor in `UserDefaults`, cleared with the account.
struct DefaultsSyncCursorStore: SyncCursorStore, @unchecked Sendable {
    // `UserDefaults` is thread-safe; the wrapper only holds the reference and a key.
    private let defaults: UserDefaults
    static let key = "Sync.pullCursor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cursor() -> Int { defaults.integer(forKey: Self.key) }
    func setCursor(_ cursor: Int) { defaults.set(cursor, forKey: Self.key) }
    func reset() { defaults.removeObject(forKey: Self.key) }
}

/// Brings back the plan and history an account already holds, for a device that has just signed in
/// to it (US-AU02). `SyncEngine` is the implementation; onboarding depends only on this.
protocol AccountRestoring: Sendable {
    /// Pulls everything the account holds into the device's store. Returns the kinds of record found.
    func restoreFromAccount() async throws -> Set<SyncRecordType>
}

/// What one sync cycle did.
struct SyncReport: Equatable, Sendable {
    /// Outbox entries settled by uploading (or because there was nothing to upload).
    var uploaded = 0
    /// Pulled records that changed the device's store.
    var applied = 0
    /// Records still waiting after the cycle.
    var pending = 0
}

/// One sync cycle over the outbox and the account (M3, US-AU03): upload everything waiting, then pull
/// whatever changed on the account since the cursor.
///
/// Uploading first means a pulled record can only replace a local one that is not waiting (or is
/// older), the same newest-wins rule the account applies. Every step is safe to interrupt: an outbox
/// entry is removed only after the account confirmed it (and only if it did not change meanwhile),
/// and the cursor moves only after a pulled page was saved - so a cycle killed at any point resumes
/// with nothing lost and nothing duplicated (the account's upsert is keyed by record id).
///
/// Cycles never overlap: a request while one runs joins it.
actor SyncEngine: AccountRestoring {
    private let store: any SyncStore
    private let remote: any SyncRemote
    private let cursorStore: any SyncCursorStore
    private let pushBatchSize: Int
    private let pullPageSize: Int
    /// Bounds one cycle, so a device whose records keep changing still finishes a cycle.
    private let maxRoundsPerCycle: Int
    private var running: Task<SyncReport, Error>?

    init(
        store: any SyncStore,
        remote: any SyncRemote,
        cursorStore: any SyncCursorStore,
        pushBatchSize: Int = 25,
        pullPageSize: Int = 100,
        maxRoundsPerCycle: Int = 40
    ) {
        self.store = store
        self.remote = remote
        self.cursorStore = cursorStore
        self.pushBatchSize = pushBatchSize
        self.pullPageSize = pullPageSize
        self.maxRoundsPerCycle = maxRoundsPerCycle
    }

    /// Runs one cycle, or joins the one already running.
    @discardableResult
    func sync() async throws -> SyncReport {
        if let running {
            return try await running.value
        }
        let task = Task { try await self.runCycle() }
        running = task
        defer { running = nil }
        return try await task.value
    }

    /// Waits for a running cycle to end, whatever its outcome.
    func waitForIdle() async {
        _ = try? await running?.value
    }

    /// Pulls everything the account holds into the store, from the start - how a device that has just
    /// signed in to an existing account gets that account's plan and history back. Returns the kinds of
    /// record the account held.
    func restoreFromAccount() async throws -> Set<SyncRecordType> {
        await waitForIdle()
        cursorStore.reset()
        return try await pullAll().types
    }

    private func runCycle() async throws -> SyncReport {
        var report = SyncReport()
        report.uploaded = try await pushAll()
        report.applied = try await pullAll().applied
        report.pending = try await store.pendingCount()
        return report
    }

    /// Uploads the outbox in batches until it is empty or the round budget is spent.
    private func pushAll() async throws -> Int {
        var settled = 0
        for _ in 0..<maxRoundsPerCycle {
            try Task.checkCancellation()
            let batch = try await store.pendingChanges(limit: pushBatchSize)
            guard !batch.isEmpty else { break }
            let uploadable = batch.filter { $0.content != nil }
            if !uploadable.isEmpty {
                try await remote.push(uploadable)
            }
            try await store.acknowledge(batch.map {
                SyncAcknowledgement(type: $0.type, recordId: $0.recordId, revision: $0.revision)
            })
            settled += batch.count
            if batch.count < pushBatchSize {
                break
            }
        }
        return settled
    }

    /// Pulls every page after the cursor, saving each page before moving the cursor past it.
    private func pullAll() async throws -> (applied: Int, types: Set<SyncRecordType>) {
        var applied = 0
        var types: Set<SyncRecordType> = []
        var since = cursorStore.cursor()
        for _ in 0..<maxRoundsPerCycle {
            try Task.checkCancellation()
            let page = try await remote.pull(since: since, limit: pullPageSize)
            applied += try await store.apply(page.records)
            types.formUnion(page.records.map(\.type))
            since = max(since, page.cursor)
            cursorStore.setCursor(since)
            if !page.hasMore {
                break
            }
        }
        return (applied, types)
    }
}
