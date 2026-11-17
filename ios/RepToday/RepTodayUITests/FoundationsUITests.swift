import XCTest

/// Exercises the foundation presentation through onboarding, a real completed session, and a cold
/// relaunch. No seeded workout history or mocked services: every log is written by the player.
final class FoundationsUITests: XCTestCase {
    /// A Back flag removes pull and hinge work (`InjuryContraindication`). Under Training Days one
    /// session never holds both, so the control is a Pull Day: once Back is protected, the Rotation
    /// passes over the Pull Day it can no longer train and the Legs Day it serves keeps its squat and
    /// lunge work without its hinges.
    func testProtectingBackRemovesPullAndHingeFromTheNextSession() throws {
        continueAfterFailure = false
        let app = TestApp(self)
        app.terminate()
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        focus(app.textFields.firstMatch, in: app)
        app.textFields.firstMatch.typeText("Riley\n")
        finishOnboardingThroughSaveYourPlan(in: app)
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(advanceToTrainingDay("Pull Day", in: app), "Today never reached a Pull Day")
        XCTAssertTrue(app.buttons["60 minute session"].waitForExistence(timeout: 15))
        let chips = app.descendants(matching: .scrollView)
            .containing(.button, identifier: "60 minute session").allElementsBoundByIndex.last!
        // At the largest text sizes the chip row can sit below Today's fold, or above it when Today kept
        // a scrolled position through the session; drag toward it.
        let today = app.descendants(matching: .scrollView).firstMatch
        let fiveMinutes = app.buttons["5 minute session"]
        let chipsAbove = fiveMinutes.frame.maxY < today.frame.minY
        scrollUntil(fiveMinutes.isHittable, in: app, within: today, from: chipsAbove ? 0.30 : 0.78, to: chipsAbove ? 0.78 : 0.30)
        XCTAssertTrue(fiveMinutes.isHittable, "Today never brought the session length chips into reach")
        // XCTest raises an error for an off-screen horizontal chip's activation point instead of
        // returning false from isHittable. Scroll by its actual frame before asking it to tap.
        for _ in 0..<4 where app.buttons["60 minute session"].frame.maxX > chips.frame.maxX {
            chips.swipeLeft()
        }
        app.buttons["60 minute session"].tap()

        let pulls = ["Superman Hold", "Reverse Snow Angel",
                     "Wall Scapular Pull", "Supine Floor Row", "Single-Arm Supine Floor Row"]
        let hinges = ["Glute Bridge", "Single-Leg Glute Bridge", "Marching Glute Bridge",
                      "Long-Lever Single-Leg Bridge",
                      "Bodyweight Good Morning", "Single-Leg Romanian Deadlift"]
        let otherStrength = ["Wall Sit", "Bodyweight Squat", "Sumo Squat", "Reverse Lunge", "Split Squat"]
        func planned(_ names: [String]) -> [String] {
            names.filter { element($0 + ",", in: app).exists }
        }
        let beforePull = planned(pulls)
        let beforeHinge = planned(hinges)
        XCTAssertFalse(beforePull.isEmpty, "The control session must actually contain Pull work")
        try capture("05-before-back-protection")

        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        scrollUntilHittable(app.buttons["Areas to protect"], in: app)
        XCTAssertTrue(app.buttons["Areas to protect"].isHittable, "Settings never brought Areas to protect into reach")
        app.buttons["Areas to protect"].tap()
        let back = app.switches["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.value as? String, "0")
        XCTAssertEqual(app.switches["Shoulders"].firstMatch.value as? String, "0")
        // The labeled switch is the whole row; pressed where the switch sits, at its trailing edge, as a
        // thumb finds it (a tap on the row's middle lands on the label, which does not move it).
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let staged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: back)
        XCTAssertEqual(XCTWaiter().wait(for: [staged], timeout: 5), .completed)
        scrollUntilHittable(app.buttons["Save changes"], in: app)
        XCTAssertTrue(app.buttons["Save changes"].isHittable, "Areas to protect never brought Save changes into reach")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(element("Saved. Your next session will use this.", in: app).waitForExistence(timeout: 10))
        try capture("06-back-protection-saved")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        let filtered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            planned(pulls).isEmpty && planned(hinges).isEmpty
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [filtered], timeout: 10), .completed)
        XCTAssertFalse(planned(otherStrength).isEmpty,
                       "The regenerated session must still contain unprotected strength work")
        XCTAssertTrue(element("Legs Day: ", in: app).exists, "the Rotation passes over the Pull Day it can no longer train")
        try capture("07-session-after-back-protection")
        let transcript = "Before protecting Back: Pull = \(beforePull); Hinge = \(beforeHinge).\n"
            + "After saving Back: Pull = \(planned(pulls)); Hinge = \(planned(hinges)); other strength = \(planned(otherStrength)).\n"
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "back-protection-session-comparison"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty {
            try transcript.write(to: URL(fileURLWithPath: root).appendingPathComponent("foundations-live/back-protection.txt"),
                                 atomically: true, encoding: .utf8)
        }
    }

    func testNewUserCompletesSessionAndSeesFourFoundationsWithoutUpgradeNote() throws {
        continueAfterFailure = false
        let app = TestApp(self)
        app.terminate()
        app.launch(.optedOutWithNoProbe)
        defer { app.terminate() }

        // Reset only this test installation through the product's own account deletion flow. This
        // keeps repeat runs independent of any session left by an earlier run on the test simulator.
        XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        scrollUntilHittable(app.buttons["Delete Account"], in: app)
        XCTAssertTrue(app.buttons["Delete Account"].isHittable)
        app.buttons["Delete Account"].tap()
        XCTAssertTrue(app.alerts.buttons["Delete Account"].waitForExistence(timeout: 5))
        app.alerts.buttons["Delete Account"].tap()

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        focus(app.textFields.firstMatch, in: app)
        app.textFields.firstMatch.typeText("Riley\n")
        finishOnboardingThroughSaveYourPlan(in: app)
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(element("Your history starts with your first session.", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("Your climb to Strength", in: app).exists)
        try capture("01-empty-history")

        app.tabBars.buttons["Today"].tap()
        let fiveMinutes = app.buttons["5 minute session"]
        XCTAssertTrue(fiveMinutes.waitForExistence(timeout: 10))
        fiveMinutes.tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        app.buttons["Start"].tap()
        if app.buttons["Got it"].waitForExistence(timeout: 3) { app.buttons["Got it"].tap() }

        let completion = element("You showed up.", in: app)
        for _ in 0..<60 {
            if completion.exists { break }
            let actions = ["Skip rest", "Done", "Complete set", "Finish exercise", "Finish session"].map { app.buttons[$0] }
            let reachable = { actions.first { $0.exists && $0.isHittable } }
            // At the largest text sizes the player's secondary controls sit below its fold.
            if reachable() == nil { scrollUntil(reachable() != nil, in: app, maxSwipes: 8) }
            let action = reachable()
            guard let action else {
                XCTFail("The session offered no completion control: \(app.descendants(matching: .any).allElementsBoundByIndex.map(\.label))")
                return
            }
            action.tap()
        }
        XCTAssertTrue(completion.waitForExistence(timeout: 10))
        try capture("02-completed-real-session")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Progress"].tap()
        try verifyFoundations(in: app, prefix: "03")

        app.terminate()
        app.launch(.optedOutWithNoProbe)
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Progress"].tap()
        try verifyFoundations(in: app, prefix: "04-relaunch")
    }

    private func verifyFoundations(in app: TestApp, prefix: String) throws {
        XCTAssertTrue(element("Your climb to Strength", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("of 4 cleared", in: app).exists)
        XCTAssertFalse(element("Your foundations are now", in: app).exists)
        for label in ["Push,", "Pull,", "Legs,", "Core,"] {
            XCTAssertTrue(element(label, in: app).exists, label)
        }
        try capture("\(prefix)-climb")

        // Capture actual phone-sized viewports while scrolling to the map; its horizontal Pull
        // ladder and the separate Legs sides must remain reachable through ordinary scrolling.
        for (index, label) in ["Where you stand", "Pull ladder.", "Single-Arm Supine Floor Row,", "Legs, squat side ladder.", "Legs, hinge side ladder."].enumerated() {
            let target = element(label, in: app)
            scrollUntilHittable(target, in: app)
            XCTAssertTrue(target.isHittable, "Could not reach \(label)")
            try capture("\(prefix)-map-\(index)")
        }
        XCTAssertFalse(element("Superman Hold,", in: app).exists)
    }

    private func element(_ text: String, in app: TestApp) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func capture(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "foundations-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty {
            let directory = URL(fileURLWithPath: root).appendingPathComponent("foundations-live")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
