import AVFoundation
import Observation
import UIKit

/// The user's profile photo for the screens that show it (the Profile tab and Account), and the one
/// place that changes it: set from the camera or the library, or removed.
///
/// The photo is saved on the phone first (`ProfilePhotoStoring`), so it shows at once, signed in or
/// not, connected or not. When an account is linked, `ProfilePhotoSync` copies each change to the
/// account's profile image in the background, and a fresh sign-in on a phone with no photo adopts the
/// account's image. A change the account has not taken stays owed and is retried: when the app comes
/// to the foreground, when the linked account changes, and after a failure on a growing back-off.
/// Nothing in the core loop waits on it.
@MainActor
@Observable
final class ProfilePhotoModel {
    /// The photo, or `nil` when none is set.
    private(set) var image: UIImage?
    /// True when saving a new photo or removing one on the phone failed (the disk refused it).
    private(set) var saveFailed = false

    private let store: any ProfilePhotoStoring
    private let sync: ProfilePhotoSync?
    /// The account this phone is linked to and may sync to now, or `nil` (no account, or the account is
    /// being deleted or the phone erased).
    private let syncableAccount: @MainActor () -> String?

    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var failureCount = 0

    /// The back-off after consecutive failures; the last value repeats.
    static let retryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(60), .seconds(300)]

    /// - Parameters:
    ///   - sync: copies the photo to the account, or `nil` when this build has no account provider (the
    ///     photo stays on the phone).
    ///   - syncableAccount: the linked account, read on every run.
    init(store: any ProfilePhotoStoring, sync: ProfilePhotoSync?, syncableAccount: @escaping @MainActor () -> String?) {
        self.store = store
        self.sync = sync
        self.syncableAccount = syncableAccount
        reload()
    }

    /// The model for this app: the container's store and account sync, syncing to the account
    /// `appState` is linked to unless it is being deleted.
    convenience init(services: ServiceContainer, appState: AppState) {
        self.init(store: services.profilePhotoStore, sync: services.profilePhotoSync) { [appState] in
            guard !appState.isAccountDeletionInProgress, !appState.isLinkedAccountBeingDeleted else { return nil }
            return appState.account?.userId
        }
    }

    var hasPhoto: Bool { image != nil }

    /// Reads the photo from the phone again: after the phone's copy was erased, or the account changed.
    func reload() {
        image = store.photo().flatMap(UIImage.init(data:))
    }

    // MARK: - Changing the photo

    /// Saves the cropped, compressed photo (`ProfilePhotoProcessing`) and copies it to the account.
    func setPhoto(_ jpeg: Data) {
        do {
            try store.setPhoto(jpeg)
            saveFailed = false
        } catch {
            saveFailed = true
        }
        reload()
        requestSync()
    }

    /// Removes the photo from the phone and the account.
    func removePhoto() {
        do {
            try store.removePhoto()
            saveFailed = false
        } catch {
            saveFailed = true
        }
        reload()
        requestSync()
    }

    /// The user has read that the photo was not saved.
    func acknowledgeSaveFailure() {
        saveFailed = false
    }

    // MARK: - Syncing with the account

    /// Schedules a run after `delay`, replacing one already scheduled.
    func requestSync(after delay: Duration = .zero) {
        guard sync != nil else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs now, or once more after the run in progress.
    func syncNow() async {
        if let running {
            rerunRequested = true
            await running.value
            return
        }
        let task = Task { await self.runUntilSettled() }
        running = task
        await task.value
        running = nil
    }

    private func runUntilSettled() async {
        repeat {
            rerunRequested = false
            await runOnce()
        } while rerunRequested
    }

    private func isSyncable(to account: String) -> Bool {
        syncableAccount() == account
    }

    private func runOnce() async {
        guard let sync, let account = syncableAccount() else { return }
        do {
            let outcome = try await sync.run(linkedAccount: account) {
                await self.isSyncable(to: account)
            }
            failureCount = 0
            switch outcome {
            case .adopted:
                reload()
            case .newerChangeOwed:
                rerunRequested = true
            case .nothingToDo, .uploaded, .removed:
                break
            }
        } catch AccountProfileImageError.notSignedIn {
            // Waits for the user to sign in again; the account change triggers the next run.
        } catch {
            let delay = Self.retryDelays[min(failureCount, Self.retryDelays.count - 1)]
            failureCount += 1
            requestSync(after: delay)
        }
    }
}

/// Whether Take Photo can be offered.
enum CameraAvailability: Equatable {
    /// The phone has a camera and the user has not refused it.
    case available
    /// The user refused camera access; turning it on in Settings is the way back.
    case deniedInSettings
    /// No camera (the Simulator), or camera use is restricted on this phone.
    case unavailable

    static func resolve(hasCamera: Bool, authorization: AVAuthorizationStatus) -> CameraAvailability {
        guard hasCamera else { return .unavailable }
        switch authorization {
        case .authorized, .notDetermined:
            return .available
        case .denied:
            return .deniedInSettings
        case .restricted:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    /// This phone, now.
    @MainActor
    static var current: CameraAvailability {
        resolve(
            hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
            authorization: AVCaptureDevice.authorizationStatus(for: .video)
        )
    }
}
