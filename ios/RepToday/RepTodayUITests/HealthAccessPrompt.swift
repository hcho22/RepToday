import XCTest

extension XCTestCase {

    /// Answers the Health share prompt the main tabs raise as they appear (US-N03), when it is up.
    ///
    /// Unlike a system permission alert, this sheet is a remote view presented *inside* the app's own
    /// process - its elements are children of `app` - so an ordinary query finds it and no
    /// interruption monitor is involved. `Don't Allow` is the control that is always enabled (`Allow`
    /// stays disabled until a category is switched on), and either answer would do for the suites
    /// that call this: the Health write is additive and gates nothing they assert.
    ///
    /// Optional and bounded on purpose. The prompt only appears while the app's Health authorization
    /// is still unanswered, so a run against a container that already answered it has no sheet to
    /// dismiss and must stay green - this waits for one, answers it if it comes, and returns quietly
    /// if it does not.
    ///
    /// Shared rather than copied because two suites now have to get past the same sheet for unrelated
    /// reasons: one to photograph the ready screen it was sitting over, the other to reach the Profile
    /// tab behind it.
    func answerHealthAccessSheetIfPresented(in app: XCUIApplication) {
        let sheet = app.navigationBars["Health Access"]
        guard sheet.waitForExistence(timeout: 5) else { return }

        let dontAllow = sheet.buttons["UIA.Health.AuthSheet.CancelButton"]
        XCTAssertTrue(dontAllow.waitForExistence(timeout: 5), "the Health prompt has no dismissing control")
        dontAllow.tap()

        // Declining raises its own confirmation ("you can turn these on later in the Health app"),
        // which is one more thing standing over the screen underneath. Bounded rather than required:
        // the follow-up is the system's to keep or drop.
        let confirmation = app.alerts["Health Access"]
        if confirmation.waitForExistence(timeout: 3) {
            confirmation.buttons["OK"].tap()
        }
    }
}
