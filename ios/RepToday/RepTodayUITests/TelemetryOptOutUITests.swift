import XCTest

/// The opt-out gate proved **out of process** (US-T06, criterion 8).
///
/// **Why this suite is hard to make mean anything, and what was done about it.** `RepTodayUITests`
/// launches the real app, so the test process never builds the `ServiceContainer` and US-T04's
/// `analyticsService` parameter cannot reach it; the only gate there is `LiveAnalyticsService`'s
/// `isEnabled` closure, which US-T06 points at the persisted `AppState.analyticsEnabled` flag. But no
/// emission call site exists yet - they are US-T07 through US-T12 - so "zero network calls with
/// telemetry off" is *trivially* true today for reasons that have nothing to do with the flag. A test
/// asserting it as written would pass with the flag deleted, and would keep passing when US-T07
/// starts POSTing on every launch.
///
/// So the app carries a Debug-only, launch-argument-gated harness (`TelemetryUITestHarness`) that
/// supplies the two things the shipping build does not: an emission attempt for the gate to block,
/// and somewhere another process can count attempts from. Under `-RepTodayTelemetryProbe YES` the
/// app clears its persisted consent flag, replaces the telemetry transport's `URLSession` with an
/// in-process counting interceptor, emits one `app_install` from `RepTodayApp.init()` - the exact
/// name and the exact place US-T07's first real emission will use - and renders the running count in
/// a HUD this suite reads.
///
/// **What these tests prove.** That the gate, in the real app, decides whether the transport
/// dispatches a request at all: with the flag off nothing is dispatched, with it on something is
/// (the positive control, without which the "zero" assertion is the vacuous case wearing a
/// disguise), and flipping the Settings toggle changes the answer for the *next* event with no
/// relaunch in between.
///
/// **What they do not prove.** The count is taken at the `URLProtocol` boundary - the same boundary
/// `LiveAnalyticsServiceTests` treats as authoritative in process - so an attempt means the transport
/// built and dispatched a request, not that bytes reached Convex. That is deliberate: a run that let
/// real bytes out would break FR-13, which forbids any test performing a real network call. Nor do
/// they prove anything about a Release build, which compiles none of the harness and today has no
/// configured endpoint at all.
final class TelemetryOptOutUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Launching

    /// Launches the real app with the probe harness on, onboarding already complete (so the Profile
    /// tab and its Settings screen are reachable), and - optionally - the consent flag pinned.
    ///
    /// `UserDefaults` reads the argument domain ahead of the persisted one, so `-AppState.*` values
    /// land without the test reaching into the installed app's container. Passing no consent argument
    /// leaves the app on the shipped default, which the harness has just reset to, so a run never
    /// inherits what the previous one's toggling left behind.
    private func launch(consent: String? = nil) {
        var arguments = [
            "-AppState.isOnboarded", "YES",
            "-RepTodayTelemetryProbe", "YES"
        ]
        if let consent {
            arguments += ["-AppState.analyticsEnabled", consent]
        }
        app.launchArguments = arguments
        app.launch()
        // The main tabs raise the Health share prompt as they appear (US-N03); it stands over the
        // probe HUD and the Profile tab alike, so it is answered before anything is read.
        answerHealthAccessSheetIfPresented(in: app)
    }

    /// The HUD's running count of telemetry requests the transport dispatched this launch.
    private func attemptCount(file: StaticString = #filePath, line: UInt = #line) -> Int {
        let readout = app.staticTexts["telemetry.probe.attempts"]
        guard readout.waitForExistence(timeout: 15) else {
            XCTFail("the telemetry probe HUD never appeared - the harness did not arm", file: file, line: line)
            return -1
        }
        // "telemetry attempts: 2" - the digits are the whole payload.
        return Int(readout.label.filter(\.isNumber)) ?? -1
    }

    /// Waits for the count to reach `expected`, or fails saying what it actually reached.
    private func waitForAttemptCount(
        _ expected: Int, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
    ) {
        let readout = app.staticTexts["telemetry.probe.attempts"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "no probe HUD", file: file, line: line)
        let predicate = NSPredicate(format: "label ENDSWITH %@", ": \(expected)")
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: readout)
        if XCTWaiter().wait(for: [matched], timeout: timeout) != .completed {
            XCTFail(
                "expected \(expected) telemetry attempts, the app reports \"\(readout.label)\"",
                file: file, line: line
            )
        }
    }

    /// Gives a dispatched send every chance to arrive before "nothing arrived" is asserted. The
    /// positive control below reaches its first attempt well inside this, so a silent run is silence
    /// rather than slowness.
    private func settleForAnyPendingSend() {
        _ = app.staticTexts["telemetry.probe.attempts"]
            .waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 4)
    }

    // MARK: - The gate

    /// **The criterion.** Launched with telemetry off, the real app dispatches no telemetry request
    /// at all - not one that fails, not one that is dropped: none is built.
    func testTelemetryOffMeansTheAppDispatchesNothing() throws {
        launch(consent: "NO")

        settleForAnyPendingSend()

        XCTAssertEqual(
            attemptCount(), 0,
            "the app tried to send telemetry while the user was opted out"
        )
    }

    /// **The positive control**, and the reason the assertion above is not vacuous: the identical run
    /// with the flag left at its default emits, so the zero is the gate's doing rather than the
    /// absence of anything to emit.
    func testTelemetryOnMeansTheSameLaunchDoesDispatch() throws {
        launch()

        waitForAttemptCount(1)
    }

    /// The launch argument reaches the same flag the user's own control shows: an app parked opted
    /// out renders its Settings toggle off, which is what makes the two halves the same gate rather
    /// than two that happen to agree.
    func testTheLaunchArgumentAndTheSettingsToggleAreTheSameFlag() throws {
        launch(consent: "NO")

        let toggle = openSettingsToggle()
        XCTAssertEqual(toggle.value as? String, "0", "the launch argument did not reach the user-facing control")

        app.terminate()
        launch()

        XCTAssertEqual(openSettingsToggle().value as? String, "1", "the default install is not opted in")
    }

    /// Turning the toggle off is honoured on the very next event, with no relaunch: one attempt from
    /// launch, none while off, and emission resumes when it goes back on.
    ///
    /// This is the only leg that needs the HUD's emit button - every real emission site is still ahead
    /// (US-T07 through US-T12), so there is nothing else in the app to press that produces an event.
    func testTogglingTelemetryOffAndOnIsHonouredWithoutARestart() throws {
        launch()
        waitForAttemptCount(1)

        let emit = app.buttons["telemetry.probe.emit"]
        XCTAssertTrue(emit.waitForExistence(timeout: 10), "the probe HUD has no emit control")
        emit.tap()
        waitForAttemptCount(2)

        setSettingsToggle(on: false)
        emit.tap()
        settleForAnyPendingSend()
        XCTAssertEqual(attemptCount(), 2, "an event was sent after the user turned telemetry off")

        setSettingsToggle(on: true)
        emit.tap()
        waitForAttemptCount(3)
    }

    // MARK: - Reaching Settings the way a user does

    /// Walks Profile -> Settings and returns the telemetry switch, asserting on the way that it is
    /// reachable by a finger and labelled - two more of this story's criteria.
    @discardableResult
    private func openSettingsToggle(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs", file: file, line: line)
        profile.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Profile has no Settings row", file: file, line: line)
        XCTAssertTrue(settings.isHittable, "the Settings row is not reachable by a finger", file: file, line: line)
        settings.tap()

        let toggle = app.switches["Share anonymous usage data"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "Settings has no clearly-labelled anonymous-usage-data toggle", file: file, line: line
        )
        XCTAssertTrue(toggle.isHittable, "the toggle is not reachable by a finger", file: file, line: line)
        XCTAssertTrue(
            app.links["Privacy Policy"].exists || app.buttons["Privacy Policy"].exists,
            "Settings carries no privacy-policy link", file: file, line: line
        )
        return toggle
    }

    /// Puts the toggle into `on` and returns to the tab root, so the HUD's emit button is clear again.
    private func setSettingsToggle(on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = openSettingsToggle(file: file, line: line)
        let wanted = on ? "1" : "0"
        if toggle.value as? String != wanted {
            // Pressed on the switch itself rather than on the element's centre: the accessibility
            // element spans the whole row, whose middle is the label, and a tap there does not move a
            // SwiftUI `Toggle` in a `List`. The switch sits at the row's trailing edge, which is
            // where a thumb finds it too.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let predicate = NSPredicate(format: "value == %@", wanted)
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        if XCTWaiter().wait(for: [matched], timeout: 5) != .completed {
            XCTFail("the toggle would not move to \(wanted)", file: file, line: line)
        }

        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
