import XCTest

/// Fails the **default** `RepToday` test run if any `RepTodayUITests` source constructs a raw
/// `XCUIApplication` outside the one file allowed to (`TestApp.swift`).
///
/// This is the enforcement half of the launch wrapper. `TestApp` makes the raw application
/// unreachable through the API a test sees, but `XCUIApplication` is an Apple framework type any file
/// can import and instantiate, so the type system alone cannot forbid a second instance being typed
/// into a test. This guard supplies the missing guarantee at the level the project can actually hold:
/// a bypass **cannot ship**, because it fails the build rather than being detected at runtime after
/// the fact. It lives in the unit bundle on purpose - this repo has no CI, and the routinely-run gate
/// is `-scheme RepToday test`, which runs `RepTodayTests` and not the on-demand `RepTodayUITests`
/// scheme - so putting the scan here is what makes "cannot ship" mean the run everyone actually
/// performs, rather than one that has to be remembered.
///
/// It replaces the retired runtime detector (`assertNobodyLaunchedBehindOurBack`), which tried to
/// *notice* an unsanctioned launch and had an empirically-verified blind spot (a standalone bare
/// `app.launch()`). A source scan has no such orderings to miss: it does not matter when or whether a
/// stray application is launched, only that its construction is present in the source, which is a
/// static fact this reads directly.
final class UITestLaunchGuardTests: XCTestCase {

    func testNoUITestSourceConstructsARawApplicationOutsideTheWrapper() throws {
        // Built by concatenation so this guard's own source never contains the literal it hunts for -
        // defensive in case the guard is ever moved into the UI bundle it scans.
        let constructor = "XCUIApplication" + "("
        let wrapperFileName = "TestApp.swift"

        // `#filePath` is this file's absolute path, baked at compile time; the UI bundle sits beside
        // this one. A test bundle controls neither its working directory nor its arguments, so walking
        // up from the source is the one stable anchor - the same way the evidence suites locate the
        // repo. `<repo>/ios/RepToday/RepTodayTests/UITestLaunchGuardTests.swift`
        // -> `<repo>/ios/RepToday/RepTodayUITests`.
        let uiTestsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RepTodayTests
            .deletingLastPathComponent() // RepToday
            .appendingPathComponent("RepTodayUITests")

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            fileManager.fileExists(atPath: uiTestsDirectory.path, isDirectory: &isDirectory)
                && isDirectory.boolValue,
            """
            could not find the RepTodayUITests source directory at \(uiTestsDirectory.path). If the \
            project layout moved, update this guard - it silently passing would leave the launch \
            wrapper unenforced.
            """
        )

        let swiftFiles = (fileManager.enumerator(at: uiTestsDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        XCTAssertFalse(
            swiftFiles.isEmpty,
            "found no Swift sources under \(uiTestsDirectory.path) - the guard is scanning the wrong place"
        )

        // Positive control: the wrapper *must* be the one file that constructs the application. If it
        // is not seen, the scan is looking somewhere empty or the wrapper was renamed - either way the
        // guard would otherwise pass vacuously, which is exactly how the retired runtime check first
        // shipped broken.
        var wrapperConstructsTheApp = false

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let constructsApplication = source.contains(constructor)

            if file.lastPathComponent == wrapperFileName {
                wrapperConstructsTheApp = constructsApplication
                continue
            }

            XCTAssertFalse(
                constructsApplication,
                """
                \(file.lastPathComponent) constructs a raw \(constructor) itself. Every launch in \
                RepTodayUITests must go through `TestApp`, the suite's sole XCUIApplication, named \
                with a `TelemetryPosture` so no launch can reach the network. Move this launch behind \
                `TestApp.launch(_:)`; a raw application is exactly the bypass this guard exists to \
                keep from shipping.
                """
            )
        }

        XCTAssertTrue(
            wrapperConstructsTheApp,
            """
            \(wrapperFileName) does not construct \(constructor). The wrapper is meant to be the one \
            place that does; if it was renamed or the construction removed, update this guard so it \
            cannot pass without actually checking anything.
            """
        )
    }
}
