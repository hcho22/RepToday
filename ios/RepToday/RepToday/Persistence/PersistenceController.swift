import CoreData

/// The app's CoreData stack (US-A04): the on-device store the app runs on, local-first.
///
/// In production the store is split into two persistent stores in one container:
///
/// - the **Cloud** store (the `Cloud` model configuration - `CDUser`, `CDWorkoutLog`,
///   `CDSessionPolicy`), named for the iCloud mirror it had before accounts; and
/// - the **Local** store (the `Local` configuration - `CDActiveSession`, `CDOutsideActivity`, and
///   since model version 3 the sync outbox `CDSyncChange`), which never mirrors to iCloud: an
///   in-progress session is device-bound, an Outside Activity may carry Apple Health data, and the
///   outbox is this device's own pending work.
///
/// Since accounts (M3, ADR-0016) the user's data syncs to their Rep Today account through the sync
/// outbox (`CoreDataSyncStore`, `SyncEngine`), not through iCloud. The container is still an
/// `NSPersistentCloudKitContainer` for one reason: a user who onboarded before accounts may have
/// history that is only in their private iCloud database, so until their one-time migration has
/// queued everything (`LegacyAccountMigrationStage.mirrorsICloud`) the Cloud store keeps its iCloud
/// mirror on, and `legacyICloudImport` reports when its import has settled. Every other launch -
/// every new user, and a migrated one - opens both stores with no iCloud mirror at all. The iCloud
/// copy is never deleted by the migration; turning the mirror off leaves it as it was.
///
/// The mirror is strictly additive: if CloudKit cannot be set up - no iCloud account, offline, or an
/// unsigned build with no iCloud entitlement (e.g. the Simulator) - the Cloud store is retried
/// **local-only** so the core loop always works. Nothing about generating and completing a
/// session depends on the network or an account.
///
/// Tests and previews use the in-memory path (`inMemory: true`), which loads every entity into
/// a single `/dev/null` store with no CloudKit, so they stay isolated, disk-free, and
/// deterministic.
final class PersistenceController {

    /// The app-wide on-disk stack. Lazily created on first access, so tests that use the
    /// in-memory `MockPersistence` never touch the device store.
    static let shared = PersistenceController()

    /// The CloudKit container the Cloud store mirrors into (the user's private database).
    /// Conventionally `iCloud.<bundle id>`; must match the app's iCloud entitlement.
    static let cloudKitContainerIdentifier = "iCloud.com.reptoday.app"

    /// The managed object model, loaded exactly once. Creating multiple containers (e.g.
    /// one per test) that each load the model separately triggers CoreData's "multiple
    /// NSEntityDescriptions claim the NSManagedObject subclass" warnings, so every
    /// container shares this single instance.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: PersistenceController.self).url(forResource: "RepToday", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to locate the RepToday CoreData model in the app bundle")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer

    /// Reports when the iCloud mirror's import has settled, for a migrating user (US-AU04). Settled
    /// as `.nothingToImport` whenever the mirror is not running.
    let legacyICloudImport: LegacyICloudImportMonitor

    /// The main-queue context views and view models read from.
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: when `true`, every entity is loaded into a single ephemeral `/dev/null` store
    ///     with no CloudKit - the isolated, disk-free stack tests and previews use. When `false`, the
    ///     production Cloud + Local split described above is loaded.
    ///   - defaults: where the migration stage is read from, deciding whether the iCloud mirror runs.
    init(inMemory: Bool = false, defaults: UserDefaults = .standard) {
        container = NSPersistentCloudKitContainer(name: "RepToday", managedObjectModel: Self.managedObjectModel)

        // A unit-test host app never mirrors: it shares the app's container and must not reach a
        // developer's iCloud.
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let mirrorsICloud = !inMemory && !isTestHost
            && (LegacyAccountMigrationStage.resolved(in: defaults)?.mirrorsICloud ?? false)
        legacyICloudImport = mirrorsICloud
            ? LegacyICloudImportMonitor(container: container, containerIdentifier: Self.cloudKitContainerIdentifier)
            : LegacyICloudImportMonitor(settled: .nothingToImport)
        if inMemory {
            Self.configureInMemoryStore(container)
        } else {
            Self.configureCloudAndLocalStores(container, in: NSPersistentContainer.defaultDirectoryURL(), mirrorsToCloudKit: mirrorsICloud)
        }
        Self.load(container, onMirrorUnavailable: legacyICloudImport.markNotMirroring)
    }

