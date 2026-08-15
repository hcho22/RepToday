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
///
/// A second case (US-CC02) drives the strength block as a circuit through the shipped controls and
/// reads the "Round N of M" label off the running player, confirming the rotation and the round label a
/// real finger sees - the one thing the in-process rotation tests cannot exercise.
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

    /// US-CC02: the strength block plays as a circuit through the shipped controls - the player surfaces
    /// "Round N of M" and rotates one set of each exercise per round rather than grinding all sets of one
    /// exercise first. Driven hands-free with **Done** so what is exercised is the production rotation a
    /// finger reaches, not a view-model call.
    func testStrengthBlockRotatesThroughRoundsHandsFree() {
        app.launch(.optedOutWithNoProbe)

        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "the Ready Screen never offered Start")
        start.tap()

        // Reach the first rep-based strength work window, skipping past the warm-up holds and any rests.
        let workWindow = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Work window"))
            .firstMatch
        var reachedWorkWindow = false
        for _ in 0..<30 {
            if workWindow.waitForExistence(timeout: 2) { reachedWorkWindow = true; break }
            if app.buttons["Skip rest"].exists { app.buttons["Skip rest"].tap(); continue }
            if app.buttons["Skip this exercise"].exists { app.buttons["Skip this exercise"].tap(); continue }
        }
        XCTAssertTrue(reachedWorkWindow, "never reached a rep-based strength set")

        // The training block is a circuit, so it surfaces "Round N of M" (US-CC02).
        XCTAssertNotNil(firstLabel(beginningWith: "Round "), "the strength circuit surfaced no \"Round N of M\" label")
        attachScreenshot(named: "01-round-label")

        // Rotate hands-free, recording the (round, exercise) pairs a finger sees. A circuit plays one set
        // of each exercise per round, so within a round the exercise changes station to station, or the
        // round advances - either proves the rotation; grinding all sets of one exercise first would show
        // the same exercise repeat with an unchanged round.
        var seen: [(round: String, exercise: String)] = []
        for _ in 0..<12 {
            guard let round = firstLabel(beginningWith: "Round "), let exercise = currentExerciseName() else { break }
            seen.append((round: round, exercise: exercise))
            guard app.buttons["Done"].waitForExistence(timeout: 4) else { break }
            app.buttons["Done"].tap()
            // Clear the between-station transition / between-round rest, then reach the next work window.
            if app.buttons["Skip rest"].waitForExistence(timeout: 4) { app.buttons["Skip rest"].tap() }
            if !workWindow.waitForExistence(timeout: 4) { break } // left the block (cooldown) or finished
        }
        attachScreenshot(named: "02-after-rotation")

        let round1 = seen.filter { $0.round.hasPrefix("Round 1 of") }
        let distinctExercisesInRound1 = Set(round1.map(\.exercise))
        let distinctRounds = Set(seen.map(\.round))
        XCTAssertTrue(
            distinctExercisesInRound1.count > 1 || distinctRounds.count > 1,
            "the strength block should play as a circuit - more than one exercise per round, or more than "
            + "one round - not grind one exercise's sets before the next; saw \(seen)"
        )
    }

    /// The label of the first element whose accessibility label begins with `prefix`, or `nil` if none
    /// appears in time.
    private func firstLabel(beginningWith prefix: String) -> String? {
        let element = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
        return element.waitForExistence(timeout: 3) ? element.label : nil
    }

    /// The exercise on screen, read off the headline the player combines as "<name>, <spoken target>"
    /// (the spoken target names its sets), so the prefix before the comma is the movement's name.
    private func currentExerciseName() -> String? {
        let element = app
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "sets of", "set of"))
            .firstMatch
        guard element.waitForExistence(timeout: 3) else { return nil }
        return element.label.components(separatedBy: ",").first
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
