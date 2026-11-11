import CoreData
import Foundation

/// CoreData mirror of `OutsideActivity` (US-HO04), new in model version 2.
///
/// It lives in the on-device `Local` configuration and never syncs to iCloud: an activity added from Apple
/// Health carries Health data, which may not be stored in iCloud, so no activity syncs until M3 moves
/// sync to Convex. It stays CloudKit-compatible all the same (every attribute optional or defaulted, no
/// unique constraint), so identity is the `id` attribute and the service upserts by it. `toOutsideActivity()` re-imposes the
/// domain's required fields. `date` is a native `Date` so activities are fetched by date range.
@objc(CDOutsideActivity)
final class CDOutsideActivity: NSManagedObject {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDOutsideActivity> {
        NSFetchRequest<CDOutsideActivity>(entityName: "CDOutsideActivity")
    }

    @NSManaged var id: UUID?
    @NSManaged var typeRaw: String?
    @NSManaged var date: Date?
    @NSManaged var durationMinutes: Int
    @NSManaged var distanceMeters: NSNumber?
    @NSManaged var healthWorkoutId: UUID?
}

// MARK: - Domain conversion

extension CDOutsideActivity {
    /// Reconstructs the domain `OutsideActivity`, throwing `PersistenceError` for a missing required
    /// field or an unknown type.
    func toOutsideActivity() throws -> OutsideActivity {
        guard let id else { throw PersistenceError.missingField("CDOutsideActivity.id") }
        guard let date else { throw PersistenceError.missingField("CDOutsideActivity.date") }
        guard let typeRaw else { throw PersistenceError.missingField("CDOutsideActivity.typeRaw") }
        guard let type = OutsideActivityType(rawValue: typeRaw) else {
            throw PersistenceError.invalidEnum(field: "CDOutsideActivity.typeRaw", value: typeRaw)
        }
        return OutsideActivity(
            id: id,
            type: type,
            date: date,
            durationMinutes: durationMinutes,
            distanceMeters: distanceMeters?.doubleValue,
            healthWorkoutId: healthWorkoutId
        )
    }

    /// Overwrites every attribute from `activity` (insert or update).
    func update(from activity: OutsideActivity) {
        id = activity.id
        typeRaw = activity.type.rawValue
        date = activity.date
        durationMinutes = activity.durationMinutes
        distanceMeters = activity.distanceMeters.map { NSNumber(value: $0) }
        healthWorkoutId = activity.healthWorkoutId
    }
}
