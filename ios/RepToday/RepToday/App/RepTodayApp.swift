import SwiftUI

/// App entry point.
///
/// US-A01 wired the minimal app shell; US-A04 attached the CoreData stack. US-N02 makes that
/// stack the CloudKit-backed production stack and wires the production `ServiceContainer`
/// (`live(...)`) over it, so the user, their history, and the in-force policy persist
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
    /// is cohorted by. Constructing it is what mints `installId` and stamps `firstLaunchAt` on a
    /// genuine first launch, so this is the one moment `isFirstLaunch` is knowable; US-T07's
    /// `app_install` emission hangs off exactly this point rather than re-deriving it later.
    ///
    /// It is built in `init()` rather than as a property default because the telemetry transport
    /// (US-T04) needs its `installId`, and the identity must be resolved exactly once: `AppState`
    /// is constructed first, and the services are built from the id it settled on.
    @State private var appState: AppState

    init() {
        // Before anything reads the opt-out flag: an XCUITest run launched with the US-T06 probe
        // argument starts from the shipped default rather than from whatever the previous run's
        // toggling left in the installed app's container. Inert in every other launch, and compiled
        // out of Release entirely.
        #if DEBUG
        TelemetryUITestHarness.resetPersistedConsentIfActive()
        #endif

        // First, because the container is built from its install id (US-T04/US-T05). `AppState` is
        // the sole resolver of that identity - it mints the id, stamps the origin, and decides
        // which of the three launch states this launch is - so the id travels *from* here rather
        // than being read again anywhere downstream.
        let appState = AppState()
        _appState = State(initialValue: appState)

        // The production services are backed by the shared stack's main-queue context, so every
        // CoreData-backed store reads and writes the one on-device (and synced) history. The
        // telemetry gate travels the same way the install id does - built from this `AppState`, so
        // it is bound to the store the Settings toggle writes rather than to one it is assumed to
        // share.
        let services = ServiceContainer.live(
            context: PersistenceController.shared.viewContext,
            installId: appState.installId,
            analyticsGate: appState.analyticsGate
        )
        self.services = services
        self.transactionListener = services.subscriptionService.startObservingTransactions()

        // The US-T06 out-of-process proof needs something for the opt-out gate to block, and no
        // emission call site exists yet (US-T07 through US-T12 add them). Under the probe launch
        // argument only, one `app_install` goes through the container's own sink from exactly the
        // place US-T07's real one will - intercepted in process, so nothing reaches the network.
        #if DEBUG
        TelemetryUITestHarness.emitProbeEventIfActive(through: services.analyticsService)
        #endif
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
