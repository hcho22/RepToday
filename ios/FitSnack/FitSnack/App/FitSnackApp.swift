import SwiftUI

/// App entry point.
///
/// US-A01 wired the minimal app shell; US-A04 attached the CoreData stack. US-N02 makes that
/// stack the CloudKit-backed production stack and wires the production `ServiceContainer`
/// (`live(context:)`) over it, so the user, their history, and the in-force policy persist
/// across relaunch and sync across devices. The stack still works fully offline and with no
/// iCloud account - sync is additive and never gates the core loop. The `ServiceContainer` and
/// `AppState` (US-A05) are injected here as the top-level app dependencies.
@main
struct FitSnackApp: App {
    /// The app-wide CloudKit-enabled CoreData stack, instantiated at launch so the store loads
    /// immediately. It degrades to local-only when CloudKit is unavailable, so it never requires
    /// an iCloud account for the core loop to work.
    private let persistenceController = PersistenceController.shared
    private let services: ServiceContainer

    @State private var appState = AppState()

    init() {
        // The production services are backed by the shared stack's main-queue context, so every
        // CoreData-backed store reads and writes the one on-device (and synced) history.
        services = ServiceContainer.live(context: PersistenceController.shared.viewContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environment(\.services, services)
                .environment(appState)
        }
    }
}
