import XCTest

/// The account-deletion path driven through the running app (US-AD01/US-AD03/US-AD04), out of
/// process: Profile tab -> Settings -> Delete Account -> confirm -> lands back on onboarding.
///
/// This is the one thing the in-process view-model and service tests cannot exercise - a real finger
/// pressing the shipped destructive control and the router actually swapping to onboarding. It launches
/// through the shared `TestApp` wrapper (`RepTodayUITests/TestApp.swift`), which owns the only
/// `XCUIApplication` in the bundle, naming the `.optedOutWithNoProbe` posture so the run is off the
/// telemetry wire (there is no account-deletion event, but every launch here must still carry a
/// posture - `UITestLaunchGuardTests` fails the build otherwise).
final class AccountDeletionUITests: XCTestCase {

    private var app: TestApp!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = TestApp(self)
        // The app process survives from a previous case; terminate a leftover before this launch.
        app.terminate()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testDeleteAccountFromSettingsRoutesBackToOnboarding() {
        app.launch(.optedOutWithNoProbe) // onboarded, lands on the main tabs

        // Profile -> Settings, the way a user reaches the control.
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Profile has no Settings row")
        settings.tap()

        // US-AD01: the destructive row is present and reachable by a finger.
        let deleteRow = app.buttons["Delete Account"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10), "Settings has no Delete Account control")
        XCTAssertTrue(deleteRow.isHittable, "the Delete Account row is not reachable by a finger")
        deleteRow.tap()

        // US-AD04: the confirmation alert, with a destructive confirm distinct from Cancel.
        let confirm = app.alerts.buttons["Delete Account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no confirmation alert was presented")
        XCTAssertTrue(
            app.alerts.buttons["Cancel"].exists,
            "the confirmation has no non-destructive Cancel"
        )
        confirm.tap()

        // US-AD03: the teardown routes back to onboarding's first screen.
        XCTAssertTrue(
            app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 20),
            "deleting the account did not route back to onboarding"
        )
        // And the main tabs are gone - there is no Profile tab on the onboarding flow.
        XCTAssertFalse(
            app.tabBars.buttons["Profile"].exists,
            "the main tabs were still present after account deletion"
        )
    }

    /// US-AD04: cancelling leaves the user on Settings with their data intact - the app stays on the
    /// main tabs and does not route to onboarding.
    func testCancellingDeletionLeavesTheUserSignedIn() {
        app.launch(.optedOutWithNoProbe)

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Profile has no Settings row")
        settings.tap()

        let deleteRow = app.buttons["Delete Account"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10), "Settings has no Delete Account control")
        deleteRow.tap()

        let cancel = app.alerts.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "no confirmation alert was presented")
        cancel.tap()

        // Still on Settings - the toggle from the Privacy section is present, and onboarding is not.
        XCTAssertTrue(
            app.switches["Share anonymous usage data"].waitForExistence(timeout: 10),
            "cancelling should leave the user on the Settings screen"
        )
        XCTAssertFalse(
            app.staticTexts["Welcome to Rep Today"].exists,
            "cancelling must not route to onboarding"
        )
    }
}
