import CoreData
import Foundation
@testable import RepToday

/// An in-memory account backend with the same rules as `convex/sync.ts`: rows keyed by record id,
/// the newer `clientUpdatedAt` wins, an identical replay changes nothing, every write takes the next
/// `serverSeq`, and `pull` pages by it. The profile and the session policy are one row each, whatever
/// their record id, exactly as the backend keys them by owner.
///
/// Failures can be scripted, so a test can interrupt an upload or a pull at a chosen point.
actor FakeAccountServer: SyncRemote {
    struct Row: Equatable {
        var recordId: String
        var clientUpdatedAt: Double
        var content: SyncRecordContent
        var serverSeq: Int
    }

    private(set) var rows: [String: Row] = [:]
    private var seq = 0
    private(set) var pushCalls = 0
    private(set) var pushedChanges = 0
    private(set) var pullCalls = 0
    private(set) var deleteCalls = 0
    /// Changes whose write actually stored something (not `unchanged` or `stale`).
    private(set) var appliedWrites = 0

    private var failPushes: [Int: SyncRemoteError] = [:]
    private var failPulls: [Int: SyncRemoteError] = [:]
    private var deleteError: SyncRemoteError?
    private var deletionOutcome: RemoteAccountDeletion = .complete
    private var losesDeletionResponse = false
    /// When set, every call fails with this, as if the device were offline.
    private var offlineError: SyncRemoteError?

    /// Makes push number `call` (1-based) fail with `error` before anything is stored.
    func failPush(call: Int, with error: SyncRemoteError) {
        failPushes[call] = error
    }

    /// Makes pull number `call` (1-based) fail with `error`.
    func failPull(call: Int, with error: SyncRemoteError) {
        failPulls[call] = error
    }

    func failDeletion(with error: SyncRemoteError?) {
        deleteError = error
    }

    /// What a successful deletion answers: `.underWay` when Clerk could not be reached.
    func answerDeletion(with outcome: RemoteAccountDeletion) {
        deletionOutcome = outcome
    }

    /// Makes the next deletion commit on the server and then lose its answer on the way back.
    func loseDeletionResponse() {
        losesDeletionResponse = true
    }

    func setOffline(_ offline: Bool) {
        offlineError = offline ? .unreachable : nil
    }

    /// Seeds a row as another device would have written it.
    func seed(_ type: SyncRecordType, recordId: String, clientUpdatedAt: Date, content: SyncRecordContent) {
        seq += 1
        rows[key(type, recordId)] = Row(recordId: recordId, clientUpdatedAt: clientUpdatedAt.syncMilliseconds, content: content, serverSeq: seq)
    }

    func row(_ type: SyncRecordType, recordId: String) -> Row? {
        rows[key(type, recordId)]
    }

    func rows(of type: SyncRecordType) -> [Row] {
        rows.filter { $0.key.hasPrefix("\(type.rawValue):") }.map(\.value).sorted { $0.serverSeq < $1.serverSeq }
    }

    // MARK: - SyncRemote

    func push(_ changes: [PendingSyncChange]) async throws {
        pushCalls += 1
        if let offlineError { throw offlineError }
        if let error = failPushes[pushCalls] { throw error }
        for change in changes {
            guard let content = change.content else { continue }
            pushedChanges += 1
            let id = key(change.type, change.recordId)
            let incoming = change.changedAt.syncMilliseconds
            if let existing = rows[id] {
                if existing.clientUpdatedAt > incoming { continue }
                if existing.clientUpdatedAt == incoming, existing.content == content, existing.recordId == change.recordId { continue }
            }
            seq += 1
            appliedWrites += 1
            rows[id] = Row(recordId: change.recordId, clientUpdatedAt: incoming, content: content, serverSeq: seq)
        }
    }

    func pull(since: Int, limit: Int) async throws -> SyncPullPage {
        pullCalls += 1
        if let offlineError { throw offlineError }
        if let error = failPulls[pullCalls] { throw error }
        let after = rows.map { ($0.key, $0.value) }
            .filter { $0.1.serverSeq > since }
            .sorted { $0.1.serverSeq < $1.1.serverSeq }
        let page = after.prefix(limit)
        let records = page.compactMap { entry -> RemoteSyncRecord? in
            guard let type = SyncRecordType(rawValue: String(entry.0.split(separator: ":")[0])) else { return nil }
            return RemoteSyncRecord(
                type: type,
                recordId: entry.1.recordId,
                clientUpdatedAt: Date(syncMilliseconds: entry.1.clientUpdatedAt),
                content: entry.1.content
            )
        }
        return SyncPullPage(records: records, cursor: page.last?.1.serverSeq ?? since, hasMore: after.count > limit)
    }

    func deleteAccount() async throws -> RemoteAccountDeletion {
        deleteCalls += 1
        if let offlineError { throw offlineError }
        if let deleteError { throw deleteError }
        rows = [:]
        if losesDeletionResponse { throw SyncRemoteError.noResponse }
        return deletionOutcome
    }

    /// The profile and the policy are one row per account; logs, activities and Custom Workouts are keyed
    /// by id.
    private func key(_ type: SyncRecordType, _ recordId: String) -> String {
        switch type {
        case .profile, .sessionPolicy:
            return "\(type.rawValue):singleton"
        case .workoutLog, .outsideActivity, .customWorkout:
            return "\(type.rawValue):\(recordId)"
        }
    }
}

