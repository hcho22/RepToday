import XCTest

extension XCTestCase {

    /// Answers the Health share prompt the main tabs raise as they appear (US-N03), when it is up.
    ///
    /// Unlike a system permission alert, this sheet is a remote view presented *inside* the app's own
    /// process - its elements are children of `app` - so an ordinary query finds it and no
    /// interruption monitor is involved. `Don't Allow` is the control that is always enabled (`Allow`
    /// stays disabled until a category is switched on), and either answer would do for the suites
    /// that call this: the Health write is additive and gates nothing they assert. It is matched by
    /// its own identifier/label rather than through the sheet's navigation bar, because on some OS
    /// versions (seen on iOS 18.6) that bar carries "Health Access" only as a title label, not an
    /// identifier, so a `navigationBars["Health Access"]` query never resolves and the sheet is left
    /// standing over the screen.
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
        // The sheet only surfaces once the main tabs finish rendering, which trails the Ready Screen's
        // session generation, so on a cold or loaded machine it can appear several seconds after launch
        // returns. Poll for the dismiss control - by its stable identifier first, then by its visible
        // label as a fallback - but stop as soon as the tab bar is reachable with nothing over it, so a
        // container that already answered (no sheet ever comes) returns at once rather than waiting the
        // whole window out.
        let byIdentifier = app.buttons["UIA.Health.AuthSheet.CancelButton"]
        let byLabel = app.buttons["Don't Allow"]
        let anyTab = app.tabBars.buttons.firstMatch
        let deadline = Date().addingTimeInterval(20)
        var tabsBecameHittableAt: Date?
        var dontAllow: XCUIElement?
        while Date() < deadline {
            if byIdentifier.exists { dontAllow = byIdentifier; break }
            if byLabel.exists { dontAllow = byLabel; break }
            // A tab can become hittable just before MainTabsView's asynchronous Health request
            // presents its remote sheet. Require a short clear interval instead of returning on that
            // first frame; otherwise the helper can leave the prompt to race the test's first tap.
            // A sheet standing over the tabs resets the interval by making them non-hittable.
            if anyTab.isHittable {
                let now = Date()
                if let tabsBecameHittableAt,
                   now.timeIntervalSince(tabsBecameHittableAt) >= 2 {
                    return
                }
                tabsBecameHittableAt = tabsBecameHittableAt ?? now
            } else {
                tabsBecameHittableAt = nil
            }
            usleep(300_000)
        }
        guard let dontAllow else { return }
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
