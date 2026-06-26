import CoreData
import Foundation

/// CoreData mirror of `WorkoutLog` (US-A04).
///
/// Identity, timing, and the fields the engine queries (`completedAt`, `shapeRaw`,
/// `focusPillarRaw`) are native attributes; the per-exercise outcomes (`exercises`) are
/// stored as JSON-encoded `Data`. `completedAt` is a native `Date` precisely so logs can
/// be fetched by date range (staleness windows, the Progress calendar) without decoding
/// every record. As with `CDUser`, attributes are optional for CloudKit (US-J02) and
/// `toWorkoutLog()` re-imposes the non-optional domain contract.
@objc(CDWorkoutLog)
final class CDWorkoutLog: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDWorkoutLog> {
        NSFetchRequest<CDWorkoutLog>(entityName: "CDWorkoutLog")
    }

    @NSManaged var id: UUID?
    @NSManaged var workoutId: UUID?
    @NSManaged var completedAt: Date?
    @NSManaged var durationMinutes: Int
    @NSManaged var shapeRaw: String?
    @NSManaged var focusPillarRaw: String?
    @NSManaged var perceivedDifficultyRaw: String?
    @NSManaged var exercisesData: Data?
}

// MARK: - Domain conversion

extension CDWorkoutLog {
    /// Reconstructs the domain `WorkoutLog`, throwing `PersistenceError` for a missing
    /// required field or an unknown enum raw value, and rethrowing any JSON decode failure.
    func toWorkoutLog() throws -> WorkoutLog {
        guard let id else { throw PersistenceError.missingField("CDWorkoutLog.id") }
        guard let workoutId else { throw PersistenceError.missingField("CDWorkoutLog.workoutId") }
        guard let completedAt else { throw PersistenceError.missingField("CDWorkoutLog.completedAt") }
        guard let shapeRaw else { throw PersistenceError.missingField("CDWorkoutLog.shapeRaw") }
        guard let shape = SessionShape(rawValue: shapeRaw) else {
            throw PersistenceError.invalidEnum(field: "CDWorkoutLog.shapeRaw", value: shapeRaw)
        }
        guard let exercisesData else { throw PersistenceError.missingField("CDWorkoutLog.exercisesData") }

        // Optional enums: nil stays nil, but a present-yet-unknown raw value is an error.
        let focusPillar = try focusPillarRaw.map { raw -> Pillar in
            guard let pillar = Pillar(rawValue: raw) else {
                throw PersistenceError.invalidEnum(field: "CDWorkoutLog.focusPillarRaw", value: raw)
            }
            return pillar
        }
        let perceivedDifficulty = try perceivedDifficultyRaw.map { raw -> PerceivedDifficulty in
            guard let difficulty = PerceivedDifficulty(rawValue: raw) else {
                throw PersistenceError.invalidEnum(field: "CDWorkoutLog.perceivedDifficultyRaw", value: raw)
            }
            return difficulty
        }

        return WorkoutLog(
            id: id,
            workoutId: workoutId,
            completedAt: completedAt,
            durationMinutes: durationMinutes,
            shape: shape,
            focusPillar: focusPillar,
            perceivedDifficulty: perceivedDifficulty,
            exercises: try PersistenceCoder.decoder.decode([LoggedExercise].self, from: exercisesData)
        )
    }

    /// Overwrites every attribute from `log` (insert or update).
    func update(from log: WorkoutLog) throws {
        id = log.id
        workoutId = log.workoutId
        completedAt = log.completedAt
        durationMinutes = log.durationMinutes
        shapeRaw = log.shape.rawValue
        focusPillarRaw = log.focusPillar?.rawValue
        perceivedDifficultyRaw = log.perceivedDifficulty?.rawValue
        exercisesData = try PersistenceCoder.encoder.encode(log.exercises)
    }
}

// MARK: - Queries

extension CDWorkoutLog {
    /// Logs whose `completedAt` falls in the half-open interval `[start, end)`, oldest
    /// first. This is the query the engine's staleness windows and the Progress calendar
    /// build on, so it lives with the entity rather than in a service.
    static func fetchRequest(from start: Date, to end: Date) -> NSFetchRequest<CDWorkoutLog> {
        let request = NSFetchRequest<CDWorkoutLog>(entityName: "CDWorkoutLog")
        request.predicate = NSPredicate(
            format: "completedAt >= %@ AND completedAt < %@",
            start as NSDate, end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: true)]
        return request
    }
}
