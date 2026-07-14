import Foundation
import HealthKit

/// The real HealthKit integration (US-N03): mirrors each completed session into Health as a workout, on
/// device only, and degrades gracefully whenever Health is unavailable or the user denies access.
///
/// Design:
/// - **Write-only.** FitSnack *shares* (writes) the workout and its active-energy sample and never reads
///   Health data, so only `NSHealthUpdateUsageDescription` is required and the authorization request asks
///   for share access alone (`read: []`).
/// - **Never gates the loop.** Every method is best-effort: no Health data available (e.g. iPad), a
///   denied authorization, or a write failure all return quietly, so a completed session is never blocked
///   (the completion recorder also wraps the call in `try?`).
/// - **Authorization is requested up front, not in the write path.** `requestAuthorization()` is called
///   once when the user enters the main app (`MainTabsView`), so the share prompt appears at a calm moment
///   rather than mid-loop, and `saveWorkoutLog` never itself issues a blocking authorization request
///   (which cannot be presented from a headless/background context). The write only proceeds when share
///   access is already granted - a non-blocking status read - and is a quiet no-op otherwise, so it stays
///   safe to `await` from the completion recorder.
/// - **Idempotent per session.** Each workout carries the completed log's id as its `HKMetadataKeyExternalUUID`;
///   before writing, an existing workout with that id short-circuits the write, so a resume, a relaunch,
///   or a re-save never duplicates the session in Health.
/// - **Energy from MET x duration.** Active energy is estimated by the pure, unit-tested
///   `HealthKitWorkoutSample` from the session's movements' MET values (resolved from the catalog) and the
///   user's body weight; this shell only performs the HealthKit ceremony.
final class HealthKitService: HealthKitServiceProtocol {

    private let healthStore: HKHealthStore
    private let exerciseService: any ExerciseServiceProtocol

    /// The types FitSnack writes: the workout itself plus its active-energy sample.
    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    init(exerciseService: any ExerciseServiceProtocol, healthStore: HKHealthStore = HKHealthStore()) {
        self.exerciseService = exerciseService
        self.healthStore = healthStore
    }

    func authorizationStatus() async throws -> HealthKitAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .sharingDenied }
        return Self.map(healthStore.authorizationStatus(for: HKObjectType.workoutType()))
    }

    func requestAuthorization() async throws -> HealthKitAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .sharingDenied }
        try await healthStore.requestAuthorization(toShare: shareTypes, read: [])
        return Self.map(healthStore.authorizationStatus(for: HKObjectType.workoutType()))
    }

    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Only write when share access is already granted. This is a non-blocking status read, never a
        // request (the request is issued up front from the UI): a denied or still-undetermined state means
        // we quietly skip the write, so the completion recorder can safely `await` this even from a
        // background/headless context and a user who never grants access is never blocked or hung.
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            return
        }

        // Idempotency: a workout already written for this session's log id means we're done (no duplicate
        // on a resume, relaunch, or re-save).
        if try await workoutExists(externalUUID: log.id.uuidString) { return }

        let metValues = try await metValuesByExerciseId(for: log)
        let sample = HealthKitWorkoutSample.from(log: log, user: user, metValuesByExerciseId: metValues)
        try await write(sample)
    }

    // MARK: - Helpers

    /// Resolve each logged exercise's MET value from the catalog so the energy estimate reflects the
    /// movements actually worked. A missing catalog or unknown id simply drops out of the map, and the
    /// pure builder falls back to a default MET when the map is empty.
    private func metValuesByExerciseId(for log: WorkoutLog) async throws -> [String: Double] {
        let ids = Set(log.exercises.map(\.exerciseId))
        guard !ids.isEmpty else { return [:] }
        let all = (try? await exerciseService.exercises()) ?? []
        return Dictionary(
            uniqueKeysWithValues: all.filter { ids.contains($0.id) }.map { ($0.id, $0.metValue) }
        )
    }

    /// Whether a workout carrying `externalUUID` (this session's log id) already exists in Health - the
    /// idempotency check that prevents duplicates.
    private func workoutExists(externalUUID: String) async throws -> Bool {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalUUID]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: !(samples ?? []).isEmpty)
                }
            }
            healthStore.execute(query)
        }
    }

    /// Build the `HKWorkout` from the pure sample and save it, attaching the external UUID for idempotency
    /// and an active-energy sample estimated from MET x duration.
    private func write(_ sample: HealthKitWorkoutSample) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: sample.activityKind)

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: sample.start)

        let energyType = HKQuantityType(.activeEnergyBurned)
        let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: sample.energyKilocalories)
        let energySample = HKQuantitySample(
            type: energyType,
            quantity: energyQuantity,
            start: sample.start,
            end: sample.end
        )
        // The active-energy sample is best-effort: the HealthKit prompt lets the user grant workout sharing
        // while independently denying energy sharing, in which case `add` throws. Swallow only that failure
        // so the workout itself still lands; the workout-type guard above already confirmed the write is
        // authorized. `add(_:)` has no auto-generated async variant (unlike beginCollection/endCollection/
        // finishWorkout), so bridge the completion handler.
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add([energySample]) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: sample.externalUUID])
        try await builder.endCollection(at: sample.end)
        _ = try await builder.finishWorkout()
    }

    private static func map(_ status: HKAuthorizationStatus) -> HealthKitAuthorizationStatus {
        switch status {
        case .sharingAuthorized: return .sharingAuthorized
        case .sharingDenied: return .sharingDenied
        default: return .notDetermined
        }
    }

    private static func activityType(
        for kind: HealthKitWorkoutSample.ActivityKind
    ) -> HKWorkoutActivityType {
        switch kind {
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .flexibility: return .flexibility
        }
    }
}
