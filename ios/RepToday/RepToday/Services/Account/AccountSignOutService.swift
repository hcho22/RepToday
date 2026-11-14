import Foundation

/// What the upload before signing out left behind (US-SO01, decision 14).
enum SignOutUploadResult: Equatable, Sendable {
    /// Everything on the phone is on the account, so signing out loses nothing.
    case allSaved
    /// Changes are still waiting - offline, refused, or the upload ran out of time. Signing out now
    /// would lose them, so the user is warned first.
    case unsavedChanges
}

/// Signs the user out of their Rep Today account (US-SO01/US-SO02): first an attempt to upload what is
/// waiting, then the phone's copy of the account erased, leaving the account's data on the server.
///
/// The two steps are separate calls because the user decides between them: `AccountSignOutViewModel`
/// shows the decision 14 warning when the upload leaves changes behind, and only "Sign Out Anyway"
/// goes on to `signOut`.
protocol AccountSignOutServiceProtocol {
    /// Uploads the sync outbox, waiting at most the service's bound, then reports whether anything is
    /// still waiting. Changes nothing but the outbox and the account, so a Cancel after it leaves the
    /// user signed in exactly as before.
    func uploadPendingChanges(appState: AppState) async -> SignOutUploadResult

    /// Erases the phone's copy of the account and returns to sign-in. Idempotent: a second call finds
    /// nothing left to erase.
    ///
    /// - Throws: when a step of the erase fails; the user stays signed in and on Settings, and a retry
    ///   finishes it.
    func signOut(appState: AppState) async throws
}

/// The production sign-out, built on the one device teardown Delete Account and the different-account
/// erase already share (`AccountDeletionServiceProtocol.eraseThisDevice`), so the three can never
/// disagree about what the phone keeps of an account.
struct AccountSignOutService: AccountSignOutServiceProtocol {
    /// The sync engine, or `nil` when this build has no account backend: then nothing on the phone ever
    /// reached an account, and anything in the outbox counts as unsaved.
    let engine: SyncEngine?
    let syncStore: any SyncStore
    let eraser: any AccountDeletionServiceProtocol
    /// How long the upload may take before the user is told what is still waiting. Long enough for a
    /// slow connection to upload a few sessions, short enough that a phone that will never connect
    /// answers well inside the time someone waits on a spinner; an offline phone answers at once.
    var uploadTimeout: Duration = Self.defaultUploadTimeout

    static let defaultUploadTimeout: Duration = .seconds(15)

    func uploadPendingChanges(appState: AppState) async -> SignOutUploadResult {
        // A user who onboarded before accounts and has not finished moving to theirs may still have
        // records the outbox has not been given, so the outbox alone cannot say they are saved.
        let migrationStage = await MainActor.run { appState.legacyMigrationStage }
        if migrationStage == .awaitingSignIn || migrationStage == .importingFromICloud {
            return .unsavedChanges
        }
        if let engine {
            // A cycle that runs past the bound keeps going in the background; erasing waits for it to
            // end, so nothing it pulls can land after the erase.
            await Self.run(for: uploadTimeout) { _ = try? await engine.sync() }
        }
        // The outbox decides, whatever the upload threw: an entry leaves it only once the account
        // confirmed it.
        guard let pending = try? await syncStore.pendingCount() else { return .unsavedChanges }
        return pending == 0 ? .allSaved : .unsavedChanges
    }

    func signOut(appState: AppState) async throws {
        try await eraser.eraseThisDevice(appState: appState)
        await Self.returnToSignIn(appState: appState)
    }

    /// Where signing out lands - the one place to change it. The erase has already routed the app to
    /// onboarding's start (`isOnboarded == false`), the same place Delete Account and the
    /// different-account erase land.
    @MainActor
    static func returnToSignIn(appState: AppState) {}

    /// Runs `work` for at most `limit`, returning when it finishes or the time is up, whichever is
    /// first. `work` is not cancelled: `SyncEngine.sync()` ignores cancellation of its caller, and a
    /// cycle stopped half-way is no better than one left to finish.
    static func run(for limit: Duration, _ work: @escaping @Sendable () async -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: limit)
                resume()
            }
            Task {
                await work()
                timer.cancel()
                resume()
            }
        }
    }

    /// Resumes a continuation exactly once, whichever of the upload and the timer gets there first.
    private final class ResumeOnce: @unchecked Sendable {
        // Safe: `continuation` is only touched under `lock`.
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func callAsFunction() {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume()
        }
    }
}
