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
///   a per-side hold's planned seconds cover both sides, and the player's hold timer runs the prescribed
///   seconds *per side* (two legs), so the two agree on the same set;
/// - the number sits generously above the catalog's typical-case authored estimate, governed by the one
///   documented constant (`SessionAssembly.workPaceGenerosityFactor`);
/// - it stays a pure function of the exercise and the prescribed target - no wall clock, no `asOf`;
/// - and the accepted trade-off is bounded: the fit still lands every length within ±60s, and no
///   training block is squeezed below a single round.
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
    /// A per-side hold's *planned* seconds cover both sides (`sidesPerSet`), and what the player runs is
    /// the prescribed seconds **per side**, once per leg - so a whole set of the same slot costs the plan
    /// and the user the same holding time, with the authored setup as the only remainder.
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

        // Planning: both sides are charged.
        let planned = SessionAssembly.workSecondsPerSet(of: prescription)
        XCTAssertEqual(movement.sidesPerSet, 2)
        XCTAssertGreaterThanOrEqual(
            planned, movement.sidesPerSet * seconds,
            "a per-side hold's planned set must cover the hold on both sides"
        )
        XCTAssertEqual(
            planned - movement.sidesPerSet * seconds,
            movement.estimatedTimePerSetSeconds - movement.sidesPerSet * (movement.defaultDurationSeconds ?? 0),
            "the only thing planning charges beyond the two legs is the movement's own authored setup"
        )

        // Runtime: the timer runs the prescribed seconds per side, one leg each, and both legs together
        // are the holding half of that same planned number.
        let vm = ActiveSessionViewModel(workout: workout, now: { self.asOf })
        vm.start()
        XCTAssertEqual(vm.holdSecondsPerSide, seconds, "each leg is the prescribed per-side hold, not the pair")
        vm.startHold()
        vm.completeHoldIfElapsed(asOf: asOf.addingTimeInterval(TimeInterval(seconds)))
        XCTAssertEqual(vm.holdSecondsPerSide, seconds, "side 2 runs the same prescribed seconds")
    }

    // MARK: - The calibration itself

    /// The number is a *generous runtime* pace, not the catalog's typical-case estimate, and exactly one
    /// documented constant governs how generous. Asserted across the whole catalog so it cannot hold for
    /// a lucky movement and fail elsewhere: every rep-based movement is priced at its authored estimate
    /// scaled by the factor - the sweep spans the whole catalog, so mobility stretches are included and a
    /// rep-based one is paced like any other - and every hold is left alone, because a hold's per-second
    /// cost is definitional rather than estimated (prescribed seconds are elapsed seconds).
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
                    atDefault, movement.estimatedTimePerSetSeconds,
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
                    XCTAssertEqual(
                        SessionAssembly.workSecondsPerSet(of: slot),
                        SessionAssembly.workSecondsPerSet(
                            for: slot.exercise, reps: slot.reps, durationSeconds: slot.durationSeconds
                        ),
                        "\(slot.exercise.id) must price off the exercise and target alone"
                    )
                }
            }
        }
    }

    // MARK: - The accepted trade-off, bounded

    /// The trade-off US-CC08 accepts is *fewer rounds*, not a session that misses the minutes asked for
    /// or a block squeezed out of existence. So after the pacing factor inflates every rep-based set:
    /// every length still lands within ±60s of the request for every fitness level, and every training
    /// block still runs at least one full round with at least one station.
    func testGenerousPaceStillLandsEveryLengthAndNeverStarvesABlockOfItsLastRound() async throws {
        let library = try await library()
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library)
                let drift = abs(SessionAssembly.plannedSeconds(of: workout) - minutes * 60)
                XCTAssertLessThanOrEqual(
                    drift, SessionAssembly.toleranceSeconds,
                    "\(level) \(minutes)-min drifted \(drift)s under the generous pace"
                )
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                XCTAssertFalse(training.isEmpty, "\(level) \(minutes)-min must still train something")
                for block in training {
                    XCTAssertFalse(block.exercises.isEmpty, "\(level) \(minutes)-min: \(block.title) lost every station")
                    XCTAssertGreaterThanOrEqual(
                        block.exercises[0].sets, SessionAssembly.minTrainingSets,
                        "\(level) \(minutes)-min: \(block.title) was squeezed below one round"
                    )
                }
            }
        }
    }
}
