import CoreData
import Foundation

/// Where accepted Custom Workouts live on the device (M4, US-CA05).
///
/// Only an accepted workout is ever saved here: a proposal stays in the Coach conversation until the
/// user accepts it, which is what makes "nothing plays until it is accepted" (FR-11) a property of the
/// store rather than of a screen.
protocol CustomWorkoutServiceProtocol: Sendable {
    /// Every accepted workout, newest first.
    func workouts() async throws -> [CustomWorkout]
    func workout(id: UUID) async throws -> CustomWorkout?
    /// Saves an accepted workout (inserting or updating by `id`) and queues it to sync. Refuses one the
    /// user has not accepted.
    func save(_ workout: CustomWorkout) async throws
    /// Records one play to the end.
    func markPlayed(id: UUID, at date: Date) async throws
    func delete(id: UUID) async throws
    /// Removes every workout without queueing anything (account deletion).
    func deleteAll() async throws
}

enum CustomWorkoutServiceError: Error, Equatable {
    /// Only an accepted Custom Workout can be saved or played (FR-11).
    case notAccepted
}

/// The CoreData-backed store, in the Local configuration, writing the sync outbox in the same save.
final class CoreDataCustomWorkoutService: CustomWorkoutServiceProtocol, @unchecked Sendable {
    // Safe: every access to the context happens inside `context.perform`.
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func workouts() async throws -> [CustomWorkout] {
        try await context.perform {
            let request = CDCustomWorkout.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "acceptedAt", ascending: false)]
            return try self.context.fetch(request).compactMap { try? $0.toCustomWorkout() }
        }
    }

    func workout(id: UUID) async throws -> CustomWorkout? {
        try await context.perform {
            try self.record(id: id)?.toCustomWorkout()
        }
    }

    func save(_ workout: CustomWorkout) async throws {
        guard workout.isAccepted else { throw CustomWorkoutServiceError.notAccepted }
        try await context.perform {
            let record = try self.record(id: workout.id) ?? CDCustomWorkout(context: self.context)
            try record.update(from: workout)
            try CDSyncChange.markChanged(.customWorkout, recordId: workout.id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func markPlayed(id: UUID, at date: Date) async throws {
        try await context.perform {
            guard let record = try self.record(id: id) else { return }
            var workout = try record.toCustomWorkout()
            workout.playedAt.append(date)
            try record.update(from: workout)
            try CDSyncChange.markChanged(.customWorkout, recordId: id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func delete(id: UUID) async throws {
        try await context.perform {
            if let record = try self.record(id: id) {
                self.context.delete(record)
            }
            try CDSyncChange.markChanged(.customWorkout, recordId: id.uuidString, in: self.context)
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    func deleteAll() async throws {
        try await context.perform {
            for record in try self.context.fetch(CDCustomWorkout.fetchRequest()) {
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }

    private func record(id: UUID) throws -> CDCustomWorkout? {
        let request = CDCustomWorkout.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

/// An in-memory store for previews and tests.
actor InMemoryCustomWorkoutService: CustomWorkoutServiceProtocol {
    private var stored: [UUID: CustomWorkout] = [:]

    init(workouts: [CustomWorkout] = []) {
        stored = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func workouts() async throws -> [CustomWorkout] {
        stored.values.sorted { ($0.acceptedAt ?? .distantPast) > ($1.acceptedAt ?? .distantPast) }
    }

    func workout(id: UUID) async throws -> CustomWorkout? { stored[id] }

    func save(_ workout: CustomWorkout) async throws {
        guard workout.isAccepted else { throw CustomWorkoutServiceError.notAccepted }
        stored[workout.id] = workout
    }

    func markPlayed(id: UUID, at date: Date) async throws {
        stored[id]?.playedAt.append(date)
    }

    func delete(id: UUID) async throws { stored[id] = nil }

    func deleteAll() async throws { stored = [:] }
}
