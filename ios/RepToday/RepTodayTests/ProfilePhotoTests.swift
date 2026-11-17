import AVFoundation
import UIKit
import XCTest
@testable import RepToday

/// Test images and a scriptable account profile image for the profile photo suites.
enum ProfilePhotoFixtures {
    /// A `width` x `height` pixel image in four colored quadrants: red top-left, green top-right, blue
    /// bottom-left, yellow bottom-right.
    static func quadrants(width: CGFloat, height: CGFloat, orientation: UIImage.Orientation = .up) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let halfW = width / 2
            let halfH = height / 2
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: halfW, height: halfH))
            UIColor.green.setFill()
            context.fill(CGRect(x: halfW, y: 0, width: halfW, height: halfH))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: halfH, width: halfW, height: halfH))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: halfW, y: halfH, width: halfW, height: halfH))
        }
        guard orientation != .up, let cgImage = image.cgImage else { return image }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    static func jpeg(_ color: UIColor = .red, side: CGFloat = 64) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    /// The color at the center of `data`'s image.
    static func centerColor(of data: Data) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: -width / 2 + 0.5, y: -height / 2 + 0.5, width: width, height: height))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}

/// An account profile image the tests script: whose session it has, whether it is reachable, and what
/// happens while an upload is in flight.
actor FakeAccountProfileImageService: AccountProfileImageServiceProtocol {
    private(set) var image: Data?
    /// The account the session belongs to, or `nil` for no session.
    private var sessionUserId: String?
    private var offline = false
    private(set) var setCalls = 0
    private(set) var removeCalls = 0
    private(set) var readCalls = 0
    /// Run during the next upload, before it lands.
    private var duringNextUpload: (@Sendable () -> Void)?

    init(sessionUserId: String?, image: Data? = nil) {
        self.sessionUserId = sessionUserId
        self.image = image
    }

    func setOffline(_ value: Bool) { offline = value }
    func setSession(_ userId: String?) { sessionUserId = userId }
    func setImage(_ data: Data?) { image = data }
    func duringNextUpload(_ work: @escaping @Sendable () -> Void) { duringNextUpload = work }

    func accountImage(forLinkedAccount userId: String) async throws -> Data? {
        try check(userId)
        readCalls += 1
        return image
    }

    func setAccountImage(_ jpeg: Data, forLinkedAccount userId: String) async throws {
        try check(userId)
        setCalls += 1
        duringNextUpload?()
        duringNextUpload = nil
        image = jpeg
    }

    func removeAccountImage(forLinkedAccount userId: String) async throws {
        try check(userId)
        removeCalls += 1
        image = nil
    }

    private func check(_ userId: String) throws {
        if offline { throw AccountProfileImageError.unreachable }
        guard sessionUserId == userId else { throw AccountProfileImageError.notSignedIn }
    }
}

// MARK: - Crop, downscale and compress