    /// The production Cloud + Local split on disk in `directory`, with no CloudKit mirroring - the
    /// exact store files and options the app opens, so a test can prove a store written by an earlier
    /// model version opens through lightweight migration and keeps its data.
    init(localOnlyStoresIn directory: URL) {
        container = NSPersistentCloudKitContainer(name: "RepToday", managedObjectModel: Self.managedObjectModel)
        legacyICloudImport = LegacyICloudImportMonitor(settled: .nothingToImport)
        Self.configureCloudAndLocalStores(container, in: directory, mirrorsToCloudKit: false)
        Self.load(container)
    }

    /// The compiled model version named `versionName` (e.g. `"RepToday"` for version 1), for migration
    /// tests that write a store the way an earlier build did.
    static func modelVersion(named versionName: String) -> NSManagedObjectModel? {
        Bundle(for: PersistenceController.self)
            .url(forResource: "RepToday", withExtension: "momd")
            .flatMap { NSManagedObjectModel(contentsOf: $0.appendingPathComponent("\(versionName).mom")) }
    }

    private static func load(_ container: NSPersistentCloudKitContainer, onMirrorUnavailable: @escaping () -> Void = {}) {
        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { description, error in
            guard let error = error as NSError? else { return }
            // A CloudKit setup failure (no iCloud account, offline, or an unsigned build with no
            // iCloud entitlement) must never break the core loop: retry this store local-only so
            // the app still opens and every session is generated and recorded on-device. Sync is
            // additive - it resumes on its own once an account and connectivity are available.
            if description.cloudKitContainerOptions != nil {
                description.cloudKitContainerOptions = nil
                onMirrorUnavailable()
                do {
                    try coordinator.addPersistentStore(
                        ofType: description.type,
                        configurationName: description.configuration,
                        at: description.url,
                        options: description.options
                    )
                } catch {
                    fatalError("Failed to load the RepToday store even local-only: \(error)")
                }
            } else {
                // The Local store holds the device-bound active-session snapshot and the logged
                // Outside Activities. A load failure here (a corrupt or half-written sqlite from an
                // interrupted write or a full disk) must never brick the otherwise-offline-capable
                // core loop, so recover the standard CoreData way: destroy the store file and
                // re-add a fresh, empty one. Losing an in-progress session and the logged activities
                // is acceptable; crashing the whole app over it is not.
                if description.configuration == "Local", let url = description.url {
                    do {
                        try coordinator.destroyPersistentStore(at: url, ofType: description.type, options: description.options)
                        try coordinator.addPersistentStore(
                            ofType: description.type,
                            configurationName: description.configuration,
                            at: url,
                            options: description.options
                        )
                        return
                    } catch {
                        // The recreate also failed - now it is a genuine defect, not a runtime condition.
                        fatalError("Failed to load or recreate the RepToday local store: \(error)")
                    }
                }
                // No URL to recover (e.g. the in-memory /dev/null store) is a genuine defect.
                fatalError("Failed to load the RepToday persistent store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// A single ephemeral store holding every entity (the model's default configuration), no
    /// CloudKit - the test/preview stack.
    private static func configureInMemoryStore(_ container: NSPersistentCloudKitContainer) {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("RepToday persistent container has no store description")
        }
        description.url = URL(fileURLWithPath: "/dev/null")
        description.cloudKitContainerOptions = nil
    }

    /// The production split: the `Cloud` configuration, mirrored to CloudKit only when
    /// `mirrorsToCloudKit` (a migrating user's pending import); the `Local` configuration
    /// (`CDActiveSession`, `CDOutsideActivity`, `CDSyncChange`) never. Both stores migrate lightweight
    /// across model versions (the description defaults: migrate automatically, infer the mapping),
    /// which is why every model change must stay additive.
    private static func configureCloudAndLocalStores(
        _ container: NSPersistentCloudKitContainer,
        in baseURL: URL,
        mirrorsToCloudKit: Bool
    ) {

        let cloud = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("RepToday.sqlite"))
        cloud.configuration = "Cloud"
        // Persistent history + remote-change notifications are prerequisites for CloudKit mirroring.
        // History stays on even with no mirror: a store that once tracked history opens read-only
        // without it, and every pre-account install's Cloud store did.
        cloud.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloud.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        cloud.cloudKitContainerOptions = mirrorsToCloudKit
            ? NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            : nil

        let local = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("RepToday-Local.sqlite"))
        local.configuration = "Local"
        local.cloudKitContainerOptions = nil

        container.persistentStoreDescriptions = [cloud, local]
    }
}
