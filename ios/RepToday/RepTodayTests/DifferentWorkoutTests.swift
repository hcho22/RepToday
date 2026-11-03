import XCTest
@testable import RepToday

/// The engine half of the Ready Screen's **Different workout** button (`SessionVariation`).
///
/// A press rebuilds the session at the same length with other moves. These tests fold a whole sequence
/// of presses through the real assembler and the real catalog, the way the Ready Screen does
/// (`SessionVariation.advanced(past:)` then `SessionAssembly.assemble(variation:)`), and check every
/// workout in it against the rules that govern any session: the ±60 s fit, the session shape, movement
/// access and injury flags, the earned progression frontier, the round cap and even rounds, and the
/// Adaptive Overload targets. They also pin that presses really change the moves, that a sequence cycles
/// back to the default session deterministically, and that an empty variation is the session exactly as
/// it was before the input existed.
final class DifferentWorkoutTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
    }

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    /// Far beyond any real sequence: every press that does not cycle shows at least one move no earlier
    /// press in the sequence showed, and the catalog is finite.
    private let pressCap = 80

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(level: FitnessLevel, phase: Phase = .discipline, injuries: [String] = []) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75,
                fitnessLevel: level, primaryGoal: .stayActive,
                sitsLong: false, injuries: injuries, typicalAvailableMinutes: 15
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }

    // MARK: - Scenarios

    private struct Scenario {
        let name: String
        let user: User
        let recentLogs: [WorkoutLog]
    }

    /// A user's last three days of sessions, each the engine's own default session for that day, logged as
    /// completed at its prescription - enough history for real frontiers, staleness, a variety window and
    /// a previous-session lead pattern.
    private func history(for user: User, library: [Exercise]) -> [WorkoutLog] {
        var logs: [WorkoutLog] = []
        for daysAgo in [3, 2, 1] {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
            let workout = SessionAssembly.assemble(
                requestedMinutes: 20, user: user, library: library,
                recentLogs: logs, asOf: day, calendar: calendar
            )
            logs.append(log(of: workout, at: day))
        }
        return logs
    }

    private func log(of workout: Workout, at date: Date) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: workout.id, completedAt: date,
            requestedMinutes: workout.requestedMinutes, durationMinutes: workout.requestedMinutes,
            wasReturn: false, shape: workout.shape, focusPillar: workout.focusPillar,
            perceivedDifficulty: .justRight,
            exercises: workout.blocks.flatMap(\.exercises).map { prescription in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: prescription.exercise.id,
                    pillar: prescription.exercise.pillar,
                    movementPattern: prescription.exercise.movementPattern,
                    completedSets: Array(
                        repeating: CompletedSet(reps: prescription.reps, durationSeconds: prescription.durationSeconds),
                        count: prescription.sets
                    ),
                    skipped: false
                )
            }
        )
    }

    private func scenarios(library: [Exercise]) -> [Scenario] {
        var result: [Scenario] = []
        for level in FitnessLevel.allCases {
            let fresh = user(level: level)
            result.append(Scenario(name: "\(level) new", user: fresh, recentLogs: []))
            result.append(Scenario(name: "\(level) with history", user: fresh, recentLogs: history(for: fresh, library: library)))
        }
        for injury in ["knees", "lower_back", "wrist"] {
            let injured = user(level: .intermediate, injuries: [injury])
            result.append(Scenario(name: "\(injury) flagged", user: injured, recentLogs: history(for: injured, library: library)))
        }
        let strength = user(level: .beginner, phase: .strength)
        result.append(Scenario(name: "strength phase", user: strength, recentLogs: history(for: strength, library: library)))
        return result
    }

    // MARK: - Folding presses

    private func assemble(_ scenario: Scenario, minutes: Int, variation: SessionVariation, library: [Exercise]) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes, user: scenario.user, library: library,
            recentLogs: scenario.recentLogs, variation: variation, asOf: asOf, calendar: calendar
        )
    }

    /// The default session followed by `presses` Different workout presses, folded exactly as the Ready
    /// Screen folds them.
    private func sequence(_ scenario: Scenario, minutes: Int, presses: Int, library: [Exercise]) -> [Workout] {
        var variation = SessionVariation.none
        var shown = assemble(scenario, minutes: minutes, variation: variation, library: library)
        var result = [shown]
        for _ in 0..<presses {
            variation = variation.advanced(past: shown)
            shown = assemble(scenario, minutes: minutes, variation: variation, library: library)
            result.append(shown)
        }
        return result
    }

    /// Everything about a workout except its fresh ids: block order and category, and each slot's move and
    /// full prescription.
    private func content(_ workout: Workout) -> [String] {
        workout.blocks.map { block in
            "\(block.category):" + block.exercises.map { item in
                "\(item.exercise.id)x\(item.sets)r\(item.reps ?? -1)d\(item.durationSeconds ?? -1)s\(item.restSeconds)"
            }.joined(separator: ",")
        }
    }

    /// The press index at which a sequence first comes back to its default session.
    private func cycleIndex(of sequence: [Workout]) -> Int? {
        let first = content(sequence[0])
        return sequence.indices.dropFirst().first { content(sequence[$0]) == first }
    }

    // MARK: - Every rule still governs every press

    func testEveryPressKeepsTheLengthShapeAccessInjuriesFrontiersRoundsAndTargets() async throws {
        let library = try await library()
        var largestStretch = 0
        defer { print("DIFFERENT WORKOUT LARGEST PER-SET STRETCH: \(largestStretch)s") }
        for scenario in scenarios(library: library) {
            let pool = ExercisePoolFilter.eligiblePool(from: library, user: scenario.user, recentLogs: scenario.recentLogs)
            let poolIds = Set(pool.map(\.id))
            let contraindicated = InjuryContraindication.contraindicatedPatterns(for: scenario.user.profile.injuries)
            for minutes in lengths {
                let presses = sequence(scenario, minutes: minutes, presses: pressCap, library: library)
                let defaultShape = presses[0].blocks.map(\.category)
                let cycle = cycleIndex(of: presses) ?? presses.count - 1
                // Every press - the default and each variation, injured scenarios included - lands within
                // the ±60 s promise: when an injury flag narrows the pool so far that the round cap and the
                // stations left cannot fill a long session, the stretched work windows do (ADR-0010).
                for (index, workout) in presses.prefix(cycle + 1).enumerated() {
                    let label = "\(scenario.name) \(minutes) min press \(index)"

                    XCTAssertLessThanOrEqual(
                        abs(SessionAssembly.plannedSeconds(of: workout) - minutes * 60),
                        SessionAssembly.toleranceSeconds,
                        "\(label): misses the requested length"
                    )
                    for block in workout.blocks {
                        for item in block.exercises {
                            XCTAssertLessThanOrEqual(item.stretchSeconds ?? 0, SessionAssembly.maxStretchSecondsPerSet, label)
                            largestStretch = max(largestStretch, item.stretchSeconds ?? 0)
                        }
                    }
                    XCTAssertEqual(workout.requestedMinutes, minutes, label)
                    XCTAssertEqual(workout.blocks.map(\.category), defaultShape, "\(label): changed the session shape")

                    for block in workout.blocks {
                        if SessionAssembly.isCircuit(block.category) {
                            XCTAssertEqual(Set(block.exercises.map(\.sets)).count, 1, "\(label): \(block.title) is uneven")
                        }
                        for item in block.exercises {
                            let exercise = item.exercise
                            XCTAssertTrue(poolIds.contains(exercise.id), "\(label): \(exercise.id) is outside movement access, injury and skip filters")
                            XCTAssertFalse(contraindicated.contains(exercise.movementPattern), "\(label): \(exercise.id) ignores an injury flag")

                            let target = AdaptiveOverload.target(for: exercise, recentLogs: scenario.recentLogs)
                            XCTAssertEqual(item.reps, target.reps, "\(label): \(exercise.id) reps are not its Adaptive Overload target")
                            XCTAssertEqual(item.durationSeconds, target.durationSeconds, "\(label): \(exercise.id) hold is not its Adaptive Overload target")

                            guard SessionAssembly.isCircuit(block.category) else { continue }
                            XCTAssertTrue((2...4).contains(item.sets), "\(label): \(exercise.id) runs \(item.sets) rounds")
                            let chain = library.filter { $0.progressionChainId == exercise.progressionChainId }
                            let frontier = ProgressionChainSelection.selectInChain(
                                chain, eligibleIds: poolIds, recentLogs: scenario.recentLogs
                            )
                            XCTAssertEqual(frontier?.exercise.id, exercise.id, "\(label): \(exercise.id) is not its chain's earned tier")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Presses change the moves, then cycle back

    func testAPressChangesTheMovesAndEachPressBeforeTheCycleShowsSomethingNew() async throws {
        let library = try await library()
        for scenario in scenarios(library: library) {
            for minutes in lengths {
                let presses = sequence(scenario, minutes: minutes, presses: pressCap, library: library)
                let label = "\(scenario.name) \(minutes) min"
                XCTAssertNotEqual(
                    SessionVariation.exerciseIds(in: presses[1]),
                    SessionVariation.exerciseIds(in: presses[0]),
                    "\(label): the first press kept every move"
                )
                let cycle = try XCTUnwrap(cycleIndex(of: presses), "\(label): never cycled back within \(pressCap) presses")
                var seen = SessionVariation.exerciseIds(in: presses[0])
                for index in 1..<cycle {
                    let ids = SessionVariation.exerciseIds(in: presses[index])
                    XCTAssertFalse(ids.isSubset(of: seen), "\(label): press \(index) showed nothing new before the cycle")
                    seen.formUnion(ids)
                }
            }
        }
    }

    func testTheSequenceCyclesBackToTheDefaultAndRepeatsExactly() async throws {
        let library = try await library()
        for scenario in scenarios(library: library) {
            for minutes in lengths {
                let label = "\(scenario.name) \(minutes) min"
                let probe = sequence(scenario, minutes: minutes, presses: pressCap, library: library)
                let cycle = try XCTUnwrap(cycleIndex(of: probe), "\(label): never cycled back")
                let twice = sequence(scenario, minutes: minutes, presses: 2 * cycle + 1, library: library)
                for index in 0...cycle {
                    XCTAssertEqual(content(twice[index + cycle]), content(twice[index]), "\(label): press \(index + cycle) does not repeat press \(index)")
                }
            }
        }
    }

    func testTheSameInputsAndPressCountGiveTheSameWorkout() async throws {
        let library = try await library()
        for scenario in scenarios(library: library) {
            for minutes in [5, 20, 60] {
                let once = sequence(scenario, minutes: minutes, presses: 6, library: library).map(content)
                let again = sequence(scenario, minutes: minutes, presses: 6, library: library).map(content)
                XCTAssertEqual(once, again, "\(scenario.name) \(minutes) min is not deterministic")
            }
        }
    }

    // MARK: - Step 3's no-repeat lead survives a press

    func testAPressNeverLeadsWithThePreviousSessionsLeadPattern() async throws {
        let library = try await library()
        for level in FitnessLevel.allCases {
            let person = user(level: level)
            let logs = history(for: person, library: library)
            let pool = ExercisePoolFilter.eligiblePool(from: library, user: person, recentLogs: logs)
            let patterns = Array(Set(pool.filter { $0.pillar == .strength }.map(\.movementPattern)))
            let blocked = try XCTUnwrap(
                PatternFocus.recentLeadPattern(among: patterns, recentLogs: logs, asOf: asOf, calendar: calendar),
                "the history must leave a previous-session lead pattern to hold back"
            )
            let scenario = Scenario(name: "\(level)", user: person, recentLogs: logs)
            for minutes in lengths {
                for (index, workout) in sequence(scenario, minutes: minutes, presses: 12, library: library).enumerated() {
                    let lead = workout.blocks.first { $0.category == .strength }?.exercises.first?.exercise.movementPattern
                    XCTAssertNotEqual(lead, blocked, "\(level) \(minutes) min press \(index) leads with yesterday's pattern")
                }
            }
        }
    }

    // MARK: - No press, no change

    /// The default request goes down the untouched path, and a variation naming no catalog move takes the
    /// varied path yet builds the same session - so the ranking it adds changes nothing until a move it
    /// names is actually on offer.
    func testAVariationNamingNoCatalogMoveBuildsTheDefaultSession() async throws {
        let library = try await library()
        let unrelated = SessionVariation(offeredExerciseIds: ["not_a_catalog_move"])
        for scenario in scenarios(library: library) {
            for minutes in lengths {
                let plain = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: scenario.user, library: library,
                    recentLogs: scenario.recentLogs, asOf: asOf, calendar: calendar
                )
                XCTAssertEqual(
                    content(assemble(scenario, minutes: minutes, variation: unrelated, library: library)),
                    content(plain),
                    "\(scenario.name) \(minutes) min"
                )
                XCTAssertEqual(
                    content(assemble(scenario, minutes: minutes, variation: .none, library: library)),
                    content(plain),
                    "\(scenario.name) \(minutes) min"
                )
            }
        }
    }

    // MARK: - SessionVariation

    func testAdvancingAddsTheShownMovesAndRestartsAfterTheDefaultComesBack() {
        let first = workout(ids: ["a", "b"])
        let second = workout(ids: ["c", "b"])
        let afterFirst = SessionVariation.none.advanced(past: first)
        XCTAssertEqual(afterFirst.offeredExerciseIds, ["a", "b"])
        let afterSecond = afterFirst.advanced(past: second)
        XCTAssertEqual(afterSecond.offeredExerciseIds, ["a", "b", "c"])
        XCTAssertTrue(afterFirst.offersSomethingNew(second))
        XCTAssertFalse(afterSecond.offersSomethingNew(first))
        // The engine fell back to the default session: nothing on screen is new, so the next press starts
        // over from it.
        XCTAssertEqual(afterSecond.advanced(past: first).offeredExerciseIds, ["a", "b"])
    }

    private func workout(ids: [String]) -> Workout {
        let exercises = ids.map { id in
            PrescribedExercise(
                id: UUID(),
                exercise: Exercise(
                    id: id, displayName: id, pillar: .strength, movementPattern: .push,
                    category: .strength, difficulty: 1, phase: .discipline, equipment: [],
                    isHold: false, defaultReps: 10, defaultDurationSeconds: nil,
                    estimatedTimePerSetSeconds: 40, metValue: 4, progressionChainId: "c",
                    progressionOrder: 0, regressionId: nil, progressionId: nil,
                    advancementCriteria: "3x12", apartmentFriendly: true
                ),
                sets: 2, reps: 10, durationSeconds: nil, restSeconds: 40
            )
        }
        return Workout(
            id: UUID(), createdAt: asOf, shape: .singleFocus, focusPillar: .strength,
            requestedMinutes: 10, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: exercises)]
        )
    }
}
