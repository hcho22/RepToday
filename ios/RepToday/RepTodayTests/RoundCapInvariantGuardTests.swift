import XCTest
@testable import RepToday

/// US-RC02 (Round Cap and Wide Circuits): the standing "2-4 rounds, always" regression guard.
///
/// US-RC01 shipped the engine core that caps every training-block exercise at `2...4` rounds and fills
/// a longer session by going *wider* (accessory chains) instead of *deeper*. This suite is the distinct
/// standing guard that story's PRD calls for: it fails the build if any future change lets a
/// training-block exercise exceed four rounds or drop below two, so the cap can never silently regress.
///
/// It is deliberately narrow - it asserts only the invariant (`2...4` on every training-block station,
/// plus each training block being internally even, ADR-0003) and not US-RC01's wider-not-deeper
/// behaviour, which `RoundCapWideCircuitsTests` owns. It lives in the routinely-run `RepTodayTests`
/// bundle, so it runs under `-scheme RepToday test` locally and in CI.
///
/// **Non-vacuity (verified 2026-08-18):** the guard was proven to actually bind - temporarily reverting
/// `SessionAssembly.maxTrainingSets` to `8` makes `testEveryTrainingBlockStationSitsInTwoToFourRounds`
/// fail (a training-block station is prescribed more than four rounds at the longer lengths); restoring
/// the shipped `2...4` rails makes it pass again. A guard that would still pass at `maxTrainingSets = 8`
/// would be worthless, so this check is the point of the story.
final class RoundCapInvariantGuardTests: XCTestCase {

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

    /// Every requested length in the product's supported band, so a regression at any one length trips.
    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    /// The invariant is pinned to the **literal** `2...4`, deliberately *not* to
    /// `SessionAssembly.minTrainingSets...maxTrainingSets`: binding the assertion to the same constants a
    /// regression would move makes the guard vacuous (bump the cap to 8 and the bound follows it). By
    /// hard-coding the bound here, reverting `maxTrainingSets` to 8 makes the depth-first fit deepen a
    /// station past four rounds at the longer lengths and this assertion trips - which is the whole point
    /// of the story (see the non-vacuity note in the class doc comment).
    ///
    /// Across 5/10/15/20/30/45/60 minutes and beginner/intermediate/advanced, every station in every
    /// *training* block (a circuit block per `SessionAssembly.isCircuit` - strength and the dedicated
    /// primal block; warm-up/cooldown bookends are linear single-set and are exempt) carries a round
    /// count (`sets`) inside `2...4`.
    func testEveryTrainingBlockStationSitsInTwoToFourRounds() async throws {
        let roundFloor = 2
        let roundCap = 4
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                XCTAssertFalse(
                    training.isEmpty,
                    "\(level) \(minutes)-min produced no training block to guard"
                )

                for block in training {
                    XCTAssertFalse(
                        block.exercises.isEmpty,
                        "\(level) \(minutes)-min: training block \(block.title) has no stations"
                    )
                    for exercise in block.exercises {
                        XCTAssertGreaterThanOrEqual(
                            exercise.sets, roundFloor,
                            "\(level) \(minutes)-min: \(block.title)/\(exercise.exercise.id) prescribed \(exercise.sets) rounds, below the floor of \(roundFloor)"
                        )
                        XCTAssertLessThanOrEqual(
                            exercise.sets, roundCap,
                            "\(level) \(minutes)-min: \(block.title)/\(exercise.exercise.id) prescribed \(exercise.sets) rounds, above the cap of \(roundCap)"
                        )
                    }
                }
            }
        }
    }

    /// Each training block is internally even: every station in a block shares one round count, so
    /// "Round N of M" is well-defined (ADR-0003). Guarding this alongside the range keeps a future
    /// change from satisfying the `2...4` bound with a block that mixes, say, 2- and 4-round stations.
    func testEveryTrainingBlockIsInternallyEven() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                for block in training {
                    let roundCounts = Set(block.exercises.map(\.sets))
                    XCTAssertEqual(
                        roundCounts.count, 1,
                        "\(level) \(minutes)-min: training block \(block.title) is uneven with round counts \(roundCounts.sorted())"
                    )
                }
            }
        }
    }

    /// The rails themselves are the shipped `2...4`. A sanity pin so a reader of this guard sees, at a
    /// glance, the exact bound it enforces - and so a change to the constants is a deliberate, visible
    /// edit here rather than a silent widening the range assertion might not surface on the mock catalog.
    func testShippedRoundRailsAreTwoToFour() {
        XCTAssertEqual(SessionAssembly.minTrainingSets, 2, "the training-block round floor must stay 2")
        XCTAssertEqual(SessionAssembly.maxTrainingSets, 4, "the training-block round cap must stay 4")
    }
}