final class ProfilePhotoProcessingTests: XCTestCase {
    func testTheStoredPhotoIsASquareDownscaledJPEG() throws {
        let photo = ProfilePhotoFixtures.quadrants(width: 3000, height: 2000)
        let geometry = ProfilePhotoCropGeometry(imageSize: CGSize(width: 3000, height: 2000), frameSide: 300)

        let data = try XCTUnwrap(ProfilePhotoProcessing.croppedPhoto(
            from: photo, normalizedCrop: geometry.normalizedCrop(zoom: 1, offset: .zero)
        ))

        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]), "a JPEG")
        XCTAssertLessThan(data.count, 150_000, "small enough to keep and upload in a moment")
    }

    func testASmallPhotoIsNeverUpscaled() throws {
        let photo = ProfilePhotoFixtures.quadrants(width: 200, height: 300)
        let data = try XCTUnwrap(ProfilePhotoProcessing.croppedPhoto(
            from: photo, normalizedCrop: ProfilePhotoCropGeometry.centeredSquare(for: CGSize(width: 200, height: 300))
        ))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 200)
    }

    func testTheCropKeepsThePartTheUserFramed() throws {
        let photo = ProfilePhotoFixtures.quadrants(width: 1000, height: 1000)
        let geometry = ProfilePhotoCropGeometry(imageSize: CGSize(width: 1000, height: 1000), frameSide: 250)
        // Zoomed in 2x and dragged so the frame sits over the bottom-right (yellow) quadrant: the image
        // moves up and left by half the frame.
        let crop = geometry.normalizedCrop(zoom: 2, offset: CGSize(width: -125, height: -125))

        let data = try XCTUnwrap(ProfilePhotoProcessing.croppedPhoto(from: photo, normalizedCrop: crop))

        let color = try XCTUnwrap(ProfilePhotoFixtures.centerColor(of: data))
        XCTAssertGreaterThan(color.red, 0.8)
        XCTAssertGreaterThan(color.green, 0.8)
        XCTAssertLessThan(color.blue, 0.3, "yellow: the framed quadrant")
    }

    func testARotatedCameraPhotoIsCroppedTheWayItIsShown() throws {
        // Stored landscape with a `.right` orientation, as the camera saves a portrait photo: shown upright
        // it is 400 wide and 800 tall.
        let photo = ProfilePhotoFixtures.quadrants(width: 800, height: 400, orientation: .right)
        let upright = ProfilePhotoProcessing.upright(photo)
        XCTAssertEqual(ProfilePhotoProcessing.uprightPixelSize(of: upright), CGSize(width: 400, height: 800))

        let data = try XCTUnwrap(ProfilePhotoProcessing.croppedPhoto(
            from: upright, normalizedCrop: ProfilePhotoCropGeometry.centeredSquare(for: CGSize(width: 400, height: 800))
        ))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, image.height)
        XCTAssertEqual(image.width, 400)
    }

    func testUprightBoundsTheLongestSide() {
        let photo = ProfilePhotoFixtures.quadrants(width: 4032, height: 3024)
        let upright = ProfilePhotoProcessing.upright(photo)
        XCTAssertEqual(ProfilePhotoProcessing.uprightPixelSize(of: upright), CGSize(width: 2048, height: 1536))
    }

    func testTheAccountsImageIsStoredAsACenteredSquare() throws {
        let rectangular = ProfilePhotoFixtures.quadrants(width: 900, height: 600).jpegData(compressionQuality: 0.9)!
        let data = try XCTUnwrap(ProfilePhotoProcessing.storedPhoto(fromAccountImage: rectangular))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertNil(ProfilePhotoProcessing.storedPhoto(fromAccountImage: Data("not an image".utf8)))
    }

    func testAnEmptyCropGivesNoPhoto() {
        let photo = ProfilePhotoFixtures.quadrants(width: 100, height: 100)
        XCTAssertNil(ProfilePhotoProcessing.croppedPhoto(from: photo, normalizedCrop: CGRect(x: 2, y: 2, width: 1, height: 1)))
    }
}

final class ProfilePhotoCropGeometryTests: XCTestCase {
    private let geometry = ProfilePhotoCropGeometry(imageSize: CGSize(width: 2000, height: 1000), frameSide: 300)

