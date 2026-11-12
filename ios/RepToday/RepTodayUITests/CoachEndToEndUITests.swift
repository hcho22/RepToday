import XCTest

/// The M4 verification walks, end to end in the Simulator against the **development** Clerk instance and
/// Convex deployment and the real Coach model: the free preview and paywall, then each Coach tool proposed
/// by the model and applied by the app, a Custom Workout reviewed, edited, accepted and played, a reminder
/// delivered, and a minor's diet question declined by the server.
///
/// Opt-in, because it reaches the real development services and makes a bounded number of real model
/// calls: it runs only with `REPTODAY_E2E_COACH=1` (a build setting the `RepTodayUITests` scheme
/// forwards). It signs in with Clerk *test* addresses (`+clerk_test`, verified with the fixed code 424242
/// and never mailed). The methods run in order (A, B1, B3, B2, C1, C2, B4) on one Simulator, with one step
/// outside the app between them: before B1 and C2 the walk account is given Premium on the development
/// backend, standing in for a sandbox purchase (the M4 row of `docs/test-coverage.md` lists the commands).
/// The purchase itself, its renewal notifications and VoiceOver on hardware are device checks, not these.
final class CoachEndToEndUITests: XCTestCase {

    private var app: TestApp!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPTODAY_E2E_COACH"] == "1",
                          "reaches the development Clerk instance, backend and Coach model; opt in with REPTODAY_E2E_COACH=1")
        continueAfterFailure = false
        app = TestApp(self)
        app.terminate()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    private static func testEmail(_ label: String) -> String {
        "reptoday-e2e-coach-\(label)-\(Int(Date().timeIntervalSince1970))+clerk_test@example.com"
    }

    // MARK: - A: a free account sees what the Coach does and where to get it

    func testA_FreeAccountSeesThePreviewAndThePaywall() throws {
        onboardFreshAccount(label: "adult", age: nil)
        openCoach()
        XCTAssertTrue(app.staticTexts["A coach that knows your training"].waitForExistence(timeout: 30),
                      "a free account sees the Coach preview")
        XCTAssertFalse(app.textFields["Message to the coach"].exists, "a free account cannot message the Coach")
        snapshot("a1-free-preview")
        app.buttons["See Premium plans"].tap()
        XCTAssertTrue(app.staticTexts["Go deeper with Premium"].waitForExistence(timeout: 15), "the preview opens the paywall")
        snapshot("a2-paywall")
    }

    // MARK: - B: Premium - every tool, then a Custom Workout

    func testB1_PremiumCoachToolsApplyThroughTheApp() throws {
        launchSignedIn()
        openCoach()
        acknowledgeDisclosureIfShown()
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30),
                      "the walk account has Premium on the backend (seed it before B1)")
        declineLeftoverProposals()
        snapshot("b01-coach-empty")

        // Logs a run (an Outside Activity), through the same path as the Today sheet.
        ask("I ran 5 km in 30 minutes this morning, can you log it?")
        confirmProposal(beginningWith: "Log a ", named: "b02-log-run")

        // Today's length.
        ask("I only have 10 minutes today. Make today's session 10 minutes.")
        confirmProposal(beginningWith: "Make today ", named: "b03-length")

        // A swap in today's session.
        ask("Please swap out the first movement in today's session for something else.")
        confirmProposal(beginningWith: "Swap out ", named: "b04-swap")

        // Focus Areas.
        ask("Please set my Focus Areas to abs.")
        confirmProposal(beginningWith: "Focus on ", named: "b05-focus")

        // Rest today, then change of mind.
        ask("I'd like to make today a rest day.")
        confirmProposal(beginningWith: "Rest today", named: "b06-rest")
        openToday()
        snapshot("b07-today-chosen-rest")
        openCoach()
        ask("Actually, I'd like to train today after all.")
        confirmProposal(beginningWith: "Train today", named: "b08-train-anyway")
    }

    func testB3_AnAdultGetsDietGuidanceAndAReminderFires() throws {
        launchSignedIn()
        openCoach()
        acknowledgeDisclosureIfShown()
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30))
        declineLeftoverProposals()

        // An adult may get general diet guidance (the positive control for C), in the app's voice.
        ask("What should I eat after a workout?")
        XCTAssertFalse(dietDecline.exists, "an adult is not declined diet guidance")
        snapshot("b09-adult-diet")

        // A reminder two minutes from now, every day, which asks for notification permission at the first
        // save and then fires on the Simulator.
        let fireAt = Calendar.current.date(byAdding: .minute, value: 2, to: Date())!
        let time = fireAt.formatted(date: .omitted, time: .shortened)
        ask("Remind me to train every day at \(time).")
        confirmProposal(beginningWith: "Remind me at ", named: "b10-reminder", allowingNotifications: true)
        app.goHome()
        // The banner reads the reminder's own text (`CoachReminderCopy.notificationBody`), which no Home
        // Screen icon does.
        let banner = app.springboardElement(matchingAnyOf: [
            "Your session is ready when you are", "A few minutes is all it takes", "Time for you. Your session is ready",
        ])
        XCTAssertTrue(banner.waitForExistence(timeout: 200), "the reminder fired as a notification")
        snapshot("b11-reminder-delivered")
    }

    func testB4_SettingsListsAndDeletesAReminderTheCoachSet() throws {
        launchSignedIn()
        openCoach()
        acknowledgeDisclosureIfShown()
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30))
        declineLeftoverProposals()
        // Formatted the way the app writes a time (its space before AM is a narrow no-break one).
        let time = Calendar.current.date(from: DateComponents(hour: 6, minute: 45))!.formatted(date: .omitted, time: .shortened)
        ask("Remind me to train on weekdays at \(time).")
        confirmProposal(beginningWith: "Remind me at ", named: "d1-reminder", allowingNotifications: true)

        // Settings lists it, and deleting it there removes it (US-CA08).
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        let remindersRow = app.buttons["Reminders"]
        scrollUntilHittable(remindersRow, in: app)
        remindersRow.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reminder at \(time), ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Settings lists the reminder the Coach set")
        snapshot("d2-settings-reminders")
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "deleting it in Settings removes it")
        snapshot("d3-settings-reminder-deleted")
    }

    func testB2_ACustomWorkoutIsReviewedEditedAcceptedAndPlayed() throws {
        launchSignedIn()
        openCoach()
        acknowledgeDisclosureIfShown()
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30))
        declineLeftoverProposals()
        ask("Write me a 10-minute workout I can do in a hotel room.")
        let review = app.buttons["Review and accept"].firstMatch
        scrollUntilVisible(review)
        XCTAssertTrue(review.waitForExistence(timeout: 10), "the Coach proposed a Custom Workout")
        snapshot("b12-custom-workout-proposed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch.exists,
                       "nothing plays before acceptance")
        review.tap()

        // Edit: open the first step and add a set.
        let accept = app.buttons["Accept and play"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "the editor opened")
        snapshot("b13-editor")
        let firstStep = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*, [0-9]+ sets? of .*")).firstMatch
        XCTAssertTrue(firstStep.waitForExistence(timeout: 5), "the editor lists the workout's steps")
        let stepBefore = firstStep.label
        firstStep.tap()
        // The row and its stepper both carry the "Sets" label; the stepper is the one with a value.
        let setsRows = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sets"))
        XCTAssertTrue(setsRows.firstMatch.waitForExistence(timeout: 5), "the step editor opened")
        let sets = setsRows.allElementsBoundByIndex.first { ($0.value as? String)?.isEmpty == false } ?? setsRows.firstMatch
        let before = sets.value as? String
        // The stepper's plus sits a fixed distance in from the screen's trailing edge: the form's 16pt
        // inset, the row's 20pt inset, and half of the 47pt plus segment.
        let screenWidth = app.descendants(matching: .window).firstMatch.frame.width
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenWidth - 60, dy: sets.frame.midY)).tap()
        let changed = expectation(for: NSPredicate(format: "value != %@", before ?? ""), evaluatedWith: sets)
        wait(for: [changed], timeout: 5)
        snapshot("b14-step-editor")
        app.navigationBars["Edit step"].buttons["Done"].tap()
        let stepAfter = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*, [0-9]+ sets? of .*")).firstMatch
        XCTAssertTrue(stepAfter.waitForExistence(timeout: 5))
        XCTAssertNotEqual(stepAfter.label, stepBefore, "the edit shows in the workout")
        snapshot("b15-editor-after-edit")

        accept.tap()
        playSessionToCompletion(in: app)
        snapshot("b16-after-custom-workout")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch
        scrollUntilVisible(play)
        XCTAssertTrue(play.exists, "the accepted workout stays playable")

        openToday()
        let recorded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Custom Workout")).firstMatch
        XCTAssertTrue(recorded.waitForExistence(timeout: 10), "a played Custom Workout is recorded like an Outside Activity")
        scrollUntilVisible(recorded)
        snapshot("b17-today-after-custom-workout")
    }

    // MARK: - C: a minor's diet question is declined by the server

    func testC1_AMinorAccountIsCreated() throws {
        deleteAccountThroughSettings()
        onboardFreshAccount(label: "minor", age: 16)
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 30))
        snapshot("c1-minor-onboarded")
    }

    func testC2_AMinorIsDeclinedDietGuidance() throws {
        launchSignedIn()
        openCoach()
        acknowledgeDisclosureIfShown()
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30),
                      "the minor account has Premium on the backend (seed it before C2)")
        ask("What should I eat to build muscle?")
        let declined = dietDecline
        XCTAssertTrue(declined.waitForExistence(timeout: 10), "the server declines diet guidance for a 16-year-old")
        snapshot("c2-minor-diet-declined")
        ask("How do I do a push-up with good form?")
        snapshot("c3-minor-training-answered")
    }

    // MARK: - Steps

    private func onboardFreshAccount(label: String, age: Int?) {
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false, liveAccount: true)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20), "a fresh install opens on onboarding")
        app.buttons["Continue"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        if let age {
            let row = app.otherElements["Age"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "the basics step has no Age row")
            let frame = row.frame
            // The row's minus button: one 44pt button and a 1pt divider in from the trailing edge.
            let minus = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 44 * 1.5 - 1, dy: frame.midY))
            for _ in 0..<60 where (row.value as? String) != "\(age) years" {
                minus.tap()
            }
            XCTAssertEqual(row.value as? String, "\(age) years")
        }
        let email = Self.testEmail(label)
        record("signed in as \(email)", named: "\(label)-account.txt")
        finishOnboardingThroughSaveYourPlan(in: app, email: email)
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30), "signing in finishes onboarding")
    }

    private func launchSignedIn() {
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 30), "the app never reached the main tabs")
    }

    private func openCoach() {
        let coach = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 20))
        coach.tap()
    }

    private func openToday() {
        dismissKeyboard()
        app.tabBars.buttons["Today"].tap()
        _ = app.buttons["Start"].waitForExistence(timeout: 10)
    }

    private func acknowledgeDisclosureIfShown() {
        let understand = app.buttons["I understand"]
        if understand.waitForExistence(timeout: 15) {
            snapshot("disclosure")
            understand.tap()
        }
    }

    /// The server's fixed diet decline (`DIET_DECLINE_REPLY` in `convex/coachSafety.ts`) as the Coach says it.
    private var dietDecline: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                             "Coach said: Food and diet questions are outside what I can help with here.")).firstMatch
    }

    /// A rerun on the same account starts with no proposal still waiting, so each step's card is the
    /// only one asking for Confirm.
    private func declineLeftoverProposals() {
        let notNow = app.buttons["Not now"]
        for _ in 0..<10 where notNow.exists {
            scrollUntilVisible(notNow)
            notNow.tap()
            _ = notNow.waitForNonExistence(timeout: 5)
        }
    }

    /// Sends one message and waits for the Coach's reply.
    private func ask(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["Message to the coach"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), file: file, line: line)
        field.tap()
        field.typeText(message)
        app.buttons["Send"].tap()
        let thinking = app.descendants(matching: .any)["Coach is thinking"]
        _ = thinking.waitForExistence(timeout: 5)
        XCTAssertTrue(thinking.waitForNonExistence(timeout: 90), "the Coach never answered: \(message)", file: file, line: line)
        XCTAssertFalse(app.staticTexts["The coach couldn't answer just now. Your workout isn't affected - tap to try again."].exists,
                       "the Coach failed to answer: \(message)", file: file, line: line)
    }

    /// Confirms the newest proposal whose title begins with `prefix`, then checks it reads as done with Undo.
    private func confirmProposal(
        beginningWith prefix: String, named name: String, allowingNotifications: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // A card's header reads "title, detail" as one element, which no quick-action chip ("Rest today")
        // does. The newest card is the last: the whole conversation stays in the tree.
        let cards = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", prefix, ", "))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "the Coach proposed nothing beginning \"\(prefix)\"", file: file, line: line)
        if let card = cards.allElementsBoundByIndex.last {
            scrollUntilVisible(card)
        }
        snapshot("\(name)-proposed")
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Confirm"))
        XCTAssertEqual(confirms.count, 1, "exactly the new proposal waits for Confirm", file: file, line: line)
        confirms.firstMatch.tap()
        if allowingNotifications {
            // The first reminder on an install asks for notification permission (US-CA08); a later one
            // finds it already granted.
            let asked = app.allowSystemAlert(timeout: 10)
            record(asked ? "notification permission asked and allowed" : "notification permission already granted",
                   named: "\(name)-permission.txt")
        }
        XCTAssertTrue(confirms.firstMatch.waitForNonExistence(timeout: 15), "the proposal was applied", file: file, line: line)
        let undo = app.buttons.matching(NSPredicate(format: "label == %@", "Undo")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the applied proposal offers Undo", file: file, line: line)
        snapshot("\(name)-applied")
    }

    /// The composer keeps the keyboard up after a send, like any chat; dragging the conversation down
    /// puts it away (the conversation dismisses it interactively), uncovering the tab bar.
    private func dismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        _ = keyboard.waitForNonExistence(timeout: 3)
    }

    private func scrollUntilVisible(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
    }

    private func deleteAccountThroughSettings() {
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()
        app.buttons["Settings"].tap()
        let delete = app.buttons["Delete Account"]
        scrollUntilHittable(delete, in: app)
        delete.tap()
        let confirm = app.alerts.buttons["Delete Account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 30), "deletion returns to onboarding")
        app.terminate()
    }

    // MARK: - Evidence

    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty {
            let directory = URL(fileURLWithPath: root).appendingPathComponent("m4-e2e")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    private func record(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty {
            let directory = URL(fileURLWithPath: root).appendingPathComponent("m4-e2e")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
