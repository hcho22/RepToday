import XCTest

/// Flows several suites walk the same way, shared so they cannot drift: scrolling a lazy list until a row
/// is reachable, playing a session to its end, moving the Rotation to a given Training Day, and getting
/// past a launch that has no profile to show.
extension XCTestCase {

    /// Walks the onboarding flow from wherever it is to "Save your plan" on the primary button, then
    /// signs in there with an email code - the stub sign-in every XCUITest launch uses accepts the one
    /// code it advertises - which finishes onboarding (US-AU02).
    func finishOnboardingThroughSaveYourPlan(in app: TestApp, file: StaticString = #filePath, line: UInt = #line) {
        let email = app.buttons["Continue with email"]
        for _ in 0..<12 where !email.exists {
            guard app.buttons["Continue"].waitForExistence(timeout: 5) else { break }
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(email.waitForExistence(timeout: 5), "onboarding never reached Save your plan", file: file, line: line)
        email.tap()
        let address = app.textFields["Email address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), file: file, line: line)
        address.tap()
        address.typeText("uitest@example.com")
        app.buttons["Send code"].tap()
        let code = app.textFields["Code from your email"]
        XCTAssertTrue(code.waitForExistence(timeout: 10), "the code screen never appeared", file: file, line: line)
        code.tap()
        code.typeText("424242")
        app.buttons["Sign in"].tap()
    }

    /// Drags the screen upward until `element` exists and is reachable by a finger. Lazy lists keep
    /// rows below the fold out of the tree entirely, so existence alone is not enough to wait on.
    func scrollUntilHittable(_ element: XCUIElement, in app: TestApp, maxSwipes: Int = 10) {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
        }
    }

    /// Plays the session on screen to its completion screen, advancing every set early (each early
    /// advance records the set as done), then closes it back to Today.
    func playSessionToCompletion(in app: TestApp, file: StaticString = #filePath, line: UInt = #line) {
        let completion = app.staticTexts["You showed up."]
        for _ in 0..<200 where !completion.exists {
            for choice in ["Got it", "Start session"] where app.buttons[choice].exists {
                app.buttons[choice].tap()
            }
            if app.buttons["Skip rest"].exists {
                app.buttons["Skip rest"].tap()
            } else if let advance = ["Done", "Complete set", "Finish exercise", "Finish session"]
                .map({ app.buttons[$0] })
                .first(where: { $0.exists && $0.isHittable }) {
                advance.tap()
            } else if app.buttons["Start hold"].exists {
                app.buttons["Start hold"].tap()
            } else {
                _ = app.buttons["Done"].waitForExistence(timeout: 1)
            }
        }
        XCTAssertTrue(completion.exists, "the session never reached its completion screen", file: file, line: line)
        for close in ["Done", "Close"] where app.buttons[close].waitForExistence(timeout: 3) {
            app.buttons[close].tap()
            break
        }
    }

    /// Plays short sessions (or trains anyway on a Rest Day) until Today names `day`, so a suite does not
    /// depend on the history an earlier suite left on the simulator. Returns whether it got there.
    @discardableResult
    func advanceToTrainingDay(_ day: String, in app: TestApp, maxSessions: Int = 4) -> Bool {
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(day): ")).firstMatch
        for _ in 0...maxSessions {
            if title.waitForExistence(timeout: 10) { return true }
            if app.buttons["Train anyway"].exists {
                app.buttons["Train anyway"].tap()
                continue
            }
            guard app.buttons["5 minute session"].waitForExistence(timeout: 10) else { return false }
            app.buttons["5 minute session"].tap()
            app.buttons["Start"].tap()
            playSessionToCompletion(in: app)
        }
        return title.exists
    }

    /// An onboarded launch on an install with no saved profile (a fresh simulator, or one a deletion test
    /// just emptied) opens on an empty Today. Walk onboarding with its defaults so the launch lands on a
    /// real session, as the suite expects.
    func onboardIfNoProfile(in app: TestApp) {
        guard app.staticTexts["No profile found yet."].waitForExistence(timeout: 8) else { return }
        app.terminate()
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("Riley\n")
        let startMoving = app.buttons["Start moving"]
        for _ in 0..<8 where !startMoving.exists {
            app.buttons["Continue"].tap()
        }
        startMoving.tap()
        app.answerHealthPromptIfPresented()
    }

    /// Starts from a clean slate through the product's own account deletion, so a suite never inherits a
    /// profile, history or safety flag an earlier suite left on the simulator. Ends on onboarding.
    func resetThroughAccountDeletion(in app: TestApp) {
        app.terminate()
        app.launch(.optedOutWithNoProbe)
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()
        app.buttons["Settings"].tap()
        let delete = app.buttons["Delete Account"]
        scrollUntilHittable(delete, in: app)
        delete.tap()
        let confirm = app.alerts.buttons["Delete Account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no deletion confirmation")
        confirm.tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15), "deletion did not route to onboarding")
    }
}
