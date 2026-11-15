import XCTest

/// The theme switch draws a 52 x 32 track but takes a press anywhere in the 44 pt band around it, as a
/// system switch does, while a press well clear of that band leaves it alone. Pressed by coordinate on
/// an Areas to protect row, without saving, so nothing the test stages is kept.
final class ThemeSwitchHitAreaUITests: XCTestCase {
    func testSwitchTakesAPressJustOutsideItsDrawnTrack() {
        continueAfterFailure = false
        let app = TestApp(self)
        app.launch(.optedOutWithNoProbe)
        defer { app.terminate() }

        XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        scrollUntilHittable(app.buttons["Areas to protect"], in: app)
        app.buttons["Areas to protect"].tap()
        let knees = app.switches["Knees"].firstMatch
        XCTAssertTrue(knees.waitForExistence(timeout: 10))
        let start = knees.value as? String

        // The track sits at the row's trailing edge, centred on the row: 26 pt in from the edge is its middle.
        let frame = knees.frame
        func press(dx: CGFloat, dy: CGFloat) {
            knees.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.width - 26 + dx, dy: frame.height / 2 + dy))
                .tap()
        }
        func waitForValue(_ value: String?) -> XCTWaiter.Result {
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value ?? ""), object: knees
            )], timeout: 5)
        }
        let flipped = start == "1" ? "0" : "1"

        press(dx: 0, dy: -20)
        XCTAssertEqual(waitForValue(flipped), .completed, "a press 4 pt above the drawn track did not move the switch")
        press(dx: 0, dy: 20)
        XCTAssertEqual(waitForValue(start), .completed, "a press 4 pt below the drawn track did not move the switch")

        press(dx: -60, dy: 0)
        XCTAssertEqual(waitForValue(flipped), .timedOut, "a press 28 pt clear of the touch target moved the switch")
        XCTAssertEqual(knees.value as? String, start)
    }
}
