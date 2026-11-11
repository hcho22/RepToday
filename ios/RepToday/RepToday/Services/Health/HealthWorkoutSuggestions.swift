import Foundation

// MARK: - HealthWorkoutCandidate

/// A workout recorded in Apple Health, HealthKit-free, as Rep Today reads it for suggestions (US-HO05).
struct HealthWorkoutCandidate: Equatable, Identifiable, Hashable {
    /// The Health workout's own identifier, which an added Outside Activity keeps
    /// (`OutsideActivity.healthWorkoutId`) so the workout is never suggested again.
    let id: UUID
    let type: OutsideActivityType
    let start: Date
    let durationMinutes: Int
    let distanceMeters: Double?
    /// The bundle identifier of the app that wrote it to Health.
    let sourceBundleIdentifier: String
    /// The workout's `HKMetadataKeyExternalUUID`, if any. Rep Today writes each completed session with
    /// its log id there (`HealthKitService`).
    let externalUUID: String?

    /// The Outside Activity "Add it" logs for this workout.
    var outsideActivity: OutsideActivity {
        OutsideActivity(
            type: type,
            date: start,
            durationMinutes: max(1, durationMinutes),
            distanceMeters: type.hasDistance ? distanceMeters : nil,
            healthWorkoutId: id
        )
    }
}

// MARK: - HealthWorkoutSuggestions

/// Which Apple Health workouts Today suggests (US-HO05, decision 22). Pure, so the rules are tested
/// without a Health store:
///
/// - **Never Rep Today's own.** A workout written by this app - by its bundle identifier, or carrying
///   one of its session log ids as its external UUID - is a session already counted, so it is never
///   suggested back.
/// - **Never twice.** A workout already added as an Outside Activity, or answered "Ignore", is gone for
///   good.
/// - **Recent only.** Only workouts that started in the last `lookbackDays` days and not in the future,
///   newest first, at most `limit` - older ones no longer shape the plan.
///
/// Nothing here applies anything: a suggestion becomes an Outside Activity only when the user taps
/// "Add it".
enum HealthWorkoutSuggestions {

    /// How far back a workout is still suggested: a week, the span the Consistency Score counts a
    /// show-up in.
    static let lookbackDays = 7

    /// The most suggestions Today shows at once.
    static let limit = 3

    /// The start of the window Health is read from, for a read at `now`.
    static func windowStart(asOf now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
    }

    static func pending(
        candidates: [HealthWorkoutCandidate],
        ownBundleIdentifier: String?,
        ownSessionIds: Set<UUID>,
        logged: [OutsideActivity],
        dismissed: Set<UUID>,
        asOf now: Date,
        calendar: Calendar = .current
    ) -> [HealthWorkoutCandidate] {
        let start = windowStart(asOf: now, calendar: calendar)
        let added = Set(logged.compactMap(\.healthWorkoutId))
        let ownExternal = Set(ownSessionIds.map(\.uuidString))
        let eligible = candidates.filter { (candidate: HealthWorkoutCandidate) -> Bool in
            if isWrittenByRepToday(candidate, ownBundleIdentifier: ownBundleIdentifier, ownExternalIds: ownExternal) {
                return false
            }
            if added.contains(candidate.id) || dismissed.contains(candidate.id) { return false }
            return candidate.start >= start && candidate.start <= now
        }
        let newestFirst = eligible.sorted { (lhs: HealthWorkoutCandidate, rhs: HealthWorkoutCandidate) -> Bool in
            lhs.start != rhs.start ? lhs.start > rhs.start : lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(newestFirst.prefix(limit))
    }

    /// Whether Rep Today wrote this workout: its source is this app (or a build of it under the same
    /// bundle family), or it carries one of this user's session log ids as its external UUID.
    static func isWrittenByRepToday(
        _ candidate: HealthWorkoutCandidate,
        ownBundleIdentifier: String?,
        ownExternalIds: Set<String>
    ) -> Bool {
        if let own = ownBundleIdentifier, !own.isEmpty,
           candidate.sourceBundleIdentifier == own || candidate.sourceBundleIdentifier.hasPrefix(own + ".") {
            return true
        }
        if let external = candidate.externalUUID, ownExternalIds.contains(external) {
            return true
        }
        return false
    }
}