    func testAtZoomOneTheShorterSideSpansTheFrame() {
        XCTAssertEqual(geometry.displayedSize(zoom: 1), CGSize(width: 600, height: 300))
        XCTAssertEqual(geometry.normalizedCrop(zoom: 1, offset: .zero), CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(
            geometry.normalizedCrop(zoom: 1, offset: .zero),
            ProfilePhotoCropGeometry.centeredSquare(for: CGSize(width: 2000, height: 1000))
        )
    }

    func testTheImageAlwaysCoversTheFrame() {
        // At zoom 1 the image is 600 x 300: it slides 150 either way sideways and not at all up or down.
        XCTAssertEqual(geometry.clampedOffset(CGSize(width: 500, height: 80), zoom: 1), CGSize(width: 150, height: 0))
        XCTAssertEqual(geometry.clampedOffset(CGSize(width: -500, height: -80), zoom: 1), CGSize(width: -150, height: 0))
        let crop = geometry.normalizedCrop(zoom: 1, offset: CGSize(width: 9999, height: 0))
        XCTAssertEqual(crop.minX, 0, accuracy: 0.0001, "dragged fully right, the frame shows the left edge")
    }

    func testZoomIsKeptBetweenOneAndTheMaximum() {
        XCTAssertEqual(geometry.clampedZoom(0.2), 1)
        XCTAssertEqual(geometry.clampedZoom(10), ProfilePhotoCropGeometry.maxZoom)
        let crop = geometry.normalizedCrop(zoom: 2, offset: .zero)
        XCTAssertEqual(crop.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.midY, 0.5, accuracy: 0.0001)
    }
}

// MARK: - On the phone

final class FileProfilePhotoStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProfilePhotoTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testANewPhoneHasNoPhotoAndOwesNothing() {
        let store = FileProfilePhotoStore(directory: directory)
        XCTAssertNil(store.photo())
        XCTAssertNil(store.record().pendingChange)
        XCTAssertNil(store.record().adoptionCheckedFor)
    }

    func testSettingAPhotoSavesItAndOwesTheAccount() throws {
        let store = FileProfilePhotoStore(directory: directory)
        let jpeg = ProfilePhotoFixtures.jpeg()

        let revision = try store.setPhoto(jpeg)

        XCTAssertEqual(store.photo(), jpeg)
        XCTAssertEqual(store.record().pendingChange, .upload)
        XCTAssertEqual(store.record().revision, revision)
        // A relaunch reads the same photo and the same debt.
        let relaunched = FileProfilePhotoStore(directory: directory)
        XCTAssertEqual(relaunched.photo(), jpeg)
        XCTAssertEqual(relaunched.record().pendingChange, .upload)
    }

    func testThePhotoStaysInsideTheAppsOwnDirectory() throws {
        let store = FileProfilePhotoStore(directory: directory)
        try store.setPhoto(ProfilePhotoFixtures.jpeg())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["photo.jpg", "record.json"])
        // The live store sits in the app's Application Support, never a shared or iCloud location.
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        XCTAssertEqual(FileProfilePhotoStore.live().directory, appSupport.appendingPathComponent("ProfilePhoto", isDirectory: true))
    }

    func testRemovingThePhotoDeletesItAndOwesTheRemoval() throws {
        let store = FileProfilePhotoStore(directory: directory)
        try store.setPhoto(ProfilePhotoFixtures.jpeg())

        try store.removePhoto()

        XCTAssertNil(store.photo())
        XCTAssertEqual(store.record().pendingChange, .remove)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("photo.jpg").path))
    }

    func testOnlyTheChangeTheAccountTookIsMarkedSaved() throws {
        let store = FileProfilePhotoStore(directory: directory)
        let first = try store.setPhoto(ProfilePhotoFixtures.jpeg(.red))
        try store.setPhoto(ProfilePhotoFixtures.jpeg(.blue))

        try store.completeChange(revision: first)
        XCTAssertEqual(store.record().pendingChange, .upload, "the newer photo is still owed")

        try store.completeChange(revision: store.record().revision)
        XCTAssertNil(store.record().pendingChange)
    }

    func testAdoptingTheAccountsImageOnlyFillsAnEmptyPhone() throws {
        let store = FileProfilePhotoStore(directory: directory)
        let accountImage = ProfilePhotoFixtures.jpeg(.green)

        XCTAssertTrue(try store.adopt(accountImage, from: "user_a"))
        XCTAssertEqual(store.photo(), accountImage)
        XCTAssertNil(store.record().pendingChange, "an adopted image owes the account nothing")
        XCTAssertEqual(store.record().adoptionCheckedFor, "user_a")

        let mine = ProfilePhotoFixtures.jpeg(.red)
        try store.setPhoto(mine)
        XCTAssertFalse(try store.adopt(accountImage, from: "user_a"), "the phone's photo wins")
        XCTAssertEqual(store.photo(), mine)
        try store.removePhoto()
        XCTAssertFalse(try store.adopt(accountImage, from: "user_a"), "a removal still owed is not undone")
    }

    func testRequeueOwesThePhotoAgain() throws {
        let store = FileProfilePhotoStore(directory: directory)
        let revision = try store.setPhoto(ProfilePhotoFixtures.jpeg())
        try store.completeChange(revision: revision)

        try store.requeueUpload()

        XCTAssertEqual(store.record().pendingChange, .upload)
    }

    func testEraseLeavesNothingBehind() throws {
        let store = FileProfilePhotoStore(directory: directory)
        try store.setPhoto(ProfilePhotoFixtures.jpeg())
        try store.markAdoptionChecked(for: "user_a")

        try store.erase()

        XCTAssertNil(store.photo())
        XCTAssertNil(store.record().pendingChange)
        XCTAssertNil(store.record().adoptionCheckedFor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNoThrow(try store.erase(), "erasing twice is safe")
    }

    func testAPhotoWithADamagedRecordIsOwedToTheAccount() throws {
        let store = FileProfilePhotoStore(directory: directory)
        let revision = try store.setPhoto(ProfilePhotoFixtures.jpeg())
        try store.completeChange(revision: revision)
        try Data("{".utf8).write(to: directory.appendingPathComponent("record.json"))

        XCTAssertEqual(store.record().pendingChange, .upload)
    }
}

