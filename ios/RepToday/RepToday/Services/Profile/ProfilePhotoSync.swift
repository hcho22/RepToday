import Foundation

/// Why the account's profile image could not be read or changed. The phone's photo is never touched by
/// a failure; the change stays owed and is tried again later.
enum AccountProfileImageError: Error, Equatable {
    /// No session for the account this phone is linked to (signed out, or a session for another
    /// account). Retried once the user signs in again.
    case notSignedIn
    /// No connection.
    case unreachable
    /// The account provider refused or failed for another reason.
    case failed(String)
}

/// The account's profile image (Clerk's user profile image in a configured build). Every call names the
/// account this phone is linked to and refuses a session for any other, so a photo can never land on
/// an account the phone's data does not belong to.
protocol AccountProfileImageServiceProtocol: Sendable {
    /// The account's own profile image, or `nil` when it has none (the provider's generated avatar does
    /// not count).
    func accountImage(forLinkedAccount userId: String) async throws -> Data?
    /// Sets `jpeg` as the account's profile image.
    func setAccountImage(_ jpeg: Data, forLinkedAccount userId: String) async throws
    /// Removes the account's profile image. Succeeds when there is none.
    func removeAccountImage(forLinkedAccount userId: String) async throws
}

/// Keeps the account's profile image a copy of the phone's photo (the phone wins), and on a fresh
/// sign-in with no photo on the phone adopts the account's image once.
///
/// It owns no schedule: `ProfilePhotoModel` decides when it runs, and signing out runs `pushPending`
/// before the phone's copy is erased.
struct ProfilePhotoSync: Sendable {
    let store: any ProfilePhotoStoring
    let remote: any AccountProfileImageServiceProtocol

    /// What a run did, for the model and the tests.
    enum Outcome: Equatable {
        case nothingToDo
        case uploaded
        case removed
        case adopted
        /// A change was saved to the account, but a newer change on the phone is still owed.
        case newerChangeOwed
    }

    /// Takes the phone's waiting change to the account, then - when nothing is waiting and the phone
    /// has no photo - adopts the account's image once for this account. `stillLinked` is asked right
    /// before an adopted image is saved, so an image fetched while the phone was signed out or erased
    /// is dropped rather than written back.
    func run(linkedAccount userId: String, stillLinked: @Sendable () async -> Bool) async throws -> Outcome {
        let pushed = try await pushPending(linkedAccount: userId)
        if pushed != .nothingToDo {
            return pushed
        }
        let record = store.record()
        guard record.pendingChange == nil, record.adoptionCheckedFor != userId else { return .nothingToDo }
        guard store.photo() == nil else {
            try store.markAdoptionChecked(for: userId)
            return .nothingToDo
        }
        guard let accountImage = try await remote.accountImage(forLinkedAccount: userId),
              let photo = ProfilePhotoProcessing.storedPhoto(fromAccountImage: accountImage) else {
            if await stillLinked() {
                try store.markAdoptionChecked(for: userId)
            }
            return .nothingToDo
        }
        guard await stillLinked() else { return .nothingToDo }
        return try store.adopt(photo, from: userId) ? .adopted : .nothingToDo
    }

    /// Takes the phone's waiting change, if any, to the account.
    @discardableResult
    func pushPending(linkedAccount userId: String) async throws -> Outcome {
        let record = store.record()
        switch record.pendingChange {
        case nil:
            return .nothingToDo
        case .upload:
            guard let photo = store.photo() else {
                // The photo went away under the record; there is nothing left to upload.
                try store.completeChange(revision: record.revision)
                return .nothingToDo
            }
            try await remote.setAccountImage(photo, forLinkedAccount: userId)
            return try finish(record, as: .uploaded, for: userId)
        case .remove:
            try await remote.removeAccountImage(forLinkedAccount: userId)
            return try finish(record, as: .removed, for: userId)
        }
    }

    private func finish(_ record: ProfilePhotoRecord, as outcome: Outcome, for userId: String) throws -> Outcome {
        try store.completeChange(revision: record.revision)
        // The account now carries the phone's choice, so there is nothing of its own left to adopt.
        try store.markAdoptionChecked(for: userId)
        return store.record().pendingChange == nil ? outcome : .newerChangeOwed
    }
}
