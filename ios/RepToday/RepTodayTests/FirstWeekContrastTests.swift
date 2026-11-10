import XCTest
@testable import RepToday

/// US-004: the cold-start first week leads strength and stays gentle, driven end-to-end through the real
/// onboarding seed (`SessionPolicy.seeded(forFitnessLevel:)`).
///
/// The hardest profile is the original bug's: a `sitsLong` beginner whose onboarding opening bias is
/// mobility. Their first sessions still walk the Push -> Pull -> Legs Rotation as strength circuits, with
/// mobility only in the bookends, and every movement stays inside the cold-start difficulty cap
/// (`cappedMaxDifficulty`).
final class FirstWeekContrastTests: XCTestCase {

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    /// A desk-worker beginner on cold-start day `sessionsLogged`, with a mobility opening bias.
    private func deskWorker(sessionsLogged: Int) -> User {
        var user = TrainingDayFixtures.user(level: .beginner, sitsLong: true)
        user.coldStart = User.ColdStart(sessionsLogged: sessionsLogged, active: true)
        user.why = User.Why(statement: "", openingBias: .mobility)
        return user
    }

    private func assemble(minutes: Int, user: User, logs: [WorkoutLog], day: TrainingDay? = nil, asOf: Date) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: .seeded(forFitnessLevel: .beginner),
            trainingDay: day,
            asOf: asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    /// `workout` completed as prescribed at `date`, logged the way the player writes it (roles and
    /// Earned Reps carried on every station).
    private func log(_ workout: Workout, at date: Date) -> WorkoutLog {
        TrainingDayFixtures.log(
            workout.blocks.flatMap(\.exercises).map { item in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: item.exercise.id,
                    pillar: item.exercise.pillar,
                    movementPattern: item.exercise.movementPattern,
                    completedSets: Array(repeating: CompletedSet(reps: item.reps, durationSeconds: item.durationSeconds), count: item.sets),
                    skipped: false,
                    role: item.role,
                    earnedReps: item.earnedReps,
                    earnedDurationSeconds: item.earnedDurationSeconds
                )
            },
            completedAt: date,
            requestedMinutes: workout.requestedMinutes
        )
    }

    /// The first three cold-start sessions, each logged before the next is built, train Push, Pull and
    /// Legs in turn as strength circuits - the mobility opening bias moves only the bookends.
    func testTheSeededFirstWeekWalksTheRotationAsStrengthCircuits() throws {
        var logs: [WorkoutLog] = []
        for (index, expected) in TrainingDay.rotation.enumerated() {
            let date = TrainingDayFixtures.date(daysAgo: 3 - index)
            let workout = assemble(minutes: 8, user: deskWorker(sessionsLogged: index), logs: logs, asOf: date)
            let label = "cold-start session \(index)"
            XCTAssertEqual(workout.trainingDay, expected, label)
            XCTAssertEqual(workout.focusPillar, .strength, label)
            XCTAssertEqual(workout.blocks.map(\.category), [.warmup, .strength], label)
            let circuit = try XCTUnwrap(workout.blocks.first { $0.category == .strength }, label)
            XCTAssertTrue(circuit.exercises.allSatisfy { $0.exercise.pillar == .strength }, label)
            XCTAssertTrue(
                circuit.exercises.allSatisfy { expected.patterns.contains($0.exercise.movementPattern) },
                "\(label): \(circuit.exercises.map(\.exercise.id)) is not a \(expected) circuit"
            )
            logs.append(log(workout, at: date))
        }
    }

    /// The seeded first week stays gentle at every length and on every day: every main station, Core
    /// Sprinkle and stretch sits at or below the cold-start difficulty cap. A Practice Movement previews
    /// the next rung at low reps under its own eligibility rule (ADR-0015), so it is outside this check.
    func testSeededSessionsStayUnderTheDifficultyCap() throws {
        let cap = try XCTUnwrap(SessionPolicy.seeded(forFitnessLevel: .beginner).coldStartContract?.cappedMaxDifficulty)
        for sessionsLogged in 0..<3 {
            for day in TrainingDay.rotation {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    let workout = assemble(
                        minutes: minutes, user: deskWorker(sessionsLogged: sessionsLogged), logs: [], day: day,
                        asOf: TrainingDayFixtures.asOf
                    )
                    for item in workout.blocks.flatMap(\.exercises) where item.role != .practice {
                        XCTAssertLessThanOrEqual(
                            item.exercise.difficulty, cap,
                            "day \(sessionsLogged) \(day) \(minutes) min: \(item.exercise.id) (\(item.role.map { "\($0)" } ?? "stretch")) exceeds the cold-start cap"
                        )
                    }
                }
            }
        }
    }
}
