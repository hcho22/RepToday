import SwiftUI
import XCTest
@testable import RepToday

@MainActor
final class AccountAccessEvidenceTests: XCTestCase {
    func testAccountShowsOptionalSignInOrExistingSignedInStatus() async throws {
        for identifier in [nil, "synthetic-apple-id"] as [String?] {
            let model = AccountViewModel(authService: MockAuthService(userIdentifier: identifier))
            let surface = HostedSurface.host(
                NavigationStack { AccountView(viewModel: model) }, size: CGSize(width: 390, height: 844)
            )
            defer { surface.window.isHidden = true }
            surface.window.windowScene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            surface.window.makeKeyAndVisible()
            await model.load()
            try await Task.sleep(nanoseconds: 700_000_000)
            surface.host.view.layoutIfNeeded()
            let labels = AccessibilityTree.labels(in: surface.host.view)
            XCTAssertTrue(labels.contains { $0.contains("Sign in is optional") })
            if identifier == nil {
                XCTAssertNotNil(AccessibilityTree.element(labeled: "Sign in with Apple", in: surface.host.view))
                XCTAssertFalse(labels.contains("Signed in with Apple"))
            } else {
                XCTAssertTrue(labels.contains("Signed in with Apple"))
                XCTAssertNil(AccessibilityTree.element(labeled: "Sign in with Apple", in: surface.host.view))
            }
            try EvidenceOutput.write(
                HostedSurface.capture(surface.host.view, size: surface.host.view.bounds.size),
                named: identifier == nil ? "account-sign-in.png" : "account-signed-in.png",
                for: "premium-access"
            )
        }
    }
}
