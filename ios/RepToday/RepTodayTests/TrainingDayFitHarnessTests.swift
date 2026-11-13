import XCTest
@testable import RepToday

/// US-TD00: the fit-feasibility harness. Prices every length x level x Training Day against the real
/// catalog and the real pace model (`SessionAssembly.workSecondsPerSet`), so a timing regression shows up
/// here before a user sees it.
///
/// Decision 17: a session lands within about three minutes of the request, or - when even the top of the
/// range and the longest rests cannot fill it - runs short and says so (an honest shortfall). It never
/// plans past the tolerance: a session still over with every rep at the short-session floor drops a
/// station and runs short instead (ADR-0018).
///
/// Each run prints a transcript (`FIT HARNESS` lines) of planned against requested minutes, for a fresh
/// history, a cold-start one and a seasoned one.
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

    /// The Focus Area sets the harness prices beside no focus (US-HO03): each area alone, Abs with its
    /// second Core Sprinkle among them, and every area at once.
    private let focusSets: [[FocusArea]] = [[]] + FocusArea.allCases.map { [$0] } + [FocusArea.allCases]

    func testEveryLengthLevelAndDayFillsWithinToleranceOrReportsAnHonestShortfall() async throws {
        let library = try await MockExerciseService().exercises()
        var transcript: [String] = []
        for focusAreas in focusSets {
            let focusLabel = focusAreas.isEmpty ? "none" : focusAreas.count == FocusArea.allCases.count ? "all" : focusAreas.map(\.rawValue).joined(separator: "+")
            for history in History.allCases {
                for level in FitnessLevel.allCases {
                    var user = TrainingDayFixtures.user(level: level, focusAreas: focusAreas, asOf: asOf)
                    if history == .coldStart { user.coldStart = User.ColdStart(sessionsLogged: 0, active: true) }
                    let policy = history == .coldStart ? SessionPolicy.seeded(forFitnessLevel: level) : .default
                    let logs = history.logs(library: library, level: level, asOf: asOf, calendar: calendar)
                    for day in TrainingDay.rotation {
                        for minutes in lengths {
                            var plan = SessionAssembly.planSession(
                                requestedMinutes: minutes,
                                user: user,
                                library: library,
                                recentLogs: logs,
                                sessionPolicy: policy,
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
                                    "\(focusLabel) \(history) \(level) \(day) \(minutes) min lands \(gap)s short with levers left"
                                )
                            } else {
                                status = "overrun"
                                XCTFail("\(focusLabel) \(history) \(level) \(day) \(minutes) min plans \(gap)s past its length, beyond the tolerance")
                            }
                            let line = String(
                                format: "FIT HARNESS focus:%@ %@ %@ %@ %2d min: planned %5.1f min (%+4ds) stations %d rest %ds pause %ds - %@",
                                focusLabel, history.rawValue, level.rawValue, day.rawValue, minutes,
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
        }
        print(transcript.joined(separator: "\n"))
    }

    /// The two ends of a user's history: a fresh start (every Earned Reps at the bottom of the range) and
    /// a seasoned one (Earned Reps climbed to the top of the range, without yet clearing a rung) - plus a
    /// brand-new user still inside the cold-start window, under their level's seeded Start Seed policy
    /// (its difficulty band and cap), which is what every user's first sessions are built from.
    private enum History: String, CaseIterable {
        case fresh
        case coldStart
        case seasoned

        func logs(library: [Exercise], level: FitnessLevel, asOf: Date, calendar: Calendar) -> [WorkoutLog] {
            switch self {
            case .fresh, .coldStart:
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
