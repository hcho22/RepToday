import XCTest
@testable import RepToday

/// The engine half of the Ready Screen's **Different workout** button (`SessionVariation`).
///
/// A press rebuilds the session at the same length and on the same Training Day with other moves where
/// the plan has a choice (which ladders fill a short session, which stretches, which core ladder). These
/// tests fold a whole sequence of presses through the real assembler and the real catalog, the way the
/// Ready Screen does (`SessionVariation.advanced(past:)` then `SessionAssembly.assemble(variation:)`), and
/// check every workout in it against the rules that govern any session: the fit (within the tolerance or
/// an honest shortfall), the session shape and Training Day, movement access and injury flags, each
/// ladder's current rung, four sets per station, and the Earned Reps behind every main and core station.
/// They also pin that presses really change the moves, that a sequence cycles back to the default
/// session deterministically, and that an empty variation is the session exactly as it was before the
/// input existed.
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
                fitnessLevel: level,
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
        /// The Training Day to build, or `nil` to let the Rotation decide from `recentLogs`.
        var day: TrainingDay? = nil
    }

    /// A user's last three days of sessions, each the engine's own default session for that day, logged as
    /// completed at its prescription the way the player writes it - enough history for real rungs, Earned
    /// Reps, a variety window and a Rotation that has moved through Push, Pull and Legs.
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
                    skipped: false,
                    role: prescription.role,
                    earnedReps: prescription.earnedReps,
                    earnedDurationSeconds: prescription.earnedDurationSeconds
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
        // Each injured scenario trains a day its flag narrows but does not empty: a knee flag takes the
        // squat-side ladders off a Legs Day, a lower-back flag the hinge ladders; a wrist flag rules out
        // push, so its Pull Day must still never show a push movement.
        for (injury, day) in [("knees", TrainingDay.legs), ("lower_back", .legs), ("wrist", .pull)] {
            let injured = user(level: .intermediate, injuries: [injury])
            result.append(Scenario(name: "\(injury) flagged", user: injured, recentLogs: history(for: injured, library: library), day: day))
        }
        let strength = user(level: .beginner, phase: .strength)
        result.append(Scenario(name: "strength phase", user: strength, recentLogs: history(for: strength, library: library)))
        return result
    }

    // MARK: - Folding presses

    private func assemble(_ scenario: Scenario, minutes: Int, variation: SessionVariation, library: [Exercise]) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes, user: scenario.user, library: library,
            recentLogs: scenario.recentLogs, variation: variation, trainingDay: scenario.day, asOf: asOf, calendar: calendar
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

    /// Everything about a workout except its fresh ids: block order, category and pause, and each slot's
    /// move and full prescription.
    private func content(_ workout: Workout) -> [String] {
        workout.blocks.map { block in
            "\(block.category)p\(block.transitionSeconds ?? 0):" + block.exercises.map { item in
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

    /// The session lands within `toleranceSeconds` of `minutes`, or runs short only because the same plan,
    /// re-fit with the press's variation, has no lever left (`isSaturated`) - an honest shortfall.
    private func fillsOrRunsHonestlyShort(_ workout: Workout, _ scenario: Scenario, minutes: Int, offered: Set<String>, library: [Exercise]) -> Bool {
        let gap = SessionAssembly.plannedSeconds(of: workout) - minutes * 60
        if abs(gap) <= SessionAssembly.toleranceSeconds { return true }
        guard gap < 0, let day = workout.trainingDay else { return false }
        var plan = SessionAssembly.planSession(
            requestedMinutes: minutes, user: scenario.user, library: library, recentLogs: scenario.recentLogs,
            offered: offered, trainingDay: day, asOf: asOf, calendar: calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        return plan.isSaturated
    }

    func testEveryPressKeepsTheLengthShapeDayAccessInjuriesRungsSetsAndEarnedReps() async throws {
        let library = try await library()
        for scenario in scenarios(library: library) {
            let user = scenario.user
            let level = user.profile.fitnessLevel
            let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: scenario.recentLogs)
            let poolIds = Set(pool.map(\.id))
            let contraindicated = InjuryContraindication.contraindicatedPatterns(for: user.profile.injuries)
            for minutes in lengths {
                var variation = SessionVariation.none
                var presses: [(Workout, Set<String>)] = []
                var shown = assemble(scenario, minutes: minutes, variation: variation, library: library)
                presses.append((shown, []))
                for _ in 0..<pressCap {
                    variation = variation.advanced(past: shown)
                    shown = assemble(scenario, minutes: minutes, variation: variation, library: library)
                    presses.append((shown, variation.offeredExerciseIds))
                    if content(shown) == content(presses[0].0) { break }
                }
                let defaultWorkout = presses[0].0
                let cycle = cycleIndex(of: presses.map(\.0)) ?? presses.count - 1
                for (index, (workout, offered)) in presses.prefix(cycle + 1).enumerated() {
                    let label = "\(scenario.name) \(minutes) min press \(index)"

                    // A press that fell back to the default session was assembled without the offered moves.
                    let assembledWith = content(workout) == content(defaultWorkout) ? [] : offered
                    XCTAssertTrue(
                        fillsOrRunsHonestlyShort(workout, scenario, minutes: minutes, offered: assembledWith, library: library),
                        "\(label): misses the requested length by \(SessionAssembly.plannedSeconds(of: workout) - minutes * 60)s with fit levers left"
                    )
                    XCTAssertEqual(workout.requestedMinutes, minutes, label)
                    XCTAssertEqual(workout.trainingDay, defaultWorkout.trainingDay, "\(label): changed the Training Day")
                    XCTAssertEqual(workout.blocks.map(\.category), defaultWorkout.blocks.map(\.category), "\(label): changed the session shape")

                    for block in workout.blocks {
                        for item in block.exercises {
                            let exercise = item.exercise
                            XCTAssertFalse(contraindicated.contains(exercise.movementPattern), "\(label): \(exercise.id) ignores an injury flag")
                            XCTAssertFalse(MovementAccess.isWithdrawn(exercise), "\(label): \(exercise.id) is withdrawn")
                            XCTAssertNil(item.stretchSeconds, "\(label): \(exercise.id) carries a stretched work window")
                            guard SessionAssembly.isCircuit(block.category) else {
                                XCTAssertTrue(poolIds.contains(exercise.id), "\(label): \(exercise.id) is outside movement access, injury and skip filters")
                                continue
                            }
                            XCTAssertEqual(item.sets, RepGrammar.setsPerStation, "\(label): \(exercise.id) runs \(item.sets) sets")
                            // A Practice Movement previews the next rung under its own eligibility (ADR-0015).
                            guard item.role != .practice else { continue }
                            XCTAssertTrue(poolIds.contains(exercise.id), "\(label): \(exercise.id) is outside movement access, injury and skip filters")

                            let chain = library.filter { $0.progressionChainId == exercise.progressionChainId }
                            let rung = ProgressionChainSelection.selectInChain(chain, eligibleIds: poolIds, recentLogs: scenario.recentLogs, level: level)
                            XCTAssertEqual(rung?.exercise.id, exercise.id, "\(label): \(exercise.id) is not its ladder's current rung")

                            let earned = AdaptiveOverload.earned(
                                for: exercise, level: level, recentLogs: scenario.recentLogs,
                                steppedDownSince: ProgressionChainSelection.stepDownDate(onto: exercise, library: library, recentLogs: scenario.recentLogs, level: level)
                            )
                            XCTAssertEqual(
                                item.earnedReps ?? item.earnedDurationSeconds,
                                RepGrammar.served(earned: earned, for: RepGrammar.kind(of: exercise), level: level),
                                "\(label): \(exercise.id) does not record its Earned Reps"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Presses change the moves, then cycle back

    /// Whether the default session already holds every move a press could bring: every day-matched
    /// stretch the user is offered (and no fallback stretch a press could change), both a ladder's rung
    /// and the rest of the day's ladders, and every core ladder they are offered. A press then has nothing
    /// new to rank ahead, so it returns the default session (ADR-0018 strict bookends).
    private func pressCanChangeNothing(_ workout: Workout, scenario: Scenario, library: [Exercise]) -> Bool {
        guard let day = workout.trainingDay else { return false }
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: scenario.user, recentLogs: scenario.recentLogs)
        let prescriptions = workout.blocks.flatMap(\.exercises)
        let shownIds = Set(prescriptions.map(\.exercise.id))
        let stretches = prescriptions.map(\.exercise).filter { $0.pillar == .mobility }
        let matches = pool.filter { $0.pillar == .mobility && SessionAssembly.complements($0, anyOf: day.patterns) }
        let offeredLadders = { (ladders: [String]) in Set(pool.map(\.progressionChainId).filter(ladders.contains)) }
        let shownLadders = { (role: StationRole) in Set(prescriptions.filter { $0.role == role }.map(\.exercise.progressionChainId)) }
        return matches.allSatisfy { shownIds.contains($0.id) }
            && stretches.allSatisfy { SessionAssembly.complements($0, anyOf: day.patterns) }
            && shownLadders(.main) == offeredLadders(day.ladders)
            && shownLadders(.core) == offeredLadders(SessionAssembly.coreLadders)
    }

    /// A press shows something new whenever the eligible pool holds anything new to show. With strict
    /// day-matched bookends (ADR-0018), a Discipline-Phase beginner or intermediate's 45 and 60 minute Push
    /// Day is the exception: it already holds all four push stretches they are offered, both push ladders
    /// with their Practice Movements and both core ladders they are offered, so a press returns the same
    /// session. That set is pinned so a change to it is a deliberate one.
    func testAPressChangesTheMovesAndEachPressBeforeTheCycleShowsSomethingNew() async throws {
        let library = try await library()
        var unchangeable: [String] = []
        for scenario in scenarios(library: library) {
            for minutes in lengths {
                let presses = sequence(scenario, minutes: minutes, presses: pressCap, library: library)
                let label = "\(scenario.name) \(minutes) min"
                if pressCanChangeNothing(presses[0], scenario: scenario, library: library) {
                    unchangeable.append(label)
                    XCTAssertEqual(content(presses[1]), content(presses[0]), "\(label): a press with nothing new returns the default")
                    continue
                }
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
        XCTAssertEqual(unchangeable, [
            "beginner new 45 min", "beginner new 60 min", "beginner with history 45 min", "beginner with history 60 min",
            "intermediate new 45 min", "intermediate new 60 min", "intermediate with history 45 min", "intermediate with history 60 min",
        ])
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

    // MARK: - A press keeps the Training Day

    /// A press never changes what the Rotation decided: on every Training Day, every press trains that
    /// day's groups, and the moves it can change are the bookends, the Core Sprinkle and which ladders fill
    /// a short session - never a group the day does not train.
    func testAPressNeverChangesTheTrainingDay() async throws {
        let library = try await library()
        for level in FitnessLevel.allCases {
            let person = user(level: level)
            let scenario = Scenario(name: "\(level)", user: person, recentLogs: history(for: person, library: library))
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    var variation = SessionVariation.none
                    for index in 0..<12 {
                        let workout = SessionAssembly.assemble(
                            requestedMinutes: minutes, user: person, library: library, recentLogs: scenario.recentLogs,
                            variation: variation, trainingDay: day, asOf: asOf, calendar: calendar
                        )
                        let label = "\(level) \(day) \(minutes) min press \(index)"
                        XCTAssertEqual(workout.trainingDay, day, label)
                        let worked = workout.blocks.filter { $0.category == .strength }.flatMap(\.exercises)
                            .filter { $0.role == .main || $0.role == .practice }
                        XCTAssertTrue(worked.allSatisfy { day.patterns.contains($0.exercise.movementPattern) }, "\(label): \(worked.map(\.exercise.id))")
                        variation = variation.advanced(past: workout)
                    }
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
                    recentLogs: scenario.recentLogs, trainingDay: scenario.day, asOf: asOf, calendar: calendar
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
