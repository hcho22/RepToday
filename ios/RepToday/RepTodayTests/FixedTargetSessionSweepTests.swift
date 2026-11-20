import XCTest
@testable import RepToday

/// US-FT03 / US-FT10: the Fixed Target sweep. Assembles every length at every level with Forearm Plank
/// and Dead Bug forced into the Core Sprinkles, and checks each session still lands within the tolerance.
///
/// Forcing: the hollow ladder is left out of the catalog, Bird Dog is cleared in the history (so the
/// stability ladder's current rung is Dead Bug), and Abs is a Focus Area (so the session carries a Core
/// Sprinkle from each remaining ladder). A beginner is in the Strength Phase, the one way a beginner is
/// served Dead Bug (`audience` intermediate, ADR-0007).
///
/// Each run prints a `FIXED TARGET SWEEP` transcript: the forced plank and Dead Bug prescriptions and
/// the warm-up and cooldown of a fresh user's Training Day, the before/after evidence US-FT10 asks for.
final class FixedTargetSessionSweepTests: XCTestCase {

    private let lengths = [5, 10, 15, 20, 30, 45, 60]
    private let evidenceLengths: Set<Int> = [15, 30, 45, 60]
    private let calendar = TrainingDayFixtures.calendar
    private let asOf = TrainingDayFixtures.asOf

    func testForcedFixedTargetSessionsFillEveryLengthAndLevelWithinTolerance() async throws {
        let library = try await MockExerciseService().exercises()
        let forcedLibrary = library.filter { $0.progressionChainId != "core_hollow" }
        var transcript = ["FIXED TARGET SWEEP | level | day | min | Forearm Plank | Dead Bug | warm-up | cooldown | planned"]
        for level in FitnessLevel.allCases {
            let forcedUser = TrainingDayFixtures.user(
                level: level,
                phase: level == .beginner ? .strength : .discipline,
                focusAreas: [.abs],
                asOf: asOf
            )
            let logs = [birdDogCleared()]
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    var plan = SessionAssembly.planSession(
                        requestedMinutes: minutes,
                        user: forcedUser,
                        library: forcedLibrary,
                        recentLogs: logs,
                        trainingDay: day,
                        asOf: asOf,
                        calendar: calendar
                    )
                    SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
                    let gap = plan.totalSeconds - minutes * 60
                    XCTAssertLessThanOrEqual(gap, SessionAssembly.toleranceSeconds, "\(level) \(day) \(minutes) min overruns by \(gap)s")
                    if gap < -SessionAssembly.toleranceSeconds {
                        XCTAssertTrue(plan.isSaturated, "\(level) \(day) \(minutes) min lands \(gap)s short with levers left")
                    }
                    // Each forced station records its target and is served at it or cut below it, never padded.
                    for item in plan.stations where item.exercise.fixedTarget != nil {
                        let target = RepGrammar.fixedTarget(for: item.exercise, level: level)
                        XCTAssertEqual(item.earned, target, "\(level) \(day) \(minutes) min: \(item.exercise.id)")
                        XCTAssertLessThanOrEqual(item.value, target ?? 0, "\(level) \(day) \(minutes) min pads \(item.exercise.id)")
                    }
                    if minutes >= 15 {
                        XCTAssertNotNil(plan.stations.first { $0.exercise.id == "core_forearm_plank" }, "\(level) \(day) \(minutes) min")
                        XCTAssertNotNil(plan.stations.first { $0.exercise.id == "core_dead_bug" }, "\(level) \(day) \(minutes) min")
                    }
                    guard evidenceLengths.contains(minutes) else { continue }
                    var fresh = SessionAssembly.planSession(
                        requestedMinutes: minutes,
                        user: TrainingDayFixtures.user(level: level, asOf: asOf),
                        library: library,
                        recentLogs: [],
                        trainingDay: day,
                        asOf: asOf,
                        calendar: calendar
                    )
                    SessionAssembly.fit(&fresh, targetSeconds: minutes * 60)
                    for item in fresh.warmup + fresh.cooldown where item.exercise.isHold {
                        XCTAssertEqual(item.value, SessionAssembly.bookendHoldSeconds, "\(level) \(day) \(minutes) min: \(item.exercise.id)")
                    }
                    transcript.append([
                        "FIXED TARGET SWEEP",
                        level.rawValue,
                        day.rawValue,
                        "\(minutes)",
                        describe(plan.stations.first { $0.exercise.id == "core_forearm_plank" }),
                        describe(plan.stations.first { $0.exercise.id == "core_dead_bug" }),
                        fresh.warmup.map(describe).joined(separator: "; "),
                        fresh.cooldown.map(describe).joined(separator: "; "),
                        String(format: "%.1f min (%+ds)", Double(plan.totalSeconds) / 60, gap),
                    ].joined(separator: " | "))
                }
            }
        }
        print(transcript.joined(separator: "\n"))
    }

    // MARK: - Fixtures

    /// A session that cleared Bird Dog (4 x 15 per side at earned 15, rated just right), so the stability
    /// ladder's current rung is Dead Bug.
    private func birdDogCleared() -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station("core_bird_dog", pattern: .core, role: .core, value: 15, earned: 15)],
            completedAt: TrainingDayFixtures.date(daysAgo: 2)
        )
    }

    private func describe(_ item: PlannedItem?) -> String {
        guard let item else { return "-" }
        let side = item.exercise.isPerSide == true ? " per side" : ""
        let value = item.exercise.isHold
            ? String(format: "%d:%02d", item.value / 60, item.value % 60)
            : "\(item.value) reps"
        let sets = item.sets > 1 ? "\(item.sets) x " : ""
        return "\(item.exercise.displayName) \(sets)\(value)\(side)"
    }
}
