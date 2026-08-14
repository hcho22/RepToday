import XCTest

/// The auto-advancing work window driven through the running app, out of process (US-CC01).
///
/// The in-process view-model and hosted-view tests prove the countdown, the recording and the
/// auto-advance deterministically; this is the one thing they cannot exercise - a real finger reaching
/// the shipped player, arriving at a rep-based strength set, and pressing the shipped **Done** control
/// to advance it early. It launches through the shared `TestApp` wrapper
/// (`RepTodayUITests/TestApp.swift`), which owns the only `XCUIApplication` in the bundle, naming the
/// `.optedOutWithNoProbe` posture so the run is off the telemetry wire (there is no work-window event,
/// but every launch here must still carry a posture - `UITestLaunchGuardTests` fails the build
/// otherwise).
///
/// Warm-up stretches are timed holds on the manual path here (US-CC05 makes the bookends hands-free
/// later), so the test skips past them to reach the first strength set, where the auto-advancing work
/// window and its **Done** control live.
final class ContinuousCircuitUITests: XCTestCase {

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

    func testStrengthSetShowsAWorkWindowAndDoneAdvancesIt() {
        app.launch(.optedOutWithNoProbe) // onboarded, lands on the main tabs (Today = Ready Screen)

        // Ready Screen -> Start the already-generated session.
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "the Ready Screen never offered Start")
        start.tap()

        // Walk forward to the first rep-based strength set. Its auto-advancing work window announces
        // itself with a "Work window, N seconds remaining" ring; everything before it (warm-up holds)
        // is skipped past. Each iteration first gives the freshly-rendered step a beat to reveal the
        // work window, so a strength set is never itself skipped in the race after the prior tap.
        let workWindow = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Work window"))
            .firstMatch

        var reachedWorkWindow = false
        for _ in 0..<30 {
            if workWindow.waitForExistence(timeout: 2) {
                reachedWorkWindow = true
                break
            }
            if app.buttons["Skip rest"].exists {
                app.buttons["Skip rest"].tap()
                continue
            }
            let skip = app.buttons["Skip this exercise"]
            if skip.exists {
                skip.tap()
                continue
            }
        }

        XCTAssertTrue(
            reachedWorkWindow,
            "never reached a rep-based strength set with an auto-advancing work window"
        )
        attachScreenshot(named: "01-strength-work-window")

        // US-CC01: a prominent Done control is present, reachable by a finger, and advances the window
        // early - no penalty, no "did you finish?" prompt.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the work window has no Done control")
        XCTAssertTrue(done.isHittable, "the Done control is not reachable by a finger")
        done.tap()

        // Done advances immediately: into the between-set rest, or - if that was the final set - into
        // the completion screen. Either proves the set was recorded and the session moved on, and
        // neither is a skip or a confirmation prompt.
        let advancedIntoRest = app.buttons["Skip rest"].waitForExistence(timeout: 5)
        let advancedIntoCompletion = app.staticTexts["You showed up."].waitForExistence(timeout: 5)
        XCTAssertTrue(
            advancedIntoRest || advancedIntoCompletion,
            "Done did not advance the session into the rest or the completion screen"
        )
        attachScreenshot(named: "02-after-done")
    }

    /// Files the running app's screen as a `.keepAlways` `.xcresult` attachment, so a reviewer opens a
    /// picture of the actual auto-advancing player on a green run rather than reading a selector
    /// transcript.
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