// MARK: - The account's copy

final class ProfilePhotoSyncTests: XCTestCase {
    private static let account = "user_photo"

    private func makeSync(store: InMemoryProfilePhotoStore, remote: FakeAccountProfileImageService) -> ProfilePhotoSync {
        ProfilePhotoSync(store: store, remote: remote)
    }

    func testANewPhotoUploadsAndIsThenSaved() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account)
        let jpeg = ProfilePhotoFixtures.jpeg()
        try store.setPhoto(jpeg)

        let outcome = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .uploaded)
        let image = await remote.image
        XCTAssertEqual(image, jpeg)
        XCTAssertNil(store.record().pendingChange)
        XCTAssertEqual(store.record().adoptionCheckedFor, Self.account, "a fresh sign-in never adopts over it later")
    }

    func testReplacingThePhotoUploadsTheNewOne() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account)
        let sync = makeSync(store: store, remote: remote)
        try store.setPhoto(ProfilePhotoFixtures.jpeg(.red))
        _ = try await sync.run(linkedAccount: Self.account) { true }

        let replacement = ProfilePhotoFixtures.jpeg(.blue)
        try store.setPhoto(replacement)
        _ = try await sync.run(linkedAccount: Self.account) { true }

        let image = await remote.image
        XCTAssertEqual(image, replacement)
        let setCalls = await remote.setCalls
        XCTAssertEqual(setCalls, 2)
    }

    func testAPhotoChangedDuringItsUploadStaysOwed() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account)
        let newer = ProfilePhotoFixtures.jpeg(.blue)
        try store.setPhoto(ProfilePhotoFixtures.jpeg(.red))
        await remote.duringNextUpload { _ = try? store.setPhoto(newer) }

        let outcome = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .newerChangeOwed)
        XCTAssertEqual(store.record().pendingChange, .upload)
        XCTAssertEqual(store.photo(), newer)
    }

    func testRemovingThePhotoRemovesTheAccountsImage() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account, image: ProfilePhotoFixtures.jpeg())
        try store.removePhoto()

        let outcome = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .removed)
        let image = await remote.image
        XCTAssertNil(image)
        XCTAssertNil(store.record().pendingChange)
    }

    func testOfflineTheChangeStaysOwedAndThePhotoStays() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account)
        await remote.setOffline(true)
        let jpeg = ProfilePhotoFixtures.jpeg()
        try store.setPhoto(jpeg)
        let sync = makeSync(store: store, remote: remote)

        do {
            _ = try await sync.run(linkedAccount: Self.account) { true }
            XCTFail("offline, the upload fails")
        } catch {
            XCTAssertEqual(error as? AccountProfileImageError, .unreachable)
        }
        XCTAssertEqual(store.photo(), jpeg, "the phone's photo is never lost")
        XCTAssertEqual(store.record().pendingChange, .upload)

        await remote.setOffline(false)
        let outcome = try await sync.run(linkedAccount: Self.account) { true }
        XCTAssertEqual(outcome, .uploaded, "a later run takes it")
    }

    func testASessionForAnotherAccountUploadsNothing() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: "someone_else")
        try store.setPhoto(ProfilePhotoFixtures.jpeg())

        do {
            _ = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { true }
            XCTFail("another account's session is refused")
        } catch {
            XCTAssertEqual(error as? AccountProfileImageError, .notSignedIn)
        }
        let image = await remote.image
        XCTAssertNil(image)
        XCTAssertEqual(store.record().pendingChange, .upload)
    }

    func testAFreshInstallAdoptsTheAccountsImageOnce() async throws {
        let store = InMemoryProfilePhotoStore()
        let accountImage = ProfilePhotoFixtures.quadrants(width: 800, height: 600).jpegData(compressionQuality: 0.9)!
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account, image: accountImage)
        let sync = makeSync(store: store, remote: remote)

        let outcome = try await sync.run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .adopted)
        let stored = try XCTUnwrap(store.photo())
        XCTAssertEqual(UIImage(data: stored)?.cgImage?.width, 512, "adopted as a stored photo: square, downscaled")
        XCTAssertNil(store.record().pendingChange, "adopting uploads nothing back")

        // Later runs leave the account alone.
        let again = try await sync.run(linkedAccount: Self.account) { true }
        XCTAssertEqual(again, .nothingToDo)
        let reads = await remote.readCalls
        XCTAssertEqual(reads, 1)
        let setCalls = await remote.setCalls
        XCTAssertEqual(setCalls, 0)
    }

    func testAnAccountWithNoImageIsCheckedOnce() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account)
        let sync = makeSync(store: store, remote: remote)

        _ = try await sync.run(linkedAccount: Self.account) { true }
        // The image set on another phone afterwards is not pulled in here: the phone's choice stands.
        await remote.setImage(ProfilePhotoFixtures.jpeg())
        let outcome = try await sync.run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertNil(store.photo())
        let reads = await remote.readCalls
        XCTAssertEqual(reads, 1)
    }

    func testAnImageFetchedAfterTheAccountWentAwayIsDropped() async throws {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account, image: ProfilePhotoFixtures.jpeg())

        let outcome = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { false }

        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertNil(store.photo(), "nothing is written back onto an erased or signed-out phone")
        XCTAssertNil(store.record().adoptionCheckedFor)
    }

    func testAPhotoAlreadyOnThePhoneIsNotReplacedByTheAccounts() async throws {
        let mine = ProfilePhotoFixtures.jpeg(.red)
        let store = InMemoryProfilePhotoStore(photo: mine)
        let remote = FakeAccountProfileImageService(sessionUserId: Self.account, image: ProfilePhotoFixtures.jpeg(.blue))

        let outcome = try await makeSync(store: store, remote: remote).run(linkedAccount: Self.account) { true }

        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertEqual(store.photo(), mine)
        let reads = await remote.readCalls
        XCTAssertEqual(reads, 0)
    }
}

