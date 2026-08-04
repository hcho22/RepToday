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
struct RepTodayApp: App {
    /// The app-wide CloudKit-enabled CoreData stack, instantiated at launch so the store loads
    /// immediately. It degrades to local-only when CloudKit is unavailable, so it never requires
    /// an iCloud account for the core loop to work.
    private let persistenceController = PersistenceController.shared
    private let services: ServiceContainer
    /// Retained for the app's lifetime: finishes out-of-band StoreKit transactions (renewals,
    /// refunds, cross-device purchases, Ask-to-Buy approvals) so none linger unfinished (US-N04).
    /// A no-op for a StoreKit-free container; never gates the core loop.
    private let transactionListener: Task<Void, Never>

    /// Onboarding/tab routing, and - since US-T05 - the anonymous per-install identity the funnel
    /// is cohorted by. Constructing it here is what mints `installId` and stamps `firstLaunchAt` on
    /// a genuine first launch, so this is the one moment `isFirstLaunch` is knowable; US-T07's
    /// `app_install` emission hangs off exactly this point rather than re-deriving it later.
    @State private var appState = AppState()

    init() {
        // The production services are backed by the shared stack's main-queue context, so every
        // CoreData-backed store reads and writes the one on-device (and synced) history.
        let services = ServiceContainer.live(context: PersistenceController.shared.viewContext)
        self.services = services
        self.transactionListener = services.subscriptionService.startObservingTransactions()
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
