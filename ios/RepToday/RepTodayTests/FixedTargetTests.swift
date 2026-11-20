import XCTest
@testable import RepToday

/// US-FT01 to US-FT07 (ADR-0022): Forearm Plank and Dead Bug are served a **Fixed Target** per fitness
/// level - 0:30 / 1:00 / 3:00 per hold, 10 / 15 / 20 per side - that never climbs, steps back, steps down
/// or pads, and clears at four clean sets at the target; held warm-up, cooldown and Recovery stretches run
/// 0:30 at every level.
final class FixedTargetTests: XCTestCase {

    private let calendar = TrainingDayFixtures.calendar
    private let asOf = TrainingDayFixtures.asOf

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(library.first { $0.id == id }, "\(id) is not served")
    }

    // MARK: - US-FT01: the catalog and the grammar

    func testTheCatalogDeclaresTheSixFixedTargets() throws {
        let plank = try exercise("core_forearm_plank")
        let deadBug = try exercise("core_dead_bug")
        XCTAssertEqual(FitnessLevel.allCases.map { RepGrammar.fixedTarget(for: plank, level: $0) }, [30, 60, 180])
        XCTAssertEqual(FitnessLevel.allCases.map { RepGrammar.fixedTarget(for: deadBug, level: $0) }, [10, 15, 20])
        XCTAssertEqual(plank.fixedTarget?.unit, .seconds)
        XCTAssertEqual(deadBug.fixedTarget?.unit, .repsPerSide)
    }

    func testOnlyForearmPlankAndDeadBugCarryAFixedTarget() throws {
        XCTAssertEqual(Set(try rawCatalog().filter { $0.fixedTarget != nil }.map(\.id)), ["core_forearm_plank", "core_dead_bug"])
    }

    /// Every question asked of a Fixed Target movement - its range, top, what it serves at, its Practice
    /// value - answers with the target; a movement without one answers exactly as before.
    func testAFixedTargetIsTheWholeRangeAndEveryOtherMovementIsUnchanged() throws {
        let plank = try exercise("core_forearm_plank")
        let deadBug = try exercise("core_dead_bug")
        let sidePlank = try exercise("core_side_plank")
        let birdDog = try exercise("core_bird_dog")
        for level in FitnessLevel.allCases {
            let plankTarget = try XCTUnwrap(RepGrammar.fixedTarget(for: plank, level: level))
            XCTAssertEqual(RepGrammar.earnedRange(for: plank, level: level), plankTarget...plankTarget)
            XCTAssertEqual(RepGrammar.served(earned: 20, for: plank, level: level), plankTarget)
            XCTAssertEqual(RepGrammar.served(earned: 400, for: plank, level: level), plankTarget)
            XCTAssertEqual(RepGrammar.practiceValue(for: plank, level: level), plankTarget)
            let deadBugTarget = try XCTUnwrap(RepGrammar.fixedTarget(for: deadBug, level: level))
            XCTAssertEqual(RepGrammar.practiceValue(for: deadBug, level: level), deadBugTarget)

            XCTAssertNil(RepGrammar.fixedTarget(for: sidePlank, level: level))
            XCTAssertEqual(RepGrammar.earnedRange(for: sidePlank, level: level), RepGrammar.earnedRange(for: .hold, level: level))
            XCTAssertEqual(RepGrammar.practiceValue(for: sidePlank, level: level), RepGrammar.practiceValue(for: .hold))
            XCTAssertEqual(RepGrammar.earnedRange(for: birdDog, level: level), 5...15)
            XCTAssertEqual(RepGrammar.practiceValue(for: birdDog, level: level), 5)
        }
    }

    func testCatalogValidationRejectsAMalformedFixedTarget() throws {
        let cases: [(String, (inout FixedTarget) -> Void, String)] = [
            ("off the grid", { $0.intermediate = 62 }, "intermediate 62 is off the grid"),
            ("under the floor", { $0.beginner = 5 }, "beginner 5 is off the grid of 5s or under the short-session floor"),
            ("missing a level", { $0.advanced = nil }, "missing the advanced level"),
            ("the wrong unit", { $0.unit = .reps }, "unit 'reps' does not match how the movement counts ('seconds')"),
        ]
        for (label, mutate, reason) in cases {
            var catalog = try rawCatalog()
            let index = try XCTUnwrap(catalog.firstIndex { $0.id == "core_forearm_plank" })
            var target = try XCTUnwrap(catalog[index].fixedTarget)
            mutate(&target)
            catalog[index].fixedTarget = target
            XCTAssertThrowsError(try MockExerciseService(library: catalog), label) { error in
                guard case let .fixedTargetInvalid(id, message) = error as? ExerciseLibraryError else {
                    return XCTFail("\(label): \(error)")
                }
                XCTAssertEqual(id, "core_forearm_plank", label)
                XCTAssertTrue(message.contains(reason), "\(label): \(message)")
            }
        }

        var onAStretch = try rawCatalog()
        let stretch = try XCTUnwrap(onAStretch.firstIndex { $0.id == "mobility_childs_pose" })
        onAStretch[stretch].fixedTarget = FixedTarget(unit: .seconds, beginner: 30, intermediate: 30, advanced: 30)
        XCTAssertThrowsError(try MockExerciseService(library: onAStretch)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .fixedTargetInvalid(exerciseId: "mobility_childs_pose", reason: "only a strength rung may carry one"))
        }
    }

    /// PRD validation (US-FT01): at 45 minutes the plank and Dead Bug stations prescribe exactly their
    /// level's numbers, and a Side Plank station still prescribes its Earned Reps.
    func testFortyFiveMinuteSessionsServeTheTargetsAndSidePlankItsEarnedReps() throws {
        for level in FitnessLevel.allCases {
            let plan = forcedPlan(level: level, minutes: 45)
            XCTAssertEqual(station("core_forearm_plank", in: plan)?.value, [30, 60, 180][level.rank], "\(level) plank")
            XCTAssertEqual(station("core_dead_bug", in: plan)?.value, [10, 15, 20][level.rank], "\(level) Dead Bug")
            XCTAssertEqual(station("core_forearm_plank", in: plan)?.earned, [30, 60, 180][level.rank])
            XCTAssertEqual(station("core_dead_bug", in: plan)?.earned, [10, 15, 20][level.rank])
        }

        // An intermediate who cleared Forearm Plank works Side Plank at its own Earned Reps.
        let sidePlank = try exercise("core_side_plank")
        let cleared = [plankLog(seconds: 60, earned: 60, daysAgo: 2)]
        let plan = forcedPlan(level: .intermediate, minutes: 45, logs: cleared + [birdDogCleared()])
        let item = try XCTUnwrap(station("core_side_plank", in: plan), "Side Plank is the plank ladder's current rung")
        let earned = AdaptiveOverload.earned(for: sidePlank, level: .intermediate, recentLogs: cleared)
        XCTAssertEqual(item.earned, RepGrammar.served(earned: earned, for: sidePlank, level: .intermediate))
        XCTAssertEqual(item.earned, 20, "a Side Plank with no history opens at the bottom of its range")
    }

    // MARK: - US-FT02: no climb, no step back, no step down, no Padding

    /// PRD validation (US-FT02): "too hard" twice and "too easy" once on Dead Bug leave an intermediate on
    /// Dead Bug at 15 per side.
    func testRatingsNeverMoveTheTargetOrTheRung() throws {
        let deadBug = try exercise("core_dead_bug")
        let logs = [
            birdDogCleared(daysAgo: 10),
            deadBugLog(reps: 15, daysAgo: 6, difficulty: .tooHard),
            deadBugLog(reps: 10, earned: 15, daysAgo: 4, difficulty: .tooEasy), // a short session's cut: it cannot clear
            deadBugLog(reps: 15, daysAgo: 2, difficulty: .tooHard),
        ]
        XCTAssertEqual(AdaptiveOverload.earned(for: deadBug, level: .intermediate, recentLogs: logs), 15)
        XCTAssertEqual(AdaptiveOverload.target(for: deadBug, level: .intermediate, recentLogs: logs).reps, 15)
        XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: deadBug, level: .intermediate, recentLogs: logs))
        XCTAssertEqual(stabilityRung(level: .intermediate, logs: logs), "core_dead_bug", "never stepped down to Bird Dog")

        let plan = forcedPlan(level: .intermediate, minutes: 30, logs: logs)
        XCTAssertEqual(station("core_dead_bug", in: plan)?.value, 15)
    }

    func testASkipOrACouldNotFinishMarkNeverStepsTheTargetBackOrDown() throws {
        let deadBug = try exercise("core_dead_bug")
        let skipped = [birdDogCleared(daysAgo: 10), deadBugLog(reps: 15, daysAgo: 2, skipped: true)]
        let marked = [birdDogCleared(daysAgo: 10), deadBugLog(reps: 15, daysAgo: 2, difficulty: .tooHard, couldNotFinish: true)]
        for logs in [skipped, marked] {
            for level in [FitnessLevel.intermediate, .advanced] {
                XCTAssertEqual(AdaptiveOverload.earned(for: deadBug, level: level, recentLogs: logs), RepGrammar.fixedTarget(for: deadBug, level: level))
                XCTAssertNil(AdaptiveOverload.floorStepBackDate(for: deadBug, level: level, recentLogs: logs))
                XCTAssertEqual(stabilityRung(level: level, logs: logs), "core_dead_bug")
            }
        }
        // That session does not count toward advancement either.
        XCTAssertFalse(RepGrammar.hasCleared(deadBug, in: marked, level: .intermediate))
    }

    /// A long session fills its time through other stations and rest, never by padding a Fixed Target.
    func testALongSessionNeverPadsAFixedTarget() {
        for level in FitnessLevel.allCases {
            for minutes in [45, 60] {
                let plan = forcedPlan(level: level, minutes: minutes)
                for id in ["core_forearm_plank", "core_dead_bug"] {
                    let item = station(id, in: plan)
                    XCTAssertEqual(item?.value, item?.earned, "\(level) \(minutes) min pads \(id)")
                    XCTAssertEqual(item?.ceiling, item?.earned, "\(level) \(minutes) min leaves \(id) room to pad")
                }
                XCTAssertLessThanOrEqual(abs(plan.totalSeconds - minutes * 60), SessionAssembly.toleranceSeconds)
            }
        }
    }

    // MARK: - US-FT03: short sessions may cut, and a cut never advances

    /// PRD validation (US-FT03): an advanced 15-minute session serves the plank below 3:00 and lands on
    /// length; four such sessions logged clean never advance to Side Plank.
    func testAShortSessionCutsThePlankAndACutSessionNeverAdvances() throws {
        let plank = try exercise("core_forearm_plank")
        let plan = forcedPlan(level: .advanced, minutes: 15)
        let item = try XCTUnwrap(station("core_forearm_plank", in: plan))
        XCTAssertLessThan(item.value, 180)
        XCTAssertGreaterThanOrEqual(item.value, RepGrammar.shortSessionFloor(for: .hold))
        XCTAssertEqual(item.earned, 180, "the prescription still records the target")
        XCTAssertLessThanOrEqual(abs(plan.totalSeconds - 15 * 60), SessionAssembly.toleranceSeconds)

        let logs = (1...4).map { plankLog(seconds: item.value, earned: 180, daysAgo: $0 * 2) }
        XCTAssertFalse(RepGrammar.hasCleared(plank, in: logs, level: .advanced))
        XCTAssertEqual(plankRung(level: .advanced, logs: logs), "core_forearm_plank")
    }

    // MARK: - US-FT04: advancement at the target

    /// PRD validation (US-FT04): four clean 60-second holds in a session rated "just right" move an
    /// intermediate up to Side Plank.
    func testFourCleanHoldsAtTheTargetMoveAnIntermediateUpToSidePlank() throws {
        let plank = try exercise("core_forearm_plank")
        let logs = [plankLog(seconds: 60, earned: 60, daysAgo: 2)]
        XCTAssertTrue(RepGrammar.hasCleared(plank, in: logs, level: .intermediate))
        XCTAssertEqual(plankRung(level: .intermediate, logs: logs), "core_side_plank")
    }

    /// Logs are read as written against today's target: an advanced user's old 90-second logs (the top of
    /// the old advanced range) no longer clear, while an intermediate's old 60-second ones still do.
    func testOldLogsCountOnlyWhenTheyReachedTheNewTarget() throws {
        let plank = try exercise("core_forearm_plank")
        let oldTop = (1...3).map { plankLog(seconds: 90, earned: 90, daysAgo: $0 * 2) }
        XCTAssertFalse(RepGrammar.hasCleared(plank, in: oldTop, level: .advanced))
        XCTAssertEqual(RepGrammar.clearingSessionCount(plank, in: oldTop, level: .advanced), 0)
        XCTAssertEqual(plankRung(level: .advanced, logs: oldTop), "core_forearm_plank")

        let intermediate = (1...3).map { plankLog(seconds: 60, earned: 60, daysAgo: $0 * 2) }
        XCTAssertEqual(RepGrammar.clearingSessionCount(plank, in: intermediate, level: .intermediate), 3)
    }

    /// PRD decision 11 (US-FT04): an advanced user's 4 x 90s plank clear from before Fixed Targets keeps the
    /// Core line and their Strength-Phase eligibility, though it still does not move them up to Side Plank.
    func testAnAdvancedCoreClearFromBeforeFixedTargetsStaysCleared() throws {
        let plank = try exercise("core_forearm_plank")
        let clearedAtNinety = [plankLog(seconds: 90, earned: 90, daysAgo: 4)]
        XCTAssertLessThan(clearedAtNinety[0].completedAt, RepGrammar.fixedTargetsTookEffect)

        XCTAssertTrue(RepGrammar.hasClearedFoundation(plank, in: clearedAtNinety, level: .advanced))
        XCTAssertEqual(isCoreCleared(clearedAtNinety, level: .advanced, asOf: asOf), true)
        XCTAssertEqual(
            PhaseEvaluator.evaluate(
                logs: sustainedHistory(endingDaysAgo: 0) + otherFoundationsCleared() + clearedAtNinety,
                library: library, level: .advanced, asOf: asOf, calendar: calendar
            ),
            .strength
        )
        XCTAssertEqual(plankRung(level: .advanced, logs: clearedAtNinety), "core_forearm_plank")

        let tooShort = [plankLog(seconds: 85, earned: 85, daysAgo: 4)]
        XCTAssertFalse(RepGrammar.hasClearedFoundation(plank, in: tooShort, level: .advanced))
    }

    /// A log from the cutoff on is judged only against the target: a short session that cut the advanced
    /// 3:00 plank to 1:40 (above the old 90-second top, earned at the target) never clears the Core line.
    func testACutPlankSessionAfterTheCutoffNeverCountsUnderTheOldBar() throws {
        let plank = try exercise("core_forearm_plank")
        let after = calendar.date(byAdding: .day, value: 2, to: RepGrammar.fixedTargetsTookEffect)!
        let cut = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("core_forearm_plank", pattern: .core, role: .core, value: 100, earned: 180, isHold: true)],
            completedAt: after
        )
        XCTAssertFalse(RepGrammar.hasClearedFoundation(plank, in: [cut], level: .advanced))
        XCTAssertEqual(isCoreCleared([cut], level: .advanced, asOf: after.addingTimeInterval(3600)), false)
    }

    /// A beginner who swaps Standard Push-Up for Wide Push-Up, the next rung of the same chain, has not
    /// cleared the Push line.
    func testASameChainSwapNeverClearsAFoundationLine() throws {
        let standard = TrainingDayFixtures.station("push_standard", pattern: .push, value: 20, earned: 20)
        let wide = TrainingDayFixtures.station("push_wide", pattern: .push, value: 20, earned: 20)
        let logs = [
            TrainingDayFixtures.log([standard], completedAt: TrainingDayFixtures.date(daysAgo: 4)),
            TrainingDayFixtures.log([wide], completedAt: TrainingDayFixtures.date(daysAgo: 2)),
        ]
        let push = PhaseEvaluator.progress(logs: logs, library: library, level: .beginner, asOf: asOf, calendar: calendar)
            .foundations.first { $0.foundation == .push }
        XCTAssertEqual(push?.isCleared, false)
    }

    /// Every movement without a Fixed Target clears its Foundation line exactly by `hasCleared`, before the
    /// cutoff and after it.
    func testEveryOtherMovementClearsItsFoundationExactlyAsBefore() throws {
        let after = calendar.date(byAdding: .day, value: 2, to: RepGrammar.fixedTargetsTookEffect)!
        for exercise in library where exercise.fixedTarget == nil {
            for level in FitnessLevel.allCases {
                let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
                for date in [TrainingDayFixtures.date(daysAgo: 4), after] {
                    for value in [top - RepGrammar.step, top] {
                        let logs = [TrainingDayFixtures.log(
                            [TrainingDayFixtures.station(
                                exercise.id, pattern: exercise.movementPattern, value: value, earned: value, isHold: exercise.isHold
                            )],
                            completedAt: date
                        )]
                        XCTAssertEqual(
                            RepGrammar.hasClearedFoundation(exercise, in: logs, level: level),
                            RepGrammar.hasCleared(exercise, in: logs, level: level),
                            "\(exercise.id) at \(level) and \(value)"
                        )
                    }
                }
            }
        }
    }

    func testDeadBugClearsOnlyAtFourCleanSetsPerSideAtTheTarget() throws {
        let deadBug = try exercise("core_dead_bug")
        XCTAssertTrue(RepGrammar.hasCleared(deadBug, in: [deadBugLog(reps: 20, daysAgo: 2)], level: .advanced))
        XCTAssertFalse(RepGrammar.hasCleared(deadBug, in: [deadBugLog(reps: 15, daysAgo: 2)], level: .advanced))
        XCTAssertFalse(RepGrammar.hasCleared(deadBug, in: [deadBugLog(reps: 20, daysAgo: 2, sets: 3)], level: .advanced))
        XCTAssertFalse(
            RepGrammar.hasCleared(deadBug, in: [deadBugLog(reps: 20, daysAgo: 2, difficulty: .tooHard)], level: .advanced),
            "a session rated too hard never clears"
        )
        XCTAssertTrue(RepGrammar.hasCleared(deadBug, in: [deadBugLog(reps: 10, daysAgo: 2)], level: .beginner))
    }

    // MARK: - US-FT05: the Return ease-in

    /// PRD validation (US-FT05): an advanced user back after a break gets a reduced plank in the Return
    /// session, which never counts toward advancement, and 3:00 again once the Return window ends.
    func testAReturnEasesThePlankAndTheTargetResumesAfterward() throws {
        let plank = try exercise("core_forearm_plank")
        let beforeTheBreak = [plankLog(seconds: 180, earned: 180, daysAgo: 20, difficulty: .tooHard)]
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: beforeTheBreak, asOf: asOf, calendar: calendar))
        let returnPlan = forcedPlan(level: .advanced, minutes: 45, logs: beforeTheBreak + [birdDogCleared(daysAgo: 21)])
        let eased = try XCTUnwrap(station("core_forearm_plank", in: returnPlan))
        XCTAssertLessThan(eased.value, 180)
        XCTAssertGreaterThanOrEqual(eased.value, RepGrammar.shortSessionFloor(for: .hold))
        XCTAssertEqual(eased.ceiling, eased.value, "a Return session is never padded")

        var returnLog = plankLog(seconds: eased.value, earned: 180, daysAgo: 0)
        returnLog.wasReturn = true
        XCTAssertFalse(RepGrammar.hasCleared(plank, in: [returnLog], level: .advanced))

        XCTAssertEqual(AdaptiveOverload.target(for: plank, level: .advanced, recentLogs: [], reentryScale: 1).durationSeconds, 180)
        XCTAssertEqual(
            AdaptiveOverload.target(for: plank, level: .advanced, recentLogs: [], reentryScale: ReturnOverride.reentryFloorScale).durationSeconds,
            125, "the Return floor scale holds 3:00 at 70%, onto the grid"
        )
    }

    // MARK: - US-FT06: a Practice station previews at the level target

    /// A Practice station of a Fixed Target movement runs at the user's level target (a beginner previews
    /// Dead Bug at 10 per side), cut on a short session like any station and counting toward nothing;
    /// every other Practice station keeps its Practice value.
    ///
    /// The shipped catalog never puts Dead Bug in a Practice slot - Core Sprinkles take none - so the
    /// station is reached through a Push Day whose next rung is given a Fixed Target.
    func testAFixedTargetPracticeStationRunsAtTheLevelTarget() throws {
        let user = TrainingDayFixtures.user(level: .beginner, asOf: asOf)
        func plan(_ catalog: [Exercise], minutes: Int) -> SessionPlan {
            var plan = SessionAssembly.planSession(
                requestedMinutes: minutes, user: user, library: catalog, recentLogs: [],
                trainingDay: .push, asOf: asOf, calendar: calendar
            )
            SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
            return plan
        }
        let practices = plan(library, minutes: 45).stations.filter { $0.role == .practice }
        XCTAssertEqual(practices.count, 2)
        let previewed = try XCTUnwrap(practices.first?.exercise)
        XCTAssertNil(previewed.fixedTarget)

        var catalog = library
        let index = try XCTUnwrap(catalog.firstIndex { $0.id == previewed.id })
        catalog[index].fixedTarget = switch RepGrammar.kind(of: previewed) {
        case .hold: FixedTarget(unit: .seconds, beginner: 30, intermediate: 45, advanced: 60)
        case .repsPerSide: FixedTarget(unit: .repsPerSide, beginner: 10, intermediate: 15, advanced: 20)
        case .reps: FixedTarget(unit: .reps, beginner: 20, intermediate: 25, advanced: 30)
        }
        let target = try XCTUnwrap(RepGrammar.fixedTarget(for: catalog[index], level: .beginner))

        let long = plan(catalog, minutes: 45)
        let practice = try XCTUnwrap(long.stations.first { $0.exercise.id == previewed.id })
        XCTAssertEqual(practice.role, .practice)
        XCTAssertEqual(practice.value, target)
        XCTAssertNil(practice.earned, "a Practice station records no Earned Reps")
        XCTAssertEqual(practice.materialize(restSeconds: 15).role?.advancesProgression, false)
        let other = try XCTUnwrap(long.stations.first { $0.role == .practice && $0.exercise.id != previewed.id })
        XCTAssertEqual(other.value, RepGrammar.practiceValue(for: RepGrammar.kind(of: other.exercise)))
        XCTAssertEqual(practice.floor, RepGrammar.shortSessionFloor(for: RepGrammar.kind(of: previewed)), "a short session may cut it")
        XCTAssertEqual(other.floor, other.value, "every other Practice value stays where it is")

        let deadBug = try exercise("core_dead_bug")
        XCTAssertEqual(RepGrammar.practiceValue(for: deadBug, level: .beginner), 10)
    }

    // MARK: - US-FT08: the player speaks the target

    /// The player and the Today lineup show and speak the target itself: "4 × 3:00" read as "4 sets of 3
    /// minute holds", never "180 second holds"; Dead Bug's "4 × 15 per side".
    func testThePlayerShowsAndSpeaksTheTarget() throws {
        func prescription(_ id: String, _ value: Int) throws -> PrescribedExercise {
            let movement = try exercise(id)
            return PrescribedExercise(
                id: UUID(), exercise: movement, sets: 4,
                reps: movement.isHold ? nil : value, durationSeconds: movement.isHold ? value : nil, restSeconds: 15
            )
        }
        let plank = try prescription("core_forearm_plank", 180)
        XCTAssertEqual(ActiveSessionView.targetText(plank), "4 × 3:00")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(plank), "4 sets of 3 minute holds")
        let intermediatePlank = try prescription("core_forearm_plank", 60)
        XCTAssertEqual(ActiveSessionView.targetText(intermediatePlank), "4 × 1:00")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(intermediatePlank), "4 sets of 1 minute holds")
        let deadBug = try prescription("core_dead_bug", 15)
        XCTAssertEqual(ActiveSessionView.targetText(deadBug), "4 × 15 per side")
        XCTAssertEqual(ActiveSessionView.targetAccessibilityText(deadBug), "4 sets of 15 reps per side")
        XCTAssertEqual(ActiveSessionView.spokenHoldLength(90), "90 second", "a part-minute hold stays in seconds")
    }

    /// After "too hard", the "couldn't finish" list flags a Fixed Target move, whose card says its target
    /// stays the same; the header keeps its ease-off promise unless every listed move holds a target.
    func testTheCouldNotFinishListFlagsAFixedTargetMove() throws {
        let block = WorkoutBlock(id: UUID(), title: "Push Day", category: .strength, exercises: [
            PrescribedExercise(id: UUID(), exercise: try exercise("push_standard"), sets: 1, reps: 15, durationSeconds: nil, restSeconds: 15),
            PrescribedExercise(id: UUID(), exercise: try exercise("core_forearm_plank"), sets: 1, reps: nil, durationSeconds: 60, restSeconds: 15),
        ])
        let workout = Workout(id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil, requestedMinutes: 15, wasReturn: false, blocks: [block])
        let vm = ActiveSessionViewModel(workout: workout, now: { self.asOf }, cuePlayer: QuietCuePlayer(), voiceOverActive: { false })
        vm.start()
        for _ in 0..<4 where !vm.isComplete { vm.completeSet() }
        XCTAssertTrue(vm.isComplete)
        XCTAssertEqual(vm.finishCheckMoves.map(\.id), ["push_standard", "core_forearm_plank"])
        XCTAssertEqual(vm.finishCheckMoves.map(\.holdsItsTarget), [false, true])

        let easeOff = "Tap them and only those ease off next time. Tap none and everything eases off a little."
        XCTAssertEqual(ActiveSessionView.finishCheckIntro(vm.finishCheckMoves), easeOff)
        XCTAssertEqual(
            ActiveSessionView.finishCheckIntro(vm.finishCheckMoves.filter(\.holdsItsTarget)),
            "Your targets stay the same either way. A tapped move's session just won't count toward moving up."
        )
        XCTAssertEqual(ActiveSessionView.finishCheckHoldNote, "Your target stays the same. This session just won't count toward moving up.")
    }

    // MARK: - US-FT07: 0:30 held bookends

    /// Every held warm-up and cooldown stretch is 0:30 at every level and length (per side when one-sided),
    /// and every rep-based bookend move keeps its catalog reps.
    func testEveryHeldBookendStretchIsThirtySeconds() {
        var sawPerSideHold = false
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    var plan = SessionAssembly.planSession(
                        requestedMinutes: minutes, user: TrainingDayFixtures.user(level: level, asOf: asOf),
                        library: library, recentLogs: [], trainingDay: day, asOf: asOf, calendar: calendar
                    )
                    SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
                    for item in plan.warmup + plan.cooldown {
                        if item.exercise.isHold {
                            XCTAssertEqual(item.value, 30, "\(level) \(day) \(minutes) min: \(item.exercise.id)")
                            sawPerSideHold = sawPerSideHold || item.exercise.isPerSide == true
                        } else {
                            XCTAssertEqual(item.value, max(10, RepGrammar.floored(item.exercise.defaultReps ?? 10)), item.exercise.id)
                        }
                        XCTAssertEqual(item.sets, 1)
                    }
                }
            }
        }
        XCTAssertTrue(sawPerSideHold, "the sweep reaches a one-sided hold")
    }

    /// The bookend rule covers every held stretch in the catalog, the 0:40 and 0:45 ones included.
    func testEveryHeldStretchInTheCatalogServesThirtySeconds() {
        let stretches = library.filter { $0.pillar == .mobility }
        XCTAssertTrue(stretches.contains { $0.isHold && ($0.defaultDurationSeconds ?? 0) > 30 })
        for stretch in stretches {
            XCTAssertEqual(
                SessionAssembly.bookendValue(for: stretch),
                stretch.isHold ? 30 : max(10, RepGrammar.floored(stretch.defaultReps ?? 10)),
                stretch.id
            )
        }
    }

    /// PRD validation (US-FT07): the Recovery flow serves the same 0:30 holds.
    func testTheRecoveryFlowHoldsAreThirtySeconds() {
        let workout = SessionAssembly.recoveryWorkout(
            user: TrainingDayFixtures.user(level: .advanced, asOf: asOf),
            library: library,
            recentLogs: [TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 1))],
            asOf: asOf
        )
        let stretches = workout.blocks.flatMap(\.exercises)
        XCTAssertTrue(stretches.contains { $0.exercise.isHold })
        for prescription in stretches {
            if prescription.exercise.isHold {
                XCTAssertEqual(prescription.durationSeconds, 30, prescription.exercise.id)
            } else {
                XCTAssertEqual(prescription.reps, SessionAssembly.bookendValue(for: prescription.exercise))
            }
        }
    }

    /// A session saved before the change resumes with the durations it was saved with: the player plays
    /// the prescription it holds and never re-derives a bookend's length.
    func testASavedSessionResumesWithTheBookendLengthsItWasSavedWith() async throws {
        let pigeon = try exercise("mobility_pigeon")
        XCTAssertEqual(pigeon.isPerSide, true)
        let workout = Workout(
            id: UUID(), createdAt: asOf, shape: .blend, focusPillar: nil, requestedMinutes: 15, wasReturn: false,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Warm-Up", category: .warmup, exercises: [
                    PrescribedExercise(id: UUID(), exercise: pigeon, sets: 1, reps: nil, durationSeconds: 45, restSeconds: 15),
                ]),
            ]
        )
        let store = InMemoryActiveSessionStore()
        let original = ActiveSessionViewModel(
            workout: workout, store: store, userId: "u1", now: { self.asOf }, cuePlayer: QuietCuePlayer(), voiceOverActive: { false }
        )
        original.start()
        await original.persistenceTask?.value
        let loaded = try await store.load(for: "u1")
        let saved = try XCTUnwrap(loaded)

        let resumed = ActiveSessionViewModel(state: saved, now: { self.asOf }, cuePlayer: QuietCuePlayer(), voiceOverActive: { false })
        XCTAssertEqual(resumed.currentStep?.prescription.durationSeconds, 45)
        resumed.start()
        resumed.autoStartHoldIfNeeded()
        XCTAssertEqual(resumed.holdTotalSeconds, 45, "the saved 0:45 per side plays as saved")
    }

    // MARK: - Fixtures

    /// The whole catalog file, withdrawn movements included, as load validation reads it.
    private func rawCatalog() throws -> [Exercise] {
        let url = try XCTUnwrap(Bundle(for: MockExerciseService.self).url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    /// A session with Forearm Plank and Dead Bug forced into the Core Sprinkles: the hollow ladder left out,
    /// Bird Dog cleared, Abs a Focus Area, and a beginner in the Strength Phase (the one way a beginner is
    /// served Dead Bug).
    private func forcedPlan(level: FitnessLevel, minutes: Int, logs: [WorkoutLog]? = nil) -> SessionPlan {
        let user = TrainingDayFixtures.user(
            level: level, phase: level == .beginner ? .strength : .discipline, focusAreas: [.abs], asOf: asOf
        )
        var plan = SessionAssembly.planSession(
            requestedMinutes: minutes, user: user,
            library: library.filter { $0.progressionChainId != "core_hollow" },
            recentLogs: logs ?? [birdDogCleared()],
            trainingDay: .push, asOf: asOf, calendar: calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        return plan
    }

    private func station(_ id: String, in plan: SessionPlan) -> PlannedItem? {
        plan.stations.first { $0.exercise.id == id }
    }

    private func birdDogCleared(daysAgo: Int = 3) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station("core_bird_dog", pattern: .core, role: .core, value: 15, earned: 15)],
            completedAt: TrainingDayFixtures.date(daysAgo: daysAgo)
        )
    }

    private func plankLog(seconds: Int, earned: Int, daysAgo: Int, difficulty: PerceivedDifficulty = .justRight) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station("core_forearm_plank", pattern: .core, role: .core, value: seconds, earned: earned, isHold: true)],
            completedAt: TrainingDayFixtures.date(daysAgo: daysAgo),
            difficulty: difficulty
        )
    }

    /// Three show-ups a week for the eight weeks the Strength Phase asks for.
    private func sustainedHistory(endingDaysAgo: Int) -> [WorkoutLog] {
        (0..<8).flatMap { week in
            [0, 2, 4].map { TrainingDayFixtures.log([], completedAt: TrainingDayFixtures.date(daysAgo: endingDaysAgo + week * 7 + $0)) }
        }
    }

    /// A clearing session at the advanced top for the entry rung of every foundation line but Core.
    private func otherFoundationsCleared() -> [WorkoutLog] {
        StrengthFoundation.displayOrder.flatMap(\.lines).filter { $0.pattern != .core }.compactMap { line in
            line.entryExercises(in: library).first.map { entry in
                let top = RepGrammar.earnedRange(for: entry, level: .advanced).upperBound
                return TrainingDayFixtures.log(
                    [TrainingDayFixtures.station(entry.id, pattern: entry.movementPattern, value: top, earned: top, isHold: entry.isHold)],
                    completedAt: TrainingDayFixtures.date(daysAgo: 3)
                )
            }
        }
    }

    private func isCoreCleared(_ logs: [WorkoutLog], level: FitnessLevel, asOf: Date) -> Bool? {
        PhaseEvaluator.progress(logs: logs, library: library, level: level, asOf: asOf, calendar: calendar)
            .foundations.first { $0.foundation == .core }?.isCleared
    }

    private func deadBugLog(
        reps: Int,
        earned: Int? = nil,
        daysAgo: Int,
        sets: Int = 4,
        difficulty: PerceivedDifficulty = .justRight,
        skipped: Bool = false,
        couldNotFinish: Bool? = nil
    ) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station(
                "core_dead_bug", pattern: .core, role: .core, value: reps, earned: earned ?? reps, sets: sets,
                skipped: skipped, couldNotFinish: couldNotFinish
            )],
            completedAt: TrainingDayFixtures.date(daysAgo: daysAgo),
            difficulty: difficulty
        )
    }

    private func rung(of chainId: String, level: FitnessLevel, logs: [WorkoutLog]) -> String? {
        let chain = library.filter { $0.progressionChainId == chainId }
        return ProgressionChainSelection.selectInChain(
            chain, eligibleIds: Set(chain.map(\.id)), recentLogs: logs, level: level
        )?.exercise.id
    }

    private func plankRung(level: FitnessLevel, logs: [WorkoutLog]) -> String? {
        rung(of: "core_plank", level: level, logs: logs)
    }

    private func stabilityRung(level: FitnessLevel, logs: [WorkoutLog]) -> String? {
        rung(of: "core_stability", level: level, logs: logs)
    }
}

/// A cue player that makes no sound, so the resume test plays no tone.
private struct QuietCuePlayer: SessionCuePlayer {
    func play(_ cue: SessionCue, suppressAudio: Bool) {}
}
