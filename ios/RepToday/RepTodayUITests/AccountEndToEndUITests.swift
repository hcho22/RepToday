import XCTest

/// The M3 verification walks, end to end in the Simulator against the **development** Clerk instance and
/// Convex deployment: a fresh install signs in at "Save your plan", a session logged with the account
/// backend offline waits on the phone and saves once it is back, account deletion removes the account,
/// and an install onboarded by a pre-account build signs in once and moves its history.
///
/// Opt-in, because it reaches the real development services: it runs only with
/// `REPTODAY_E2E_ACCOUNTS=1` (a build setting the `RepTodayUITests` scheme forwards). It signs in with a
/// Clerk *test* email (`+clerk_test`), which a development instance verifies with the fixed code 424242
/// and never mails. The methods are meant to run in order (A, B), on one Simulator; C needs an install a
/// pre-account build onboarded first, and `REPTODAY_E2E_EXISTING_USER=1` (the M3 row of
/// `docs/test-coverage.md` lists the steps). What the backend holds after each step is read with the
/// Convex CLI, outside the app.
///
/// Apple and Google sign-in, real airplane mode and real iCloud data are device checks, not these.
final class AccountEndToEndUITests: XCTestCase {

    private var app: TestApp!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPTODAY_E2E_ACCOUNTS"] == "1",
                          "reaches the development Clerk instance and backend; opt in with REPTODAY_E2E_ACCOUNTS=1")
        continueAfterFailure = false
        app = TestApp(self)
        app.terminate()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    /// A Clerk development test address, unique per run.
    private static func testEmail(_ label: String) -> String {
        "reptoday-e2e-\(label)-\(Int(Date().timeIntervalSince1970))+clerk_test@example.com"
    }

    // MARK: - A: fresh install, offline session, then sync

    func testA_FreshInstallSignsInThenAnOfflineSessionSavesOnceOnline() throws {
        // Fresh install: onboarding ends at "Save your plan", and signing in finishes it.
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false, liveAccount: true)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20), "a fresh install opens on onboarding")
        app.buttons["Continue"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        let email = Self.testEmail("fresh")
        record("signed in as \(email)", named: "a-account.txt")
        let saveYourPlan = app.staticTexts["Save your plan"]
        for _ in 0..<10 where !saveYourPlan.exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(saveYourPlan.waitForExistence(timeout: 5))
        snapshot("a1-save-your-plan")
        finishOnboardingThroughSaveYourPlan(in: app, email: email)
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30), "signing in finishes onboarding")
        snapshot("a2-today-after-sign-in")
        assertAccountScreen(says: "Everything is saved to your account.")
        snapshot("a3-account-saved")
        app.terminate()

        // Offline: a whole session generates, plays and logs with the backend unreachable.
        app.launch(.optedOutWithNoProbe, liveAccount: true, syncOffline: true)
        XCTAssertTrue(app.buttons["5 minute session"].waitForExistence(timeout: 20) || app.buttons["Train anyway"].exists)
        if app.buttons["Train anyway"].exists { app.buttons["Train anyway"].tap() }
        app.buttons["5 minute session"].tap()
        app.buttons["Start"].tap()
        playSessionToCompletion(in: app)
        snapshot("a4-offline-session-done")
        assertAccountScreen(says: "will save when you're online")
        snapshot("a5-account-waiting-offline")
        app.terminate()

        // Back online: the waiting session saves without anything to do.
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        assertAccountScreen(says: "Everything is saved to your account.")
        snapshot("a6-account-saved-after-reconnect")
    }

    // MARK: - B: account deletion

    func testB_DeletingTheAccountRemovesItAndReturnsToOnboarding() throws {
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs (run A first)")
        profile.tap()
        app.buttons["Settings"].tap()
        let deleteRow = app.buttons["Delete Account"]
        scrollUntilHittable(deleteRow, in: app)
        deleteRow.tap()
        let confirm = app.alerts.buttons["Delete Account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        snapshot("b1-delete-confirmation")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 30), "deletion returns to onboarding")
        snapshot("b2-onboarding-after-deletion")

        // The deleted account's session is gone from the device: "Save your plan" offers the three
        // choices, not the deleted account back.
        app.buttons["Continue"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        let saveYourPlan = app.staticTexts["Save your plan"]
        for _ in 0..<10 where !saveYourPlan.exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(saveYourPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue with email"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Use a different account"].exists, "the deleted account is not offered back")
        snapshot("b3-save-your-plan-after-deletion")
    }

    // MARK: - C: an existing user's one-time sign-in

    func testC_AnExistingUserSignsInOnceAndTheirHistoryMoves() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REPTODAY_E2E_EXISTING_USER"] == "1",
                          "needs an install a pre-account build onboarded; opt in with REPTODAY_E2E_EXISTING_USER=1")
        app.launch(.optedOutWithNoProbe, answersHealthPrompt: false, passesWelcomePage: false, liveAccount: true)
        XCTAssertTrue(app.staticTexts["Keep your history"].waitForExistence(timeout: 30),
                      "an install onboarded before accounts meets the one-time sign-in first")
        XCTAssertFalse(app.tabBars.buttons["Today"].exists, "nothing opens until the user signs in")
        snapshot("c1-keep-your-history")
        let email = Self.testEmail("existing")
        record("signed in as \(email)", named: "c-account.txt")
        // A session left on the device by an earlier run (the Keychain outlives an uninstall) is
        // offered back first.
        if app.buttons["Use a different account"].waitForExistence(timeout: 2) {
            app.buttons["Use a different account"].tap()
        }
        XCTAssertTrue(app.buttons["Continue with email"].waitForExistence(timeout: 10))
        app.buttons["Continue with email"].tap()
        let address = app.textFields["Email address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText(email)
        app.buttons["Send code"].tap()
        let code = app.textFields["Code from your email"]
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        code.tap()
        code.typeText("424242")
        app.buttons["Sign in"].tap()
        app.passWelcomePage()
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        snapshot("c2-today-after-sign-in")
        // The move waits (bounded) for iCloud, then uploads; the screen says when everything is saved.
        assertAccountScreen(says: "Everything is saved to your account.", timeout: 120)
        snapshot("c3-account-history-moved")
    }

    // MARK: - D: sign out and back in (US-SO01/US-SO02)

    // Run in order on one freshly erased Simulator with `REPTODAY_EVIDENCE_DIR` set, which carries the
    // walk account from D1 to the rest. Between D1 and D2, grant that account Premium on the development
    // backend (the US-SO row of `docs/test-coverage.md` says how), so D2 can show Premium surviving.

    /// A new account with one session saved to it: Today moves on from Push Day.
    func testD1_AnAccountWithASavedSession() throws {
        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false, liveAccount: true)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20), "a fresh install opens on onboarding")
        app.buttons["Continue"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Riley\n")
        let email = Self.testEmail("signout")
        try saveWalkEmail(email)
        finishOnboardingThroughSaveYourPlan(in: app, email: email)
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        XCTAssertEqual(trainingDay(), "Push Day")
        playFiveMinuteSession()
        XCTAssertEqual(trainingDay(), "Pull Day", "the session moved the Rotation")
        assertAccountScreen(says: "Everything is saved to your account.")
        snapshot("d1-account-saved")
    }

    /// Online: nothing is waiting, so signing out asks once and lands on Welcome; signing back in from
    /// Welcome brings the history and Premium back with no questions and no Restore Purchases.
    func testD2_SignOutOnlineAndSignBackIn() throws {
        let email = try walkEmail()
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        assertPremiumCoach()
        snapshot("d2-premium-before-sign-out")
        assertAccountScreen(says: "Everything is saved to your account.")
        let savedDay = trainingDay()
        signOut(expectingWarning: false)
        snapshot("d2-welcome-after-sign-out")

        signInFromWelcome(email: email)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 45), "the saved plan restores straight to Today, no questions")
        XCTAssertEqual(trainingDay(), savedDay, "the history came back")
        snapshot("d2-today-after-sign-in")
        assertPremiumCoach()
        snapshot("d2-premium-after-sign-in")
    }

    /// Offline with a workout waiting: the warning says so, Cancel keeps everything, and Sign Out Anyway
    /// loses only that workout - signing back in finds the account as it was before it.
    func testD3_SignOutOfflineWithAWorkoutWaiting() throws {
        let email = try walkEmail()
        // Signed in to the walk account, whichever account the phone was left on.
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        signOut(expectingWarning: false)
        signInFromWelcome(email: email)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 45))
        app.terminate()

        app.launch(.optedOutWithNoProbe, liveAccount: true, syncOffline: true)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        let savedDay = trainingDay()
        playFiveMinuteSession()
        let waitingDay = trainingDay()
        XCTAssertNotEqual(waitingDay, savedDay, "the offline session moved the Rotation on the phone")
        assertAccountScreen(says: "will save when you're online")

        openSettingsSignOut()
        app.alerts["Sign out of Rep Today?"].buttons["Sign Out"].tap()
        let warning = app.alerts["Recent workouts aren't saved"]
        XCTAssertTrue(warning.waitForExistence(timeout: 30), "a waiting workout is never lost silently")
        snapshot("d3-unsaved-warning")
        warning.buttons["Cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 5), "Cancel keeps the user signed in")
        XCTAssertEqual(trainingDay(), waitingDay, "Cancel changed nothing")

        openSettingsSignOut()
        app.alerts["Sign out of Rep Today?"].buttons["Sign Out"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 30))
        warning.buttons["Sign Out Anyway"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 30))
        app.terminate()

        app.launch(.optedOutWithNoProbe, onboarded: false, answersHealthPrompt: false, liveAccount: true)
        signInFromWelcome(email: email)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 45))
        XCTAssertEqual(trainingDay(), savedDay, "the workout signed out with was lost, as the warning said")
        snapshot("d3-today-after-signing-back-in")
    }

    /// Another account on the same phone finds none of the first account's data: it onboards, opens on
    /// Push Day and sees the free Coach.
    func testD4_AnotherAccountFindsACleanPhone() throws {
        app.launch(.optedOutWithNoProbe, liveAccount: true)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        signOut(expectingWarning: false)

        signInFromWelcome(email: Self.testEmail("second"))
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 30), "a new account answers the questions")
        snapshot("d4-new-account-questions")
        name.tap()
        name.typeText("Sam\n")
        let finish = app.buttons["Finish"]
        for _ in 0..<8 where !finish.exists {
            app.buttons["Continue"].tap()
        }
        finish.tap()
        app.answerHealthPromptIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 30))
        XCTAssertEqual(trainingDay(), "Push Day", "none of the first account's history")
        snapshot("d4-second-account-today")
        let coach = app.tabBars.buttons["Coach"]
        coach.tap()
        XCTAssertTrue(app.staticTexts["A coach that knows your training"].waitForExistence(timeout: 30),
                      "the second account is not Premium")
        snapshot("d4-second-account-free-coach")
    }

    private func signOut(expectingWarning: Bool) {
        openSettingsSignOut()
        snapshot("sign-out-confirmation")
        app.alerts["Sign out of Rep Today?"].buttons["Sign Out"].tap()
        if expectingWarning {
            app.alerts["Recent workouts aren't saved"].buttons["Sign Out Anyway"].tap()
        }
        XCTAssertTrue(app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 30), "signing out returns to Welcome")
        XCTAssertFalse(app.alerts["Recent workouts aren't saved"].exists, "nothing was waiting, so no warning")
    }

    private func openSettingsSignOut() {
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()
        // The Profile tab keeps whichever screen it was left on.
        if app.navigationBars["Account"].waitForExistence(timeout: 2) {
            app.navigationBars["Account"].buttons["BackButton"].tap()
        }
        if !app.navigationBars["Settings"].exists {
            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10), "Profile has no Settings row")
            settings.tap()
        }
        let row = app.buttons["Sign Out"]
        scrollUntilHittable(row, in: app)
        row.tap()
        XCTAssertTrue(app.alerts["Sign out of Rep Today?"].waitForExistence(timeout: 10))
    }

    private func signInFromWelcome(email: String) {
        let link = app.buttons["Already have an account? Sign in"]
        XCTAssertTrue(link.waitForExistence(timeout: 20), "Welcome offers signing in")
        link.tap()
        finishOnboardingThroughSaveYourPlan(in: app, email: email)
        app.answerHealthPromptIfPresented()
    }

    private func openToday() {
        app.tabBars.buttons["Today"].tap()
    }

    private func playFiveMinuteSession() {
        openToday()
        XCTAssertTrue(app.buttons["5 minute session"].waitForExistence(timeout: 20) || app.buttons["Train anyway"].exists)
        if app.buttons["Train anyway"].exists { app.buttons["Train anyway"].tap() }
        app.buttons["5 minute session"].tap()
        app.buttons["Start"].tap()
        playSessionToCompletion(in: app)
    }

    /// "Push Day", "Pull Day", "Legs Day" or "Rest Day", read off Today's title.
    private func trainingDay() -> String? {
        openToday()
        let title = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR label == %@", " Day: ", "Rest Day")).firstMatch
        guard title.waitForExistence(timeout: 30) else { return nil }
        return title.label.components(separatedBy: ":").first
    }

    private func assertPremiumCoach() {
        app.tabBars.buttons["Coach"].tap()
        let understand = app.buttons["I understand"]
        if understand.waitForExistence(timeout: 15) {
            understand.tap()
        }
        XCTAssertTrue(app.textFields["Message to the coach"].waitForExistence(timeout: 30),
                      "the walk account has Premium (grant it between D1 and D2)")
        XCTAssertFalse(app.staticTexts["A coach that knows your training"].exists)
    }

    private var walkEmailFile: URL? {
        guard let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty else { return nil }
        return URL(fileURLWithPath: root).appendingPathComponent("m3-e2e").appendingPathComponent("d-email.txt")
    }

    private func saveWalkEmail(_ email: String) throws {
        let file = try XCTUnwrap(walkEmailFile, "set REPTODAY_EVIDENCE_DIR so D1 can hand its account to D2-D4")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try email.write(to: file, atomically: true, encoding: .utf8)
    }

    private func walkEmail() throws -> String {
        let file = try XCTUnwrap(walkEmailFile, "set REPTODAY_EVIDENCE_DIR and run D1 first")
        return try String(contentsOf: file, encoding: .utf8)
    }

    // MARK: - Helpers

    private func assertAccountScreen(says headline: String, timeout: TimeInterval = 45, file: StaticString = #filePath, line: UInt = #line) {
        openAccount()
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", headline)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: timeout), "the Account screen never said: \(headline)", file: file, line: line)
    }

    private func openAccount() {
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()
        if !app.navigationBars["Account"].exists {
            let account = app.buttons["Account"]
            XCTAssertTrue(account.waitForExistence(timeout: 10))
            account.tap()
        }
    }

    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let root = ProcessInfo.processInfo.environment["REPTODAY_EVIDENCE_DIR"], !root.isEmpty {
            let directory = URL(fileURLWithPath: root).appendingPathComponent("m3-e2e")
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
            let directory = URL(fileURLWithPath: root).appendingPathComponent("m3-e2e")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }
}
