import Foundation

/// A pure, HealthKit-free description of the workout FitSnack writes to Health for one completed
/// session (US-N03).
///
/// Keeping the whole mapping - the session's start/end instants, the active-energy estimate, the
/// activity category, and the idempotency key - in a value type lets it be unit-tested without a live
/// `HKHealthStore` (which needs the HealthKit entitlement and, ideally, a device). The thin
/// `HealthKitService` shell only translates this into an `HKWorkout` and performs the HealthKit ceremony.
struct HealthKitWorkoutSample: Equatable {

    /// The high-level Health activity category. Mapped to `HKWorkoutActivityType` in the service so this
    /// value type stays HealthKit-free.
    enum ActivityKind: Equatable {
        case functionalStrengthTraining
        case flexibility
    }

    /// When the session started, derived as `completedAt - durationMinutes`.
    let start: Date
    /// When the session finished (`log.completedAt`).
    let end: Date
    let activityKind: ActivityKind
    /// Estimated active energy burned, in kilocalories. Always positive.
    let energyKilocalories: Double
    /// The completed session's stable log id, written as the workout's external UUID so a re-write of
    /// the same session is de-duplicated (idempotency, US-N03).
    let externalUUID: String

    /// Fallback MET for a session whose movements can't be resolved to catalog MET values - moderate
    /// bodyweight calisthenics.
    static let defaultMetValue = 4.0

    /// A defensive body-weight fallback (kg) so energy is never zeroed by a missing/absent weight.
    static let defaultWeightKg = 70.0

    /// Build the sample from a completed `log`, the `user` (for body weight), and the resolved MET value
    /// per exercise id (from the catalog). Pure and deterministic.
    ///
    /// Energy uses the standard MET approximation `kcal = MET x weightKg x hours`, where MET is the mean
    /// of the session's *actually-worked* movements - non-skipped, with at least one recorded set - so a
    /// movement the user passed on never inflates the estimate, falling back to `defaultMetValue` when
    /// none resolve. Duration is the actually-completed `durationMinutes` (floored at 1), matching what
    /// the Consistency Score and Default Duration learning read.
    static func from(
        log: WorkoutLog,
        user: User,
        metValuesByExerciseId: [String: Double]
    ) -> HealthKitWorkoutSample {
        let end = log.completedAt
        let minutes = max(1, log.durationMinutes)
        let start = end.addingTimeInterval(-Double(minutes) * 60)

        let workedMets: [Double] = log.exercises
            .filter { !$0.skipped && !$0.completedSets.isEmpty }
            .compactMap { metValuesByExerciseId[$0.exerciseId] }
        let met = workedMets.isEmpty
            ? defaultMetValue
            : workedMets.reduce(0, +) / Double(workedMets.count)

        let hours = Double(minutes) / 60.0
        let weightKg = user.profile.weightKg > 0 ? user.profile.weightKg : defaultWeightKg
        let energy = max(1, met * weightKg * hours)

        // A mobility-focused session reads as flexibility in Health; everything else (blend, strength,
        // primal) is functional strength training.
        let kind: ActivityKind = log.focusPillar == .mobility ? .flexibility : .functionalStrengthTraining

        return HealthKitWorkoutSample(
            start: start,
            end: end,
            activityKind: kind,
            energyKilocalories: energy,
            externalUUID: log.id.uuidString
        )
    }
}
