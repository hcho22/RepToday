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
///
/// **How a launch stays off the wire, structurally.** Every launch here goes through `TestApp`
/// (`TestApp.swift`), the bundle's sole `XCUIApplication`, named with a `TelemetryPosture` that has no
/// "neither guard" case - so a launch carrying no guard is not expressible, and a test cannot even
/// hold a raw launchable app. `XCUIApplication` is a framework type any file can still construct, so
/// the guarantee is "cannot ship a bypass" rather than "cannot type one": `UITestLaunchGuardTests` in
/// the unit bundle fails the default `RepToday` test run if any UI-test source constructs one outside
/// the wrapper. That build guard replaces an earlier runtime detector, which tried to notice a bypass
/// after the fact and had a blind spot (a standalone bare `app.launch()`); a source scan has no launch
/// orderings to miss.
final class TelemetryOptOutUITests: XCTestCase {

    private var app: TestApp!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = TestApp(self)
        // Start each test from a clean slate. `TestApp` builds a fresh `XCUIApplication` per test, but
        // the app *process* survives from the previous case, so a leftover is terminated before this
        // test launches its own posture into it.
        app.terminate()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Launching
    //
    // `TelemetryPosture` and the sole `launch(_:)` path live on `TestApp` (`TestApp.swift`), which
    // owns the only `XCUIApplication` in the bundle. The suite cannot hold a launchable raw app, and
    // `UITestLaunchGuardTests` fails the build if any UI-test source constructs one outside the
    // wrapper - so "every launch carries a posture, and neither-guard is not representable" holds
    // structurally rather than by a runtime detector watching for a bypass after the fact.

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
        app.launch(.probeWithConsentOff)

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
        app.launch(.probeWithConsentDefaultOn)

        waitForAttemptCount(1)
    }

    /// The launch argument reaches the same flag the user's own control shows: an app parked opted
    /// out renders its Settings toggle off, which is what makes the two halves the same gate rather
    /// than two that happen to agree.
    func testTheLaunchArgumentAndTheSettingsToggleAreTheSameFlag() throws {
        app.launch(.probeWithConsentOff)

        let toggle = openSettingsToggle()
        XCTAssertEqual(toggle.value as? String, "0", "the launch argument did not reach the user-facing control")

        app.terminate()
        app.launch(.probeWithConsentDefaultOn)

        XCTAssertEqual(openSettingsToggle().value as? String, "1", "the default install is not opted in")
    }

    /// Turning the toggle off is honoured on the very next event, with no relaunch: one attempt from
    /// launch, none while off, and emission resumes when it goes back on.
    ///
    /// This is the only leg that needs the HUD's emit button - every real emission site is still ahead
    /// (US-T07 through US-T12), so there is nothing else in the app to press that produces an event.
    func testTogglingTelemetryOffAndOnIsHonouredWithoutARestart() throws {
        app.launch(.probeWithConsentDefaultOn)
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
    ///
    /// `whileOnSettings` runs after the switch has settled and before Settings is popped, which is
    /// where a render of the control in its new state has to be taken from.
    private func setSettingsToggle(
        on: Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        whileOnSettings: () -> Void = {}
    ) {
        let toggle = openSettingsToggle(file: file, line: line)
        move(toggle, on: on, file: file, line: line)
        whileOnSettings()

        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Drives the switch itself to `on` and waits for it to report that state.
    private func move(_ toggle: XCUIElement, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
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
    }

    // MARK: - What a reviewer sees

    /// Renders the surfaces this story adds, from the running app, in the order a user meets them:
    /// the onboarding disclosure, the Profile row that leads to Settings, and the toggle in both
    /// states with the probe HUD's attempt count beside it.
    ///
    /// The assertions here are already made by the tests above; what this adds is a picture, because
    /// "the opt-out is findable and honestly worded" is a claim about a screen and cannot be settled
    /// by a count. Each render is filed with the result bundle, so it needs no directory of its own.
    func testRendersTheConsentSurfacesAndTheGateChangingTheCount() throws {
        // 1. The disclosure, on the *first* onboarding screen, with no probe HUD standing over it.
        // `.optedOutWithNoProbe` is what makes that true and safe at once: no harness means no HUD in
        // the picture, and consent pinned off means this launch cannot dispatch even once US-T07
        // lands an emission site at app entry.
        app.launch(.optedOutWithNoProbe, onboarded: false)
        XCTAssertTrue(
            app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 20),
            "onboarding never reached its first screen"
        )
        capture("01-onboarding-disclosure")
        app.terminate()

        // 2. Everything below is one launch, so what the renders show is a live toggle rather than a
        // sequence of relaunches into pre-set states.
        app.launch(.probeWithConsentDefaultOn)
        waitForAttemptCount(1)

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "the app never reached the main tabs")
        profile.tap()
        capture("02-profile-settings-row")

        openSettingsToggle()
        capture("03-settings-toggle-on")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 3. One attempt from app entry, a second from the HUD, then the toggle goes off and the
        // third attempt is never dispatched - the count in the render is the gate's answer.
        let emit = app.buttons["telemetry.probe.emit"]
        XCTAssertTrue(emit.waitForExistence(timeout: 10), "the probe HUD has no emit control")
        emit.tap()
        waitForAttemptCount(2)

        setSettingsToggle(on: false) { capture("04-settings-toggle-off") }
        emit.tap()
        settleForAnyPendingSend()
        capture("05-hud-after-emitting-while-opted-out")
        XCTAssertEqual(attemptCount(), 2, "an event was sent after the user turned telemetry off")

        setSettingsToggle(on: true)
        emit.tap()
        waitForAttemptCount(3)
        capture("06-hud-after-turning-telemetry-back-on")
    }

    /// Files a full-screen render with the result bundle under `name`, kept whether or not the test
    /// fails - the point of these is to be looked at on a green run.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
