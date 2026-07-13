import CoreData

/// The app's CoreData stack (US-A04, CloudKit-enabled in US-N02).
///
/// Backed by `NSPersistentCloudKitContainer`. In production the store is split into two
/// persistent stores in one container:
///
/// - a **Cloud** store (the `Cloud` model configuration - `CDUser`, `CDWorkoutLog`,
///   `CDSessionPolicy`) that mirrors to the user's private CloudKit database, so their
///   identity, history, and in-force policy sync and back up across devices; and
/// - a **Local** store (the `Local` configuration - `CDActiveSession`) that never leaves the
///   device, because an in-progress session is transient, device-bound state (it holds
///   absolute wall-clock instants tied to this device's run) that has no meaning on another.
///
/// Sync is strictly additive: if CloudKit cannot be set up - no iCloud account, offline, or an
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
    static let cloudKitContainerIdentifier = "iCloud.com.fitsnack.app"

    /// The managed object model, loaded exactly once. Creating multiple containers (e.g.
    /// one per test) that each load the model separately triggers CoreData's "multiple
    /// NSEntityDescriptions claim the NSManagedObject subclass" warnings, so every
    /// container shares this single instance.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: PersistenceController.self).url(forResource: "FitSnack", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to locate the FitSnack CoreData model in the app bundle")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer

    /// The main-queue context views and view models read from.
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameter inMemory: when `true`, every entity is loaded into a single ephemeral
    ///   `/dev/null` store with no CloudKit - the isolated, disk-free stack tests and previews
    ///   use. When `false`, the production Cloud + Local split described above is loaded.
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FitSnack", managedObjectModel: Self.managedObjectModel)

        if inMemory {
            Self.configureInMemoryStore(container)
        } else {
            Self.configureCloudAndLocalStores(container)
        }

        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { description, error in
            guard let error = error as NSError? else { return }
            // A CloudKit setup failure (no iCloud account, offline, or an unsigned build with no
            // iCloud entitlement) must never break the core loop: retry this store local-only so
            // the app still opens and every session is generated and recorded on-device. Sync is
            // additive - it resumes on its own once an account and connectivity are available.
            if description.cloudKitContainerOptions != nil {
                description.cloudKitContainerOptions = nil
                do {
                    try coordinator.addPersistentStore(
                        ofType: description.type,
                        configurationName: description.configuration,
                        at: description.url,
                        options: description.options
                    )
                } catch {
                    fatalError("Failed to load the FitSnack store even local-only: \(error)")
                }
            } else {
                // A local store failing to load is a genuine defect, not a runtime condition.
                fatalError("Failed to load the FitSnack persistent store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// A single ephemeral store holding every entity (the model's default configuration), no
    /// CloudKit - the test/preview stack.
    private static func configureInMemoryStore(_ container: NSPersistentCloudKitContainer) {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("FitSnack persistent container has no store description")
        }
        description.url = URL(fileURLWithPath: "/dev/null")
        description.cloudKitContainerOptions = nil
    }

    /// The production split: the durable `Cloud` configuration mirrors to CloudKit; the transient
    /// `Local` configuration (`CDActiveSession`) stays on-device.
    private static func configureCloudAndLocalStores(_ container: NSPersistentCloudKitContainer) {
        let baseURL = NSPersistentContainer.defaultDirectoryURL()

        let cloud = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("FitSnack.sqlite"))
        cloud.configuration = "Cloud"
        // Persistent history + remote-change notifications are prerequisites for CloudKit mirroring
        // and let the view context merge changes synced in from other devices.
        cloud.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloud.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        cloud.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )

        let local = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("FitSnack-Local.sqlite"))
        local.configuration = "Local"
        local.cloudKitContainerOptions = nil

        container.persistentStoreDescriptions = [cloud, local]
    }
}
