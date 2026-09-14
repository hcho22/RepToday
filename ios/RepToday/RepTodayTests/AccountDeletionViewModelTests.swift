import SwiftUI
import UIKit
import XCTest
@testable import RepToday

/// Tests for `AccountDeletionViewModel` (US-AD04 confirmation + re-entrancy, US-AD05 Apple-credential
/// guidance decision). The teardown is stubbed so these assert only the presentation logic: what the
/// confirmation names, that a confirm runs the teardown at most once, and that the post-deletion
/// Apple-ID guidance is armed only in the genuine Sign in with Apple case.
@MainActor
final class AccountDeletionViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var renderWindows: [UIWindow] = []
    private let confirmationSize = CGSize(width: 393, height: 852)
    private let evidenceStory = "account-deletion-subscription-warning"

    override func setUp() {
        super.setUp()
        suiteName = "AccountDeletionViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        renderWindows.forEach { $0.isHidden = true }
        renderWindows = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - App Store subscription warning on the shipped confirmation

    /// The local-only confirmation renders the billing warning before the destructive action. This
    /// reads the production alert's live accessibility output and captures its pixels; it does not
    /// inspect SettingsView source or invoke the teardown.
    func testLocalConfirmationWarnsBeforeDestructiveAction() async throws {
        try await assertConfirmationSurface(
            auth: MockAuthService(userIdentifier: nil),
            credentialStatus: .authorized,
            expectedMessage: SettingsView.confirmMessageLocal,
            excludesAppleLink: true,
            evidenceName: "01-local-account-confirmation.png"
        )
    }

    /// The Apple-linked confirmation preserves its narrower Sign in with Apple disclosure and adds
    /// the same billing warning before the destructive action.
    func testAppleLinkedConfirmationWarnsBeforeDestructiveAction() async throws {
        try await assertConfirmationSurface(
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized,
            expectedMessage: SettingsView.confirmMessageApple,
            excludesAppleLink: false,
            evidenceName: "02-apple-linked-confirmation.png"
        )
    }

    // MARK: - US-AD05: guidance shows only in the Apple-credential case

    func testTappingResolvesAppleCaseAndPresentsConfirmation() async {
        let model = makeModel(
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized
        )
        await model.deleteAccountTapped()
        XCTAssertTrue(model.usedAppleCredential, "a stored, authorized Apple credential must read as used")
        XCTAssertTrue(model.isConfirmationPresented, "the confirmation was not presented")
    }

    func testConfirmingAnAppleAccountArmsTheGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized
        )
        await model.deleteAccountTapped()
        await model.confirmDeletion()
        XCTAssertTrue(appState.showAppleSignOutGuidance, "the Apple-ID guidance was not armed for an Apple account")
    }

    func testLocalUUIDAccountNeitherReadsAsAppleNorArmsGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: nil), // never signed in with Apple
            credentialStatus: .authorized // irrelevant: no stored identifier to query
        )
        await model.deleteAccountTapped()
        XCTAssertFalse(model.usedAppleCredential, "a local-UUID account must not read as an Apple account")
        await model.confirmDeletion()
        XCTAssertFalse(appState.showAppleSignOutGuidance, "the local-UUID case must not surface Apple guidance")
    }

    /// A stored identifier Apple no longer recognizes (`.notFound`) is treated as "no Apple credential
    /// in play", so no guidance - the guidance is for genuinely still-linked accounts.
    func testStoredIdentifierAppleReportsNotFoundShowsNoGuidance() async {
        let appState = makeAppState()
        let model = makeModel(
            appState: appState,
            auth: MockAuthService(userIdentifier: "stale-apple-id"),
            credentialStatus: .notFound
        )
        await model.deleteAccountTapped()
        XCTAssertFalse(model.usedAppleCredential)
        await model.confirmDeletion()
        XCTAssertFalse(appState.showAppleSignOutGuidance)
    }

    // MARK: - Failure surfacing: a thrown teardown must not route to onboarding and must be visible

    /// A teardown that throws leaves the user onboarded (the service's routing reset is its last step,
    /// so it never ran) and arms the failure alert, rather than silently dismissing the confirmation.
    func testTeardownFailureSurfacesAlertAndDoesNotRouteToOnboarding() async {
        let appState = makeAppState()
        appState.isOnboarded = true
        let spy = SpyAccountDeletionService()
        spy.errorToThrow = SpyTeardownError.boom
        let model = makeModel(service: spy, appState: appState, auth: MockAuthService(userIdentifier: nil))

        await model.confirmDeletion()

        XCTAssertEqual(spy.callCount, 1, "the teardown must have been attempted")
        XCTAssertTrue(model.isFailureAlertPresented, "a thrown teardown must surface the failure alert")
        XCTAssertTrue(appState.isOnboarded, "a failed teardown must not route the user to onboarding")
        XCTAssertFalse(model.isDeleting, "the re-entrancy guard must be released so the user can retry")
    }

    /// The Apple-ID guidance must not be armed when the teardown fails - it belongs only to a completed
    /// deletion that actually routed to onboarding.
    func testTeardownFailureDoesNotArmAppleGuidance() async {
        let appState = makeAppState()
        let spy = SpyAccountDeletionService()
        spy.errorToThrow = SpyTeardownError.boom
        let model = makeModel(
            service: spy,
            appState: appState,
            auth: MockAuthService(userIdentifier: "apple-user-123"),
            credentialStatus: .authorized
        )

        await model.deleteAccountTapped()
        await model.confirmDeletion()

        XCTAssertTrue(model.isFailureAlertPresented)
        XCTAssertFalse(appState.showAppleSignOutGuidance, "a failed teardown must not arm the Apple guidance")
    }

    // MARK: - US-AD04: re-entrancy

    /// Confirming twice while the first teardown is still in flight runs it exactly once.
    func testConfirmDeletionRunsTeardownOnceEvenOnDoubleTap() async {
        let spy = SpyAccountDeletionService()
        spy.block = true
        let model = makeModel(service: spy, auth: MockAuthService(userIdentifier: nil))

        let first = Task { await model.confirmDeletion() }
        let second = Task { await model.confirmDeletion() }

        // Let both invocations reach the guard: the first sets `isDeleting` and suspends in the
        // blocked teardown, the second must see the guard and return without a second call.
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(spy.callCount, 1, "the destructive teardown ran more than once on a double-tap")

        spy.release()
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(spy.callCount, 1, "a second teardown ran after the first completed")
    }

    // MARK: - Factories

    private func makeAppState() -> AppState {
        AppState(userDefaults: defaults)
    }

    private func assertConfirmationSurface(
        auth: MockAuthService,
        credentialStatus: AppleCredentialStatus,
        expectedMessage: String,
        excludesAppleLink: Bool,
        evidenceName: String
    ) async throws {
        let deletionService = SpyAccountDeletionService()
        let appState = makeAppState()
        let model = makeModel(
            service: deletionService,
            appState: appState,
            auth: auth,
            credentialStatus: credentialStatus
        )
        await model.deleteAccountTapped()

        let surface = hostConfirmationSurface(
            NavigationStack { SettingsView(deletion: model) }
                .environment(\.services, ServiceContainer.mock())
                .environment(appState)
        )
        renderWindows.append(surface.window)

        let spoken = AccessibilityTree.spokenStrings(in: surface.window)
        let warning = "Deleting your account does not cancel your App Store subscription."
        XCTAssertTrue(
            spoken.contains(expectedMessage),
            "the shipped confirmation did not speak its complete variant: \(spoken)"
        )
        XCTAssertTrue(
            spoken.contains { $0.contains(warning) },
            "the shipped confirmation did not plainly warn that App Store billing continues: \(spoken)"
        )
        XCTAssertEqual(
            spoken.contains { $0.contains("Sign in with Apple link") },
            !excludesAppleLink,
            "the confirmation drifted between the Apple-linked and local-only variants: \(spoken)"
        )
        XCTAssertNotNil(
            AccessibilityTree.element(labeled: "Delete Account", in: surface.window),
            "the warning did not appear alongside the destructive confirmation"
        )
        XCTAssertNotNil(
            AccessibilityTree.element(labeled: "Cancel", in: surface.window),
            "the confirmation lost its non-destructive escape"
        )
        XCTAssertEqual(
            deletionService.callCount,
            0,
            "presenting the warning invoked account deletion before confirmation"
        )

        let image = captureDisplayedSurface(surface.window)
        let path = try EvidenceOutput.write(image, named: evidenceName, for: evidenceStory)
        print("ACCOUNT DELETION SUBSCRIPTION WARNING EVIDENCE: \(path)")
    }

    /// `UIAlertController` uses visual-effect views. The shared offscreen `layer.render` path is the
    /// right default for tall SwiftUI evidence, but it omits that material; this surface fits on one
    /// screen, so hierarchy drawing captures the alert exactly as UIKit displays it.
    private func captureDisplayedSurface(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = HostedSurface.captureScale
        return UIGraphicsImageRenderer(size: confirmationSize, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: confirmationSize), afterScreenUpdates: true)
        }
    }

    /// Unlike the shared long-surface host, this one-screen UIKit alert must belong to the test
    /// application's live scene. That lets `drawHierarchy` composite the system material as it is
    /// actually displayed instead of asking an unattached offscreen window for a blank snapshot.
    private func hostConfirmationSurface<V: View>(
        _ view: V
    ) -> (host: UIHostingController<V>, window: UIWindow) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            preconditionFailure("the hosted confirmation needs the test application's live window scene")
        }

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: confirmationSize)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        HostedSurface.pump(for: HostedSurface.settleInterval)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (host, window)
    }

    private func makeModel(
        service: any AccountDeletionServiceProtocol = SpyAccountDeletionService(),
        appState: AppState? = nil,
        auth: MockAuthService = MockAuthService(userIdentifier: nil),
        credentialStatus: AppleCredentialStatus = .authorized
    ) -> AccountDeletionViewModel {
        AccountDeletionViewModel(
            accountDeletionService: service,
            authService: auth,
            appState: appState ?? AppState(userDefaults: defaults),
            credentialStateProvider: StubCredentialStateProvider(status: credentialStatus)
        )
    }
}

/// A stubbed credential-state provider (US-AD05) so the Apple-vs-local decision is tested without
/// AuthenticationServices or a live Apple service.
private struct StubCredentialStateProvider: AppleCredentialStateProviding {
    let status: AppleCredentialStatus
    func credentialStatus(forUserID userID: String) async -> AppleCredentialStatus { status }
}

/// A teardown spy that counts calls and can block mid-teardown, so the re-entrancy guard (US-AD04)
/// is provable: a blocked first call keeps `isDeleting` true while a second call is attempted.
private final class SpyAccountDeletionService: AccountDeletionServiceProtocol, @unchecked Sendable {
    private(set) var callCount = 0
    var block = false
    var errorToThrow: Error?
    private var continuation: CheckedContinuation<Void, Never>?

    func deleteAccount(appState: AppState) async throws {
        callCount += 1
        if block {
            await withCheckedContinuation { continuation = $0 }
        }
        if let errorToThrow {
            throw errorToThrow
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

/// A stand-in teardown failure so the view model's failure path can be driven without a real store.
private enum SpyTeardownError: Error {
    case boom
}
