import CoreData
import XCTest
@testable import RepToday

/// US-HO04 / US-HO02 persistence: the CloudKit-compatible `CDOutsideActivity` entity of model version 2,
/// its store, account deletion, and the lightweight migration of a store an earlier build wrote.
final class OutsideActivityPersistenceTests: XCTestCase {

    // MARK: The store

    func testTheCoreDataStoreLogsEditsQueriesAndDeletes() async throws {
        let persistence = MockPersistence.controller()
        let service = CoreDataOutsideActivityService(context: persistence.viewContext)
        let run = OutsideActivity(type: .run, date: TrainingDayFixtures.date(daysAgo: 1), durationMinutes: 30, distanceMeters: 4828)
        let swim = OutsideActivity(type: .swim, date: TrainingDayFixtures.date(daysAgo: 3), durationMinutes: 45, healthWorkoutId: UUID())

        try await service.save(run)
        try await service.save(swim)
        let all = try await service.activities(from: nil, to: nil)
        XCTAssertEqual(all, [swim, run], "oldest first, every field kept")

        var edited = run
        edited.type = .hike
        edited.durationMinutes = 90
        edited.distanceMeters = nil
        try await service.save(edited)
        let afterEdit = try await service.activities(from: nil, to: nil)
        XCTAssertEqual(afterEdit, [swim, edited], "an edit replaces in place by id")

        let ranged = try await service.activities(from: TrainingDayFixtures.date(daysAgo: 2), to: nil)
        XCTAssertEqual(ranged, [edited])

        try await service.delete(id: swim.id)
        let afterDelete = try await service.activities(from: nil, to: nil)
        XCTAssertEqual(afterDelete, [edited])

        try await service.deleteAll()
        let empty = try await service.activities(from: nil, to: nil)
        XCTAssertTrue(empty.isEmpty)
        try await service.deleteAll()
    }

