import XCTest

/// Exercises post-onboarding navigation without starting Apple's authorization ceremony.
final class AccountAccessUITests: XCTestCase {
    func testProfileReachesOptionalAppleSignInAfterOnboarding() {
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

        let signIn = app.buttons["Sign in with Apple"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.isHittable)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Premium purchases and restores use your App Store account"
        )).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Welcome to Rep Today"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "profile-account-optional-apple-sign-in"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
