import XCTest

/// Fails the **default** `RepToday` test run if the active-session player ever grows a user-facing
/// "manual mode" toggle (US-CC06, and the PRD Non-Goals).
///
/// The continuous-circuit design has exactly one player: the hands-free follow-along flow. Self-pacing
/// is preserved not by a second mode but by the quiet in-flow escape hatches (**+ More time**, **Done**,
/// **Pause**, **Skip**, **Swap**, round-rest **+/skip**). A "manual mode" toggle would reintroduce the
/// retired tap-to-advance model the PRD explicitly removes, so this guard turns "there is no manual mode"
/// from a review-time promise into a build-time fact - the same enforcement pattern as
/// `UITestLaunchGuardTests`, and living in the routinely-run unit bundle for the same reason (the gate is
/// `-scheme RepToday test`, which the XCUITest scheme is not part of).
///
/// It scans the active-session player sources for a `manualMode` / `ManualMode` identifier. This catches
/// the concrete regression - a `manualMode` state flag, a `ManualMode` enum, an `isManualMode` toggle -
/// without being so broad it trips on prose: the word "manual" appears legitimately in comments (the
/// *manual* Start-hold path, the *manual* Complete set), so the guard keys on the camel/Pascal-cased
/// identifier a real toggle would introduce, not the English word.
final class NoManualModeGuardTests: XCTestCase {

    func testTheActiveSessionPlayerHasNoManualModeToggle() throws {
        // Built by concatenation so this guard's own source never contains the literal it hunts for.
        let needles = ["manual" + "Mode", "Manual" + "Mode"]

        // `#filePath` -> `<repo>/ios/RepToday/RepTodayTests/NoManualModeGuardTests.swift`. The player
        // sources sit under `<repo>/ios/RepToday/RepToday/` in the ViewModels and Views/ActiveSession
        // directories; walk up to the app source root and scan both, the same source anchor the launch
        // guard and the evidence suites use.
        let appSourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepTodayTests
            .deletingLastPathComponent() // RepToday
            .appendingPathComponent("RepToday") // app sources

        let playerSources = [
            appSourceRoot.appendingPathComponent("ViewModels/ActiveSessionViewModel.swift"),
            appSourceRoot.appendingPathComponent("Views/ActiveSession/ActiveSessionView.swift")
        ]

        let fileManager = FileManager.default
        for source in playerSources {
            XCTAssertTrue(
                fileManager.fileExists(atPath: source.path),
                """
                could not find the player source at \(source.path). If the project layout moved, update \
                this guard - it silently passing would leave "no manual mode" unenforced.
                """
            )
            let text = try String(contentsOf: source, encoding: .utf8)
            for needle in needles {
                XCTAssertFalse(
                    text.contains(needle),
                    """
                    \(source.lastPathComponent) references `\(needle)`. The continuous-circuit player is \
                    the only player (US-CC06, PRD Non-Goals): self-pacing lives in the quiet in-flow \
                    escape hatches (+ More time, Done, Pause, Skip, Swap, round-rest +/skip), never a \
                    separate manual mode. Remove the mode toggle - a second mode is exactly what this \
                    guard exists to keep from shipping.
                    """
                )
            }
        }
    }
}
