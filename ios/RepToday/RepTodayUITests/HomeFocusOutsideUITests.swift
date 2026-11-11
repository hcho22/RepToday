import XCTest

/// M2 on a real touch path (US-HO02, US-HO04, US-HO01), run on demand like the other XCUITests: Focus
/// Areas picked in onboarding and edited in Settings, an Outside Activity logged on Today that moves the
/// next Training Day at once and moves it back when deleted, and the Welcome Page on the next cold launch
/// naming the day with the Cycle strip. Screenshots are attached to the result for the visual check.
final class HomeFocusOutsideUITests: XCTestCase {

    private var app: TestApp!

    override func setUp() {
        continueAfterFailure = false
        app = TestApp(self)
    }

    func testFocusAreasOutsideActivityAndTheWelcomePage() {
        resetThroughAccountDeletion(in: app)
        defer { app.terminate() }

        // Onboarding, with Chest and Abs as Focus Areas.
        let welcome = app.buttons["Continue"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "the app did not reach onboarding")
        welcome.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        let chest = app.buttons["Chest"]
        for _ in 0..<4 where !chest.exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(chest.waitForExistence(timeout: 5), "onboarding never asked for Focus Areas")
        chest.tap()
        app.buttons["Abs"].tap()
        XCTAssertTrue(chest.isSelected)
        attach("01-onboarding-focus-areas")
        let startMoving = app.buttons["Start moving"]
        for _ in 0..<6 where !startMoving.exists {
            app.buttons["Continue"].tap()
        }
        startMoving.tap()
        app.answerHealthPromptIfPresented()

        // A new user starts at Push; play a short session so the Rotation reaches Pull.
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 20), "Today never offered a session")
        attach("02-today-with-focus")
        XCTAssertTrue(advanceToTrainingDay("Pull Day", in: app), "Today never reached Pull Day")

        // A swim works Pull, so Pull swaps behind Legs - on Today, at once.
        let logButton = app.buttons["Log outside activity"]
        scrollTo(logButton)
        attach("03-today-outside-activity-card")
        logButton.tap()
        if !app.navigationBars["Log activity"].waitForExistence(timeout: 3) {
            // A tap that landed while the scroll was still settling.
            logButton.tap()
        }
        XCTAssertTrue(app.navigationBars["Log activity"].waitForExistence(timeout: 5))
        attach("04-log-activity-sheet")
        let swim = app.buttons["Swim"]
        XCTAssertTrue(swim.waitForExistence(timeout: 5))
        swim.tap()
        XCTAssertTrue(swim.isSelected)
        attach("05-log-activity-swim")
        app.navigationBars["Log activity"].buttons["Save"].tap()
        XCTAssertNotNil(label(beginningWith: "Legs Day: ", timeout: 10), "the swim moved Pull behind Legs")
        attach("06-today-after-swim")

        // Deleting it hands Pull its day back.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Swim, '")).firstMatch
        scrollTo(row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit activity"].waitForExistence(timeout: 5))
        attach("07-edit-activity-sheet")
        let deleteRow = app.buttons["Delete activity"].firstMatch
        let form = app.descendants(matching: .collectionView).firstMatch
        for _ in 0..<10 where !(deleteRow.exists && deleteRow.isHittable) {
            form.swipeUp()
        }
        let rowFrame = deleteRow.frame
        deleteRow.tap()
        // The confirmation's own "Delete activity", not the form row behind it.
        let sheetButton = app.sheets.buttons["Delete activity"]
        if sheetButton.waitForExistence(timeout: 3) {
            sheetButton.tap()
        } else {
            let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete activity'"))
                .allElementsBoundByIndex
                .first { $0.frame != rowFrame && $0.isHittable }
            XCTAssertNotNil(confirm, "the delete confirmation never appeared")
            confirm?.tap()
        }
        XCTAssertNotNil(label(beginningWith: "Pull Day: ", timeout: 10), "deleting the swim gave Pull its day back")

        // Settings: the Focus Areas editor shows the onboarding answer and saves a change.
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        let focusRow = app.buttons["Focus Areas"]
        let settingsList = app.descendants(matching: .collectionView).firstMatch
        XCTAssertTrue(settingsList.waitForExistence(timeout: 5))
        for _ in 0..<10 where !(focusRow.exists && focusRow.isHittable) {
            settingsList.swipeUp()
        }
        XCTAssertEqual(focusRow.value as? String, "Chest, Abs")
        attach("08-settings")
        focusRow.tap()
        XCTAssertTrue(app.navigationBars["Focus Areas"].waitForExistence(timeout: 5))
        // "Back" is both a Focus Area and the word on a navigation button, so match the row by its detail.
        let backArea = app.buttons.matching(NSPredicate(format: "label == 'Back' AND value BEGINSWITH 'Rows'")).firstMatch
        let editorList = app.descendants(matching: .collectionView).firstMatch
        let saveBar = app.buttons["Save changes"]
        // Clear of the pinned Save bar, not merely on screen: a row half under it takes the bar's tap.
        for _ in 0..<10 where !(backArea.exists && backArea.frame.maxY < saveBar.frame.minY) {
            editorList.swipeUp()
        }
        backArea.tap()
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: backArea)
        wait(for: [selected], timeout: 5)
        attach("09-settings-focus-areas")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.staticTexts["Saved. Your next session will use this."].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<10 where !(focusRow.exists && focusRow.isHittable) {
            settingsList.swipeUp()
        }
        XCTAssertEqual(focusRow.value as? String, "Chest, Back, Abs")

        // The next cold launch opens on the Welcome Page: today is Pull Day, Push is done.
        app.terminate()
        app.launch(.optedOutWithNoProbe, answersHealthPrompt: false, passesWelcomePage: false)
        XCTAssertTrue(app.buttons["Let's go"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Good morning, Riley."].exists
            || app.staticTexts["Good afternoon, Riley."].exists
            || app.staticTexts["Good evening, Riley."].exists
            || app.staticTexts["Hello, Riley."].exists, "the Welcome Page greets by name")
        XCTAssertNotNil(label(beginningWith: "Today is Pull Day", timeout: 5))
        XCTAssertNotNil(label(beginningWith: "This cycle: Push, done. Pull, today.", timeout: 5))
        attach("10-welcome-page")
        app.passWelcomePage()
        XCTAssertNotNil(label(beginningWith: "Pull Day: ", timeout: 20))
    }

    // MARK: Helpers

    private func label(beginningWith prefix: String, timeout: TimeInterval) -> String? {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
        return element.waitForExistence(timeout: timeout) ? element.label : nil
    }

    private func scrollTo(_ element: XCUIElement) {
        let scroll = app.descendants(matching: .scrollView).firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            scroll.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) never came on screen")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
