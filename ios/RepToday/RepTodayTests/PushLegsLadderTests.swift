import XCTest
@testable import RepToday

/// ADR-0020: the horizontal push ladder starts at Standard Push-Up and runs through eleven rungs, Burpee
/// (no push-up) joins the squat ladder after Sumo Squat, and both Nordic curls leave, so the bridge ladder
/// ends at Long-Lever Single-Leg Bridge. Wall, Incline and Knee Push-Up and the Nordic curls are retired:
/// they stay in the file so history resolves, are never served, and a user who was on one stands on the
/// rung that replaces it (`Exercise.replaces`).
///
/// Everything runs over the real bundled `Exercises.json`, so the ladders below are the captain's decision
/// as shipped data.
final class PushLegsLadderTests: XCTestCase {

    // MARK: - The decided ladders

    /// The horizontal push ladder, entry first, with each rung's audience.
    private let pushLadder: [(id: String, audience: MovementAudience)] = [
        ("push_standard", .beginner),
        ("push_wide", .beginner),
        ("push_one_leg", .beginner),
        ("push_diamond", .intermediate),
        ("push_side_to_side", .intermediate),
        ("push_spider", .intermediate),
        ("push_explosive", .intermediate),
        ("push_burpee", .intermediate),
        ("push_archer", .advanced),
        ("push_one_arm_assisted", .advanced),
        ("push_one_arm", .advanced),
    ]
    private let squatLadder = [
        "squat_wall_sit", "squat_bodyweight", "squat_sumo", "squat_burpee",
        "squat_cossack", "squat_shrimp", "squat_pistol_assisted", "squat_pistol",
    ]
    private let bridgeLadder = ["hinge_glute_bridge", "hinge_single_leg_bridge", "hinge_bridge_march", "hinge_long_lever_bridge"]

    /// The movements this change retired, and the rung each user on one now stands on.
    private let removedPush = ["push_wall", "push_incline", "push_knee"]
    private let removedNordic = ["hinge_nordic_assisted", "hinge_nordic"]
    private var removed: [String] { removedPush + removedNordic }

