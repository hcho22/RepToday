import CoreData
import Foundation

/// CoreData mirror of an accepted `CustomWorkout` (M4, US-CA05), new in model version 4.
///
/// It lives in the on-device `Local` configuration, never in iCloud, and syncs to the account through
/// the outbox like every other record (M3). The whole workout is kept as its JSON (`workoutData`), so a
/// step shape a later build adds never needs another model version; `id` and `acceptedAt` are
/// attributes so the store can find and order it.
@objc(CDCustomWorkout)
final class CDCustomWorkout: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCustomWorkout> {
        NSFetchRequest<CDCustomWorkout>(entityName: "CDCustomWorkout")
    }

    @NSManaged var id: UUID?
    @NSManaged var acceptedAt: Date?
    @NSManaged var workoutData: Data?
}

extension CDCustomWorkout {
    func toCustomWorkout() throws -> CustomWorkout {
        guard let workoutData else { throw PersistenceError.missingField("CDCustomWorkout.workoutData") }
        return try SyncPayloadCoder.decode(CustomWorkout.self, from: String(decoding: workoutData, as: UTF8.self))
    }

    func update(from workout: CustomWorkout) throws {
        id = workout.id
        acceptedAt = workout.acceptedAt
        workoutData = Data(try SyncPayloadCoder.encode(workout).utf8)
    }
}
