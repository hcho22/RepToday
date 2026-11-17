import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// The profile photo on the production screens, in the dark visual direction: the Profile tab with the
/// placeholder and with a photo set (at the default and the largest text size), the Account screen
/// with a photo, and the crop screen - with what VoiceOver says asserted on the live tree. PNGs under
/// `artifacts/reports/profile-photo/`.
@MainActor
final class ProfilePhotoEvidenceTests: XCTestCase {
    private let story = EvidenceOutput.Story.profilePhoto
    private let phone = CGSize(width: 393, height: 852)

    override func tearDown() {
        HostedSurface.dismantleAllHostedWindows()
        super.tearDown()
    }

    /// A synthetic stand-in for a photo: a warm gradient with a soft light, square like a stored photo.
    private static func samplePhoto() -> Data {
        let side: CGFloat = 512
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colors = [UIColor(red: 0.98, green: 0.55, blue: 0.27, alpha: 1).cgColor,
                          UIColor(red: 0.42, green: 0.25, blue: 0.62, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            UIColor(white: 1, alpha: 0.85).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: side * 0.32, y: side * 0.18, width: side * 0.36, height: side * 0.36))
            context.cgContext.fillEllipse(in: CGRect(x: side * 0.14, y: side * 0.6, width: side * 0.72, height: side * 0.62))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func model(photo: Data?) -> ProfilePhotoModel {
        ProfilePhotoModel(store: InMemoryProfilePhotoStore(photo: photo), sync: nil) { nil }
    }

    private func profileTab(_ model: ProfilePhotoModel, dynamicTypeSize: DynamicTypeSize = .large) -> some View {
        ProfileTabView()
            .environment(\.services, ServiceContainer.mock())
            .environment(model)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
    }

    func testTheProfileTabShowsAPlaceholderUntilAPhotoIsSet() throws {
        let (host, _) = HostedSurface.host(profileTab(model(photo: nil)), size: phone)

        let button = try XCTUnwrap(AccessibilityTree.element(labeled: "Profile photo", in: host.view),
                                   "\(AccessibilityTree.labels(in: host.view))")
        XCTAssertTrue(button.accessibilityTraits.contains(.button))
        XCTAssertEqual(button.accessibilityValue, "No photo")
        XCTAssertEqual(button.accessibilityHint, "Take a photo or choose one")
        XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, Theme.Spacing.minTouchTarget)
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "profile-placeholder.png", for: story)
    }

    func testTheProfileTabShowsTheSetPhoto() throws {
        let (host, _) = HostedSurface.host(profileTab(model(photo: Self.samplePhoto())), size: phone)

        let button = try XCTUnwrap(AccessibilityTree.element(labeled: "Profile photo", in: host.view))
        XCTAssertEqual(button.accessibilityValue, "Photo set")
        XCTAssertEqual(button.accessibilityHint, "Change or remove your photo")
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Account", in: host.view), "the rows below are unchanged")
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "profile-photo-set.png", for: story)
    }

    func testThePhotoKeepsTheHeaderReadableAtTheLargestTextSize() throws {
        let size = CGSize(width: 393, height: 1100)
        let (host, _) = HostedSurface.host(profileTab(model(photo: Self.samplePhoto()), dynamicTypeSize: .accessibility5), size: size)

        XCTAssertNotNil(AccessibilityTree.element(labeled: "Profile photo", in: host.view))
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Profile", in: host.view))
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: size), named: "profile-photo-set-ax5.png", for: story)
    }

    func testWithoutTheModelTheHeaderKeepsItsPlaceholderAndNoButton() throws {
        let (host, _) = HostedSurface.host(ProfileTabView().environment(\.services, ServiceContainer.mock()), size: phone)
        XCTAssertNil(AccessibilityTree.element(labeled: "Profile photo", in: host.view))
        XCTAssertNotNil(AccessibilityTree.element(labeled: "Settings", in: host.view))
    }

    func testTheAccountScreenShowsThePhotoBesideTheAccount() throws {
        let suite = "ProfilePhotoEvidenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appState = AppState(userDefaults: defaults)
        try appState.linkAccount(AccountIdentity(userId: "user_1", email: "riley@example.com", method: .apple))
        appState.isOnboarded = true

        let (host, _) = HostedSurface.host(
            NavigationStack { AccountView() }
                .environment(\.services, ServiceContainer.mock())
                .environment(appState)
                .environment(model(photo: Self.samplePhoto())),
            size: phone
        )
        let deadline = Date().addingTimeInterval(8)
        while AccessibilityTree.element(whereLabel: { $0.contains("riley@example.com") }, in: host.view) == nil, Date() < deadline {
            HostedSurface.pump(for: 0.1)
        }
        XCTAssertNotNil(AccessibilityTree.element(whereLabel: { $0.contains("Signed in with Apple") && $0.contains("riley@example.com") }, in: host.view),
                        "the row still reads as the account: \(AccessibilityTree.labels(in: host.view))")
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "account-photo.png", for: story)
    }

    func testTheCropScreenFramesThePhotoInACircle() throws {
        let photo = ProfilePhotoProcessing.upright(UIImage(data: Self.samplePhoto())!)
        let (host, _) = HostedSurface.host(
            ProfilePhotoCropView(image: photo, onChoose: { _ in }, onCancel: {}),
            size: phone
        )

        let crop = try XCTUnwrap(AccessibilityTree.element(labeled: "Photo crop", in: host.view))
        XCTAssertTrue(crop.accessibilityTraits.contains(.adjustable), "VoiceOver zooms with swipes")
        XCTAssertEqual(crop.accessibilityValue, "100 percent zoom")
        for label in ["Cancel", "Use Photo"] {
            let button = try XCTUnwrap(AccessibilityTree.element(labeled: label, in: host.view))
            XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, Theme.Spacing.minTouchTarget)
        }
        try EvidenceOutput.write(HostedSurface.capture(host.view, size: phone), named: "crop.png", for: story)
    }
}
