import CoreData

/// The app's CoreData stack (US-A04).
///
/// Backed by `NSPersistentCloudKitContainer` so it is ready to sync, but wired
/// **local-only** for now: no `cloudKitContainerOptions` are set, so the store never
/// requires an iCloud account and the core loop works fully offline. CloudKit sync and
/// persistent-history wiring land in US-J02.
final class PersistenceController {

    /// The app-wide on-disk stack. Lazily created on first access, so tests that use the
    /// in-memory `MockPersistence` never touch the device store.
    static let shared = PersistenceController()

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

    /// - Parameter inMemory: when `true`, the store is written to `/dev/null`, giving an
    ///   ephemeral stack for tests and previews that leaves nothing on disk.
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FitSnack", managedObjectModel: Self.managedObjectModel)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("FitSnack persistent container has no store description")
        }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        // Local-only until US-J02: leaving cloudKitContainerOptions unset means the
        // container behaves like a plain on-device store and never needs iCloud.
        description.cloudKitContainerOptions = nil

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Failed to load the FitSnack persistent store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
