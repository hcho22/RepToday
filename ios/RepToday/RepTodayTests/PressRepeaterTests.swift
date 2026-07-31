import XCTest
@testable import RepToday

/// Tests the touch path behind the onboarding step buttons (US-O04) - the half of a hand-drawn
/// stepper that the accessibility-driven `OnboardingBasicsEvidenceTests` never reaches, because
/// `accessibilityIncrement()` routes through the adjustable action and never presses anything.
///
/// Three properties are gated, and each is a regression that shipped once. Nothing commits while the
/// finger is down: the step lands on release, so a finger that touches `+` on its way to a scroll
/// moves nothing, and a press that is only ever cancelled commits nothing at all. A press produces
/// exactly the steps it showed while it was held - the original control stacked a tap gesture on a
/// long press, so a held button took one more step on release than the read-out had reported. And a
/// hold stops at the end of the range rather than spinning: the value is clamped, so every further
/// "step" wrote the same number back through the binding, and Observation notifies on every write
/// regardless of equality - roughly eleven pointless invalidations a second until the finger lifted.
///
/// The clock is injected, so a whole hold is driven without waiting on one and nothing here is timed.
@MainActor
final class PressRepeaterTests: XCTestCase {

    /// Lets the repeat task run to wherever it is going. Every sleep is injected, so this only has to
    /// hand the main actor over often enough - it never waits on wall-clock time.
    private func drain() async {
        for _ in 0..<128 { await Task.yield() }
    }

    /// A repeater whose hold delay lands past the end of the test, so the press under test can only
    /// ever be a tap. The sleep is a real one, but draining yields rather than waiting, so nothing
    /// here spends the ten seconds - the press is cancelled long before.
    private func tapOnlyRepeater() -> PressRepeater {
        PressRepeater(holdDelay: .seconds(10))
    }

    // MARK: - The step lands on release, not on touch-down

    func testAFingerLandingOnTheButtonCommitsNothingUntilItLifts() async {
        var steps = 0
        let repeater = tapOnlyRepeater()

        repeater.pressBegan { steps += 1; return true }
        await drain()

        XCTAssertEqual(steps, 0, "a press must not move the value while the finger is still down")

        repeater.pressEnded()
        repeater.pressReleased { steps += 1; return true }
        await drain()

        XCTAssertEqual(steps, 1, "a tap must move the value by a single step, on release")
    }

    /// One release delivers both calls and the gesture layer decides their order, so neither ordering
    /// may double-count or swallow the step.
    func testTheOrderOfTheReleaseAndTheEndOfTrackingDoesNotMatter() async {
        var steps = 0
        let repeater = tapOnlyRepeater()

        repeater.pressBegan { steps += 1; return true }
        repeater.pressReleased { steps += 1; return true }
        repeater.pressEnded()
        await drain()

        XCTAssertEqual(steps, 1, "a tap is one step whichever way round the release is reported")
    }

    func testAPressThatIsCancelledCommitsNothing() async {
        var steps = 0
        let repeater = tapOnlyRepeater()

        // The scroll view took the press over, or the finger dragged off the button: tracking ends
        // and no release is ever reported.
        repeater.pressBegan { steps += 1; return true }
        repeater.pressEnded()
        await drain()

        XCTAssertEqual(steps, 0, "a press the user never completed on the button must move nothing")
    }

    // MARK: - One press, one source of steps

    func testAHeldPressEndsExactlyWhereItStoodWhenTheFingerLifted() async {
        var steps = 0
        var sleeps: [Duration] = []
        var repeater: PressRepeater?
        repeater = PressRepeater(
            holdDelay: .milliseconds(400),
            repeatInterval: .milliseconds(90),
            sleep: { duration in
                sleeps.append(duration)
                // The finger lifts partway through the hold.
                if sleeps.count == 4 {
                    repeater?.pressEnded()
                    repeater?.pressReleased { steps += 1; return true }
                }
                await Task.yield()
            }
        )

        repeater?.pressBegan { steps += 1; return true }
        await drain()

        XCTAssertEqual(steps, 3, "the release must not add a step on top of the ones taken while held")
        XCTAssertEqual(
            sleeps, [.milliseconds(400), .milliseconds(90), .milliseconds(90), .milliseconds(90)],
            "the repeat waits out the hold delay once, then runs on the repeat interval"
        )
    }

    /// The two ends of a press meeting at the bound: the hold has taken over and walked the value to
    /// the top of the range, so the release that ends it must not step past it.
    func testAReleaseAfterAHoldThatReachedTheBoundStillAddsNothing() async {
        var value = 4
        var repeater: PressRepeater?
        var sleeps = 0
        repeater = PressRepeater(
            sleep: { _ in
                sleeps += 1
                // The hold has had its first step - the one that lands on the bound - and the finger
                // lifts on it.
                if sleeps == 2 {
                    repeater?.pressEnded()
                    repeater?.pressReleased { value += 1; return true }
                }
                await Task.yield()
            }
        )

        repeater?.pressBegan {
            guard value < 5 else { return false }
            value += 1
            return true
        }
        await drain()

        XCTAssertEqual(value, 5, "a release that only ends a hold must not step past the range")
    }

    // MARK: - The repeat stops at the end of the range

    func testAHeldPressStopsAsSoonAsTheValueCannotMove() async {
        var value = 3
        var sleeps = 0
        let repeater = PressRepeater(sleep: { _ in sleeps += 1; await Task.yield() })

        // Never released: only the bound can end this.
        repeater.pressBegan {
            guard value < 5 else { return false }
            value += 1
            return true
        }
        await drain()

        XCTAssertEqual(value, 5, "the hold must walk the value up to the bound")
        XCTAssertEqual(
            sleeps, 3,
            "the loop must end on the refusal - one hold delay and two repeat intervals - rather than "
            + "keep firing at the bound until the finger lifts"
        )
    }
}
