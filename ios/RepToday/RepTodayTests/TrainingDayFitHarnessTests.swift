import XCTest
@testable import RepToday

/// US-TD00: the fit-feasibility harness. Prices every length x level x Training Day against the real
/// catalog and the real pace model (`SessionAssembly.workSecondsPerSet`), so a timing regression shows up
/// here before a user sees it.
///
/// Decision 17: a session lands within about three minutes of the request, or - when even the top of the
/// range and the longest rests cannot fill it - runs short and says so (an honest shortfall). It never
/// overruns past the tolerance unless every rep is already at the short-session floor.
///
/// Each run prints a transcript (`FIT HARNESS` lines) of planned against requested minutes.
final class TrainingDayFitHarnessTests: XCTestCase {

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    }

    func testEveryLengthLevelAndDayFillsWithinToleranceOrReportsAnHonestShortfall() async throws {
        let library = try await MockExerciseService().exercises()
        var transcript: [String] = []
        for history in History.allCases {
            for level in FitnessLevel.allCases {
                let user = TrainingDayFixtures.user(level: level, asOf: asOf)
                let logs = history.logs(library: library, level: level, asOf: asOf, calendar: calendar)
                for day in TrainingDay.rotation {
                    for minutes in lengths {
                        var plan = SessionAssembly.planSession(
                            requestedMinutes: minutes,
                            user: user,
                            library: library,
                            recentLogs: logs,
                            trainingDay: day,
                            asOf: asOf,
                            calendar: calendar
                        )
                        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
                        let planned = plan.totalSeconds
                        let gap = planned - minutes * 60
                        let status: String
                        if abs(gap) <= SessionAssembly.toleranceSeconds {
                            status = "ok"
                        } else if gap < 0 {
                            status = "honest shortfall"
                            XCTAssertTrue(
                                plan.isSaturated,
                                "\(history) \(level) \(day) \(minutes) min lands \(gap)s short with levers left"
                            )
                        } else {
                            status = "overrun"
                            XCTAssertTrue(
                                plan.stations.allSatisfy { $0.value - RepGrammar.step < $0.floor },
                                "\(history) \(level) \(day) \(minutes) min overruns \(gap)s with reps above the floor"
                            )
                        }
                        let line = String(
                            format: "FIT HARNESS %@ %@ %@ %2d min: planned %5.1f min (%+4ds) stations %d rest %ds pause %ds - %@",
                            history.rawValue, level.rawValue, day.rawValue, minutes,
                            Double(planned) / 60, gap, plan.stations.count, plan.roundRestSeconds,
                            plan.transitionSeconds, status
                        )
                        transcript.append(line)
                        // The materialized session prices exactly as the plan did.
                        XCTAssertEqual(SessionAssembly.plannedSeconds(of: plan.materialize()), planned)
                    }
                }
            }
        }
        print(transcript.joined(separator: "\n"))
    }

    /// The two ends of a user's history: a fresh start (every Earned Reps at the bottom of the range) and
    /// a seasoned one (Earned Reps climbed to the top of the range, without yet clearing a rung).
    private enum History: String, CaseIterable {
        case fresh
        case seasoned

        func logs(library: [Exercise], level: FitnessLevel, asOf: Date, calendar: Calendar) -> [WorkoutLog] {
            switch self {
            case .fresh:
                return []
            case .seasoned:
                let worked = library.filter { $0.pillar == .strength && MovementAccess.isAvailable($0, level: level, phase: .discipline) }
                let exercises = worked.map { exercise -> LoggedExercise in
                    let earned = RepGrammar.earnedRange(for: exercise, level: level).upperBound - RepGrammar.step
                    return LoggedExercise(
                        id: UUID(),
                        exerciseId: exercise.id,
                        pillar: exercise.pillar,
                        movementPattern: exercise.movementPattern,
                        completedSets: Array(repeating: exercise.isHold
                            ? CompletedSet(reps: nil, durationSeconds: earned)
                            : CompletedSet(reps: earned, durationSeconds: nil), count: 4),
                        skipped: false,
                        role: .main,
                        earnedReps: exercise.isHold ? nil : earned,
                        earnedDurationSeconds: exercise.isHold ? earned : nil
                    )
                }
                return [WorkoutLog(
                    id: UUID(),
                    workoutId: UUID(),
                    completedAt: calendar.date(byAdding: .day, value: -3, to: asOf)!,
                    requestedMinutes: 30,
                    durationMinutes: 30,
                    shape: .blend,
                    focusPillar: .strength,
                    perceivedDifficulty: .justRight,
                    exercises: exercises
                )]
            }
        }
    }
}
