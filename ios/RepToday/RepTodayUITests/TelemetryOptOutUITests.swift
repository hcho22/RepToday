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
        // Closes the one ordering the entry check cannot see: a raw launch that happens after the
        // last helper launch, with nothing following it to trip the check on the way in.
        assertNobodyLaunchedBehindOurBack()
        lastArgumentsSetHere = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Launching

    /// How a launch keeps itself off the wire. **Every launch in this suite must pick one**, and the
    /// point of modelling it as an enum is that "neither" is not representable.
    ///
    /// This exists because it was got wrong once, here, inside the story whose whole purpose is the
    /// guarantee: a render leg opened with a raw `app.launchArguments = [...]` carrying no guard at
    /// all, which built the real transport against the dev deployment with the gate open. It was
    /// harmless only because nothing calls `record(_:)` yet - the moment US-T07 hangs `app_install`
    /// off app entry, that launch would POST a live row on every run. US-T04 faced the same shape of
    /// problem and answered it the same way, reworking FR-13 so it held "structural rather than a
    /// reading of the current code"; a per-launch opt-in guard that a raw assignment silently
    /// bypasses is exactly a guarantee that holds only while every future author remembers.
    ///
    /// Note that the invariant is **not** "consent is always off". Two tests need the gate genuinely
    /// open - the positive control, without which the zero-attempts assertion is vacuous, and the
    /// runtime-toggle test - and they are safe because the probe harness swaps the transport's
    /// `URLSession` for an in-process counting `URLProtocol`. So there are two ways to be safe, and
    /// each case below carries at least one of them.
    private enum TelemetryPosture {
        /// Consent pinned off by `-AppState.analyticsEnabled NO`, and **no probe harness** - so
        /// nothing can be dispatched, and no HUD stands over the screen. This is the posture for
        /// renders, where the probe overlay would be in the picture.
        case optedOutWithNoProbe

        /// Probe harness on, consent left at the shipped default (on). The gate is open and the
        /// interceptor is what keeps the run off the network.
        case probeWithConsentDefaultOn

        /// Probe harness on *and* consent pinned off - both guards, for the tests that assert the
        /// gate closes.
        case probeWithConsentOff

        /// The launch arguments this posture contributes, beyond onboarding routing.
        var arguments: [String] {
            switch self {
            case .optedOutWithNoProbe:
                return ["-AppState.analyticsEnabled", "NO"]
            case .probeWithConsentDefaultOn:
                return ["-RepTodayTelemetryProbe", "YES"]
            case .probeWithConsentOff:
                return ["-RepTodayTelemetryProbe", "YES", "-AppState.analyticsEnabled", "NO"]
            }
        }
    }

    /// The **only** sanctioned way to launch in this suite. Every call names its telemetry posture,
    /// and no posture leaves the app able to reach the network.
    ///
    /// `UserDefaults` reads the argument domain ahead of the persisted one, so `-AppState.*` values
    /// land without the test reaching into the installed app's container - a run never inherits what
    /// the previous one's toggling left behind.
    ///
    /// - Parameter onboarded: `false` parks the app on onboarding, for the disclosure render.
    private func launch(_ posture: TelemetryPosture, onboarded: Bool = true) {
        assertNobodyLaunchedBehindOurBack()
        app.launchArguments =
            ["-AppState.isOnboarded", onboarded ? "YES" : "NO"] + posture.arguments
        lastArgumentsSetHere = app.launchArguments
        app.launch()
        // The main tabs raise the Health share prompt as they appear (US-N03); it stands over the
        // probe HUD and the Profile tab alike, so it is answered before anything is read.
        answerHealthAccessSheetIfPresented(in: app)
    }

    /// What `launch(_:onboarded:)` last wrote, so a change made by anything else is detectable.
    private var lastArgumentsSetHere: [String]?

    /// The net under the enum, for a launch that never went through `launch(_:onboarded:)` at all.
    ///
    /// `TelemetryPosture` makes an unguarded launch unrepresentable *through the helper*, but a
    /// future `app.launchArguments = [...]` written straight into a test sails past the type system -
    /// which is precisely how this suite acquired the hole in the first place. So the bypass is
    /// caught by state instead: `launchArguments` persists on the application object, so any value
    /// there that this helper did not write came from somewhere else.
    ///
    /// **This is checked on entry to every launch, not only at teardown, and the difference is the
    /// whole point.** Teardown alone sees only the *final* arguments, and the bug this exists to
    /// catch was a test that launched unguarded and then launched again through the helper - the
    /// second launch overwrites the first, so teardown finds a guarded array and reports nothing.
    /// That is not a hypothetical: this net was written teardown-only, and a deliberate re-injection
    /// of the original bug passed it. Checking here as well closes the raw-then-helper ordering,
    /// and the teardown call closes a raw launch that happens last.
    private func assertNobodyLaunchedBehindOurBack(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let app else { return }
        let arguments = app.launchArguments
        // Nothing has launched yet, or these are exactly the arguments this helper installed.
        guard !arguments.isEmpty, arguments != lastArgumentsSetHere else { return }

        let optedOut = zip(arguments, arguments.dropFirst())
            .contains { $0 == "-AppState.analyticsEnabled" && $1 == "NO" }
        let probed = zip(arguments, arguments.dropFirst())
            .contains { $0 == "-RepTodayTelemetryProbe" && $1 == "YES" }

        XCTAssertTrue(
            optedOut || probed,
            """
            a launch in this suite bypassed `launch(_:onboarded:)` and carried neither telemetry \
            guard: \(arguments). Every launch must either pin consent off \
            (-AppState.analyticsEnabled NO) or arm the probe harness (-RepTodayTelemetryProbe YES), \
            which intercepts the transport in process. Without one of the two, the launch builds the \
            real transport against the dev deployment with the gate open, and will POST live rows \
            into the telemetry table once US-T07 adds an emission call site. Launch through \
            `launch(_:onboarded:)` and name a `TelemetryPosture`.
            """,
            file: file, line: line
        )
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
        launch(.probeWithConsentOff)

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
        launch(.probeWithConsentDefaultOn)

        waitForAttemptCount(1)
    }

    /// The launch argument reaches the same flag the user's own control shows: an app parked opted
    /// out renders its Settings toggle off, which is what makes the two halves the same gate rather
    /// than two that happen to agree.
    func testTheLaunchArgumentAndTheSettingsToggleAreTheSameFlag() throws {
        launch(.probeWithConsentOff)

        let toggle = openSettingsToggle()
        XCTAssertEqual(toggle.value as? String, "0", "the launch argument did not reach the user-facing control")

        app.terminate()
        launch(.probeWithConsentDefaultOn)

        XCTAssertEqual(openSettingsToggle().value as? String, "1", "the default install is not opted in")
    }

    /// Turning the toggle off is honoured on the very next event, with no relaunch: one attempt from
    /// launch, none while off, and emission resumes when it goes back on.
    ///
    /// This is the only leg that needs the HUD's emit button - every real emission site is still ahead
    /// (US-T07 through US-T12), so there is nothing else in the app to press that produces an event.
    func testTogglingTelemetryOffAndOnIsHonouredWithoutARestart() throws {
        launch(.probeWithConsentDefaultOn)
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
        launch(.optedOutWithNoProbe, onboarded: false)
        XCTAssertTrue(
            app.staticTexts["Welcome to Rep Today"].waitForExistence(timeout: 20),
            "onboarding never reached its first screen"
        )
        capture("01-onboarding-disclosure")
        app.terminate()

        // 2. Everything below is one launch, so what the renders show is a live toggle rather than a
        // sequence of relaunches into pre-set states.
        launch(.probeWithConsentDefaultOn)
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