// MARK: - The model the screens use

@MainActor
final class ProfilePhotoModelTests: XCTestCase {
    func testSettingAPhotoShowsItAtOnceAndCopiesItToTheAccount() async {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: "user_m")
        let model = ProfilePhotoModel(store: store, sync: ProfilePhotoSync(store: store, remote: remote)) { "user_m" }
        XCTAssertFalse(model.hasPhoto)

        model.setPhoto(ProfilePhotoFixtures.jpeg())
        XCTAssertTrue(model.hasPhoto, "shown before any upload")
        await model.syncNow()

        let setCalls = await remote.setCalls
        XCTAssertEqual(setCalls, 1)
        XCTAssertNil(store.record().pendingChange)
    }

    func testRemovingThePhotoShowsThePlaceholderAndClearsTheAccount() async {
        let store = InMemoryProfilePhotoStore(photo: ProfilePhotoFixtures.jpeg())
        let remote = FakeAccountProfileImageService(sessionUserId: "user_m", image: ProfilePhotoFixtures.jpeg())
        let model = ProfilePhotoModel(store: store, sync: ProfilePhotoSync(store: store, remote: remote)) { "user_m" }
        XCTAssertTrue(model.hasPhoto)

        model.removePhoto()
        await model.syncNow()

        XCTAssertFalse(model.hasPhoto)
        let image = await remote.image
        XCTAssertNil(image)
    }

    func testWithNoAccountThePhotoStaysOnThePhone() async {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: "user_m")
        let model = ProfilePhotoModel(store: store, sync: ProfilePhotoSync(store: store, remote: remote)) { nil }

        model.setPhoto(ProfilePhotoFixtures.jpeg())
        await model.syncNow()

        XCTAssertTrue(model.hasPhoto)
        let setCalls = await remote.setCalls
        XCTAssertEqual(setCalls, 0)
        XCTAssertEqual(store.record().pendingChange, .upload, "uploaded once an account is linked")
    }

    func testABuildWithNoAccountProviderKeepsThePhotoLocal() {
        let store = InMemoryProfilePhotoStore()
        let model = ProfilePhotoModel(store: store, sync: nil) { "user_m" }
        model.setPhoto(ProfilePhotoFixtures.jpeg())
        XCTAssertTrue(model.hasPhoto)
    }

    func testAFreshSignInShowsTheAdoptedImage() async {
        let store = InMemoryProfilePhotoStore()
        let remote = FakeAccountProfileImageService(sessionUserId: "user_m", image: ProfilePhotoFixtures.jpeg(.green))
        let model = ProfilePhotoModel(store: store, sync: ProfilePhotoSync(store: store, remote: remote)) { "user_m" }

        await model.syncNow()

        XCTAssertTrue(model.hasPhoto)
    }

    func testReloadShowsAnErasedPhoneAsEmpty() throws {
        let store = InMemoryProfilePhotoStore(photo: ProfilePhotoFixtures.jpeg())
        let model = ProfilePhotoModel(store: store, sync: nil) { nil }
        XCTAssertTrue(model.hasPhoto)

        try store.erase()
        model.reload()

        XCTAssertFalse(model.hasPhoto)
    }

    func testTheModelCarriesTheContainersStoreAndAccountLink() throws {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "ProfilePhotoModelTests.\(UUID().uuidString)")!)
        let model = ProfilePhotoModel(services: .mock(), appState: appState)
        XCTAssertFalse(model.hasPhoto)
    }
}