    /// The seven movements this change added, all without Trainer art for now.
    private let added = [
        "push_wide", "push_one_leg", "push_side_to_side", "push_spider", "push_explosive", "push_burpee", "squat_burpee",
    ]

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
    }

    private func offeredLibrary() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// The whole file, retired movements included - what the service reads before it filters.
    private func fullFileLibrary() throws -> [Exercise] {
        let bundle = Bundle(for: MockExerciseService.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    private func user(level: FitnessLevel, phase: Phase = .discipline) -> User {
        TrainingDayFixtures.user(level: level, phase: phase)
    }

    private func ladder(_ chainId: String, in library: [Exercise]) -> [Exercise] {
        library.filter { $0.progressionChainId == chainId }.sorted { $0.progressionOrder < $1.progressionOrder }
    }

    /// A session `daysAgo` with one station of `exerciseId` at `value`, written as a Training Day logs it.
    private func workLog(_ exerciseId: String, pattern: MovementPattern, value: Int = 15, daysAgo: Int) -> WorkoutLog {
        TrainingDayFixtures.log(
            [TrainingDayFixtures.station(exerciseId, pattern: pattern, value: value, earned: value)],
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
        )
    }

    /// A session that clears `exercise` for a user at `level`: four sets at the top of the range, at earned reps.
    private func clearingLog(_ exercise: Exercise, level: FitnessLevel, daysAgo: Int) -> WorkoutLog {
        let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
        return TrainingDayFixtures.log(
            [TrainingDayFixtures.station(exercise.id, pattern: exercise.movementPattern, value: top, earned: top, isHold: exercise.isHold)],
            completedAt: calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
        )
    }

    /// What Step 5 serves a user on one chain, through the real pool filter.
    private func selection(
        chain chainId: String, level: FitnessLevel, phase: Phase = .discipline, logs: [WorkoutLog], library: [Exercise]
    ) -> ChainSelection? {
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: level, phase: phase), recentLogs: logs)
        return ProgressionChainSelection.selectInChain(
            ladder(chainId, in: library), eligibleIds: Set(pool.map(\.id)), recentLogs: logs, level: level
        )
    }

    // MARK: - Ladders

    func testThePushLadderStartsAtStandardAndRunsThroughElevenRungs() async throws {
        let library = try await offeredLibrary()
        let push = ladder("push_horizontal", in: library)
        XCTAssertEqual(push.map(\.id), pushLadder.map(\.id))
        XCTAssertEqual(push.map(\.progressionOrder), Array(0..<pushLadder.count))
        for (rung, decided) in zip(push, pushLadder) {
            XCTAssertEqual(rung.audience, decided.audience, rung.id)
            XCTAssertEqual(rung.phase, ["push_one_arm_assisted", "push_one_arm"].contains(rung.id) ? .strength : .discipline, rung.id)
            XCTAssertEqual(rung.equipment, [], rung.id)
            XCTAssertFalse(rung.isHold, rung.id)
        }
        XCTAssertEqual(push.filter { $0.isPerSide == true }.map(\.id),
                       ["push_side_to_side", "push_spider", "push_archer", "push_one_arm_assisted", "push_one_arm"])
        XCTAssertEqual(push.map(\.difficulty), push.map(\.difficulty).sorted(), "difficulty never drops up the ladder")
    }

    func testEachLevelGetsItsPushTierAndTheStrengthPhaseUnlocksTheTop() async throws {
        let push = ladder("push_horizontal", in: try await offeredLibrary())
        func available(_ level: FitnessLevel, _ phase: Phase = .discipline) -> [String] {
            MovementAccess.available(in: push, level: level, phase: phase).map(\.id)
        }
        XCTAssertEqual(available(.beginner), ["push_standard", "push_wide", "push_one_leg"])
        XCTAssertEqual(available(.intermediate), [
            "push_standard", "push_wide", "push_one_leg", "push_diamond", "push_side_to_side",
            "push_spider", "push_explosive", "push_burpee",
        ])
        XCTAssertEqual(available(.advanced), Array(pushLadder.map(\.id).dropLast(2)), "Assisted One-Arm and One-Arm keep their lock")
        for level in FitnessLevel.allCases {
            XCTAssertEqual(available(level, .strength), pushLadder.map(\.id), "\(level): the Strength Phase opens the whole ladder")
        }
    }

    func testBurpeeJoinsTheSquatLadderAfterSumoSquatForIntermediates() async throws {
        let squat = ladder("squat", in: try await offeredLibrary())
        XCTAssertEqual(squat.map(\.id), squatLadder)
        let burpee = try XCTUnwrap(squat.first { $0.id == "squat_burpee" })
        XCTAssertEqual(burpee.displayName, "Burpee")
        XCTAssertEqual(burpee.audience, .intermediate)
        XCTAssertEqual(burpee.phase, .discipline)
        XCTAssertEqual(MovementAccess.available(in: squat, level: .beginner, phase: .discipline).map(\.id),
                       ["squat_wall_sit", "squat_bodyweight"])
        XCTAssertEqual(MovementAccess.available(in: squat, level: .intermediate, phase: .discipline).map(\.id),
                       ["squat_wall_sit", "squat_bodyweight", "squat_sumo", "squat_burpee"])
    }

    func testTheBridgeLadderEndsAtLongLeverWithNoStrengthPhaseRung() async throws {
        let library = try await offeredLibrary()
        let bridge = ladder("hinge_bridge", in: library)
        XCTAssertEqual(bridge.map(\.id), bridgeLadder)
        XCTAssertNil(bridge.last?.progressionId, "Long-Lever Single-Leg Bridge is the top rung")
        XCTAssertTrue(bridge.allSatisfy { $0.phase == .discipline })
        let hinge = library.filter { $0.movementPattern == .hinge }
        XCTAssertFalse(hinge.contains { $0.phase == .strength }, "hinge has no Strength-Phase skill, like Pull")
    }

    /// An intermediate user who clears Diamond Push-Up now climbs to Side-to-Side, an intermediate rung,
    /// where before Archer's advanced audience held them on Diamond; one who clears Sumo Squat climbs to
    /// Burpee.
    func testIntermediatesClimbPastDiamondAndSumoSquat() async throws {
        let library = try await offeredLibrary()
        let diamond = try XCTUnwrap(library.first { $0.id == "push_diamond" })
        let sumo = try XCTUnwrap(library.first { $0.id == "squat_sumo" })
        let fromDiamond = selection(chain: "push_horizontal", level: .intermediate,
                                    logs: [clearingLog(diamond, level: .intermediate, daysAgo: 1)], library: library)
        XCTAssertEqual(fromDiamond?.exercise.id, "push_side_to_side")
        XCTAssertEqual(fromDiamond?.didAdvance, true)
        let fromSumo = selection(chain: "squat", level: .intermediate,
                                 logs: [clearingLog(sumo, level: .intermediate, daysAgo: 1)], library: library)
        XCTAssertEqual(fromSumo?.exercise.id, "squat_burpee")
    }

    // MARK: - Removed movements are retired, never served

    func testRemovedMovementsStayInTheFileAsRetiredInTheirOwnChains() throws {
        let file = try fullFileLibrary()
        let byId = Dictionary(uniqueKeysWithValues: file.map { ($0.id, $0) })
        for id in removed {
            let exercise = try XCTUnwrap(byId[id], "\(id) stays in the file so history resolves")
            XCTAssertEqual(exercise.audience, .retired, id)
            XCTAssertTrue(MovementAccess.isWithdrawn(exercise), id)
        }
        XCTAssertEqual(ladder("push_horizontal_retired", in: file).map(\.id), removedPush)
        XCTAssertEqual(ladder("hinge_nordic", in: file).map(\.id), removedNordic)
        XCTAssertEqual(file.count, 83)
    }

    func testTheServiceNeverServesARemovedMovement() async throws {
        let service = try MockExerciseService()
        let offered = Set(try await service.exercises().map(\.id))
        XCTAssertEqual(offered.count, 70)
        XCTAssertTrue(offered.isDisjoint(with: removed))
        XCTAssertTrue(offered.isSuperset(of: added))
        for id in removed {
            let found = try await service.exercise(id: id)
            XCTAssertNil(found, id)
        }
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                let available = Set(MovementAccess.available(in: try fullFileLibrary(), level: level, phase: phase).map(\.id))
                XCTAssertTrue(available.isDisjoint(with: removed), "\(level)/\(phase)")
            }
        }
    }

    /// No session, Practice Movement, Different workout press or swap serves a removed movement, for any
    /// level, phase, Training Day or length - even fed the whole file and a history that worked every one.
    func testNoSessionDifferentWorkoutOrSwapServesARemovedMovement() throws {
        let library = try fullFileLibrary()
        let history = removed.enumerated().map { index, id in
            workLog(id, pattern: id.hasPrefix("push") ? .push : .hinge, daysAgo: 6 - index)
        }
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                let user = user(level: level, phase: phase)
                for day in TrainingDay.rotation {
                    for minutes in [5, 10, 15, 20, 30, 45, 60] {
                        for logs in [[], history] {
                            var variation = SessionVariation.none
                            for press in 0..<3 {
                                let workout = SessionAssembly.assemble(
                                    requestedMinutes: minutes, user: user, library: library, recentLogs: logs,
                                    variation: variation, trainingDay: day, asOf: asOf, calendar: calendar
                                )
                                let served = workout.blocks.flatMap(\.exercises)
                                XCTAssertTrue(Set(served.map(\.exercise.id)).isDisjoint(with: removed),
                                              "\(level)/\(phase)/\(day)/\(minutes) min press \(press)")
                                variation = variation.advanced(past: workout)
                                guard press == 0, minutes == 60 else { continue }
                                for slot in served {
                                    if case .substituted(let substitute) = ExerciseSwap.swap(
                                        slot, in: workout, user: user, library: library, recentLogs: logs
                                    ) {
                                        XCTAssertFalse(removed.contains(substitute.exercise.id), "\(level)/\(phase)/\(day): swap")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - A user on a removed rung keeps their place

    func testStandardAndLongLeverReplaceTheRemovedRungs() async throws {
        let library = try await offeredLibrary()
        XCTAssertEqual(library.first { $0.id == "push_standard" }?.replaces, removedPush)
        XCTAssertEqual(library.first { $0.id == "hinge_long_lever_bridge" }?.replaces, removedNordic)
        XCTAssertEqual(library.filter { $0.replaces != nil }.map(\.id).sorted(), ["hinge_long_lever_bridge", "push_standard"])
    }

    /// A beginner whose history is only on Wall, Incline or Knee Push-Up is served Standard Push-Up, at
    /// the bottom of its range: the removed rung's clear never carries over to advance them past it.
    func testAUserOnARemovedPushRungIsServedStandardAtTheBottomOfItsRange() async throws {
        let library = try await offeredLibrary()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        for id in removedPush {
            let removedRung = try XCTUnwrap(try fullFileLibrary().first { $0.id == id })
            // Cleared, so its own ladder would have moved them up a rung.
            let logs = [clearingLog(removedRung, level: .beginner, daysAgo: 2)]
            let original = logs
            let served = selection(chain: "push_horizontal", level: .beginner, logs: logs, library: library)
            XCTAssertEqual(served?.exercise.id, "push_standard", id)
            XCTAssertEqual(served?.didAdvance, false, id)
            let target = AdaptiveOverload.target(for: standard, level: .beginner, recentLogs: logs)
            XCTAssertEqual(target.earned, RepGrammar.earnedRange(for: standard, level: .beginner).lowerBound,
                           "\(id): Standard Push-Up opens at the bottom of its range")
            XCTAssertEqual(logs, original, "history is read, never rewritten")
        }
    }

    /// A Strength-Phase user whose recent history is only on a Nordic curl - their last Long-Lever work
    /// outside the engine's window - stands on Long-Lever Single-Leg Bridge, not the ladder's entry.
    func testAUserOnANordicRungIsServedLongLeverNotGluteBridge() async throws {
        let library = try await offeredLibrary()
        for id in removedNordic {
            let logs = [workLog(id, pattern: .hinge, value: 10, daysAgo: 3)]
            for level in FitnessLevel.allCases {
                let served = selection(chain: "hinge_bridge", level: level, phase: .strength, logs: logs, library: library)
                XCTAssertEqual(served?.exercise.id, "hinge_long_lever_bridge", "\(id) / \(level)")
            }
            // A Discipline beginner who somehow carries that history gets the closest bridge they get.
            XCTAssertEqual(selection(chain: "hinge_bridge", level: .beginner, logs: logs, library: library)?.exercise.id,
                           "hinge_single_leg_bridge")
        }
    }

    /// Real history on a rung above the replacement wins: a user who logged Knee Push-Up and later Diamond
    /// stands on Diamond.
    func testAReplacedLogNeverPullsAUserBelowARungTheyReallyWorked() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("push_knee", pattern: .push, daysAgo: 20), workLog("push_diamond", pattern: .push, daysAgo: 2)]
        XCTAssertEqual(selection(chain: "push_horizontal", level: .intermediate, logs: logs, library: library)?.exercise.id,
                       "push_diamond")
    }

    /// The whole Push Day agrees: a beginner on Knee Push-Up gets Standard Push-Up as the horizontal
    /// ladder's station, and the session fits.
    func testABeginnerOnKneePushUpsGetsAPushDayOnStandard() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("push_knee", pattern: .push, daysAgo: 3)]
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            let workout = SessionAssembly.assemble(
                requestedMinutes: minutes, user: user(level: .beginner), library: library, recentLogs: logs,
                trainingDay: .push, asOf: asOf, calendar: calendar
            )
            let main = workout.blocks.flatMap(\.exercises).filter { $0.role == .main }
            let horizontal = main.filter { $0.exercise.progressionChainId == "push_horizontal" }.map(\.exercise.id)
            XCTAssertTrue(horizontal.allSatisfy { $0 == "push_standard" }, "\(minutes) min served \(horizontal)")
            XCTAssertLessThanOrEqual(SessionAssembly.plannedSeconds(of: workout) - minutes * 60, SessionAssembly.toleranceSeconds)
        }
    }

    /// The Progress tab reports the rung the user is served: Standard for a Knee Push-Up history, Long-Lever
    /// for a Nordic one, and names no removed movement anywhere, while the old sessions still count.
    func testProgressReportsTheReplacementAndNamesNoRemovedMovement() async throws {
        let library = try await offeredLibrary()
        let cases: [(logs: [WorkoutLog], pattern: MovementPattern, expected: String, phase: Phase)] = [
            ([workLog("push_wall", pattern: .push, daysAgo: 9), workLog("push_knee", pattern: .push, daysAgo: 2)],
             .push, "push_standard", .discipline),
            ([workLog("hinge_nordic", pattern: .hinge, value: 10, daysAgo: 2)], .hinge, "hinge_long_lever_bridge", .strength),
        ]
        for (logs, pattern, expected, phase) in cases {
            let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .advanced, phase: phase, asOf: asOf, calendar: calendar)
            let position = try XCTUnwrap(analytics.chainPositions.first { $0.pattern == pattern })
            XCTAssertEqual(position.currentExercise?.id, expected)
            XCTAssertEqual(position.tier, expected == "push_standard" ? 1 : 4)
            let map = try XCTUnwrap(analytics.progressionMap.ladders.first { $0.pattern == pattern })
            XCTAssertEqual(map.currentRung?.exerciseId, expected)
            let named = analytics.progressionMap.ladders.flatMap { $0.rungs.map(\.exerciseId) }
                + analytics.chainPositions.compactMap { $0.currentExercise?.id }
                + analytics.deep.strengthJourney.chains.flatMap { $0.milestones.map(\.exerciseId) }
            XCTAssertTrue(Set(named).isDisjoint(with: removed), "a Progress surface named a removed movement")
            XCTAssertEqual(analytics.personalBests.totalSessions, logs.count, "the old sessions still count")
        }
    }

    // MARK: - Foundations

    func testThePushFoundationClearsOnStandardOrFloorTricepDipsNotOnARemovedRung() async throws {
        let library = try await offeredLibrary()
        let push = try XCTUnwrap(StrengthFoundation.push.lines.first)
        XCTAssertEqual(Set(push.entryExercises(in: library).map(\.id)), ["push_standard", "push_floor_dips"])

        func isPushCleared(_ logs: [WorkoutLog]) -> Bool {
            let progress = PhaseEvaluator.progress(logs: logs, weeklyGoal: 3, library: library, level: .beginner, asOf: asOf, calendar: calendar)
            return progress.foundations.first { $0.foundation == .push }?.isCleared == true
        }
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let dips = try XCTUnwrap(library.first { $0.id == "push_floor_dips" })
        XCTAssertTrue(isPushCleared([clearingLog(standard, level: .beginner, daysAgo: 1)]))
        XCTAssertTrue(isPushCleared([clearingLog(dips, level: .beginner, daysAgo: 1)]))
        for id in removedPush {
            let removedRung = try XCTUnwrap(try fullFileLibrary().first { $0.id == id })
            XCTAssertFalse(isPushCleared([clearingLog(removedRung, level: .beginner, daysAgo: 1)]), "\(id) no longer clears Push")
        }
    }

    // MARK: - The Standard card's line, and the new movements' icon fallback

    func testTheStandardPushUpCardNamesTheEasierOptions() async throws {
        let library = try await offeredLibrary()
        let cue = try XCTUnwrap(library.first { $0.id == "push_standard" }?.cue)
        XCTAssertEqual(cue, "Can't do a full push-up yet? Do it against a wall, on an incline or on your knees.")
        XCTAssertEqual(library.filter { $0.cue != nil }.map(\.id), ["push_standard"])
    }

    func testTheNewMovementsHaveNoTrainerArtAndShowTheIcon() async throws {
        let library = try await offeredLibrary()
        let resolver = TrainerPoseResolver.bundled
        for id in added {
            let exercise = try XCTUnwrap(library.first { $0.id == id })
            for trainer in Trainer.allCases {
                XCTAssertEqual(resolver.art(exerciseId: id, trainer: trainer), .none, "\(id) / \(trainer)")
            }
            XCTAssertFalse(SessionAssembly.hasBundledTrainerArt(exercise), id)
        }
    }

    // MARK: - The loader guards `replaces`

    private func catalog(editing edit: (inout [Exercise]) -> Void) throws -> [Exercise] {
        var library = try fullFileLibrary()
        edit(&library)
        return library
    }

    private func index(_ id: String, in library: [Exercise]) -> Int {
        library.firstIndex { $0.id == id }!
    }

    func testTheLoaderRejectsAReplacementOfAnOfferedMovement() throws {
        let library = try catalog { $0[index("push_standard", in: $0)].replaces = ["push_diamond"] }
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .replacementInvalid(exerciseId: "push_standard", replacedId: "push_diamond"))
        }
    }

    func testTheLoaderRejectsAReplacementOfAnotherPattern() throws {
        let library = try catalog { $0[index("squat_wall_sit", in: $0)].replaces = ["hinge_nordic"] }
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .replacementInvalid(exerciseId: "squat_wall_sit", replacedId: "hinge_nordic"))
        }
    }

    func testTheLoaderRejectsAMovementTwoRungsReplace() throws {
        let library = try catalog { $0[index("push_wide", in: $0)].replaces = ["push_knee"] }
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .replacementInvalid(exerciseId: "push_wide", replacedId: "push_knee"))
        }
    }

    func testTheLoaderRejectsAReplacementOnAWithdrawnRung() throws {
        let library = try catalog { $0[index("push_knee", in: $0)].replaces = ["push_wall"] }
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .replacementInvalid(exerciseId: "push_knee", replacedId: "push_wall"))
        }
    }

    func testTheLoaderRejectsAReplacementOfAnUnknownMovement() throws {
        let library = try catalog { $0[index("push_standard", in: $0)].replaces = ["push_nope"] }
        XCTAssertThrowsError(try MockExerciseService(library: library)) { error in
            XCTAssertEqual(error as? ExerciseLibraryError, .replacementInvalid(exerciseId: "push_standard", replacedId: "push_nope"))
        }
    }
}
