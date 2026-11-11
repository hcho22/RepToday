import XCTest
@testable import RepToday

/// US-M04: one uniform session vocabulary, length-scaled bookends.
///
/// Every session, at every length and on every Training Day, reads as **Warm-Up -> <Day> circuit ->
/// Cooldown**: a warm-up of one or two stretches, one circuit block titled for the day ("Push Day",
/// "Pull Day", "Legs Day"), and a closing cooldown past 10 minutes. Asserted off the blocks the assembly
/// actually produced, not off a re-derived plan:
///
///   1. **Uniform shape.** The ordered block categories are exactly `.warmup`, `.strength`, then
///      `.cooldown` only past `cooldownThresholdMinutes`, with no other block and no empty block.
///   2. **Length-scaled, non-forced bookends.** The warm-up holds one stretch up to 10 minutes and two
///      beyond; the cooldown none up to 10 minutes, one at 15-20 and two from 30. Every stretch is one set.
///   3. **The circuit owns the clock.** Every circuit station is a strength-pillar movement, and the
///      circuit holds the majority of the planned session at every length.
///
/// `TrainingDaySessionTests` pins the slots inside the circuit; this suite pins the frame around it.
final class UniformSessionShapeTests: XCTestCase {

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func assemble(minutes: Int, day: TrainingDay, level: FitnessLevel = .intermediate) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(level: level),
            library: library,
            recentLogs: [],
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    // MARK: - 1. Uniform Warm-Up -> circuit -> Cooldown shape

    func testEveryLengthAndDayMapsOntoTheUniformShape() {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = assemble(minutes: minutes, day: day, level: level)
                    let label = "\(level) \(day) \(minutes) min"
                    let expected: [ExerciseCategory] = minutes > 10 ? [.warmup, .strength, .cooldown] : [.warmup, .strength]
                    XCTAssertEqual(workout.blocks.map(\.category), expected, label)
                    XCTAssertEqual(
                        workout.blocks.map(\.title),
                        minutes > 10 ? ["Warm-Up", day.displayName, "Cooldown"] : ["Warm-Up", day.displayName],
                        label
                    )
                    XCTAssertTrue(workout.blocks.allSatisfy { !$0.exercises.isEmpty }, "\(label): an empty block")
                }
            }
        }
    }

    // MARK: - 2. Bookends stay lean and length-scaled

    /// Bound to literals so a changed constant cannot silently loosen the shape.
    func testBookendsAreLengthScaledAndNotForcedOntoShortSessions() throws {
        let warmups = [5: 1, 10: 1, 15: 2, 20: 2, 30: 2, 45: 2, 60: 2]
        let cooldowns = [5: 0, 10: 0, 15: 1, 20: 1, 30: 2, 45: 2, 60: 2]
        for day in TrainingDay.rotation {
            for minutes in lengths {
                let workout = assemble(minutes: minutes, day: day)
                let label = "\(day) \(minutes) min"
                let warmup = try XCTUnwrap(workout.blocks.first { $0.category == .warmup }, label)
                XCTAssertEqual(warmup.exercises.count, warmups[minutes], "\(label): warm-up count")
                XCTAssertEqual(warmup.exercises.count, SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes), label)
                let cooldown = workout.blocks.first { $0.category == .cooldown }?.exercises ?? []
                XCTAssertEqual(cooldown.count, cooldowns[minutes], "\(label): cooldown count")
                XCTAssertEqual(cooldown.count, SessionAssembly.cooldownExerciseCount(forRequestedMinutes: minutes), label)
                for stretch in warmup.exercises + cooldown {
                    XCTAssertEqual(stretch.exercise.pillar, .mobility, "\(label): \(stretch.exercise.id) is not a stretch")
                    XCTAssertEqual(stretch.sets, 1, "\(label): \(stretch.exercise.id) is not one set")
                }
            }
        }
    }

    // MARK: - 3. The circuit owns the clock

    func testTheCircuitIsStrengthAndHoldsTheMajorityOfTheSession() throws {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = assemble(minutes: minutes, day: day, level: level)
                    let label = "\(level) \(day) \(minutes) min"
                    let circuit = try XCTUnwrap(workout.blocks.first { $0.category == .strength }, label)
                    XCTAssertTrue(
                        circuit.exercises.allSatisfy { $0.exercise.pillar == .strength },
                        "\(label): \(circuit.exercises.map(\.exercise.id))"
                    )
                    let share = Double(SessionAssembly.blockSeconds(of: circuit)) / Double(SessionAssembly.plannedSeconds(of: workout))
                    XCTAssertGreaterThan(share, 0.5, "\(label): the circuit holds only \(share) of the session")
                }
            }
        }
    }

    // MARK: - Determinism

    func testUniformShapeIsDeterministic() {
        for day in TrainingDay.rotation {
            for minutes in lengths {
                let first = assemble(minutes: minutes, day: day).blocks.map { $0.exercises.map(\.exercise.id) }
                let again = assemble(minutes: minutes, day: day).blocks.map { $0.exercises.map(\.exercise.id) }
                XCTAssertEqual(again, first, "\(day) \(minutes) min is not deterministic")
            }
        }
    }
}