final class CameraAvailabilityTests: XCTestCase {
    func testTakePhotoIsOfferedOnlyWithACameraTheUserHasNotRefused() {
        XCTAssertEqual(CameraAvailability.resolve(hasCamera: false, authorization: .authorized), .unavailable,
                       "the Simulator has no camera")
        XCTAssertEqual(CameraAvailability.resolve(hasCamera: true, authorization: .notDetermined), .available,
                       "the permission prompt waits for Take Photo")
        XCTAssertEqual(CameraAvailability.resolve(hasCamera: true, authorization: .authorized), .available)
        XCTAssertEqual(CameraAvailability.resolve(hasCamera: true, authorization: .denied), .deniedInSettings)
        XCTAssertEqual(CameraAvailability.resolve(hasCamera: true, authorization: .restricted), .unavailable)
    }

    func testTheCameraUsageStringSaysWhy() throws {
        let description = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        XCTAssertTrue(description.contains("profile photo"))
    }
}

// MARK: - Sign-out, erasing and account deletion

final class ProfilePhotoTeardownTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ProfilePhotoTeardownTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private static let identity = AccountIdentity(userId: "user_photo_teardown", email: "sam@example.com", method: .google)

    private struct Fixture {
        let stack: SyncTestStack
        let server: FakeAccountServer
        let engine: SyncEngine
        let photoStore: InMemoryProfilePhotoStore
        let profileImage: FakeAccountProfileImageService
        let service: AccountDeletionService
        let appState: AppState
    }

    private func makeFixture() async throws -> Fixture {
        let stack = SyncTestStack()
        let user = SyncFixtures.user()
        try await stack.users.save(user)
        let server = FakeAccountServer()
        let cursor = InMemorySyncCursorStore()
        let engine = stack.engine(server, cursor: cursor)
        try await engine.sync()
        let photo = ProfilePhotoFixtures.jpeg()
        let photoStore = InMemoryProfilePhotoStore(photo: photo)
        let profileImage = FakeAccountProfileImageService(sessionUserId: Self.identity.userId, image: photo)
        let service = AccountDeletionService(
            userService: stack.users,
            workoutLogService: stack.logs,
            sessionPolicyStore: stack.policies,
            activeSessionStore: stack.activeSessions,
            authService: MockAuthService(),
            outsideActivityService: stack.activities,
            account: AccountDeletionService.AccountTeardown(
                remote: server,
                auth: StubAccountAuthService(isConfigured: true, identity: Self.identity, token: "session-token"),
                syncStore: stack.store,
                cursorStore: cursor,
                engine: engine,
                defaults: defaults,
                profileImage: profileImage
            ),
            profilePhotoStore: photoStore
        )
        let appState = try await MainActor.run { () throws -> AppState in
            let state = AppState(userDefaults: defaults)
            try state.linkAccount(Self.identity)
            state.isOnboarded = true
            return state
        }
        return Fixture(
            stack: stack, server: server, engine: engine, photoStore: photoStore, profileImage: profileImage,
            service: service, appState: appState
        )
    }

    func testDeletingTheAccountLeavesNoPhotoOnTheServerOrThePhone() async throws {
        let fixture = try await makeFixture()

        try await fixture.service.deleteAccount(appState: fixture.appState)

        let image = await fixture.profileImage.image
        XCTAssertNil(image, "the account's profile image is removed before the account is deleted")
        XCTAssertNil(fixture.photoStore.photo())
        XCTAssertNil(fixture.photoStore.record().pendingChange)
        let deleteCalls = await fixture.server.deleteCalls
        XCTAssertEqual(deleteCalls, 1)
    }

    func testADeletionThatStopsWithNothingDeletedPutsThePhotoBack() async throws {
        let fixture = try await makeFixture()
        await fixture.server.failDeletion(with: .rejected(code: "deletion_unavailable", message: "Deletion is unavailable."))

        do {
            try await fixture.service.deleteAccount(appState: fixture.appState)
            XCTFail("deletion is unavailable")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .unavailable)
        }

        XCTAssertNotNil(fixture.photoStore.photo(), "the phone keeps its photo")
        XCTAssertEqual(fixture.photoStore.record().pendingChange, .upload, "the account is owed its image again")
        let restored = try await ProfilePhotoSync(store: fixture.photoStore, remote: fixture.profileImage)
            .run(linkedAccount: Self.identity.userId) { true }
        XCTAssertEqual(restored, .uploaded)
    }

    func testSigningOutErasesThePhonesPhotoAndKeepsTheAccountsImage() async throws {
        let fixture = try await makeFixture()
        let signOut = AccountSignOutService(
            engine: fixture.engine, syncStore: fixture.stack.store, eraser: fixture.service,
            profilePhotoSync: ProfilePhotoSync(store: fixture.photoStore, remote: fixture.profileImage)
        )

        try await signOut.signOut(appState: fixture.appState)

        XCTAssertNil(fixture.photoStore.photo())
        let image = await fixture.profileImage.image
        XCTAssertNotNil(image, "like the rest of the account's data, the image stays with the account")
        let removeCalls = await fixture.profileImage.removeCalls
        XCTAssertEqual(removeCalls, 0)
    }

    func testTheUploadBeforeSigningOutTakesAWaitingPhoto() async throws {
        let fixture = try await makeFixture()
        let newer = ProfilePhotoFixtures.jpeg(.blue)
        try fixture.photoStore.setPhoto(newer)
        let signOut = AccountSignOutService(
            engine: fixture.engine, syncStore: fixture.stack.store, eraser: fixture.service,
            profilePhotoSync: ProfilePhotoSync(store: fixture.photoStore, remote: fixture.profileImage)
        )

        let result = await signOut.uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .allSaved)
        let image = await fixture.profileImage.image
        XCTAssertEqual(image, newer)
    }

    func testAPhotoThatCannotUploadBeforeSigningOutIsAnUnsavedChange() async throws {
        let fixture = try await makeFixture()
        try fixture.photoStore.setPhoto(ProfilePhotoFixtures.jpeg(.blue))
        await fixture.profileImage.setOffline(true)
        let signOut = AccountSignOutService(
            engine: fixture.engine, syncStore: fixture.stack.store, eraser: fixture.service,
            profilePhotoSync: ProfilePhotoSync(store: fixture.photoStore, remote: fixture.profileImage)
        )

        let result = await signOut.uploadPendingChanges(appState: fixture.appState)

        XCTAssertEqual(result, .unsavedChanges)
        XCTAssertNotNil(fixture.photoStore.photo(), "nothing is erased until the user chooses to sign out anyway")
    }
}

