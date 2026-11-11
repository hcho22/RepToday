import CoreData
import Foundation
import Network
import Observation
import UIKit

/// Keeps the device's data flowing to the user's account (M3, US-AU03/US-AU04): decides **when** the
/// sync engine runs and reports how it went, so the Account screen can say so.
///
/// Sync is always in the background of the app, never in front of it. Sessions generate, play and log
/// from Core Data whether or not this has ever run (FR-10); a sync that cannot run simply leaves the
/// outbox for later. A cycle runs:
///
/// - shortly after any change lands in the outbox (a session logged, an activity edited);
/// - when the app comes to the foreground, and when the device regains a connection;
/// - after a failure, on a growing back-off (5 s, 15 s, 1 min, then every 5 min).
///
/// Each cycle asks iOS for a little background time, so a session logged just before the user leaves
/// the app still uploads. Nothing runs while account deletion is in progress
/// (`AppState.isAccountDeletionInProgress`); deletion also waits out a cycle that was already running.
@MainActor
@Observable
final class AccountSyncCoordinator {
    enum Status: Equatable {
        /// No account is linked yet.
        case signedOut
        /// Linked, but this build has no account backend (a Debug or test build without Clerk): the
        /// data stays on the device.
        case localOnly
        case syncing
        /// Everything on the device is on the account.
        case upToDate
        /// Changes are waiting for a connection.
        case waitingForConnection
        /// The account did not accept this device's session; signing in again resumes syncing.
        case needsSignIn
        /// The account is being deleted (from another device); nothing more syncs to it, and signing
        /// in to it again could only be refused.
        case accountBeingDeleted
        /// The last attempt failed for another reason; it will try again.
        case retrying
    }

    private(set) var status: Status = .signedOut
    /// Records waiting to sync.
    private(set) var pendingCount = 0
    private(set) var lastSyncedAt: Date?

    private let engine: SyncEngine?
    private let store: any SyncStore
    private let appState: AppState
    private let migrator: LegacyAccountMigrator
    private let now: () -> Date
    private let beginBackgroundWork: @MainActor (String) -> (@MainActor () -> Void)
    private let onRemoteChangesApplied: @MainActor () -> Void

    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var cycle: Task<Void, Never>?
    @ObservationIgnored private var failureCount = 0
    /// The migration waits for iCloud at most once per launch; later cycles upload without waiting.
    @ObservationIgnored private var migrationPreparedThisLaunch = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    /// The back-off after consecutive failures; the last value repeats.
    static let retryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(60), .seconds(300)]

    /// - Parameters:
    ///   - engine: the sync engine, or `nil` when this build has no account backend.
    ///   - onRemoteChangesApplied: called when a pull changed the store, so the screens showing today's
    ///     plan reload.
    init(
        engine: SyncEngine?,
        store: any SyncStore,
        appState: AppState,
        migrator: LegacyAccountMigrator,
        now: @escaping () -> Date = Date.init,
        beginBackgroundWork: @escaping @MainActor (String) -> (@MainActor () -> Void) = AccountSyncCoordinator.liveBackgroundWork,
        onRemoteChangesApplied: @escaping @MainActor () -> Void
    ) {
        self.engine = engine
        self.store = store
        self.appState = appState
        self.migrator = migrator
        self.now = now
        self.beginBackgroundWork = beginBackgroundWork
        self.onRemoteChangesApplied = onRemoteChangesApplied
        // Nothing is claimed as saved before the first cycle has run; `start` runs one at once.
        status = appState.account == nil ? .signedOut : (engine == nil ? .localOnly : .syncing)
    }

    // MARK: - Triggers

    /// Starts watching for changes and connectivity, then syncs. Call once, at launch.
    func start(observing context: NSManagedObjectContext?) {
        guard observers.isEmpty else { return }
        if let context {
            observers.append(NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: context,
                queue: .main
            ) { [weak self] notification in
                let changed = [NSInsertedObjectsKey, NSUpdatedObjectsKey].contains { key in
                    (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is CDSyncChange } ?? false
                }
                guard changed else { return }
                MainActor.assumeIsolated { self?.requestSync() }
            })
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.status == .waitingForConnection || self.status == .retrying else { return }
                self.requestSync(after: .zero)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.reptoday.sync.path"))
        pathMonitor = monitor
        requestSync(after: .zero)
    }

    /// Schedules a cycle after `delay`, replacing one already scheduled, so a burst of changes uploads
    /// once.
    func requestSync(after delay: Duration = .milliseconds(1500)) {
        guard !appState.isAccountDeletionInProgress else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs one cycle now (or waits for the one running) and updates the status.
    func syncNow() async {
        if let cycle {
            await cycle.value
            return
        }
        let task = Task { await self.runCycle() }
        cycle = task
        await task.value
        cycle = nil
    }

    // MARK: - Account changes

    /// Links the account the user just signed in to, synchronously, then syncs.
    ///
    /// - Throws: `AccountLinkError.belongsToAnotherAccount` when the device is linked to a different
    ///   account; nothing changes then.
    func linkAccount(_ identity: AccountIdentity) throws {
        try appState.linkAccount(identity)
        failureCount = 0
        status = engine == nil ? .localOnly : .syncing
        requestSync(after: .zero)
    }

    // MARK: - The cycle

    private func runCycle() async {
        guard !appState.isAccountDeletionInProgress else { return }
        guard appState.account != nil else {
            pendingCount = 0
            lastSyncedAt = nil
            status = .signedOut
            return
        }
        guard let engine else {
            status = .localOnly
            pendingCount = (try? await store.pendingCount()) ?? pendingCount
            return
        }
        status = .syncing
        let endBackgroundWork = beginBackgroundWork("Rep Today sync")
        defer { endBackgroundWork() }
        do {
            if !migrationPreparedThisLaunch {
                try await migrator.prepareUpload()
                migrationPreparedThisLaunch = true
            }
            let report = try await engine.sync()
            pendingCount = report.pending
            lastSyncedAt = now()
            failureCount = 0
            migrator.completeIfUploaded(pendingAfterSync: report.pending)
            if report.applied > 0 {
                onRemoteChangesApplied()
            }
            if report.pending > 0 {
                // The cycle's round budget ran out with more waiting (or a change arrived mid-cycle).
                status = .syncing
                requestSync(after: .seconds(1))
            } else {
                status = .upToDate
            }
        } catch is CancellationError {
            status = .retrying
        } catch {
            pendingCount = (try? await store.pendingCount()) ?? pendingCount
            status = Self.status(for: error)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        let delays = Self.retryDelays
        let delay = delays[min(failureCount, delays.count - 1)]
        failureCount += 1
        requestSync(after: delay)
    }

    static func status(for error: Error) -> Status {
        switch error as? SyncRemoteError {
        case .unreachable, .noResponse:
            return .waitingForConnection
        case .notSignedIn, .unauthenticated:
            return .needsSignIn
        case .accountDeleting:
            return .accountBeingDeleted
        default:
            return .retrying
        }
    }

    /// Asks iOS for background time for one cycle; the returned closure ends it.
    static func liveBackgroundWork(_ name: String) -> (@MainActor () -> Void) {
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        return {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
