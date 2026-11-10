import XCTest
@testable import RepToday

/// US-TD01 / US-TD04 / US-TD05: the Training Day slot plan and its standing invariant guard.
final class TrainingDaySessionTests: XCTestCase {

    private var library: [Exercise] = []
    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func session(
        _ day: TrainingDay,
        minutes: Int,
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        injuries: [String] = [],
        logs: [WorkoutLog] = []
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(level: level, phase: phase, injuries: injuries),
            library: library,
            recentLogs: logs,
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    private func stations(_ workout: Workout) -> [PrescribedExercise] {
        workout.blocks.filter { $0.category == .strength }.flatMap(\.exercises)
    }

    // MARK: Invariant guard (US-TD04)

    /// Every main, Practice and core station runs exactly 4 sets; every rep and hold number is a multiple
    /// of 5; no session mixes groups; no primal; no `pull_ytw`; the bookends hold at most two stretches
    /// each; and the movement counts follow decision 8. Bound to literals so a changed constant cannot
    /// silently loosen it.
    func testEverySessionKeepsTheTrainingDayInvariants() {
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                for day in TrainingDay.rotation {
                    for minutes in lengths {
                        let workout = session(day, minutes: minutes, level: level, phase: phase)
                        let label = "\(level) \(phase) \(day) \(minutes) min"
                        let all = workout.blocks.flatMap(\.exercises)
                        let circuit = stations(workout)

                        XCTAssertEqual(workout.trainingDay, day, label)
                        XCTAssertTrue(circuit.allSatisfy { $0.sets == 4 }, "\(label): a station is not 4 sets")
                        for item in all {
                            let value = item.reps ?? item.durationSeconds ?? 0
                            XCTAssertEqual(value % 5, 0, "\(label): \(item.exercise.id) at \(value)")
                        }
                        XCTAssertFalse(all.contains { $0.exercise.pillar == .primal }, "\(label): primal")
                        XCTAssertFalse(all.contains { $0.exercise.id == "pull_ytw" }, "\(label): pull_ytw")

                        let worked = circuit.filter { $0.role == .main || $0.role == .practice }
                        XCTAssertTrue(
                            worked.allSatisfy { day.patterns.contains($0.exercise.movementPattern) },
                            "\(label): mixes groups \(worked.map(\.exercise.id))"
                        )
                        let core = circuit.filter { $0.role == .core }
                        XCTAssertTrue(core.allSatisfy { $0.exercise.movementPattern == .core }, label)
                        XCTAssertEqual(core.count, minutes <= 10 ? 0 : 1, "\(label): Core Sprinkle")

                        let mains = [5: 1, 10: 1, 15: 1, 20: 1, 30: 2, 45: 3, 60: 4][minutes]!
                        XCTAssertEqual(worked.count, mains, "\(label): main slots")

                        let warmup = workout.blocks.first { $0.category == .warmup }?.exercises.count ?? 0
                        let cooldown = workout.blocks.first { $0.category == .cooldown }?.exercises.count ?? 0
                        XCTAssertLessThanOrEqual(warmup, 2, label)
                        XCTAssertLessThanOrEqual(cooldown, 2, label)
                        let distinct = Set(all.map(\.exercise.id)).count
                        if minutes == 45 { XCTAssertLessThanOrEqual(distinct, 8, label) }
                        if minutes == 60 { XCTAssertLessThanOrEqual(distinct, 9, label) }
                    }
                }
            }
        }
    }

    // MARK: Slots (decisions 8-11)

    func testAPushDayFillsSlotsThreeAndFourWithPracticeOfTheNextRung() throws {
        let workout = session(.push, minutes: 60, level: .beginner)
        let circuit = stations(workout)
        XCTAssertEqual(circuit.map { $0.role }, [.main, .main, .practice, .practice, .core])

        for (mainIndex, practiceIndex) in [(0, 2), (1, 3)] {
            let main = circuit[mainIndex]
            let practice = circuit[practiceIndex]
            XCTAssertEqual(practice.exercise.progressionChainId, main.exercise.progressionChainId)
            XCTAssertEqual(practice.exercise.progressionOrder, main.exercise.progressionOrder + 1)
            XCTAssertEqual(practice.reps ?? practice.durationSeconds, practice.exercise.isHold ? 15 : (practice.exercise.isPerSide == true ? 5 : 10))
            XCTAssertNil(practice.earnedReps)
        }
    }

    func testPracticeBypassesTheStapleGateButNeverAWithdrawnRung() throws {
        // A beginner on Superman Hold practices Reverse Snow Angel, which is not a beginner staple.
        let beginner = stations(session(.pull, minutes: 60, level: .beginner))
        XCTAssertTrue(beginner.contains { $0.role == .practice && $0.exercise.id == "pull_reverse_snow_angel" })
        let staples = MovementAccess.available(in: library, level: .beginner, phase: .discipline).map(\.id)
        XCTAssertFalse(staples.contains("pull_reverse_snow_angel"))

        // An advanced user already on Reverse Snow Angel would practice Prone Y-T-W Raises, which is
        // withdrawn, so the slot takes the rung below at volume reps instead.
        let atSnowAngel = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("pull_reverse_snow_angel", pattern: .pull, value: 20, earned: 20)],
            completedAt: TrainingDayFixtures.date(daysAgo: 2)
        )
        let advanced = stations(session(.pull, minutes: 60, level: .advanced, logs: [atSnowAngel]))
        let postural = advanced.filter { $0.exercise.progressionChainId == "pull_postural" }
        XCTAssertEqual(postural.first { $0.role == .main }?.exercise.id, "pull_reverse_snow_angel")
        XCTAssertEqual(postural.first { $0.role == .practice }?.exercise.id, "pull_superman")
        XCTAssertFalse(advanced.contains { $0.exercise.id == "pull_ytw" })
    }

    func testPracticeNeverBypassesAStrengthPhaseLock() throws {
        // An advanced Discipline user on Archer Push-Up: the next rung is a Strength-Phase skill, so the
        // Practice slot takes the rung below instead.
        let atArcher = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_archer", pattern: .push, value: 10, earned: 10)],
            completedAt: TrainingDayFixtures.date(daysAgo: 2)
        )
        let circuit = stations(session(.push, minutes: 60, level: .advanced, logs: [atArcher]))
        XCTAssertFalse(circuit.contains { $0.exercise.phase == .strength })
        XCTAssertEqual(circuit.first { $0.role == .practice && $0.exercise.progressionChainId == "push_horizontal" }?.exercise.id, "push_diamond")
    }

    func testALegsDayLeadsWithOneSquatSideAndOneHingeSideLadder() {
        let circuit = stations(session(.legs, minutes: 30))
        let sides = circuit.filter { $0.role == .main }.map(\.exercise.movementPattern)
        XCTAssertEqual(Set(sides), [.squat, .hinge])
        let full = stations(session(.legs, minutes: 60)).filter { $0.role == .main }.map(\.exercise.progressionChainId)
        XCTAssertEqual(Set(full), ["squat", "lunge", "hinge_bridge", "hinge_hip"])
    }

    func testEachLadderContributesItsCurrentRungUntilEarned() {
        let atStandard = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 20, earned: 20)],
            completedAt: TrainingDayFixtures.date(daysAgo: 3)
        )
        let main = stations(session(.push, minutes: 30, level: .beginner, logs: [atStandard]))
            .first { $0.exercise.progressionChainId == "push_horizontal" }
        XCTAssertEqual(main?.exercise.id, "push_standard")
        XCTAssertEqual(main?.earnedReps, 25)
    }

    // MARK: Fit (decisions 16-17)

    func testALongSessionPadsAboveEarnedRepsAndRecordsWhatWasEarned() {
        let circuit = stations(session(.push, minutes: 45, level: .advanced))
        let mains = circuit.filter { $0.role == .main }
        XCTAssertTrue(mains.contains { ($0.reps ?? 0) > ($0.earnedReps ?? 0) }, "nothing padded: \(mains.map { ($0.reps, $0.earnedReps) })")
        XCTAssertTrue(mains.allSatisfy { $0.earnedReps == ($0.exercise.isPerSide == true ? 5 : 15) })
    }

    func testRestCapsFollowLengthAndLevel() {
        for level in FitnessLevel.allCases {
            for minutes in lengths {
                for day in TrainingDay.rotation {
                    let workout = session(day, minutes: minutes, level: level)
                    guard let block = workout.blocks.first(where: { $0.category == .strength }) else { continue }
                    let rest = block.exercises[0].restSeconds
                    let pause = block.transitionSeconds ?? 15
                    if minutes <= 30 {
                        XCTAssertLessThanOrEqual(rest, 60)
                        XCTAssertEqual(pause, 15)
                    } else {
                        XCTAssertLessThanOrEqual(rest, [FitnessLevel.beginner: 120, .intermediate: 90, .advanced: 60][level]!)
                        XCTAssertLessThanOrEqual(pause, 60)
                    }
                }
            }
        }
    }

    // MARK: Swap keeps the slot's role

    func testASwapKeepsTheSlotsRole() async throws {
        let user = TrainingDayFixtures.user(level: .advanced)
        let workout = session(.push, minutes: 60, level: .advanced)
        for prescription in stations(workout) {
            let outcome = ExerciseSwap.swap(prescription, in: workout, user: user, library: library, recentLogs: [])
            guard case let .substituted(substitute) = outcome else { continue }
            XCTAssertEqual(substitute.role, prescription.role, prescription.exercise.id)
            XCTAssertEqual(substitute.sets, 4)
            if prescription.role == .practice {
                XCTAssertNil(substitute.earnedReps)
                XCTAssertEqual(substitute.reps ?? substitute.durationSeconds, substitute.exercise.isHold ? 15 : (substitute.exercise.isPerSide == true ? 5 : 10))
            }
        }
    }

    // MARK: Recovery (US-TD05)

    func testTheRecoveryFlowIsShortMobilityOnlyAndNeverASession() {
        let workout = SessionAssembly.recoveryWorkout(
            user: TrainingDayFixtures.user(),
            library: library,
            recentLogs: [],
            asOf: TrainingDayFixtures.asOf
        )
        let exercises = workout.blocks.flatMap(\.exercises)
        XCTAssertEqual(exercises.count, 4)
        XCTAssertTrue(exercises.allSatisfy { $0.exercise.pillar == .mobility && $0.role == .recovery })
        XCTAssertNil(workout.trainingDay)
        XCTAssertLessThanOrEqual(SessionAssembly.plannedSeconds(of: workout), 7 * 60)
    }

    // MARK: Catalog (US-TD01)

    func testPrimalIsRetiredAndPullYTWSitsWithdrawnAtTheTopOfThePosturalChain() throws {
        let data = try Data(contentsOf: Bundle.main.url(forResource: "Exercises", withExtension: "json")!)
        let catalog = try JSONDecoder().decode([Exercise].self, from: data)
        XCTAssertEqual(catalog.count, 76)
        XCTAssertTrue(catalog.filter { $0.pillar == .primal }.allSatisfy { $0.audience == .retired })
        XCTAssertEqual(library.count, 68)
        XCTAssertFalse(library.contains { MovementAccess.isWithdrawn($0) })
        let ytw = try XCTUnwrap(catalog.first { $0.id == "pull_ytw" })
        XCTAssertEqual(ytw.progressionChainId, "pull_postural")
        XCTAssertEqual(ytw.regressionId, "pull_reverse_snow_angel")
        XCTAssertTrue(MovementAccess.isWithdrawn(ytw))
    }

    func testTheLoaderRejectsAWithdrawnRungBelowALiveOne() throws {
        let data = try Data(contentsOf: Bundle.main.url(forResource: "Exercises", withExtension: "json")!)
        var catalog = try JSONDecoder().decode([Exercise].self, from: data)
        // Withdraw Superman Hold, the bottom of the postural chain, under the live Reverse Snow Angel.
        let index = try XCTUnwrap(catalog.firstIndex { $0.id == "pull_superman" })
        catalog[index].audience = .version2
        XCTAssertThrowsError(try MockExerciseService(library: catalog)) { error in
            guard case ExerciseLibraryError.withdrawnMovementInLiveChain = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    // MARK: Days an injury empties

    func testADayAnInjuryEmptiesIsPassedOverSoTheRotationNeverStalls() {
        // A wrist flag removes every push ladder: the Rotation skips Push, and a Cycle of Pull and Legs
        // owes the Rest Day.
        let user = TrainingDayFixtures.user(injuries: ["wrist"])
        XCTAssertEqual(SessionAssembly.trainableDays(user: user, library: library, recentLogs: []), [.pull, .legs])
        XCTAssertEqual(SessionAssembly.trainingPlan(user: user, library: library, recentLogs: [], asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar), .train(.pull))
        let cycle = [
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2)),
            TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 1)),
        ]
        XCTAssertEqual(
            SessionAssembly.trainingPlan(user: user, library: library, recentLogs: cycle, asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar),
            .rest(next: .pull, isEarly: false)
        )
        let workout = SessionAssembly.assemble(
            requestedMinutes: 30,
            user: user,
            library: library,
            recentLogs: [],
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        XCTAssertEqual(workout.trainingDay, .pull)
        XCTAssertTrue(stations(workout).contains { $0.role == .main })
    }

    // MARK: Practice under the cold-start cap

    func testPracticeNeverExceedsTheColdStartDifficultyCap() {
        let user = TrainingDayFixtures.user(level: .beginner)
        let policy = SessionPolicy.seeded(forFitnessLevel: .beginner)
        let cap = try! XCTUnwrap(policy.coldStartContract).cappedMaxDifficulty
        for day in TrainingDay.rotation {
            for minutes in [45, 60] {
                let workout = SessionAssembly.assemble(
                    requestedMinutes: minutes,
                    user: user,
                    library: library,
                    recentLogs: [],
                    sessionPolicy: policy,
                    trainingDay: day,
                    asOf: TrainingDayFixtures.asOf,
                    calendar: TrainingDayFixtures.calendar
                )
                for station in stations(workout) {
                    XCTAssertLessThanOrEqual(station.exercise.difficulty, cap, "\(day) \(minutes) min: \(station.exercise.id)")
                }
            }
        }
    }
}
