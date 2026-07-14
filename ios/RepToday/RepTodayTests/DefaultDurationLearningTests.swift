import XCTest
@testable import RepToday

/// Tests Default Duration learning (US-F04): `DefaultDurationLearning`, which folds completed
/// session durations into `User.Duration.completedDurationEWMA` and snaps `defaultMinutes` to a
/// valid Ready-Screen chip, so the learned default tracks what the user *finishes* (completed
/// `durationMinutes`), never what they *request*.
///
/// Coverage mirrors the PRD acceptance criteria: the EWMA tracks completed durations; the default
/// snaps to a chip value (5/10/15/20/30/45/60); learning is deterministic; and the validation case
/// (five sessions requested at 20 but completed at ~12 -> the default drops to 10 or 15 and no
/// longer tracks the requested 20).
final class DefaultDurationLearningTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var day0: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0)!
    }

    private func log(on date: Date, requestedMinutes: Int, durationMinutes: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date,
            requestedMinutes: requestedMinutes,
            durationMinutes: durationMinutes,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: []
        )
    }

    // MARK: - Chip snapping

    func testSnapsToNearestChip() {
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(5), 5)
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(12), 10)   // 2 from 10, 3 from 15
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(13), 15)   // 3 from 10, 2 from 15
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(23), 20)
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(38), 45)   // 8 from 30, 7 from 45
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(100), 60)  // clamps to the top chip
    }

    func testSnapBoundaryResolvesToShorterChip() {
        // Exactly between 10 and 15: the gentler (shorter) chip wins.
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(12.5), 10)
        // Exactly between 20 and 30.
        XCTAssertEqual(DefaultDurationLearning.snappedToChip(25), 20)
    }

    func testEveryLearnedDefaultIsAValidChip() {
        for finished in stride(from: 3, through: 62, by: 1) {
            let learned = DefaultDurationLearning.learned(
                .seeded(minutes: 30),
                completing: [finished]
            )
            XCTAssertTrue(
                DefaultDurationLearning.chipValues.contains(learned.defaultMinutes),
                "learned default \(learned.defaultMinutes) for \(finished) min is not a chip"
            )
        }
    }

    // MARK: - EWMA

    func testEmptyInputLeavesDurationUnchanged() {
        let seeded = User.Duration.seeded(minutes: 20)
        XCTAssertEqual(DefaultDurationLearning.learned(seeded, completing: []), seeded)
    }

    func testEWMAAnchorsToOnboardingSeedThenMovesTowardCompleted() {
        // No prior EWMA: the prior is the onboarding seed (20), and the completed 12 pulls it down.
        let seeded = User.Duration.seeded(minutes: 20)
        let once = DefaultDurationLearning.learned(seeded, completing: [12])
        let ewma = once.completedDurationEWMA ?? 0
        // 0.3 * 12 + 0.7 * 20 = 17.6: moved off the seed toward completed, never overshooting below.
        XCTAssertEqual(ewma, 17.6, accuracy: 0.0001)
        XCTAssertGreaterThan(ewma, 12)
        XCTAssertLessThan(ewma, 20)
    }

    func testEWMAUsesExistingAverageAsPriorWhenPresent() {
        var duration = User.Duration.seeded(minutes: 20)
        duration.completedDurationEWMA = 12   // already learned from prior sessions
        let learned = DefaultDurationLearning.learned(duration, completing: [12])
        // Prior 12, complete 12: stays 12, not re-anchored to the seed.
        XCTAssertEqual(learned.completedDurationEWMA ?? 0, 12, accuracy: 0.0001)
    }

    func testEWMATracksCompletedNotRequested() {
        // Requested is irrelevant to learning; only completed durations move the EWMA.
        let logs = (0..<5).map { log(on: day($0), requestedMinutes: 20, durationMinutes: 12) }
        let learned = DefaultDurationLearning.learned(.seeded(minutes: 20), from: logs)
        // Trends toward 12, never toward the requested 20.
        let ewma = learned.completedDurationEWMA ?? 0
        XCTAssertLessThan(ewma, 15, "EWMA tracked requested 20 instead of completed 12")
        XCTAssertGreaterThan(ewma, 12, "EWMA overshot below completed")
    }

    func testLearningIsDeterministic() {
        let logs = (0..<5).map { log(on: day($0), requestedMinutes: 20, durationMinutes: 12) }
        let a = DefaultDurationLearning.learned(.seeded(minutes: 20), from: logs)
        let b = DefaultDurationLearning.learned(.seeded(minutes: 20), from: logs)
        XCTAssertEqual(a, b)
    }

    func testFromLogsFoldsInChronologicalOrder() {
        // Out-of-order logs are sorted by completedAt before folding, so order of the array
        // passed in does not change the result.
        let ordered = [
            log(on: day(0), requestedMinutes: 30, durationMinutes: 30),
            log(on: day(1), requestedMinutes: 30, durationMinutes: 10),
        ]
        let shuffled = [ordered[1], ordered[0]]
        XCTAssertEqual(
            DefaultDurationLearning.learned(.seeded(minutes: 30), from: ordered),
            DefaultDurationLearning.learned(.seeded(minutes: 30), from: shuffled)
        )
    }

    func testOnboardingSeedIsNeverMutated() {
        let logs = (0..<5).map { log(on: day($0), requestedMinutes: 20, durationMinutes: 12) }
        let learned = DefaultDurationLearning.learned(.seeded(minutes: 20), from: logs)
        XCTAssertEqual(learned.onboardingSeedMinutes, 20)
    }

    // MARK: - PRD validation

    /// US-F04 validation: a user whose last five sessions were requested at 20 min but completed at
    /// ~12 min. After a weekly re-program folds those completions, `completedDurationEWMA` trends
    /// toward ~12 and `defaultMinutes` snaps to 10 or 15 - never the requested 20.
    func testValidationRequestedTwentyCompletedTwelve() {
        let completed = [13, 12, 11, 12, 12]   // "~12"
        let logs = zip(0..., completed).map { offset, done in
            log(on: day(offset), requestedMinutes: 20, durationMinutes: done)
        }

        let learned = DefaultDurationLearning.learned(.seeded(minutes: 20), from: logs)

        let ewma = learned.completedDurationEWMA ?? 0
        XCTAssertGreaterThan(ewma, 12, "EWMA should trend toward ~12, not below")
        XCTAssertLessThan(ewma, 16, "EWMA should have moved well off the requested 20")
        XCTAssertTrue(
            [10, 15].contains(learned.defaultMinutes),
            "defaultMinutes should snap to 10 or 15, got \(learned.defaultMinutes)"
        )
        XCTAssertNotEqual(learned.defaultMinutes, 20, "default must not track the requested 20")
    }
}
