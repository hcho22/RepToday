import XCTest

/// The imperial basics step pressed with a real finger (US-O04).
///
/// `OnboardingBasicsEvidenceTests` hosts the same screen in the unit bundle and can say what it draws
/// and what VoiceOver speaks, but not what a touch does to it: a `Button`'s press state comes from
/// touch delivery, which only a real run of the app has. That gap is exactly where this step's
/// hand-drawn steppers went wrong repeatedly - the value moved on the wrong edge of the press, or a
/// press drifting a few points was silently dropped. So the rules those fixes settled on are asserted
/// here by pressing the buttons in the shipping app:
///
/// 1. the step opens on the imperial defaults, with no metric unit anywhere in the live element tree,
/// 2. a tap on `+` steps the row by its own unit and `-` walks it back,
/// 3. a press held past the hold delay repeats rather than stepping once,
/// 4. a press abandoned rather than completed commits nothing.
///
/// The step buttons are `accessibilityHidden` (the row is one adjustable element, which is the
/// VoiceOver idiom for a value control), so they are pressed by coordinate off the row's own frame -
/// the same way a thumb finds them.
///
/// This bundle runs under its own `RepTodayUITests` scheme, not the app's: it installs and launches
/// the app out of process, which is a slower and more fragile thing to stand on than the unit
/// bundle's hosted windows, and the documented `-scheme RepToday test` should not inherit an app
/// launch's failure modes on every run.
final class OnboardingImperialUITests: XCTestCase {

    /// Renders land in a per-run temporary directory unless `REPTODAY_WRITE_EVIDENCE=1` /
    /// `REPTODAY_EVIDENCE_DIR` redirect them, matching `PerSideSwapEvidenceTests` and
    /// `OnboardingBasicsEvidenceTests`, so a plain test run never dirties the worktree. The runner is a
    /// Simulator process and inherits no shell environment, so the `RepTodayUITests` scheme forwards
    /// both variables from build settings - which is what makes the redirect reach this bundle at all.
    private static let evidenceRoot: String = {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["REPTODAY_EVIDENCE_DIR"], !override.isEmpty { return override }
        if environment["REPTODAY_WRITE_EVIDENCE"] == "1" {
            return URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // RepTodayUITests
                .deletingLastPathComponent() // RepToday
                .deletingLastPathComponent() // ios
                .deletingLastPathComponent() // the repo root
                .appendingPathComponent("artifacts")
                .appendingPathComponent("reports")
                .appendingPathComponent("us-o04")
                .path
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("RepTodayEvidence")
            .appendingPathComponent(UUID().uuidString)
            .path
    }()

    /// A step button is a 44pt square; the pair sits flush against the row's trailing edge with a
    /// hairline divider between them, so their centres are a fixed inset in from that edge.
    private let stepButtonSide: CGFloat = 44
    private let dividerWidth: CGFloat = 1

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `UserDefaults` reads the argument domain first, so this parks the app on onboarding without
        // reaching into the installed app's container - a run never depends on what the last one left.
        app.launchArguments = ["-AppState.isOnboarded", "NO"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Reaching the step the way a user does

    /// Walks the shipping app from its first screen to the basics step, with a name typed in.
    @discardableResult
    private func goToBasicsStep() -> XCUIElement {
        let welcomeContinue = app.buttons["Continue"]
        XCTAssertTrue(welcomeContinue.waitForExistence(timeout: 10), "the app did not reach onboarding")
        welcomeContinue.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the basics step has no name field")
        nameField.tap()
        // The keyboard covers the measurement rows entirely, so it is dismissed the way the user
        // does it - otherwise every press below lands on a letter key instead of a step button.
        nameField.typeText("Riley\n")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
            "the keyboard stayed up over the measurement rows"
        )

        let height = app.otherElements["Height"]
        XCTAssertTrue(height.waitForExistence(timeout: 5), "the basics step has no Height row")
        XCTAssertTrue(height.isHittable, "the Height row is not reachable by a finger")
        return height
    }

    private func row(_ label: String) -> XCUIElement {
        let element = app.otherElements[label]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "no \(label) row on the basics step")
        return element
    }

    /// The centre of a row's `+` button: the trailing 44pt square of the pair.
    private func plusButton(of row: XCUIElement) -> XCUICoordinate {
        coordinate(in: row, insetFromTrailingEdge: stepButtonSide / 2)
    }

