import CoreData
import Foundation
import os

/// The Core Data side of local-first sync (M3, US-AU03): the outbox (`CDSyncChange`) and the synced
/// records it names, read and written on the app's one context.
///
/// Core Data stays the store the app runs on. This type only translates between it and the sync
/// engine: it reads each waiting record as it is now, settles outbox entries after an upload, and
/// writes pulled records back - **without** queueing them, so a pulled record is never echoed back up.
///
/// Every access happens inside `context.perform`, like the other Core Data services.
final class CoreDataSyncStore: SyncStore, @unchecked Sendable {
    // Safe: the only state is this immutable reference, and every access to the context happens
    // inside `context.perform`, which serializes onto its queue.
    private let context: NSManagedObjectContext
    private static let log = Logger(subsystem: "com.reptoday.app", category: "sync")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Outbox

    func pendingChanges(limit: Int) async throws -> [PendingSyncChange] {
        try await context.perform {
            let request = CDSyncChange.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "changedAt", ascending: true)]
            request.fetchLimit = limit
            let changes: [PendingSyncChange] = try self.context.fetch(request).compactMap { entry in
                guard let rawType = entry.recordType,
                      let type = SyncRecordType(rawValue: rawType),
                      let recordId = entry.recordId,
                      let revision = entry.revision else {
                    // A malformed entry can never be uploaded; drop it so it cannot block the queue.
                    self.context.delete(entry)
                    return nil
                }
                return PendingSyncChange(
                    type: type,
                    recordId: recordId,
                    revision: revision,
                    changedAt: entry.changedAt ?? Date(timeIntervalSince1970: 0),
                    content: try self.currentContent(type, recordId: recordId)
                )
            }
            if self.context.hasChanges {
                try self.context.save()
            }
            return changes
        }
    }

    func pendingCount() async throws -> Int {
        try await context.perform {
            try self.context.count(for: CDSyncChange.fetchRequest())
        }
    }

    func acknowledge(_ acknowledgements: [SyncAcknowledgement]) async throws {
        guard !acknowledgements.isEmpty else { return }
        try await context.perform {
            for acknowledgement in acknowledgements {
                guard let entry = try self.entry(acknowledgement.type, recordId: acknowledgement.recordId),
                      entry.revision == acknowledgement.revision else {
                    continue
                }
                self.context.delete(entry)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func clearOutbox() async throws {
        try await context.perform {
            for entry in try self.context.fetch(CDSyncChange.fetchRequest()) {
                self.context.delete(entry)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func eraseSyncedRecords() async throws {
        try await context.perform {
            try self.deleteAll(CDUser.fetchRequest())
            try self.deleteAll(CDSessionPolicy.fetchRequest())
            try self.deleteAll(CDWorkoutLog.fetchRequest())
            try self.deleteAll(CDOutsideActivity.fetchRequest())
            try self.deleteAll(CDCustomWorkout.fetchRequest())
            try self.deleteAll(CDSyncChange.fetchRequest())
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    private func deleteAll<Record: NSManagedObject>(_ request: NSFetchRequest<Record>) throws {
        for record in try context.fetch(request) {
            context.delete(record)
        }
    }

    func enqueueAllRecords(changedAt: Date) async throws -> Int {
        try await context.perform {
            var queued = 0
            for user in try self.context.fetch(CDUser.fetchRequest()) {
                guard let id = user.id else { continue }
                try CDSyncChange.markChanged(.profile, recordId: id, changedAt: changedAt, in: self.context)
                queued += 1
            }
            for policy in try self.context.fetch(CDSessionPolicy.fetchRequest()) {
                guard let userId = policy.userId else { continue }
                try CDSyncChange.markChanged(.sessionPolicy, recordId: userId, changedAt: changedAt, in: self.context)
                queued += 1
            }
            for log in try self.context.fetch(CDWorkoutLog.fetchRequest()) {
                guard let id = log.id else { continue }
                try CDSyncChange.markChanged(.workoutLog, recordId: id.uuidString, changedAt: changedAt, in: self.context)
                queued += 1
            }
            for activity in try self.context.fetch(CDOutsideActivity.fetchRequest()) {
                guard let id = activity.id else { continue }
                try CDSyncChange.markChanged(.outsideActivity, recordId: id.uuidString, changedAt: changedAt, in: self.context)
                queued += 1
            }
            for workout in try self.context.fetch(CDCustomWorkout.fetchRequest()) {
                guard let id = workout.id else { continue }
                try CDSyncChange.markChanged(.customWorkout, recordId: id.uuidString, changedAt: changedAt, in: self.context)
                queued += 1
            }
            if self.context.hasChanges {
                try self.context.save()
            }
            return queued
        }
    }

    // MARK: - Reading a record for upload

    /// The record's contents as they are now. A deleted log or activity uploads as a deletion; a
    /// profile or policy that is missing has nothing to upload. A record that exists but no longer
    /// decodes has nothing to upload either: it stays on the device, and its entry is settled so it
    /// cannot hold up the records behind it.
    private func currentContent(_ type: SyncRecordType, recordId: String) throws -> SyncRecordContent? {
        switch type {
        case .profile:
            guard let record = try fetchUser(id: recordId) else { return nil }
            do {
                let user = try record.toUser()
                return .profile(
                    payload: try SyncPayloadCoder.encode(user),
                    focusAreas: user.profile.focusAreas.map(\.rawValue)
                )
            } catch {
                Self.log.error("A stored profile could not be read for sync and was skipped: \(String(describing: error), privacy: .public)")
                return nil
            }
        case .sessionPolicy:
            guard let record = try context.fetch(CDSessionPolicy.fetchRequest(userId: recordId)).first else { return nil }
            do {
                return .sessionPolicy(payload: try SyncPayloadCoder.encode(try record.toSessionPolicy()))
            } catch {
                Self.log.error("A stored session policy could not be read for sync and was skipped: \(String(describing: error), privacy: .public)")
                return nil
            }
        case .workoutLog:
            guard let uuid = UUID(uuidString: recordId), let record = try fetchLog(id: uuid) else { return .deleted }
            do {
                let log = try record.toWorkoutLog()
                return .workoutLog(payload: try SyncPayloadCoder.encode(log), completedAt: log.completedAt)
            } catch {
                Self.log.error("A stored workout log could not be read for sync and was skipped: \(String(describing: error), privacy: .public)")
                return nil
            }
        case .outsideActivity:
            guard let uuid = UUID(uuidString: recordId), let record = try fetchActivity(id: uuid) else { return .deleted }
            do {
                let activity = try record.toOutsideActivity()
                return .outsideActivity(payload: try SyncPayloadCoder.encode(activity), date: activity.date)
            } catch {
                Self.log.error("A stored outside activity could not be read for sync and was skipped: \(String(describing: error), privacy: .public)")
                return nil
            }
        case .customWorkout:
            guard let uuid = UUID(uuidString: recordId), let record = try fetchCustomWorkout(id: uuid) else { return .deleted }
            do {
                return .customWorkout(payload: try SyncPayloadCoder.encode(try record.toCustomWorkout()))
            } catch {
                Self.log.error("A stored custom workout could not be read for sync and was skipped: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Applying pulled records

    func apply(_ records: [RemoteSyncRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        return try await context.perform {
            var changed = 0
            for record in records {
                do {
                    if try self.applyOne(record) {
                        changed += 1
                    }
                } catch {
                    // One unreadable record must not stop the rest of the page; it stays on the account.
                    Self.log.error("A pulled \(record.type.rawValue, privacy: .public) could not be applied: \(String(describing: error), privacy: .public)")
                }
            }
            if self.context.hasChanges {
                try self.context.save()
            }
            return changed
        }
    }

    /// Applies one pulled record. Returns whether the store changed.
    private func applyOne(_ record: RemoteSyncRecord) throws -> Bool {
        switch (record.type, record.content) {
        case (.profile, .profile(let payload, let focusAreas)):
            var user = try SyncPayloadCoder.decode(User.self, from: payload)
            user.profile.focusAreas = focusAreas.compactMap(FocusArea.init(rawValue:)).canonicallyOrdered
            // The device keeps its own user id: the profile is one per account, and a local id may key
            // the policy and a paused session.
            let existing = try context.fetch(CDUser.fetchRequest()).first
            let localId = existing?.id ?? user.id
            guard try takesPrecedence(record, over: .profile, recordId: localId) else { return false }
            user.id = localId
            let localPhase = existing?.phaseRaw.flatMap(Phase.init(rawValue:))
            let merged = localPhase.map { user.advancingPhase(to: $0) } ?? user
            // This device's own upload coming back changes nothing, so it writes nothing.
            if let current = try? existing?.toUser(), current == merged { return false }
            try (existing ?? CDUser(context: context)).update(from: merged)
            if merged.phase != user.phase {
                // An earned phase is never given back: the device keeps it and tells the account.
                try CDSyncChange.markChanged(.profile, recordId: localId, in: context)
            }
            return true

        case (.sessionPolicy, .sessionPolicy(let payload)):
            let policy = try SyncPayloadCoder.decode(SessionPolicy.self, from: payload)
            let userId = try context.fetch(CDUser.fetchRequest()).first?.id ?? record.recordId
            guard try takesPrecedence(record, over: .sessionPolicy, recordId: userId) else { return false }
            let existing = try context.fetch(CDSessionPolicy.fetchRequest(userId: userId)).first
            if let current = try? existing?.toSessionPolicy(), current == policy { return false }
            try (existing ?? CDSessionPolicy(context: context)).update(from: policy, userId: userId)
            return true

        case (.workoutLog, .workoutLog(let payload, _)):
            guard try takesPrecedence(record, over: .workoutLog, recordId: record.recordId) else { return false }
            let log = try SyncPayloadCoder.decode(WorkoutLog.self, from: payload)
            let existing = try fetchLog(id: log.id)
            if let current = try? existing?.toWorkoutLog(), current == log { return false }
            try (existing ?? CDWorkoutLog(context: context)).update(from: log)
            return true

        case (.workoutLog, .deleted):
            guard try takesPrecedence(record, over: .workoutLog, recordId: record.recordId),
                  let uuid = UUID(uuidString: record.recordId),
                  let stored = try fetchLog(id: uuid) else { return false }
            context.delete(stored)
            return true

        case (.outsideActivity, .outsideActivity(let payload, _)):
            guard try takesPrecedence(record, over: .outsideActivity, recordId: record.recordId) else { return false }
            let activity = try SyncPayloadCoder.decode(OutsideActivity.self, from: payload)
            let existing = try fetchActivity(id: activity.id)
            if let current = try? existing?.toOutsideActivity(), current == activity { return false }
            (existing ?? CDOutsideActivity(context: context)).update(from: activity)
            return true

        case (.outsideActivity, .deleted):
            guard try takesPrecedence(record, over: .outsideActivity, recordId: record.recordId),
                  let uuid = UUID(uuidString: record.recordId),
                  let stored = try fetchActivity(id: uuid) else { return false }
            context.delete(stored)
            return true

        case (.customWorkout, .customWorkout(let payload)):
            guard try takesPrecedence(record, over: .customWorkout, recordId: record.recordId) else { return false }
            let workout = try SyncPayloadCoder.decode(CustomWorkout.self, from: payload)
            let existing = try fetchCustomWorkout(id: workout.id)
            if let current = try? existing?.toCustomWorkout(), current == workout { return false }
            try (existing ?? CDCustomWorkout(context: context)).update(from: workout)
            return true

        case (.customWorkout, .deleted):
            guard try takesPrecedence(record, over: .customWorkout, recordId: record.recordId),
                  let uuid = UUID(uuidString: record.recordId),
                  let stored = try fetchCustomWorkout(id: uuid) else { return false }
            context.delete(stored)
            return true

        default:
            Self.log.error("A pulled record's content did not match its type \(record.type.rawValue, privacy: .public)")
            return false
        }
    }

    /// The same newest-wins rule the account applies: a pulled record replaces the local one unless a
    /// local change is still waiting and is at least as new. When the pulled one wins, the waiting
    /// entry is dropped - the account already holds something newer than it.
    private func takesPrecedence(_ record: RemoteSyncRecord, over type: SyncRecordType, recordId: String) throws -> Bool {
        guard let waiting = try entry(type, recordId: recordId) else { return true }
        let localMilliseconds = (waiting.changedAt ?? .distantPast).syncMilliseconds
        guard record.clientUpdatedAt.syncMilliseconds > localMilliseconds else { return false }
        context.delete(waiting)
        return true
    }

    // MARK: - Fetching

    private func entry(_ type: SyncRecordType, recordId: String) throws -> CDSyncChange? {
        let request = CDSyncChange.fetchRequest()
        request.predicate = NSPredicate(format: "recordType == %@ AND recordId == %@", type.rawValue, recordId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchUser(id: String) throws -> CDUser? {
        let request = CDUser.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchLog(id: UUID) throws -> CDWorkoutLog? {
        let request = CDWorkoutLog.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchCustomWorkout(id: UUID) throws -> CDCustomWorkout? {
        let request = CDCustomWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchActivity(id: UUID) throws -> CDOutsideActivity? {
        let request = CDOutsideActivity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