/// The Core Data services and sync store over one in-memory stack, as `ServiceContainer.live` wires them.
struct SyncTestStack {
    let persistence: PersistenceController
    let users: CoreDataUserService
    let logs: CoreDataWorkoutLogService
    let activities: CoreDataOutsideActivityService
    let customWorkouts: CoreDataCustomWorkoutService
    let policies: CoreDataSessionPolicyStore
    let activeSessions: CoreDataActiveSessionStore
    let store: CoreDataSyncStore

    init(persistence: PersistenceController = MockPersistence.controller()) {
        self.persistence = persistence
        let context = persistence.viewContext
        users = CoreDataUserService(context: context)
        logs = CoreDataWorkoutLogService(context: context)
        activities = CoreDataOutsideActivityService(context: context)
        customWorkouts = CoreDataCustomWorkoutService(context: context)
        policies = CoreDataSessionPolicyStore(context: context)
        activeSessions = CoreDataActiveSessionStore(context: context)
        store = CoreDataSyncStore(context: context)
    }

    func engine(_ server: FakeAccountServer, cursor: InMemorySyncCursorStore = InMemorySyncCursorStore(), pushBatchSize: Int = 25, pullPageSize: Int = 100) -> SyncEngine {
        SyncEngine(store: store, remote: server, cursorStore: cursor, pushBatchSize: pushBatchSize, pullPageSize: pullPageSize)
    }

    /// The outbox entries, as `type:recordId`.
    func outbox() async throws -> [String] {
        let context = persistence.viewContext
        return try await context.perform {
            try context.fetch(CDSyncChange.fetchRequest())
                .map { "\($0.recordType ?? "?"):\($0.recordId ?? "?")" }
                .sorted()
        }
    }
}

enum SyncFixtures {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static func user(id: String = "local-user", name: String = "Riley", phase: Phase = .discipline) -> User {
        var user = MockPersistence.sampleUser
        user.id = id
        user.displayName = name
        user.phase = phase
        user.createdAt = base
        return user
    }

    static func log(daysAgo: Int, id: UUID = UUID()) -> WorkoutLog {
        WorkoutLog(
            id: id,
            workoutId: UUID(),
            completedAt: base.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            requestedMinutes: 15,
            durationMinutes: 15,
            wasReturn: false,
            shape: .singleFocus,
            focusPillar: nil,
            perceivedDifficulty: .justRight,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "push_standard",
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: [CompletedSet(reps: 15, durationSeconds: nil)],
                    skipped: false
                ),
            ]
        )
    }

    static func activity(daysAgo: Int) -> OutsideActivity {
        OutsideActivity(type: .run, date: base.addingTimeInterval(TimeInterval(-daysAgo * 86_400)), durationMinutes: 30)
    }

    static func payload<T: Encodable>(_ value: T) throws -> String {
        try SyncPayloadCoder.encode(value)
    }
}
