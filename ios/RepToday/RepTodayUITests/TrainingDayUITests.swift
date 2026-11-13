import XCTest

/// M1 exit criterion: a full 45-minute Training Day plays end to end in the running app, every movement
/// shows Trainer art, and Today moves on to the next group afterwards.
///
/// Walks the session with the player's own early-advance controls (**Done**, **Skip rest**) so it runs
/// in minutes, recording each movement's illustration label on the way.
final class TrainingDayUITests: XCTestCase {

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

    func testAFortyFiveMinuteTrainingDayPlaysEndToEndWithTrainerArtOnEveryMovement() {
        // Onboard from the first screen, straight through on the primary button, so the session is built
        // for a real profile (a new user starts at Push).
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false)
        let welcome = app.buttons["Continue"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "the app did not reach onboarding")
        welcome.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        finishOnboardingThroughSaveYourPlan(in: app)
        app.answerHealthPromptIfPresented()

        let title = firstLabel(containing: " Day: ", timeout: 20)
        XCTAssertNotNil(title, "Today never named its Training Day")
        let startingDay = title?.components(separatedBy: ":").first ?? ""

        let fortyFive = app.buttons["45 minute session"]
        XCTAssertTrue(fortyFive.waitForExistence(timeout: 10), "no 45 minute chip")
        // The chip row scrolls sideways; bring the longer lengths on screen.
        app.buttons["15 minute session"].swipeLeft()
        fortyFive.tap()
        XCTAssertNotNil(firstLabel(containing: "\(startingDay): ", timeout: 10))
        attachScreenshot(named: "01-today-45")

        app.buttons["Start"].tap()

        var illustrations: [String: String] = [:]
        var finished = false
        for _ in 0..<400 {
            if app.staticTexts["You showed up."].exists {
                finished = true
                break
            }
            for choice in ["Got it", "Start session"] where app.buttons[choice].exists {
                app.buttons[choice].tap()
            }
            if let label = illustrationLabel(), let name = label.components(separatedBy: ",").first, illustrations[name] == nil {
                illustrations[name] = label
                attachScreenshot(named: "02-\(illustrations.count)-\(name)")
            }
            if app.buttons["Skip rest"].exists {
                app.buttons["Skip rest"].tap()
            } else if let advance = ["Done", "Complete set", "Finish exercise", "Finish session"]
                .map({ app.buttons[$0] })
                .first(where: { $0.exists && $0.isHittable }) {
                // Every early-advance records the set as done (never a skip), so the walk logs the session.
                advance.tap()
            } else if app.buttons["Start hold"].exists {
                app.buttons["Start hold"].tap()
            } else {
                _ = app.buttons["Done"].waitForExistence(timeout: 1)
            }
        }
        XCTAssertTrue(finished, "the session never reached its completion screen; saw \(illustrations.keys.sorted())")
        attachScreenshot(named: "03-complete")

        XCTAssertGreaterThanOrEqual(illustrations.count, 6, "too few movements seen: \(illustrations)")
        // ADR-0018: 2 warm-up + 4 main + 2 Core Sprinkles + 2 cooldown (no Focus Areas picked here).
        XCTAssertLessThanOrEqual(illustrations.count, 10, "a 45 minute session serves at most 10 movements: \(illustrations.keys.sorted())")
        for (name, label) in illustrations {
            XCTAssertTrue(label.contains("trainer showing"), "\(name) shows no Trainer art: \(label)")
        }

        // Close the completion screen: Today now offers the next group of the Rotation.
        for close in ["Done", "Close"] where app.buttons[close].waitForExistence(timeout: 3) {
            app.buttons[close].tap()
            break
        }
        let next = firstLabel(containing: " Day: ", timeout: 20)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next?.components(separatedBy: ":").first, startingDay, "Today did not move to the next Training Day")
        attachScreenshot(named: "04-today-next")
    }

    private func illustrationLabel() -> String? {
        let element = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR label ENDSWITH %@", "trainer showing", "demonstration"))
            .firstMatch
        return element.exists ? element.label : nil
    }

    private func firstLabel(containing text: String, timeout: TimeInterval) -> String? {
        let element = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
        return element.waitForExistence(timeout: timeout) ? element.label : nil
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
