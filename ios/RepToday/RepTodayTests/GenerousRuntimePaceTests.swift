import XCTest
@testable import RepToday

/// US-CC08: the on-screen work window and the engine's planning wall-clock are the **same generously
/// calibrated number**.
///
/// The coupling itself is structural (the player calls `SessionAssembly.workSecondsPerSet(of:)` rather
/// than carrying a second value, since US-CC01), so what these tests lock is that it *stays* structural
/// and that the number is genuinely a runtime pace:
/// - the player's window for a set equals the engine's per-set seconds for that same prescription,
///   asserted over every auto-advancing set of a **real assembled session** rather than a fixture, so a
///   second window value could not be introduced anywhere along the walk without failing here;
/// - per-side and hold movements price identically runtime and planning, because there is one function:
///   a per-side hold's planned seconds are its two legs and the "Switch sides" beat between them, which
///   is exactly what the player runs, so the two agree on the same set;
/// - the number sits generously above the catalog's typical-case authored estimate, governed by the one
///   documented constant (`SessionAssembly.workPaceGenerosityFactor`);
/// - it stays a pure function of the exercise and the prescribed target - no wall clock, no `asOf` -
///   and the window is exactly that pace: the engine never stretches a work window;
/// - and the trade-off is bounded: every length lands within the tolerance or runs honestly short (every
///   fit lever spent), and every circuit station keeps its four sets.
final class GenerousRuntimePaceTests: XCTestCase {

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

    private func user(level: FitnessLevel = .intermediate) -> User {
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

    private func assemble(minutes: Int, level: FitnessLevel = .intermediate, library: [Exercise]) -> Workout {
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

    /// The session lands within `SessionAssembly.toleranceSeconds` of `minutes`, or runs short only
    /// because the same plan, re-fit, has no lever left (`isSaturated`) - an honest shortfall.
    private func assertFillsOrRunsHonestlyShort(
        _ workout: Workout,
        minutes: Int,
        level: FitnessLevel,
        library: [Exercise],
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gap = SessionAssembly.plannedSeconds(of: workout) - minutes * 60
        guard abs(gap) > SessionAssembly.toleranceSeconds else { return }
        XCTAssertLessThan(gap, 0, "\(label): overruns by \(gap)s", file: file, line: line)
        guard let day = workout.trainingDay else { return XCTFail("\(label): no Training Day", file: file, line: line) }
        var plan = SessionAssembly.planSession(
            requestedMinutes: minutes,
            user: user(level: level),
            library: library,
            recentLogs: [],
            trainingDay: day,
            asOf: asOf,
            calendar: calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        XCTAssertTrue(plan.isSaturated, "\(label): runs \(-gap)s short with fit levers left", file: file, line: line)
    }

    // MARK: - One source of truth: the screen window is the planned number

    /// The PRD validation case, run over a real 20-minute session rather than a fixture: at every
    /// auto-advancing set the player's work window is **exactly** the seconds the fit budgeted that set
    /// at - including the per-side rep slots the session happens to contain - so the window can never be
    /// roomier than the plan (which would overrun the requested minutes) nor tighter (which would rush
    /// the user). Walking the whole session is the point: a second window value introduced at any step of
    /// the rotation would be caught here, where a single-step assertion would miss it.
    func testEveryAutoAdvancingSetsWindowIsTheEnginesPlannedSecondsForThatSet() async throws {
        let workout = assemble(minutes: 20, library: try await library())
        let vm = ActiveSessionViewModel(workout: workout, now: { self.asOf })
        vm.start()

        var checkedSets = 0
        var checkedRunningWindows = 0
        var guardRail = 0
        while !vm.isComplete {
            guardRail += 1
            guard guardRail < 500 else { return XCTFail("the walk should finish long before this") }

            if let step = vm.currentStep, vm.currentStepAutoAdvances {
                let planned = SessionAssembly.workSecondsPerSet(of: step.prescription)
                XCTAssertGreaterThan(planned, 0, "\(step.prescription.exercise.id) must cost real seconds")
                XCTAssertEqual(
                    vm.workWindowSecondsPerSet, planned,
                    "\(step.prescription.exercise.id): the window must be the engine's own per-set seconds"
                )
                checkedSets += 1
                // And when the window is actually up, it is *that* number the user watches count down -
                // not a value re-derived on the way to the screen.
                if vm.isRunningWorkWindow {
                    XCTAssertEqual(vm.workWindowTotalSeconds, planned, "the running window's total is that number")
                    XCTAssertEqual(vm.workWindowRemaining(asOf: asOf), planned)
                    checkedRunningWindows += 1
                }
            }

            if vm.isRunningWorkWindow {
                vm.finishWorkWindowEarly()
            } else if vm.holdSecondsPerSide != nil, !vm.isHolding, !vm.isResting {
                vm.completeSet()
            } else if vm.isHolding {
                vm.cancelHold()
                vm.completeSet()
            } else if vm.isResting {
                vm.skipRest()
            } else {
                vm.completeSet()
            }
        }

        XCTAssertGreaterThan(checkedSets, 0, "a 20-minute session must contain auto-advancing training sets")
        XCTAssertGreaterThan(checkedRunningWindows, 0, "and the window must actually have been up on some of them")
    }

    /// Per-side and hold movements price the same way runtime and planning, because it is one function.
    /// A per-side hold's *planned* seconds are both sides (`sidesPerSet`) plus the "Switch sides" beat,
    /// and what the player runs is the prescribed seconds **per side**, once per leg, with that beat
    /// between - so a whole set of the same slot costs the plan and the user the same seconds.
    func testPerSideHoldPricesBothSidesInPlanningAndRunsPerSideInThePlayer() async throws {
        let library = try await library()
        let movement = try XCTUnwrap(library.first { $0.isHold && $0.isPerSide == true })
        let seconds = 30
        let prescription = PrescribedExercise(
            id: UUID(), exercise: movement, sets: 1, reps: nil, durationSeconds: seconds, restSeconds: 30
        )
        let workout = Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil,
            requestedMinutes: 15, wasReturn: false,
            blocks: [WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: [prescription])]
        )

        // Planning: both sides and the beat between them are charged, and nothing else.
        let planned = SessionAssembly.workSecondsPerSet(of: prescription)
        XCTAssertEqual(movement.sidesPerSet, 2)
        XCTAssertEqual(
            planned, movement.sidesPerSet * seconds + SessionAssembly.switchSidesSeconds,
            "a per-side hold's planned set is its two legs and the Switch sides beat"
        )

        // Runtime: the hold starts itself, runs the prescribed seconds per side, one leg each, with the
        // beat between, and the set ends exactly when the plan said it would.
        var clock = asOf
        let vm = ActiveSessionViewModel(workout: workout, now: { clock })
        vm.start()
        XCTAssertTrue(vm.isHolding, "the hold starts on its own")
        XCTAssertEqual(vm.holdSecondsPerSide, seconds, "each leg is the prescribed per-side hold, not the pair")
        clock = clock.addingTimeInterval(TimeInterval(seconds))
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isSwitchingSides)
        clock = clock.addingTimeInterval(TimeInterval(vm.restRemaining(asOf: clock)))
        vm.completeRestIfElapsed(asOf: clock)
        XCTAssertEqual(vm.holdSecondsPerSide, seconds, "side 2 runs the same prescribed seconds")
        clock = clock.addingTimeInterval(TimeInterval(vm.holdRemaining(asOf: clock)))
        vm.completeHoldIfElapsed(asOf: clock)
        XCTAssertTrue(vm.isComplete)
        XCTAssertEqual(Int(clock.timeIntervalSince(asOf)), planned, "the set played exactly its planned seconds")
    }