    func testTheEntityIsCloudKitCompatible() throws {
        let model = try XCTUnwrap(PersistenceController.modelVersion(named: "RepToday 2"))
        let entity = try XCTUnwrap(model.entitiesByName["CDOutsideActivity"])
        XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "CloudKit forbids unique constraints")
        for attribute in entity.attributesByName.values {
            XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name) must be optional or defaulted")
        }
        let cloud = try XCTUnwrap(model.entities(forConfigurationName: "Cloud"))
        XCTAssertTrue(cloud.contains { $0.name == "CDOutsideActivity" }, "it syncs with the logs until M3")
    }

    func testAccountDeletionDeletesEveryActivity() async throws {
        let activities = InMemoryOutsideActivityService(activities: [
            OutsideActivity(type: .row, date: TrainingDayFixtures.date(daysAgo: 1)),
        ])
        let suiteName = "OutsideActivityPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = await MainActor.run { () -> AppState in
            let state = AppState(userDefaults: defaults)
            state.isOnboarded = true
            state.healthWorkoutSuggestionsEnabled = true
            state.dismissHealthWorkout(UUID())
            return state
        }
        let deletion = AccountDeletionService(
            userService: MockUserService(user: MockPersistence.sampleUser),
            workoutLogService: MockWorkoutLogService(),
            sessionPolicyStore: InMemorySessionPolicyStore(),
            activeSessionStore: InMemoryActiveSessionStore(),
            authService: MockAuthService(),
            outsideActivityService: activities
        )
        try await deletion.deleteAccount(appState: appState)
        let remaining = try await activities.activities(from: nil, to: nil)
        XCTAssertTrue(remaining.isEmpty)
        await MainActor.run {
            XCTAssertFalse(appState.healthWorkoutSuggestionsEnabled)
            XCTAssertTrue(appState.dismissedHealthWorkoutIds.isEmpty)
        }
    }

    // MARK: Migration

    /// A store written by model version 1 - the build before M2 - opens through lightweight migration in
    /// the production Cloud + Local layout and keeps its user, its log and its paused session; the user's
    /// profile, stored with the old goal field, decodes with no Focus Areas; and the new entity is ready.
    func testAStoreFromTheEarlierModelVersionMigratesAndKeepsItsData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("m2-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let v1 = try XCTUnwrap(PersistenceController.modelVersion(named: "RepToday"))
        XCTAssertNil(v1.entitiesByName["CDOutsideActivity"])

        let log = TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 1))
        let library = try await MockExerciseService().exercises()
        let workout = SessionAssembly.assemble(
            requestedMinutes: 15,
            user: TrainingDayFixtures.user(),
            library: library,
            recentLogs: [],
            trainingDay: .push,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        let session = ActiveSessionState(fresh: workout)
        try writeVersionOneStore(in: directory, model: v1, log: log, session: session)

        let migrated = PersistenceController(localOnlyStoresIn: directory)
        let context = migrated.viewContext

        let user = try await CoreDataUserService(context: context).currentUser()
        XCTAssertEqual(user?.id, "legacy-user")
        XCTAssertEqual(user?.displayName, "Sam")
        XCTAssertEqual(user?.profile.focusAreas, [])
        XCTAssertEqual(user?.profile.injuries, ["knees"])

        let logs = try await CoreDataWorkoutLogService(context: context).workoutLogs(from: nil, to: nil)
        XCTAssertEqual(logs, [log])

        let resumed = try await CoreDataActiveSessionStore(context: context).load(for: "legacy-user")
        XCTAssertEqual(resumed?.workout.id, session.workout.id)

        let activities = CoreDataOutsideActivityService(context: context)
        let run = OutsideActivity(type: .run, date: TrainingDayFixtures.date(daysAgo: 0))
        try await activities.save(run)
        let stored = try await activities.activities(from: nil, to: nil)
        XCTAssertEqual(stored, [run])

        // A Focus Area written now survives a reopen of the migrated store.
        var withFocus = try XCTUnwrap(user)
        withFocus.profile.focusAreas = [.abs, .back]
        try await CoreDataUserService(context: context).save(withFocus)
        let reopened = PersistenceController(localOnlyStoresIn: directory)
        let reread = try await CoreDataUserService(context: reopened.viewContext).currentUser()
        XCTAssertEqual(reread?.profile.focusAreas, [.back, .abs])
    }

    /// Writes the two stores the way a version-1 build did: the Cloud store (user, log) with persistent
    /// history on, and the Local store (paused session).
    private func writeVersionOneStore(in directory: URL, model: NSManagedObjectModel, log: WorkoutLog, session: ActiveSessionState) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let cloudURL = directory.appendingPathComponent("RepToday.sqlite")
        let localURL = directory.appendingPathComponent("RepToday-Local.sqlite")
        let cloud = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: "Cloud",
            at: cloudURL,
            options: [NSPersistentHistoryTrackingKey: true as NSNumber]
        )
        let local = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: "Local", at: localURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let legacyProfile = """
        {"age":40,"sex":"male","heightCm":180,"weightKg":80,"fitnessLevel":"beginner",
         "primaryGoal":"stay_active","sitsLong":false,"injuries":["knees"],"typicalAvailableMinutes":20}
        """
        let base = MockPersistence.sampleUser
        let user = NSManagedObject(entity: try XCTUnwrap(model.entitiesByName["CDUser"]), insertInto: context)
        user.setValue("legacy-user", forKey: "id")
        user.setValue("Sam", forKey: "displayName")
        user.setValue(base.createdAt, forKey: "createdAt")
        user.setValue(base.phase.rawValue, forKey: "phaseRaw")
        user.setValue(Data(legacyProfile.utf8), forKey: "profileData")
        user.setValue(try PersistenceCoder.encoder.encode(base.subscription), forKey: "subscriptionData")
        user.setValue(try PersistenceCoder.encoder.encode(base.consistency), forKey: "consistencyData")
        context.assign(user, to: cloud)

        let record = NSManagedObject(entity: try XCTUnwrap(model.entitiesByName["CDWorkoutLog"]), insertInto: context)
        record.setValue(log.id, forKey: "id")
        record.setValue(log.workoutId, forKey: "workoutId")
        record.setValue(log.completedAt, forKey: "completedAt")
        record.setValue(log.durationMinutes, forKey: "durationMinutes")
        record.setValue(log.requestedMinutes, forKey: "requestedMinutes")
        record.setValue(log.wasReturn, forKey: "wasReturn")
        record.setValue(log.shape.rawValue, forKey: "shapeRaw")
        record.setValue(log.focusPillar?.rawValue, forKey: "focusPillarRaw")
        record.setValue(log.perceivedDifficulty?.rawValue, forKey: "perceivedDifficultyRaw")
        record.setValue(try PersistenceCoder.encoder.encode(log.exercises), forKey: "exercisesData")
        context.assign(record, to: cloud)

        let paused = NSManagedObject(entity: try XCTUnwrap(model.entitiesByName["CDActiveSession"]), insertInto: context)
        paused.setValue("legacy-user", forKey: "userId")
        paused.setValue(try PersistenceCoder.encoder.encode(session), forKey: "stateData")
        context.assign(paused, to: local)

        try context.save()
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
