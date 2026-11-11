import CloudKit
import CoreData
import Foundation

/// How the one-time import of a pre-account user's iCloud data ended (M3, US-AU04).
enum LegacyICloudImportOutcome: Equatable, Sendable {
    /// The iCloud mirror finished an import: everything in iCloud is now in the store on the phone.
    case imported
    /// There is nothing to import: the mirror is off, or the device has no iCloud account.
    case nothingToImport
    /// No answer yet (offline, or iCloud is slow). The migration uploads what is on the phone and
    /// waits again on the next launch.
    case unconfirmed
}

/// Waits for the iCloud import a migrating user's history depends on.
protocol LegacyICloudImporting: Sendable {
    func waitForImport(timeout: Duration) async -> LegacyICloudImportOutcome
}

/// Watches the store's iCloud mirror (`NSPersistentCloudKitContainer`) for its first import after
/// launch, so the migration knows when iCloud data has reached the phone (M3, US-AU04).
///
/// It starts listening when the container is built, before any store loads, so an import that
/// finishes while the user is still on the sign-in screen is not missed. While it waits it also asks
/// CloudKit whether the device has an iCloud account at all: with none, there is nothing to import and
/// no import event may ever come.
final class LegacyICloudImportMonitor: LegacyICloudImporting, @unchecked Sendable {
    // Safe: `state` is only read and written under `lock`; the other stored values are immutable.
    private let lock = NSLock()
    private var state: LegacyICloudImportOutcome = .unconfirmed
    private var observer: NSObjectProtocol?
    private let accountStatus: (@Sendable () async -> CKAccountStatus)?

    /// A monitor that already knows the answer, for a store with no mirror.
    init(settled outcome: LegacyICloudImportOutcome) {
        state = outcome
        accountStatus = nil
    }

    /// A monitor with no mirroring events, answering from the iCloud account status alone (tests).
    init(accountStatus: @escaping @Sendable () async -> CKAccountStatus) {
        self.accountStatus = accountStatus
    }

    /// Listens to `container`'s mirroring events and asks `containerIdentifier`'s account status.
    init(container: NSPersistentCloudKitContainer, containerIdentifier: String) {
        accountStatus = {
            (try? await CKContainer(identifier: containerIdentifier).accountStatus()) ?? .couldNotDetermine
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            self?.record(event)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The mirror is not running (the store loaded without it), so iCloud has nothing to add.
    func markNotMirroring() {
        settle(.nothingToImport)
    }

    func waitForImport(timeout: Duration) async -> LegacyICloudImportOutcome {
        if current() == .unconfirmed, let accountStatus {
            switch await accountStatus() {
            case .noAccount, .restricted:
                settle(.nothingToImport)
            default:
                break
            }
        }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let outcome = current()
            if outcome != .unconfirmed {
                return outcome
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { break }
        }
        return current()
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else { return }
        switch event.type {
        case .import where event.succeeded:
            settle(.imported)
        case .setup, .import:
            // An iCloud account the device does not have can never deliver data; anything else
            // (offline, throttled) is worth waiting for on the next launch.
            if Self.meansNoICloudAccount(event.error) {
                settle(.nothingToImport)
            }
        default:
            break
        }
    }

    /// CloudKit's "not signed in", or the mirror's own "Unable to initialize without an iCloud account"
    /// (`NSCocoaErrorDomain` 134400).
    static func meansNoICloudAccount(_ error: Error?) -> Bool {
        if let error = error as? CKError, error.code == .notAuthenticated {
            return true
        }
        guard let error = error as NSError? else { return false }
        return error.domain == NSCocoaErrorDomain && error.code == 134400
    }

    private func settle(_ outcome: LegacyICloudImportOutcome) {
        lock.lock()
        defer { lock.unlock() }
        if state == .unconfirmed {
            state = outcome
        }
    }

    private func current() -> LegacyICloudImportOutcome {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}