    /// ADR-0010's "no tap after start" promise, measured: a whole session played hands-free - every
    /// work window, hold leg, "Switch sides" beat and rest run to zero, not one tap - lasts exactly the
    /// seconds the engine planned it at, so it ends where the plan said: within the tolerance of the
    /// length chosen, or honestly short. Every length and fitness level, for a brand-new user. A hold the
    /// plan priced with setup seconds the player never runs would end the session early.
    func testAHandsFreeSessionPlaysExactlyItsPlannedSecondsAtEveryLength() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                var clock = asOf
                let vm = ActiveSessionViewModel(workout: workout, now: { clock })
                vm.start()

                var guardRail = 0
                while !vm.isComplete {
                    guardRail += 1
                    guard guardRail < 1_000 else { return XCTFail("\(level) \(minutes)-min never finished") }
                    if vm.isHolding {
                        clock = clock.addingTimeInterval(TimeInterval(vm.holdRemaining(asOf: clock)))
                        vm.completeHoldIfElapsed(asOf: clock)
                    } else if vm.isResting {
                        clock = clock.addingTimeInterval(TimeInterval(vm.restRemaining(asOf: clock)))
                        vm.completeRestIfElapsed(asOf: clock)
                    } else if vm.isRunningWorkWindow {
                        clock = clock.addingTimeInterval(TimeInterval(vm.workWindowRemaining(asOf: clock)))
                        vm.completeWorkWindowIfElapsed(asOf: clock)
                    } else {
                        return XCTFail("\(level) \(minutes)-min stalled waiting for a tap")
                    }
                }

