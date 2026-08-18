import XCTest
@testable import RepToday

/// US-RC01 (Round Cap and Wide Circuits, engine core): no exercise is ever prescribed more than four
/// times in a session, and a long session is filled by adding distinct movements - a pattern's further
/// progression chains, drawn as accessories - rather than by cranking a single station's round count.
///
/// Coverage mirrors the PRD's own validation case: every training-block exercise's round count
/// (`sets`) sits in `2...4` at every requested length and fitness level, every training block stays
/// internally even (ADR-0003), every session still lands within `±toleranceSeconds`, a 60-minute
/// advanced session goes wider than four distinct strength movements, and a 15/20-minute session does
/// not - it stays at roughly one movement per pattern.
final class RoundCapWideCircuitsTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(level: FitnessLevel) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: level,
                primaryGoal: .stayActive,
                sitsLong: false,
                injuries: [],
                typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3,
                score: 50,
                workoutsThisWeek: 1,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            )
        )
    }

    private func assemble(minutes: Int, level: FitnessLevel, library: [Exercise]) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user(level: level),
            library: library,
            recentLogs: [],
            asOf: asOf,
            calendar: calendar
        )
    }

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    // MARK: - Every training-block exercise sits in 2...4 rounds, and every block stays even

    func testEveryTrainingBlockExerciseHasTwoToFourRoundsAtEveryLengthAndLevel() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                XCTAssertFalse(training.isEmpty, "\(level) \(minutes)-min must still train something")

                for block in training {
                    XCTAssertFalse(block.exercises.isEmpty, "\(level) \(minutes)-min: \(block.title) lost every station")
                    for exercise in block.exercises {
                        XCTAssertGreaterThanOrEqual(
                            exercise.sets, SessionAssembly.minTrainingSets,
                            "\(level) \(minutes)-min: \(block.title)/\(exercise.exercise.id) below the round floor"
                        )
                        XCTAssertLessThanOrEqual(
                            exercise.sets, SessionAssembly.maxTrainingSets,
                            "\(level) \(minutes)-min: \(block.title)/\(exercise.exercise.id) exceeded the round cap"
                        )
                    }
                    XCTAssertEqual(
                        Set(block.exercises.map(\.sets)).count, 1,
                        "\(level) \(minutes)-min: \(block.title) is not an even circuit (mismatched round counts)"
                    )
                }
            }
        }
    }

    // MARK: - Every session still lands within tolerance

    func testEverySessionStillLandsWithinToleranceUnderTheRoundCap() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let drift = abs(SessionAssembly.plannedSeconds(of: workout) - minutes * 60)
                XCTAssertLessThanOrEqual(
                    drift, SessionAssembly.toleranceSeconds,
                    "\(level) \(minutes)-min drifted \(drift)s under the 2...4 round cap"
                )
            }
        }
    }

    // MARK: - Long sessions go wide; short/medium sessions do not

    /// A 60-minute advanced session (the deepest pool, the widest band) contains more than four
    /// distinct strength movements: with the round cap alone unable to carry 60 minutes, the block must
    /// have drawn at least one pattern's second-chain accessory to fill the time.
    func testSixtyMinuteAdvancedSessionGoesWiderThanFourStrengthMovements() async throws {
        let library = try await library()
        let workout = assemble(minutes: 60, level: .advanced, library: library)
        let strength = try XCTUnwrap(
            workout.blocks.first { $0.category == .strength },
            "a 60-min session must carry a strength block"
        )
        let distinctMovements = Set(strength.exercises.map(\.exercise.id))
        XCTAssertGreaterThan(
            distinctMovements.count, 4,
            "a 60-min advanced session should widen past four distinct strength movements, got \(distinctMovements.count)"
        )

        // Going wide is specifically a second chain of an *already-represented* pattern joining as an
        // accessory - not just more patterns existing in the pool - so at least one pattern should now
        // carry more than one station.
        let patternCounts = Dictionary(grouping: strength.exercises, by: { $0.exercise.movementPattern })
            .mapValues(\.count)
        XCTAssertTrue(
            patternCounts.values.contains { $0 > 1 },
            "a 60-min advanced session should carry a second-chain accessory alongside some pattern's primary"
        )
    }

    /// A 15/20-minute session stays at roughly one movement per pattern - the round cap alone is enough
    /// to carry it, so the depth-first fit should never need to promote an accessory. Every station's
    /// pattern in the strength (or, at these lengths, strength-with-primal-folded-in) block is distinct.
    func testFifteenToTwentyMinuteSessionStaysAtOneMovementPerPatternAcrossLevels() async throws {
        let library = try await library()
        for minutes in [15, 20] {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                for block in training {
                    let patterns = block.exercises.map(\.exercise.movementPattern)
                    XCTAssertEqual(
                        Set(patterns).count, patterns.count,
                        "\(level) \(minutes)-min: \(block.title) sprouted an accessory (repeated pattern) at a length the round cap alone should carry"
                    )
                }
            }
        }
    }
}
