import XCTest

/// Sign Out driven through the running app (US-SO01/US-SO02), out of process: Profile -> Settings ->
/// Sign Out, its confirmation and the decision 14 warning, then back to Welcome and in again through
/// its "Already have an account? Sign in" link.
///
/// These launches sign in on the device only and have no account backend, so whatever the outbox holds
/// can never reach an account: every sign-out here meets the warning, which is what lets one suite
/// press both dialogs. The upload that succeeds is walked against the development backend
/// (`artifacts/reports/sign-out/validation.md`).
final class SignOutUITests: XCTestCase {

    private var app: TestApp!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = TestApp(self)
        app.terminate()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testSignOutConfirmsWarnsAndReturnsToWelcome() {
        resetThroughAccountDeletion(in: app)
        app.buttons["Continue"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        finishOnboardingThroughSaveYourPlan(in: app)
        app.answerHealthPromptIfPresented()
        openSettings()

        // Decision 13: Sign Out sits above Delete Account.
        let signOutRow = app.buttons["Sign Out"]
        scrollUntilHittable(signOutRow, in: app)
        XCTAssertTrue(signOutRow.isHittable, "Settings has no reachable Sign Out row")
        let deleteRow = app.buttons["Delete Account"]
        scrollUntilHittable(deleteRow, in: app)
        XCTAssertLessThan(signOutRow.frame.minY, deleteRow.frame.minY, "Sign Out is not above Delete Account")
        attachScreenshot(named: "01-settings-sign-out-row")

        // Cancel on the confirmation changes nothing.
        signOutRow.tap()
        let confirm = app.alerts["Sign out of Rep Today?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no sign-out confirmation")
        XCTAssertTrue(confirm.buttons["Cancel"].exists)
        attachScreenshot(named: "02-sign-out-confirmation")
        confirm.buttons["Cancel"].tap()
        XCTAssertTrue(signOutRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists, "Cancel left the user signed in")

        // Confirming meets the warning, and Cancel there changes nothing either.
        signOutRow.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.buttons["Sign Out"].tap()
        let warning = app.alerts["Recent workouts aren't saved"]
        XCTAssertTrue(warning.waitForExistence(timeout: 30), "changes that cannot upload were not warned about")
        XCTAssertTrue(warning.buttons["Sign Out Anyway"].exists)
        attachScreenshot(named: "03-unsaved-workouts-warning")
        warning.buttons["Cancel"].tap()
        XCTAssertTrue(signOutRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists, "Cancel on the warning left the user signed in")

        // Sign Out Anyway erases the phone and lands on Welcome, offering to sign back in.
        signOutRow.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.buttons["Sign Out"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 30))
        warning.buttons["Sign Out Anyway"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 20), "signing out did not return to Welcome")
        XCTAssertTrue(app.buttons["Already have an account? Sign in"].exists, "Welcome does not offer signing back in")
        XCTAssertFalse(app.tabBars.buttons["Profile"].exists)
        attachScreenshot(named: "04-welcome-after-sign-out")
    }

    /// Welcome's link goes straight to the sign-in; Back returns to Welcome; and an account with no plan
    /// (every account here, with no backend to hold one) goes on to the questions and finishes from the
    /// last of them, without a second sign-in.
    func testWelcomeSignInWithNoPlanContinuesIntoTheQuestions() {
        resetThroughAccountDeletion(in: app)
        let link = app.buttons["Already have an account? Sign in"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        attachScreenshot(named: "05-welcome-sign-in-link")

        link.tap()
        XCTAssertTrue(app.staticTexts["Save your plan"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 5), "Back did not return to Welcome")

        link.tap()
        finishOnboardingThroughSaveYourPlan(in: app)
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15), "an account with no plan did not continue into the questions")
        name.tap()
        name.typeText("Riley\n")
        let finish = app.buttons["Finish"]
        for _ in 0..<8 where !finish.exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "the last question does not finish")
        XCTAssertFalse(app.staticTexts["Save your plan"].exists, "signed in already, so no second sign-in")
        finish.tap()
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "finishing did not land on Today")
    }

    private func openSettings() {
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
    }

    /// Files the running app's screen as a `.keepAlways` `.xcresult` attachment, so a reviewer opens a
    /// picture of the actual sign-out flow on a green run.
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
