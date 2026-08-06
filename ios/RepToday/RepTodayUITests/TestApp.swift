import XCTest

/// How a launch keeps itself off the wire. **Every launch in `RepTodayUITests` must pick one**, and
/// the point of modelling it as an enum is that "neither" is not representable: there is no case that
/// leaves a launch able to reach the network, and `TestApp.launch(_:)` - the suite's only launch path -
/// takes one of these by value, so a launch that named no posture would not compile.
///
/// The invariant is **not** "consent is always off". Two `TelemetryOptOutUITests` legs need the gate
/// genuinely open - the positive control, without which the zero-attempts assertion is vacuous, and
/// the runtime-toggle test - and they are safe because the probe harness swaps the transport's
/// `URLSession` for an in-process counting `URLProtocol`. So there are two ways to be safe, and each
/// case below carries at least one of them.
enum TelemetryPosture {
    /// Consent pinned off by `-AppState.analyticsEnabled NO`, and **no probe harness** - so nothing
    /// can be dispatched, and no HUD stands over the screen. This is the posture for renders, where
    /// the probe overlay would be in the picture, and for `OnboardingImperialUITests`, which walks the
    /// real onboarding flow and only needs to be off the wire.
    case optedOutWithNoProbe

    /// Probe harness on, consent left at the shipped default (on). The gate is open and the
    /// interceptor is what keeps the run off the network.
    case probeWithConsentDefaultOn

    /// Probe harness on *and* consent pinned off - both guards, for the tests that assert the gate
    /// closes.
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

/// The suite's **sole** launchable application. `RepTodayUITests` used to hand every test a raw
/// `XCUIApplication`, and the launch guard sat *behind* that: a `TelemetryPosture` enum plus a
/// runtime detector (`assertNobodyLaunchedBehindOurBack`) that tried to notice a launch which skipped
/// the sanctioned helper. That net *detected* rather than *prevented*, and it leaked - four
/// corrections each closed one launch ordering and revealed another, and a standalone bare
/// `app.launch()` was caught in one ordering but not the other, root cause undiagnosed. The signature
/// of an approach that leaks by nature.
///
/// `TestApp` closes that structurally by owning the only `XCUIApplication` in the bundle. It is
/// `private let`, exposed only through the posture-typed `launch(_:)` and the read-only element
/// queries a test legitimately needs - so a test cannot hold a launchable app to begin with, and the
/// enum stays the only way to express a launch. What that does **not** achieve on its own is a compile
/// error for `let a = XCUIApplication(); a.launch()` written straight into a test: `XCUIApplication` is
/// an Apple framework type any file can import and construct, so the type system alone cannot forbid a
/// second instance. The guarantee is therefore "**cannot ship a bypass**", not "cannot type one":
/// `UITestLaunchGuardTests` in the unit bundle scans every `RepTodayUITests` source and fails the
/// default test run if `XCUIApplication(` is constructed anywhere but this file. So a bypass fails the
/// build rather than being detected at runtime after the fact - which is why the old detector is
/// retired rather than kept as defence in depth: with no raw application constructible in a test,
/// there is nothing to launch behind anyone's back, and a second net over a hole that can no longer
/// exist is only more surface to drift.
final class TestApp {

    /// The one `XCUIApplication` the bundle is allowed to build. Kept private: the whole point is that
    /// no test ever holds a launchable app, so launching goes through `launch(_:)` and nothing else.
    private let app: XCUIApplication

    /// Held so the shared `answerHealthAccessSheetIfPresented(in:)` seam (an `XCTestCase` extension)
    /// can run its `XCTAssert`s and file failures against the owning test. `unowned` because the test
    /// owns the wrapper, not the other way round, and they share a lifetime.
    private unowned let testCase: XCTestCase

    init(_ testCase: XCTestCase) {
        self.testCase = testCase
        self.app = XCUIApplication()
    }

    // MARK: - Launching

    /// The **only** way to launch in this suite. Every call names its telemetry posture, and no
    /// posture leaves the app able to reach the network.
    ///
    /// `UserDefaults` reads the argument domain ahead of the persisted one, so `-AppState.*` values
    /// land without the test reaching into the installed app's container - a run never inherits what
    /// the previous one's toggling left behind.
    ///
    /// - Parameters:
    ///   - posture: the telemetry guard this launch carries; there is no "neither" case.
    ///   - onboarded: `false` parks the app on onboarding, for the disclosure render and for
    ///     `OnboardingImperialUITests`, which walks the flow from its first screen.
    ///   - answersHealthPrompt: whether to dismiss the Health share sheet the main tabs raise on
    ///     arrival. `true` for launches that land on the tabs; `false` for a launch that parks on
    ///     onboarding, where there is no sheet and the wait would only cost time.
    func launch(_ posture: TelemetryPosture, onboarded: Bool = true, answersHealthPrompt: Bool = true) {
        app.launchArguments = ["-AppState.isOnboarded", onboarded ? "YES" : "NO"] + posture.arguments
        app.launch()
        if answersHealthPrompt {
            answerHealthPromptIfPresented()
        }
    }

    /// Terminates the running app, for the tests that relaunch mid-case into a different posture.
    func terminate() {
        app.terminate()
    }

    /// Answers the Health share prompt the main tabs raise as they appear (US-N03), via the shared
    /// `RepTodayUITests/HealthAccessPrompt.swift` seam. The private `app` never leaves the wrapper
    /// except into that trusted helper, which only queries the sheet and never launches.
    func answerHealthPromptIfPresented() {
        testCase.answerHealthAccessSheetIfPresented(in: app)
    }

    // MARK: - Reading the running app

    // Read-only query surfaces forwarded from the private application. None of these can launch; they
    // are how a test reaches the live element tree without ever holding the app itself.

    var staticTexts: XCUIElementQuery { app.staticTexts }
    var buttons: XCUIElementQuery { app.buttons }
    var switches: XCUIElementQuery { app.switches }
    var tabBars: XCUIElementQuery { app.tabBars }
    var navigationBars: XCUIElementQuery { app.navigationBars }
    var links: XCUIElementQuery { app.links }
    var textFields: XCUIElementQuery { app.textFields }
    var keyboards: XCUIElementQuery { app.keyboards }
    var otherElements: XCUIElementQuery { app.otherElements }

    func descendants(matching type: XCUIElement.ElementType) -> XCUIElementQuery {
        app.descendants(matching: type)
    }

    func coordinate(withNormalizedOffset offset: CGVector) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: offset)
    }
}