    /// The centre of a row's `-` button: one button and one divider further in.
    private func minusButton(of row: XCUIElement) -> XCUICoordinate {
        coordinate(in: row, insetFromTrailingEdge: stepButtonSide * 1.5 + dividerWidth)
    }

    private func coordinate(in row: XCUIElement, insetFromTrailingEdge inset: CGFloat) -> XCUICoordinate {
        let frame = row.frame
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - inset, dy: frame.midY))
    }

    /// Waits for a row to re-read itself, so an assertion never races the animation the press starts.
    private func waitForValue(
        _ expected: String,
        on row: XCUIElement,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let matched = XCTNSPredicateExpectation(predicate: predicate, object: row)
        guard XCTWaiter().wait(for: [matched], timeout: 3) == .completed else {
            XCTFail(
                "\(message) - the row reads \"\(row.value as? String ?? "nothing")\", expected \"\(expected)\"",
                file: file, line: line
            )
            return
        }
    }

    // MARK: - What the step says, in the shipping app

    /// The default the user meets is imperial, and no metric unit survives anywhere on the step.
    func testBasicsStepOpensOnImperialDefaults() throws {
        goToBasicsStep()

        XCTAssertEqual(
            row("Height").value as? String, "5 feet 8 inches",
            "the height row does not open on the US-median imperial default"
        )
        XCTAssertEqual(row("Weight").value as? String, "175 pounds")

        for element in app.descendants(matching: .any).allElementsBoundByIndex {
            let spoken = "\(element.label) \(element.value as? String ?? "")"
            XCTAssertFalse(
                spoken.contains(" cm") || spoken.contains(" kg"),
                "the running app still shows a metric unit: \"\(spoken)\""
            )
        }

        attach(screenshot: XCUIScreen.main.screenshot(), named: "live-basics-imperial-default.png")
    }

    // MARK: - What a finger does to it

    /// A tap on `+` steps the row by exactly its own unit - an inch for height, five pounds for
    /// weight - and a tap on `-` walks it back.
    func testTappingAStepButtonMovesTheRowByItsOwnUnit() throws {
        goToBasicsStep()

        let height = row("Height")
        plusButton(of: height).tap()
        waitForValue("5 feet 9 inches", on: height, message: "one tap on + must add a single inch")

        let weight = row("Weight")
        plusButton(of: weight).tap()
        waitForValue("180 pounds", on: weight, message: "one tap on + must add the weight's 5lb step")

        attach(screenshot: XCUIScreen.main.screenshot(), named: "live-basics-after-taps.png")

        minusButton(of: weight).tap()
        waitForValue("175 pounds", on: weight, message: "one tap on - must walk the weight back")
    }

    /// A press held past the hold delay repeats - the one thing a hand-drawn stepper otherwise gives
    /// up against the platform one, and what makes 70...445 lb reachable without 75 taps.
    func testHoldingAStepButtonRepeats() throws {
        goToBasicsStep()

        let weight = row("Weight")
        plusButton(of: weight).press(forDuration: 1.5)

        let pounds = try XCTUnwrap(poundsRead(from: weight))
        XCTAssertGreaterThan(
            pounds, 180,
            "a 1.5s hold added \(pounds - 175)lb - the press is not repeating, only stepping once"
        )
        attach(screenshot: XCUIScreen.main.screenshot(), named: "live-basics-after-hold.png")
    }

    /// A press abandoned rather than completed commits nothing: the value the user's own body
    /// measurements are seeded from must not move because a finger brushed the row on its way past.
    ///
    /// Two ways to abandon one, both exercised because they take different routes through the
    /// control: dragging *down the step* hands the press to the enclosing `ScrollView`, which cancels
    /// it, while dragging *along the row* simply lifts clear of the button. Neither may step.
    ///
    /// The distances are deliberate. A lift stays "inside" a button for as long as the platform's own
    /// touch slop says it does, which reaches well past the drawn 44pt square, so these lift 200pt
    /// clear of it. Landing on `+` and lifting over the adjacent `-` is a much shorter move, still
    /// inside `+`'s slop, and it steps `+` - the press belongs to the button it landed on, the way it
    /// does for two adjacent buttons anywhere else in iOS. That is deliberately left unasserted in
    /// either direction: the boundary is the platform's, so pinning it here would turn an SDK change
    /// in Apple's slop into a failure of ours. What is asserted is the part we own - that a press
    /// carried decisively away from the control commits nothing.
    func testAPressAbandonedRatherThanCompletedCommitsNothing() throws {
        goToBasicsStep()

        let weight = row("Weight")
        XCTAssertEqual(weight.value as? String, "175 pounds", "precondition")

        // A plain tap first, so this test cannot pass by pressing empty space: if the coordinate
        // missed the button, nothing would move here either and the miss is reported as a miss
        // rather than as the no-op the abandoned presses below are supposed to produce.
        plusButton(of: weight).tap()
        waitForValue("180 pounds", on: weight, message: "the + coordinate does not land on the button")

        let frame = weight.frame
        let scrolledAway = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - stepButtonSide / 2, dy: frame.midY - 200))
        plusButton(of: weight).press(forDuration: 0.05, thenDragTo: scrolledAway)
        _ = weight.waitForExistence(timeout: 0.5)
        XCTAssertEqual(
            weight.value as? String, "180 pounds",
            "a press the scroll view took over stepped the row anyway"
        )

        let liftedClear = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - stepButtonSide / 2 - 200, dy: frame.midY))
        plusButton(of: weight).press(forDuration: 0.05, thenDragTo: liftedClear)
        _ = weight.waitForExistence(timeout: 0.5)
        XCTAssertEqual(
            weight.value as? String, "180 pounds",
            "a press that lifted clear of the button stepped the row anyway"
        )
    }

    // MARK: - The whole flow, in imperial

    /// The story's acceptance path end to end: a US user dials in the PRD's validation measurements -
    /// 5 ft 7 in and 165 lb - with the step buttons, finishes onboarding, and lands on a generated
    /// session.
    ///
    /// The per-control tests above prove the rows read and move in imperial; this one proves the
    /// imperial answers are actually *accepted* by the flow they feed. Nothing downstream of
    /// onboarding speaks pounds - the profile is saved in cm/kg and the engine seeds off it - so a
    /// conversion that failed at the boundary would surface here as a flow that never reaches a
    /// session, which is the failure a user would actually experience.
    func testImperialAnswersCarryThroughOnboardingToAReadySession() throws {
        goToBasicsStep()

        let height = row("Height")
        minusButton(of: height).tap()
        waitForValue("5 feet 7 inches", on: height, message: "one tap on - must remove a single inch")

        let weight = row("Weight")
        minusButton(of: weight).tap()
        minusButton(of: weight).tap()
        waitForValue("165 pounds", on: weight, message: "two taps on - must remove 10lb")

        attach(screenshot: XCUIScreen.main.screenshot(), named: "live-basics-prd-values.png")

        // Every remaining step answers itself with a usable default, so the flow is walked the way a
        // user in a hurry walks it - straight through on the primary button. Bounded by the flow's
        // own length, so a step that stops advancing fails here rather than spinning.
        let startMoving = app.buttons["Start moving"]
        for _ in 0..<OnboardingStepBudget.remainingAfterBasics where !startMoving.exists {
            let advance = app.buttons["Continue"]
            XCTAssertTrue(advance.waitForExistence(timeout: 5), "onboarding stopped advancing")
            advance.tap()
        }
        XCTAssertTrue(
            startMoving.waitForExistence(timeout: 5),
            "the imperial answers never reached the last onboarding step"
        )
        startMoving.tap()

        let greeting = app.staticTexts["Ready when you are, Riley."]
        XCTAssertTrue(
            greeting.waitForExistence(timeout: 15),
            "onboarding with imperial measurements did not produce a ready session"
        )
        attach(screenshot: XCUIScreen.main.screenshot(), named: "live-ready-after-imperial-onboarding.png")
    }

    /// Steps left after `.basics` in the six-step flow, named so the walk above reads as a bound
    /// rather than a magic number.
    private enum OnboardingStepBudget {
        static let remainingAfterBasics = 4
    }

    // MARK: - Helpers

    private func poundsRead(from row: XCUIElement) -> Int? {
        guard let value = row.value as? String else { return nil }
        return Int(value.prefix { $0.isNumber })
    }

    /// Files the screenshot with the result bundle *and* writes a copy to `evidenceRoot`, so it is
    /// reviewable without opening an xcresult - beside the other US-O04 renders when the evidence
    /// opt-in points it there.
    private func attach(screenshot: XCUIScreenshot, named fileName: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)

        do {
            try FileManager.default.createDirectory(
                atPath: Self.evidenceRoot, withIntermediateDirectories: true
            )
            let path = (Self.evidenceRoot as NSString).appendingPathComponent(fileName)
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT_WRITTEN \(path)")
        } catch {
            XCTFail("could not write \(fileName): \(error)")
        }
    }
}
