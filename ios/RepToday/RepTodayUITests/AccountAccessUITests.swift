import XCTest

/// Profile -> Account after onboarding (M3): the signed-in account and where its data stands.
final class AccountAccessUITests: XCTestCase {
    func testProfileReachesTheAccountScreenAfterOnboarding() {
        continueAfterFailure = false
        let app = TestApp(self)
        app.terminate()
        app.launch(.optedOutWithNoProbe)
        defer { app.terminate() }

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()
        let account = app.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        XCTAssertTrue(account.isHittable)
        account.tap()

        let note = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Premium purchases and restores use your App Store account"
        )).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Sign in with Apple"].exists, "signing in is no longer optional, so nothing offers it here")
        XCTAssertFalse(app.staticTexts["Welcome to Rep Today"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "profile-account-status"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
