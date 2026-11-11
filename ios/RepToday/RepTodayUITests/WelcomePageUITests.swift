import XCTest

/// US-HO01: the Welcome Page on a real cold launch - shown before Today with the day and the Cycle strip,
/// passed with "Let's go", and never shown again on a resume from the background.
final class WelcomePageUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAColdLaunchOpensOnTheWelcomePageAndAResumeDoesNot() {
        let app = TestApp(self)
        app.terminate()
        app.launch(.optedOutWithNoProbe, answersHealthPrompt: false, passesWelcomePage: false)
        defer { app.terminate() }

        let letsGo = app.buttons["Let's go"]
        XCTAssertTrue(letsGo.waitForExistence(timeout: 20), "the Welcome Page replaces the launch spinner")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Today is '")).firstMatch.exists,
            "the page names today's Training Day or Rest Day"
        )
        XCTAssertTrue(
            app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'This cycle: '")).firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'This cycle: '")).firstMatch.exists,
            "the page shows the Cycle strip"
        )
        attach(XCUIScreen.main.screenshot(), named: "welcome-page.png")

        app.passWelcomePage()
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected, "Let's go opens Today")
        XCTAssertFalse(letsGo.exists)

        app.backgroundAndResume()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(letsGo.waitForExistence(timeout: 3), "a resume from the background never shows the page")
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
