import XCTest
@testable import RepToday

/// Tests the touch path behind the onboarding step buttons (US-O04) - the half of a hand-drawn
/// stepper that the accessibility-driven `OnboardingBasicsEvidenceTests` never reaches, because
/// `accessibilityIncrement()` routes through the adjustable action and never presses anything.
///
/// Two properties are gated, and both are regressions that shipped once. A press must produce exactly
/// the steps it showed while it was held - the original control stacked a tap gesture on a long press,
/// so a held button took one more step on release than the read-out had reported. And a hold must stop
/// at the end of the range rather than spinning: the value is clamped, so every further "step" wrote
/// the same number back through the binding, and Observation notifies on every write regardless of
/// equality - roughly eleven pointless invalidations a second until the finger lifted.
///
/// The clock is injected, so a whole hold is driven without waiting on one and nothing here is timed.
@MainActor
final class PressRepeaterTests: XCTestCase {

    /// Lets the repeat task run to wherever it is going. Every sleep is injected, so this only has to
    /// hand the main actor over often enough - it never waits on wall-clock time.
    private func drain() async {
        for _ in 0..<128 { await Task.yield() }
    }

    // MARK: - One press, one source of steps

    func testAShortPressStepsExactlyOnce() async {
        var steps = 0
        let repeater = PressRepeater()

        repeater.pressBegan { steps += 1; return true }
        repeater.pressEnded()
        await drain()

        XCTAssertEqual(steps, 1, "a tap must move the value by a single step")
    }

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
                if sleeps.count == 4 { repeater?.pressEnded() }
                await Task.yield()
            }
        )

        repeater?.pressBegan { steps += 1; return true }
        await drain()

        XCTAssertEqual(steps, 4, "the release must not add a step on top of the ones taken while held")
        XCTAssertEqual(
            sleeps, [.milliseconds(400), .milliseconds(90), .milliseconds(90), .milliseconds(90)],
            "the repeat waits out the hold delay once, then runs on the repeat interval"
        )
    }

    func testAPressOnADisabledDirectionNeverStarts() async {
        var sleeps = 0
        let repeater = PressRepeater(sleep: { _ in sleeps += 1; await Task.yield() })

        // The value is already at the bound, so the very first step refuses.
        repeater.pressBegan { false }
        await drain()

        XCTAssertEqual(sleeps, 0, "a press that cannot move the value must not schedule a repeat at all")
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
            sleeps, 2,
            "the loop must end on the refusal - one hold delay and one repeat interval - rather than "
            + "keep firing at the bound until the finger lifts"
        )
    }
}