// MARK: - Where the photo never goes

/// The profile photo goes to the phone's own container and the account's profile image, nowhere else:
/// no Coach, telemetry or Waitlist source may name it.
final class ProfilePhotoBoundaryGuardTests: XCTestCase {
    func testNoCoachTelemetryOrWaitlistCodeReadsTheProfilePhoto() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepTodayTests
            .deletingLastPathComponent() // RepToday
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository
        let app = repository.appendingPathComponent("ios/RepToday/RepToday")
        let guarded = [
            app.appendingPathComponent("Services/Coach"),
            app.appendingPathComponent("Services/Analytics"),
            app.appendingPathComponent("Views/Coach"),
            repository.appendingPathComponent("convex"),
            repository.appendingPathComponent("proxy/src"),
            repository.appendingPathComponent("tools/waitlist"),
        ]
        // Built by concatenation so this guard's own source is not a match.
        let names = ["Profile" + "Photo", "profile" + "Photo", "profile" + "Image", "Profile" + "Image", "setProfile" + "Image"]
        var offenders: [String] = []
        for directory in guarded {
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where ["swift", "ts", "js", "py"].contains(file.pathExtension) {
                guard !file.path.contains("/node_modules/"), !file.path.contains("/_generated/"),
                      let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                if names.contains(where: source.contains) {
                    offenders.append(file.path.replacingOccurrences(of: repository.path + "/", with: ""))
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Services/Coach").path),
                      "the guard must be scanning real sources")
        XCTAssertEqual(offenders, [], "the profile photo must never reach the Coach, telemetry or the Waitlist")
    }
}
