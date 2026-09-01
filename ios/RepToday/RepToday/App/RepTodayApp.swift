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
    /// (US-T04) needs the identity owner: `AppState` is constructed first, and the services receive
    /// both its launch value and its per-emission reader so account deletion can rotate it in place.
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
        // which of the three launch states this launch is - so both the id and the reader that can
        // observe its deletion rotation travel *from* here rather than being re-derived downstream.
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
            analyticsInstallId: appState.analyticsInstallId,
            analyticsGate: appState.analyticsGate
        )
        self.services = services
        self.transactionListener = services.subscriptionService.startObservingTransactions()

        // US-T07: the three app-entry funnel events - `app_install`, `day7_return`, `day30_return` -
        // decided from the identity `AppState` just settled and a single wall-clock read, then handed
        // to the sink fire-and-forget. This site emits **unconditionally**: consent lives inside the
        // sink (`LiveAnalyticsService.record(_:)` reads the opt-out gate per emission), so re-checking
        // the flag here would only be a second gate that could disagree with the first. The decision
        // unit is what makes the window/dedup logic testable off an injected clock; here it takes the
        // one `Date()` this entry point is allowed. `record(_:)` returns immediately after dispatching
        // to its own detached task, so the wrapping `Task` only bridges `init`'s synchronous context.
        let entryEvents = AppEntryTelemetry.eventsForLaunch(
            isFirstLaunch: appState.isFirstLaunch,
            firstLaunchAt: appState.firstLaunchAt,
            installWeek: appState.installWeek,
            now: Date(),
            defaults: appState.telemetryDefaults
        )
        let analytics = services.analyticsService
        Task {
            for event in entryEvents {
                await analytics.record(event)
            }
        }

        // The US-T06 out-of-process proof needs something for the opt-out gate to block that fires on
        // *every* probe launch. US-T07's real emission above cannot serve that role: the probe suite
        // launches onboarded, so `isFirstLaunch` is false and `app_install` never fires there. The
        // probe therefore keeps emitting its own `app_install` from this exact place - intercepted in
        // process, so nothing reaches the network - and the two never collide, because no probe launch
        // is ever a genuine first launch.
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
