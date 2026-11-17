import Foundation

/// What the phone knows about its profile photo beyond the image itself: which change the account has
/// not yet taken, and whether the account's own image has been looked at for this account.
struct ProfilePhotoRecord: Codable, Equatable, Sendable {
    /// A change made on the phone that the account's profile image has not yet taken.
    enum AccountChange: String, Codable, Sendable {
        /// The phone's photo is newer than the account's image.
        case upload
        /// The photo was removed on the phone; the account's image is still to be removed.
        case remove
    }

    var pendingChange: AccountChange?
    /// Moves on every change made on the phone, so an upload that finishes after a newer change does
    /// not mark the newer one as saved.
    var revision: UUID
    /// The account whose own image has been looked at (and adopted, if there was one and the phone had
    /// none). A fresh sign-in on a phone with no photo adopts the account's image once, never again.
    var adoptionCheckedFor: String?

    static func empty() -> ProfilePhotoRecord {
        ProfilePhotoRecord(pendingChange: nil, revision: UUID(), adoptionCheckedFor: nil)
    }
}

/// The phone's copy of the user's profile photo: a square JPEG kept in the app's own container, with
/// its `ProfilePhotoRecord`. It is the photo the app shows, whether or not anyone is signed in; the
/// account's profile image is a copy of it (`ProfilePhotoSync`), so the photo survives a reinstall or a
/// new phone.
///
/// Nothing here reads or writes the photo library, iCloud Photos or any shared location.
protocol ProfilePhotoStoring: Sendable {
    /// The photo's JPEG data, or `nil` when none is set.
    func photo() -> Data?
    func record() -> ProfilePhotoRecord

    /// Saves `jpeg` as the photo, owed to the account. Returns the new revision.
    @discardableResult
    func setPhoto(_ jpeg: Data) throws -> UUID

    /// Removes the photo, the removal owed to the account. Returns the new revision.
    @discardableResult
    func removePhoto() throws -> UUID

    /// Saves the account's image as the photo, only when the phone has no photo and no change waiting
    /// for the account. Owes the account nothing. Returns whether it was saved.
    @discardableResult
    func adopt(_ jpeg: Data, from account: String) throws -> Bool

    /// Records that `account`'s own image has been looked at.
    func markAdoptionChecked(for account: String) throws

    /// Marks the change at `revision` as taken by the account. A newer change stays owed.
    func completeChange(revision: UUID) throws

    /// Owes the account the phone's photo again, when there is one: used when the account's image was
    /// removed but the account itself stayed (account deletion that stopped before deleting anything).
    func requeueUpload() throws

    /// Deletes the photo and its record: signing out, erasing the phone, and account deletion.
    func erase() throws
}

/// The production store: `Application Support/ProfilePhoto/` in the app's own container, holding
/// `photo.jpg` and `record.json`, each written atomically and protected until the phone is first
/// unlocked after a restart. It is as local as the Core Data Local store beside it (ADR-0016).
final class FileProfilePhotoStore: ProfilePhotoStoring, @unchecked Sendable {
    // Safe: every file access happens under `lock`.
    private let lock = NSLock()
    /// Where the photo and its record live.
    let directory: URL
    private let fileManager = FileManager.default

    private var photoURL: URL { directory.appendingPathComponent("photo.jpg") }
    private var recordURL: URL { directory.appendingPathComponent("record.json") }

    init(directory: URL) {
        self.directory = directory
    }

    /// The store in the app's Application Support directory.
    static func live() -> FileProfilePhotoStore {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return FileProfilePhotoStore(directory: base.appendingPathComponent("ProfilePhoto", isDirectory: true))
    }

    func photo() -> Data? {
        lock.withLock { try? Data(contentsOf: photoURL) }
    }

    func record() -> ProfilePhotoRecord {
        lock.withLock { readRecord() }
    }