                let played = Int(clock.timeIntervalSince(asOf))
                XCTAssertEqual(
                    played, SessionAssembly.plannedSeconds(of: workout),
                    "\(level) \(minutes)-min: played seconds must be the planned seconds"
                )
                assertFillsOrRunsHonestlyShort(
                    workout, minutes: minutes, level: level, library: library, "\(level) \(minutes)-min played \(played)s"
                )
            }
        }
    }

    // MARK: - The calibration itself

    /// The number is a *generous runtime* pace, not the catalog's typical-case estimate, and exactly one
    /// documented constant governs how generous. Asserted across the whole catalog so it cannot hold for
    /// a lucky movement and fail elsewhere: every rep-based movement is priced at its authored estimate
    /// scaled by the factor - the sweep spans the whole catalog, so mobility stretches are included and a
    /// rep-based one is paced like any other - and every hold is left alone, because a hold's per-second
    /// cost is definitional rather than estimated (prescribed seconds are elapsed seconds): it costs its
    /// legs and the "Switch sides" beat between them, exactly what the player runs.
    func testGenerousPaceScalesEveryRepBasedMovementAndLeavesHoldsAlone() async throws {
        let library = try await library()
        let factor = SessionAssembly.workPaceGenerosityFactor
        XCTAssertGreaterThan(factor, 1.0, "the pace must be generous relative to the authored estimate")
        XCTAssertLessThanOrEqual(factor, 1.5, "and not so generous that a session stops being the minutes asked for")

        var repMovements = 0
        var holdMovements = 0
        for movement in library {
            guard let baseline = movement.isHold ? movement.defaultDurationSeconds : movement.defaultReps,
                  baseline > 0 else { continue }
            let atDefault = SessionAssembly.workSecondsPerSet(
                for: movement,
                reps: movement.isHold ? nil : baseline,
                durationSeconds: movement.isHold ? baseline : nil
            )
            if movement.isHold {
                XCTAssertEqual(
                    atDefault,
                    movement.sidesPerSet * baseline + (movement.sidesPerSet - 1) * SessionAssembly.switchSidesSeconds,
                    "\(movement.id): a hold's seconds are definitional, so the pacing factor must not touch them"
                )
                holdMovements += 1
            } else {
                XCTAssertEqual(
                    atDefault,
                    Int((Double(movement.estimatedTimePerSetSeconds) * factor).rounded()),
                    "\(movement.id): a rep-based set is the authored estimate at the generous pace"
                )
                repMovements += 1
            }
        }
        XCTAssertGreaterThan(repMovements, 0)
        XCTAssertGreaterThan(holdMovements, 0)
    }

    /// The value stays a pure function of the exercise and the prescribed target - no wall clock reaches
    /// it, so two calls seconds apart, and a call made from a session assembled at a different `asOf`,
    /// all agree. This is the `asOf`-purity half of the acceptance criteria, kept as a live assertion
    /// rather than a promise in a comment.
    func testWorkSecondsPerSetIsAPureFunctionOfTheExerciseAndTarget() async throws {
        let library = try await library()
        let movement = try XCTUnwrap(library.first { !$0.isHold && $0.defaultReps != nil })
        let reps = try XCTUnwrap(movement.defaultReps)

        let first = SessionAssembly.workSecondsPerSet(for: movement, reps: reps, durationSeconds: nil)
        try await Task.sleep(nanoseconds: 10_000_000)
        let second = SessionAssembly.workSecondsPerSet(for: movement, reps: reps, durationSeconds: nil)
        XCTAssertEqual(first, second, "the same exercise at the same target prices identically whenever it is asked")

        // The same slot inside two sessions assembled a month apart prices the same too.
        let early = assemble(minutes: 20, library: library)
        let late = SessionAssembly.assemble(
            requestedMinutes: 20,
            user: user(),
            library: library,
            recentLogs: [],
            asOf: calendar.date(byAdding: .day, value: 30, to: asOf)!,
            calendar: calendar
        )
        for workout in [early, late] {
            for block in workout.blocks {
                for slot in block.exercises {
                    // The pace is a pure function of the exercise and target, and the window is exactly
                    // that pace: the engine never stores a stretch on a slot.
                    XCTAssertNil(slot.stretchSeconds, "\(slot.exercise.id) carries a stretched window")
                    XCTAssertEqual(
                        SessionAssembly.paceSecondsPerSet(of: slot),
                        SessionAssembly.workSecondsPerSet(
                            for: slot.exercise, reps: slot.reps, durationSeconds: slot.durationSeconds
                        ),
                        "\(slot.exercise.id) must price off the exercise and target alone"
                    )
                    XCTAssertEqual(SessionAssembly.workSecondsPerSet(of: slot), SessionAssembly.paceSecondsPerSet(of: slot))
                }
            }
        }
    }

    // MARK: - The trade-off, bounded

    /// After the pacing factor inflates every rep-based set, every length still lands within the
    /// tolerance of the request (or runs honestly short with every lever spent) for every fitness level
    /// and Training Day, and every circuit station keeps its four sets - the pace moves served reps and
    /// rest, never a station's set count.
    func testGenerousPaceStillLandsEveryLengthAndKeepsEveryStationsFourSets() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                for day in TrainingDay.rotation {
                    let workout = SessionAssembly.assemble(
                        requestedMinutes: minutes,
                        user: user(level: level),
                        library: library,
                        recentLogs: [],
                        trainingDay: day,
                        asOf: asOf,
                        calendar: calendar
                    )
                    let label = "\(level) \(day) \(minutes)-min"
                    assertFillsOrRunsHonestlyShort(workout, minutes: minutes, level: level, library: library, label)
                    let circuit = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }.flatMap(\.exercises)
                    XCTAssertFalse(circuit.isEmpty, "\(label) must still train something")
                    XCTAssertTrue(circuit.allSatisfy { $0.sets == RepGrammar.setsPerStation }, "\(label): \(circuit.map(\.sets))")
                }
            }
        }
    }
}