    func setPhoto(_ jpeg: Data) throws -> UUID {
        try lock.withLock {
            try prepareDirectory()
            try jpeg.write(to: photoURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var record = readRecord()
            record.pendingChange = .upload
            record.revision = UUID()
            try write(record)
            return record.revision
        }
    }

    func removePhoto() throws -> UUID {
        try lock.withLock {
            if fileManager.fileExists(atPath: photoURL.path) {
                try fileManager.removeItem(at: photoURL)
            }
            var record = readRecord()
            record.pendingChange = .remove
            record.revision = UUID()
            try prepareDirectory()
            try write(record)
            return record.revision
        }
    }

    func adopt(_ jpeg: Data, from account: String) throws -> Bool {
        try lock.withLock {
            var record = readRecord()
            guard record.pendingChange == nil, !fileManager.fileExists(atPath: photoURL.path) else { return false }
            try prepareDirectory()
            try jpeg.write(to: photoURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            record.adoptionCheckedFor = account
            record.revision = UUID()
            try write(record)
            return true
        }
    }

    func markAdoptionChecked(for account: String) throws {
        try lock.withLock {
            var record = readRecord()
            guard record.adoptionCheckedFor != account else { return }
            record.adoptionCheckedFor = account
            try prepareDirectory()
            try write(record)
        }
    }

    func completeChange(revision: UUID) throws {
        try lock.withLock {
            var record = readRecord()
            guard record.revision == revision, record.pendingChange != nil else { return }
            record.pendingChange = nil
            try write(record)
        }
    }

    func requeueUpload() throws {
        try lock.withLock {
            guard fileManager.fileExists(atPath: photoURL.path) else { return }
            var record = readRecord()
            record.pendingChange = .upload
            record.revision = UUID()
            try write(record)
        }
    }

    func erase() throws {
        try lock.withLock {
            guard fileManager.fileExists(atPath: directory.path) else { return }
            try fileManager.removeItem(at: directory)
        }
    }

    // MARK: - Under the lock

    private func readRecord() -> ProfilePhotoRecord {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONDecoder().decode(ProfilePhotoRecord.self, from: data) else {
            // No record (nothing ever saved, or erased). A photo with no readable record is owed to the
            // account, so a damaged record can never strand a photo the account never got.
            var record = ProfilePhotoRecord.empty()
            if fileManager.fileExists(atPath: photoURL.path) {
                record.pendingChange = .upload
            }
            return record
        }
        return record
    }

    private func write(_ record: ProfilePhotoRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: recordURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// An in-memory store for previews, tests and the mock container.
final class InMemoryProfilePhotoStore: ProfilePhotoStoring, @unchecked Sendable {
    // Safe: every access happens under `lock`.
    private let lock = NSLock()
    private var storedPhoto: Data?
    private var storedRecord = ProfilePhotoRecord.empty()

    init(photo: Data? = nil, record: ProfilePhotoRecord? = nil) {
        storedPhoto = photo
        if let record {
            storedRecord = record
        }
    }

    func photo() -> Data? { lock.withLock { storedPhoto } }

    func record() -> ProfilePhotoRecord { lock.withLock { storedRecord } }

    func setPhoto(_ jpeg: Data) throws -> UUID {
        lock.withLock {
            storedPhoto = jpeg
            storedRecord.pendingChange = .upload
            storedRecord.revision = UUID()
            return storedRecord.revision
        }
    }

    func removePhoto() throws -> UUID {
        lock.withLock {
            storedPhoto = nil
            storedRecord.pendingChange = .remove
            storedRecord.revision = UUID()
            return storedRecord.revision
        }
    }

    func adopt(_ jpeg: Data, from account: String) throws -> Bool {
        lock.withLock {
            guard storedRecord.pendingChange == nil, storedPhoto == nil else { return false }
            storedPhoto = jpeg
            storedRecord.adoptionCheckedFor = account
            storedRecord.revision = UUID()
            return true
        }
    }

    func markAdoptionChecked(for account: String) throws {
        lock.withLock { storedRecord.adoptionCheckedFor = account }
    }

    func completeChange(revision: UUID) throws {
        lock.withLock {
            guard storedRecord.revision == revision else { return }
            storedRecord.pendingChange = nil
        }
    }

    func requeueUpload() throws {
        lock.withLock {
            guard storedPhoto != nil else { return }
            storedRecord.pendingChange = .upload
            storedRecord.revision = UUID()
        }
    }

    func erase() throws {
        lock.withLock {
            storedPhoto = nil
            storedRecord = .empty()
        }
    }
}
