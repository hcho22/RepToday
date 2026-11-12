import XCTest
@testable import RepToday

/// ADR-0007: beginner and intermediate users get staple movements only while in the Discipline Phase,
/// advanced users keep today's variety, and the Strength Phase opens everything. Two kinds of movement
/// are withdrawn for everyone: the whole primal pillar, retired with its block (ADR-0014), and Prone
/// Y-T-W Raises, held until version 2 as the withdrawn top of the postural pull chain.
///
/// Everything here runs over the real bundled `Exercises.json`, so the lists below are the captain's
/// decision as shipped data: the per-level pool contents are pinned exactly, not by a rule that could
/// drift with the data. The deterministic access rule itself (`MovementAccess`) is covered where it is
/// consumed - the pool filter, session assembly, swap, the Progress analytics and the one-time note.
final class StapleMovementsTests: XCTestCase {

    // MARK: - The decided lists

    /// Training staples for beginner and intermediate users.
    private let beginnerTraining: Set<String> = [
        "push_wall", "push_incline", "push_knee", "push_standard", "push_floor_dips",
        "pull_superman", "pull_wall_scapular_pull",
        "squat_wall_sit", "squat_bodyweight", "lunge_reverse",
        "hinge_glute_bridge", "hinge_single_leg_bridge", "hinge_good_morning",
        "core_forearm_plank", "core_bird_dog",
    ]
    /// Training staples for intermediate users only.
    private let intermediateTraining: Set<String> = [
        "push_diamond", "pull_floor_row", "squat_sumo", "lunge_split_squat",
        "hinge_bridge_march", "hinge_single_leg_rdl", "core_side_plank", "core_dead_bug",
    ]
    /// Training movements for advanced users only (Strength-Phase skills excluded).
    private let advancedTraining: Set<String> = [
        "push_pike", "push_archer",
        "pull_reverse_snow_angel", "pull_floor_row_single_arm",
        "squat_cossack", "squat_shrimp",
        "hinge_long_lever_bridge",
        "core_bear_hold", "core_hollow_hold", "core_hollow_rock", "core_tuck_l_sit",
    ]
    /// The existing Strength-Phase movements, which stay as they are.
    private let strengthPhaseMovements: Set<String> = [
        "push_one_arm_assisted", "push_one_arm", "squat_pistol_assisted", "squat_pistol",
        "core_one_leg_l_sit", "core_l_sit", "hinge_nordic_assisted", "hinge_nordic",
    ]
    /// Warm-up and cooldown staples for beginner and intermediate users.
    private let stapleStretches: Set<String> = [
        "mobility_arm_circles", "mobility_hip_circles", "mobility_cat_cow", "mobility_childs_pose",
        "mobility_cobra", "mobility_down_dog", "mobility_forward_fold", "mobility_standing_quad",
        "mobility_butterfly", "mobility_kneeling_hip_flexor", "mobility_figure_four",
        "mobility_wall_calf", "mobility_wall_chest_opener", "mobility_side_bend",
        "mobility_supine_twist", "mobility_deep_squat_hold",
    ]
    /// Stretches for advanced users only.
    private let advancedStretches: Set<String> = [
        "mobility_9090_hip", "mobility_thoracic_rotation", "mobility_worlds_greatest", "mobility_pigeon",
        "mobility_frog", "mobility_lizard_lunge", "mobility_thread_needle", "mobility_puppy_pose",
        "mobility_cossack", "mobility_ankle_rocks",
    ]
    /// The primal pillar, retired for everyone with its block (ADR-0014).
    private let retired: Set<String> = [
        "primal_gorilla_walk", "primal_lizard_crawl", "primal_underswitch",
        "primal_bear_crawl", "primal_crab_walk", "primal_ground_to_standing", "primal_bear_shoulder_tap",
    ]
    /// Held back for everyone until version 2.
    private let versionTwo: Set<String> = ["pull_ytw"]
    /// Every movement no user is offered.
    private var withdrawn: Set<String> { retired.union(versionTwo) }

    private func expectedPool(level: FitnessLevel, phase: Phase) -> Set<String> {
        if phase == .strength {
            return beginnerTraining.union(intermediateTraining).union(advancedTraining)
                .union(strengthPhaseMovements).union(stapleStretches).union(advancedStretches)
        }
        switch level {
        case .beginner: return beginnerTraining.union(stapleStretches)
        case .intermediate: return beginnerTraining.union(intermediateTraining).union(stapleStretches)
        case .advanced:
            return beginnerTraining.union(intermediateTraining).union(advancedTraining)
                .union(stapleStretches).union(advancedStretches)
        }
    }

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    }

    private func offeredLibrary() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// The whole file, withdrawn movements included - what the service reads before it filters - so the
    /// access gate itself (not only the service's filtering) is exercised.
    private func fullFileLibrary() throws -> [Exercise] {
        let bundle = Bundle(for: MockExerciseService.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Exercises", withExtension: "json"))
        return try JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
    }

    private func user(level: FitnessLevel, phase: Phase = .discipline, injuries: [String] = []) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35, sex: .other, heightCm: 175, weightKg: 75, fitnessLevel: level,
                sitsLong: false, injuries: injuries, typicalAvailableMinutes: 15
            ),
            phase: phase,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1, longestChain: 0,
                totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A session `daysAgo` with one station of `exerciseId`, `sets` sets of `reps` (or `seconds`), as a
    /// log written before Training Days records it: no role, earned = performed.
    private func workLog(
        _ exerciseId: String,
        pillar: Pillar = .strength,
        pattern: MovementPattern,
        reps: Int? = nil,
        seconds: Int? = nil,
        sets: Int = 3,
        daysAgo: Int
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20, durationMinutes: 20, wasReturn: false,
            shape: .singleFocus, focusPillar: pillar, perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(), exerciseId: exerciseId, pillar: pillar, movementPattern: pattern,
                    completedSets: (0..<sets).map { _ in CompletedSet(reps: reps, durationSeconds: seconds) },
                    skipped: false
                )
            ]
        )
    }

    private func ids(_ exercises: [Exercise]) -> Set<String> { Set(exercises.map(\.id)) }

    /// A session that clears `exerciseId` for a user at `level`: four sets at the top of the level's range.
    private func clearingLog(_ exerciseId: String, in library: [Exercise], level: FitnessLevel, daysAgo: Int) throws -> WorkoutLog {
        let exercise = try XCTUnwrap(library.first { $0.id == exerciseId }, exerciseId)
        let top = RepGrammar.earnedRange(for: exercise, level: level).upperBound
        return workLog(
            exerciseId, pattern: exercise.movementPattern,
            reps: exercise.isHold ? nil : top, seconds: exercise.isHold ? top : nil, sets: RepGrammar.setsPerStation,
            daysAgo: daysAgo
        )
    }

    // MARK: - Pool contents

    func testCatalogPartitionsIntoTheDecidedLists() async throws {
        let all = try fullFileLibrary()
        let partition = [beginnerTraining, intermediateTraining, advancedTraining, strengthPhaseMovements,
                         stapleStretches, advancedStretches, retired, versionTwo]
        XCTAssertEqual(all.count, partition.reduce(0) { $0 + $1.count }, "every movement is on exactly one list")
        XCTAssertEqual(Set(all.map(\.id)), partition.reduce(into: Set<String>()) { $0.formUnion($1) })
        XCTAssertEqual(all.count, 76)
    }

    func testEachAudienceFieldMatchesItsList() throws {
        let all = try fullFileLibrary()
        for exercise in all {
            let expected: MovementAudience
            if beginnerTraining.contains(exercise.id) || stapleStretches.contains(exercise.id) { expected = .beginner }
            else if intermediateTraining.contains(exercise.id) { expected = .intermediate }
            else if retired.contains(exercise.id) { expected = .retired }
            else if versionTwo.contains(exercise.id) { expected = .version2 }
            else { expected = .advanced }
            XCTAssertEqual(exercise.audience, expected, "\(exercise.id) carries the wrong audience")
        }
    }

    func testPoolContentsPerLevelAndPhaseMatchTheListsExactly() async throws {
        let library = try await offeredLibrary()
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: level, phase: phase), recentLogs: [])
                XCTAssertEqual(
                    ids(pool), expectedPool(level: level, phase: phase),
                    "pool for \(level) in \(phase) must equal the decided list exactly"
                )
            }
        }
    }

    func testPoolSizesAreWhatTheDecisionSays() async throws {
        let library = try await offeredLibrary()
        func count(_ level: FitnessLevel, training: Bool) -> Int {
            ExercisePoolFilter.eligiblePool(from: library, user: user(level: level), recentLogs: [])
                .filter { ($0.pillar != .mobility) == training }.count
        }
        XCTAssertEqual(count(.beginner, training: true), 15)
        XCTAssertEqual(count(.beginner, training: false), 16)
        XCTAssertEqual(count(.intermediate, training: true), 23)
        XCTAssertEqual(count(.intermediate, training: false), 16)
        XCTAssertEqual(count(.advanced, training: true), 34)
        XCTAssertEqual(count(.advanced, training: false), 26)
    }

    func testTheAccessRuleHasOneSourceForRestrictionAndForAvailability() {
        XCTAssertTrue(MovementAccess.isRestrictedToStaples(level: .beginner, phase: .discipline))
        XCTAssertTrue(MovementAccess.isRestrictedToStaples(level: .intermediate, phase: .discipline))
        XCTAssertFalse(MovementAccess.isRestrictedToStaples(level: .advanced, phase: .discipline))
        for level in FitnessLevel.allCases {
            XCTAssertFalse(MovementAccess.isRestrictedToStaples(level: level, phase: .strength), "the Strength Phase lifts it")
        }
    }

    func testPoolFilterIsStillZeroEquipmentAndInjurySafe() async throws {
        let library = try await offeredLibrary()
        let kneePool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: .beginner, injuries: ["knees"]), recentLogs: [])
        XCTAssertFalse(kneePool.contains { $0.movementPattern == .squat }, "injury filtering is untouched")
        XCTAssertTrue(kneePool.allSatisfy { $0.equipment.isEmpty })
    }

    // MARK: - Withdrawn movements

    func testWithdrawnMovementsStayInTheFileButAreNeverServedByTheCatalogService() async throws {
        let service = try MockExerciseService()
        let offered = ids(try await service.exercises())
        XCTAssertTrue(offered.isDisjoint(with: withdrawn), "the service never serves a withdrawn movement")
        XCTAssertEqual(offered.count, 68)
        for pillar in Pillar.allCases {
            let byPillar = try await service.exercises(for: pillar)
            XCTAssertTrue(ids(byPillar).isDisjoint(with: withdrawn))
        }
        for pattern in MovementPattern.allCases {
            let byPattern = try await service.exercises(for: pattern)
            XCTAssertTrue(ids(byPattern).isDisjoint(with: withdrawn))
        }
        for id in withdrawn {
            let found = try await service.exercise(id: id)
            XCTAssertNil(found, "\(id) is not resolvable as an offered movement")
        }
        // Recoverable: both primal chains are still in the file whole and retired, and Prone Y-T-W Raises
        // is the withdrawn top of the postural chain, above the live ladder.
        let file = try fullFileLibrary()
        let primal = file.filter { $0.pillar == .primal }
        XCTAssertEqual(ids(primal), retired)
        XCTAssertEqual(Set(primal.map(\.progressionChainId)), ["primal_ground_flow", "primal_locomotion"])
        XCTAssertTrue(primal.allSatisfy { $0.audience == .retired })
        let postural = file.filter { $0.progressionChainId == "pull_postural" }.sorted { $0.progressionOrder < $1.progressionOrder }
        XCTAssertEqual(postural.map(\.id), ["pull_superman", "pull_reverse_snow_angel", "pull_ytw"])
        XCTAssertEqual(postural.last?.audience, .version2)
    }

    /// Prone Y-T-W Raises is the withdrawn top of the postural chain, so the live chain a user is offered
    /// tops out at Reverse Snow Angel. A user who climbed through Reverse Snow Angel to Y-T-W keeps that
    /// history and is served Reverse Snow Angel, the closest rung they get; history on Y-T-W alone places
    /// no one on the offered chain, so such a user enters it at its entry, as ADR-0007 records for history
    /// on a movement no surface can name.
    func testProneYTWHistoryIsServedTheClosestPosturalRung() async throws {
        let library = try await offeredLibrary()
        let postural = library.filter { $0.progressionChainId == "pull_postural" }
            .sorted { $0.progressionOrder < $1.progressionOrder }
        XCTAssertEqual(postural.map(\.id), ["pull_superman", "pull_reverse_snow_angel"])
        let next = try await MockExerciseService().nextInChain(after: "pull_reverse_snow_angel")
        XCTAssertNil(next, "Reverse Snow Angel is the offered chain's top rung")

        let climbed = [
            workLog("pull_reverse_snow_angel", pattern: .pull, reps: 15, daysAgo: 6),
            workLog("pull_ytw", pattern: .pull, reps: 12, daysAgo: 2),
        ]
        let eligible = Set(ExercisePoolFilter.eligiblePool(
            from: library, user: user(level: .advanced, phase: .discipline), recentLogs: climbed
        ).map(\.id))
        XCTAssertFalse(eligible.contains("pull_ytw"))
        let served = ProgressionChainSelection.selectInChain(postural, eligibleIds: eligible, recentLogs: climbed, level: .advanced)
        XCTAssertEqual(served?.exercise.id, "pull_reverse_snow_angel")

        let ytwOnly = [workLog("pull_ytw", pattern: .pull, reps: 12, daysAgo: 2)]
        let reentry = ProgressionChainSelection.selectInChain(postural, eligibleIds: eligible, recentLogs: ytwOnly, level: .advanced)
        XCTAssertEqual(reentry?.exercise.id, "pull_superman", "Y-T-W-only history enters the offered chain at its entry")

        for phase in [Phase.discipline, .strength] {
            let analytics = ProgressAnalytics.from(
                logs: climbed, library: library, level: .advanced, phase: phase, asOf: asOf, calendar: calendar
            )
            let named = analytics.progressionMap.ladders.flatMap { $0.rungs.map(\.exerciseId) }
                + analytics.chainPositions.compactMap { $0.currentExercise?.id }
                + analytics.deep.strengthJourney.chains.flatMap { $0.milestones.map(\.exerciseId) }
            XCTAssertFalse(named.contains("pull_ytw"), "\(phase): a Progress surface named Prone Y-T-W Raises")
            XCTAssertEqual(analytics.personalBests.totalSessions, 2, "the Y-T-W session still counts")
        }
    }

    /// No session serves a withdrawn movement, for any user, length or Training Day - not even to a
    /// user whose history has worked every one of them, the strongest pull toward re-serving them - and
    /// no session has a primal block.
    func testWithdrawnMovementsNeverAppearInAnySessionForAnyUser() throws {
        let library = try fullFileLibrary() // withdrawn movements deliberately present
        XCTAssertTrue(ids(library).isSuperset(of: withdrawn))
        let logs = retired.sorted().enumerated().map { index, id in
            workLog(id, pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 10 - index)
        } + [workLog("pull_ytw", pattern: .pull, reps: 15, daysAgo: 2)]
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                for day in TrainingDay.rotation {
                    for minutes in [5, 10, 15, 20, 30, 45, 60] {
                        for history in [[], logs] {
                            let workout = SessionAssembly.assemble(
                                requestedMinutes: minutes, user: user(level: level, phase: phase), library: library,
                                recentLogs: history, trainingDay: day, asOf: asOf, calendar: calendar
                            )
                            let served = Set(workout.blocks.flatMap(\.exercises).map(\.exercise.id))
                            XCTAssertTrue(
                                served.isDisjoint(with: withdrawn),
                                "\(level)/\(phase)/\(day)/\(minutes) min served a withdrawn movement: \(served.intersection(withdrawn))"
                            )
                            XCTAssertFalse(workout.blocks.contains { $0.category == .primal }, "\(level)/\(phase)/\(day)/\(minutes) min")
                        }
                    }
                }
            }
        }
    }

    func testWithdrawnMovementsAreNeverASwapSubstitute() throws {
        let library = try fullFileLibrary()
        let advanced = user(level: .advanced, phase: .strength)
        for day in TrainingDay.rotation {
            let workout = SessionAssembly.assemble(
                requestedMinutes: 60, user: advanced, library: library, recentLogs: [], trainingDay: day,
                asOf: asOf, calendar: calendar
            )
            for block in workout.blocks {
                for slot in block.exercises {
                    if case .substituted(let replacement) = ExerciseSwap.swap(
                        slot, in: workout, user: advanced, library: library, recentLogs: []
                    ) {
                        XCTAssertFalse(withdrawn.contains(replacement.exercise.id), "\(day): swap handed back \(replacement.exercise.id)")
                    }
                }
            }
        }
    }

    /// Retired primal work stays in the user's history wherever a surface reads the log's own pillar and
    /// pattern, while nothing names a retired movement.
    func testRetiredPrimalLogsStillCountInHistoryButNothingNamesThem() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 3),
            workLog("primal_lizard_crawl", pillar: .primal, pattern: .locomotion, reps: 15, daysAgo: 2),
            workLog("push_standard", pattern: .push, reps: 12, daysAgo: 1),
        ]
        for level in FitnessLevel.allCases {
            let analytics = ProgressAnalytics.from(
                logs: logs, library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar
            )
            // The history still counts where it reads the log's own pillar and pattern.
            XCTAssertEqual(analytics.personalBests.totalSessions, 3)
            let primal = analytics.pillarBalance.first { $0.pillar == .primal }
            XCTAssertEqual(primal?.exerciseCount, 2, "past primal work still counts toward pillar balance")
            XCTAssertEqual(analytics.deep.patternBalance.first { $0.pattern == .locomotion }?.exerciseCount, 2)
            XCTAssertEqual(analytics.deep.weeklyVolume.reduce(0) { $0 + $1.sessionCount }, 3)

            // Nothing names a withdrawn movement.
            let named = analytics.progressionMap.ladders.flatMap { $0.rungs.map(\.exerciseId) }
                + analytics.chainPositions.compactMap { $0.currentExercise?.id }
                + analytics.deep.strengthJourney.chains.flatMap { $0.milestones.map(\.exerciseId) }
                + [analytics.personalBests.bestReps?.exerciseId, analytics.personalBests.bestHold?.exerciseId].compactMap { $0 }
            XCTAssertTrue(Set(named).isDisjoint(with: withdrawn), "\(level): a surface named a retired movement")
            XCTAssertEqual(analytics.personalBests.bestReps?.exerciseId, "push_standard")
        }
    }

    /// The Progress tab, read through its production view model and the real exercise service, still
    /// shows the sessions retired primal work was logged in: the calendar marks their days and the totals
    /// count them, while nothing on the tab names a retired movement.
    @MainActor
    func testRetiredPrimalLogsStillShowInTheProgressTabHistory() async throws {
        let logs = [
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 3),
            workLog("primal_lizard_crawl", pillar: .primal, pattern: .locomotion, reps: 15, daysAgo: 2),
            workLog("push_standard", pattern: .push, reps: 12, daysAgo: 1),
        ]
        let viewModel = ProgressViewModel(
            userService: MockUserService(user: user(level: .beginner)),
            workoutLogService: MockWorkoutLogService(logs: logs),
            exerciseService: try MockExerciseService(),
            subscriptionService: MockSubscriptionService(subscription: .free),
            consistencyService: ConsistencyScoreService(now: { self.asOf }, calendar: calendar),
            now: { self.asOf },
            calendar: calendar
        )
        await viewModel.load()

        XCTAssertTrue(viewModel.hasHistory)
        XCTAssertEqual(viewModel.completedDays, Set(logs.map { calendar.startOfDay(for: $0.completedAt) }),
                       "every logged day, crawl sessions included, is marked on the calendar")
        let analytics = try XCTUnwrap(viewModel.analytics)
        XCTAssertEqual(analytics.personalBests.totalSessions, 3)
        XCTAssertEqual(analytics.pillarBalance.first { $0.pillar == .primal }?.exerciseCount, 2)
        XCTAssertEqual(analytics.personalBests.bestReps?.exerciseId, "push_standard")
    }

    // MARK: - Chains stay clean ladders

    func testBundledCatalogLoadsAsCleanDoublyLinkedLadders() throws {
        // The service validates this on load; loading the real file is the proof.
        XCTAssertNoThrow(try MockExerciseService())
    }

    func testSumoSquatMovesBehindBodyweightSquatAndBeginnersGetWallSitThenBodyweightSquat() async throws {
        let library = try await offeredLibrary()
        let squat = library.filter { $0.progressionChainId == "squat" }.sorted { $0.progressionOrder < $1.progressionOrder }
        XCTAssertEqual(squat.map(\.id), [
            "squat_wall_sit", "squat_bodyweight", "squat_sumo", "squat_cossack", "squat_shrimp",
            "squat_pistol_assisted", "squat_pistol",
        ])
        let beginnerChain = MovementAccess.available(in: squat, level: .beginner, phase: .discipline).map(\.id)
        XCTAssertEqual(beginnerChain, ["squat_wall_sit", "squat_bodyweight"])
    }

    func testCoreProgressionIsBirdDogThenDeadBugForIntermediates() async throws {
        let library = try await offeredLibrary()
        let core = library.filter { $0.progressionChainId == "core_stability" }.sorted { $0.progressionOrder < $1.progressionOrder }
        XCTAssertEqual(core.map(\.id), ["core_bird_dog", "core_dead_bug", "core_bear_hold"])
        XCTAssertEqual(MovementAccess.available(in: core, level: .beginner, phase: .discipline).map(\.id), ["core_bird_dog"])
        XCTAssertEqual(
            MovementAccess.available(in: core, level: .intermediate, phase: .discipline).map(\.id),
            ["core_bird_dog", "core_dead_bug"]
        )
    }

    // MARK: - Foundations stay clearable from staples

    func testEveryFoundationHasABeginnerStapleEntryRung() async throws {
        let library = try await offeredLibrary()
        for line in StrengthFoundation.allLines {
            let staples = line.entryExercises(in: library)
                .filter { MovementAccess.isAvailable($0, level: .beginner, phase: .discipline) }
            XCTAssertFalse(staples.isEmpty, "\(line.spokenName) has no entry rung a beginner gets")
        }
        let entries = StrengthFoundation.allLines.flatMap { line in
            line.entryExercises(in: library).filter { MovementAccess.isAvailable($0, level: .beginner, phase: .discipline) }.map(\.id)
        }
        XCTAssertTrue(Set(entries).isSuperset(of: [
            "push_wall", "pull_wall_scapular_pull", "squat_wall_sit", "hinge_glute_bridge", "core_forearm_plank",
        ]))
    }

    func testABeginnerEarnsTheStrengthPhaseUsingStaplesOnly() async throws {
        let library = try await offeredLibrary()
        let cleared = ["push_wall", "pull_wall_scapular_pull", "squat_wall_sit", "hinge_glute_bridge", "core_forearm_plank"]
        for id in cleared {
            let exercise = try XCTUnwrap(library.first { $0.id == id })
            XCTAssertTrue(MovementAccess.isAvailable(exercise, level: .beginner, phase: .discipline), "\(id) must be a beginner staple")
        }
        let showUps = (0..<8).flatMap { week in
            (0..<3).map { day in
                WorkoutLog(
                    id: UUID(), workoutId: UUID(),
                    completedAt: calendar.date(byAdding: .day, value: -(week * 7 + day), to: asOf)!,
                    requestedMinutes: 15, durationMinutes: 15, shape: .singleFocus, focusPillar: .strength,
                    perceivedDifficulty: nil, exercises: []
                )
            }
        }
        // Each entry rung cleared at the top of a beginner's range: four sets of 30 reps or 60-second holds.
        let clearing = try cleared.map { try clearingLog($0, in: library, level: .beginner, daysAgo: 0) }
        let progress = PhaseEvaluator.progress(
            logs: showUps + clearing, weeklyGoal: 3, library: library, level: .beginner, asOf: asOf, calendar: calendar
        )
        XCTAssertTrue(progress.foundations.allSatisfy(\.isCleared), "every foundation clears from staples alone")
        XCTAssertTrue(progress.hasEarnedStrength)
    }

    // MARK: - Sessions stay inside the length, run four rounds, and serve only what the level gets

    /// Staples-only pools still build every Training Day at every length: no session overruns the
    /// tolerance (`TrainingDayFitHarnessTests` owns the fit itself, including honest shortfalls), every
    /// circuit station runs the rep grammar's four rounds, and nothing served is a movement the level
    /// does not get.
    func testSessionsAtEveryLengthLevelAndDayStayInsideTheLengthAndServeOnlyWhatTheLevelGets() async throws {
        let library = try await offeredLibrary()
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    let workout = SessionAssembly.assemble(
                        requestedMinutes: minutes, user: user(level: level), library: library,
                        recentLogs: [], trainingDay: day, asOf: asOf, calendar: calendar
                    )
                    let planned = SessionAssembly.plannedSeconds(of: workout)
                    XCTAssertLessThanOrEqual(
                        planned - minutes * 60, SessionAssembly.toleranceSeconds,
                        "\(level) \(day) \(minutes) min planned \(planned)s, over the +\(SessionAssembly.toleranceSeconds)s tolerance"
                    )
                    for block in workout.blocks where SessionAssembly.isCircuit(block.category) {
                        for slot in block.exercises {
                            XCTAssertEqual(slot.sets, RepGrammar.setsPerStation, "\(level) \(day) \(minutes) min: \(slot.exercise.id)")
                        }
                    }
                    for slot in workout.blocks.flatMap(\.exercises) {
                        if slot.role == .practice {
                            // A Practice Movement may sit above the staple level (ADR-0015), never past a
                            // Strength-Phase lock or onto a withdrawn movement.
                            XCTAssertFalse(MovementAccess.isWithdrawn(slot.exercise), "\(level) \(day) \(minutes) min: \(slot.exercise.id)")
                            XCTAssertTrue(MovementAccess.isPhaseEarned(slot.exercise, phase: .discipline), "\(level) \(day) \(minutes) min: \(slot.exercise.id)")
                        } else {
                            XCTAssertTrue(
                                MovementAccess.isAvailable(slot.exercise, level: level, phase: .discipline),
                                "\(level) \(day) \(minutes) min served \(slot.exercise.id), which that level does not get"
                            )
                        }
                    }
                }
            }
        }
    }

    /// A user whose history sits on movements they no longer get - advanced rungs, retired primal work -
    /// still gets a session inside the length on every Training Day, built from the rungs they do get
    /// (a Practice Movement may preview the next rung above the staple level, ADR-0015).
    func testSessionsFitForUsersWhoseHistorySitsOnMovementsTheyNoLongerGet() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("squat_cossack", pattern: .squat, reps: 10, daysAgo: 6),
            workLog("core_hollow_hold", pattern: .core, seconds: 30, daysAgo: 5),
            workLog("push_archer", pattern: .push, reps: 8, daysAgo: 4),
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 3),
        ]
        for level in [FitnessLevel.beginner, .intermediate] {
            for day in TrainingDay.rotation {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    let workout = SessionAssembly.assemble(
                        requestedMinutes: minutes, user: user(level: level), library: library,
                        recentLogs: logs, trainingDay: day, asOf: asOf, calendar: calendar
                    )
                    XCTAssertLessThanOrEqual(
                        SessionAssembly.plannedSeconds(of: workout) - minutes * 60, SessionAssembly.toleranceSeconds,
                        "\(level) \(day) \(minutes) min"
                    )
                    XCTAssertFalse(workout.blocks.flatMap(\.exercises).isEmpty, "\(level) \(day) \(minutes) min")
                    for slot in workout.blocks.flatMap(\.exercises) where slot.role != .practice {
                        XCTAssertTrue(
                            MovementAccess.isAvailable(slot.exercise, level: level, phase: .discipline),
                            "\(level) \(day) \(minutes) min served \(slot.exercise.id)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Stretch coverage

    func testEveryStrengthPatternKeepsAtLeastTwoStapleStretches() async throws {
        let library = try await offeredLibrary()
        let staples = library.filter { $0.pillar == .mobility && MovementAccess.isAvailable($0, level: .beginner, phase: .discipline) }
        XCTAssertEqual(ids(staples), stapleStretches)
        for pattern in StrengthFoundation.foundationPatterns {
            let covering = staples.filter { ($0.complements ?? []).contains(pattern) }
            XCTAssertGreaterThanOrEqual(covering.count, 2, "\(pattern) has fewer than two staple stretches")
        }
    }

    func testBookendsForBeginnerAndIntermediateUseStapleStretchesOnly() async throws {
        let library = try await offeredLibrary()
        for level in [FitnessLevel.beginner, .intermediate] {
            for day in TrainingDay.rotation {
                for minutes in [10, 20, 45, 60] {
                    let workout = SessionAssembly.assemble(
                        requestedMinutes: minutes, user: user(level: level), library: library,
                        recentLogs: [], trainingDay: day, asOf: asOf, calendar: calendar
                    )
                    let stretches = workout.blocks.filter { $0.category == .warmup || $0.category == .cooldown }
                        .flatMap(\.exercises).map(\.exercise.id)
                    XCTAssertFalse(stretches.isEmpty)
                    XCTAssertTrue(
                        Set(stretches).isSubset(of: stapleStretches),
                        "\(level) \(day) \(minutes) min: \(Set(stretches).subtracting(stapleStretches))"
                    )
                }
            }
        }
    }

    // MARK: - Existing users move to the closest rung they get

    /// What Step 5 serves a user of `level` on one chain, through the real pool filter.
    private func selection(
        chain chainId: String, level: FitnessLevel, logs: [WorkoutLog], library: [Exercise]
    ) -> ChainSelection? {
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: level), recentLogs: logs)
        return ProgressionChainSelection.selectInChain(
            library.filter { $0.progressionChainId == chainId },
            eligibleIds: Set(pool.map(\.id)),
            recentLogs: logs,
            level: level
        )
    }

    /// What Step 5 serves a user of `level` for a whole pattern (every chain ranked, best first).
    private func selection(
        _ pattern: MovementPattern, level: FitnessLevel, logs: [WorkoutLog], library: [Exercise]
    ) -> ChainSelection? {
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: level), recentLogs: logs)
        return ProgressionChainSelection.select(pattern: pattern, library: library, pool: pool, recentLogs: logs, level: level)
    }

    func testCossackSquatUserMovesToTheClosestSquatTheyGet() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("squat_bodyweight", pattern: .squat, reps: 20, daysAgo: 8),
            workLog("squat_cossack", pattern: .squat, reps: 4, daysAgo: 1), // nowhere near the top: still on it
        ]
        let original = logs
        XCTAssertEqual(selection(chain: "squat", level: .advanced, logs: logs, library: library)?.exercise.id, "squat_cossack",
                       "advanced users keep where they were")
        XCTAssertEqual(selection(chain: "squat", level: .intermediate, logs: logs, library: library)?.exercise.id, "squat_sumo")
        XCTAssertEqual(selection(chain: "squat", level: .beginner, logs: logs, library: library)?.exercise.id, "squat_bodyweight")
        XCTAssertEqual(logs, original, "history is read, never rewritten")

        for (level, expected) in [(FitnessLevel.intermediate, "squat_sumo"), (.beginner, "squat_bodyweight")] {
            let analytics = ProgressAnalytics.from(logs: logs, library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar)
            let squat = try XCTUnwrap(analytics.chainPositions.first { $0.pattern == .squat })
            XCTAssertEqual(squat.currentExercise?.id, expected, "\(level): Progress shows the rung they are served")
            let ladder = try XCTUnwrap(analytics.progressionMap.ladders.first { $0.pattern == .squat })
            XCTAssertEqual(ladder.currentRung?.exerciseId, expected)
            XCTAssertTrue(ladder.rungs.first { $0.exerciseId == "squat_cossack" }?.isLocked == true)
        }
    }

    func testSumoSquatUserKeepsItAsAnIntermediateAndMovesToBodyweightSquatAsABeginner() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("squat_sumo", pattern: .squat, reps: 15, daysAgo: 2)]
        XCTAssertEqual(selection(chain: "squat", level: .intermediate, logs: logs, library: library)?.exercise.id, "squat_sumo")
        XCTAssertEqual(selection(chain: "squat", level: .beginner, logs: logs, library: library)?.exercise.id, "squat_bodyweight")
        let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .discipline, asOf: asOf, calendar: calendar)
        XCTAssertEqual(analytics.chainPositions.first { $0.pattern == .squat }?.currentExercise?.id, "squat_bodyweight")
    }

    /// An existing beginner who did Wall Sit ten weeks ago and Sumo Squat every week since is served
    /// Bodyweight Squat, which they have never worked. The strength journey agrees with that:
    /// both past rungs stay in the timeline as history, the served rung is never reported as reached,
    /// and nine weeks on Sumo Squat are not read as a stall on Bodyweight Squat. Once they work it, it
    /// becomes their current milestone and the climb from Wall Sit reads as a recent advancement.
    func testExistingBeginnerMovedOffSumoSquatKeepsTheHistoryWithoutAFalseStall() async throws {
        let library = try await offeredLibrary()
        let history = [workLog("squat_wall_sit", pattern: .squat, seconds: 30, daysAgo: 70)]
            + (0...9).map { week in workLog("squat_sumo", pattern: .squat, reps: 15, daysAgo: 64 - week * 7) }

        func journey(_ logs: [WorkoutLog], level: FitnessLevel) throws -> (ProgressAnalytics, ChainJourney) {
            let analytics = ProgressAnalytics.from(logs: logs, library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar)
            return (analytics, try XCTUnwrap(analytics.deep.strengthJourney.chains.first { $0.pattern == .squat }))
        }

        let (beginner, squat) = try journey(history, level: .beginner)
        XCTAssertEqual(beginner.chainPositions.first { $0.pattern == .squat }?.currentExercise?.id, "squat_bodyweight")
        XCTAssertEqual(squat.currentExerciseId, "squat_bodyweight", "the journey sits on the rung the user is served")
        XCTAssertEqual(squat.currentDisplayName, "Bodyweight Squat")
        XCTAssertEqual(squat.milestones.map(\.exerciseId), ["squat_wall_sit", "squat_sumo"],
                       "both rungs the user really worked stay as past milestones")
        XCTAssertEqual(squat.milestones.first { $0.exerciseId == "squat_sumo" }?.firstReachedAt, date(daysAgo: 64))
        XCTAssertNil(squat.currentMilestone, "Bodyweight Squat is never reported as reached before it is worked")
        XCTAssertFalse(squat.hasAdvanced)
        XCTAssertNil(squat.weeksClimbed)

        // Working the served rung makes it the current milestone: a fresh climb from Wall Sit, not a stall.
        let (workedAnalytics, worked) = try journey(
            history + [workLog("squat_bodyweight", pattern: .squat, reps: 15, daysAgo: 0)], level: .beginner
        )
        XCTAssertEqual(worked.milestones.map(\.exerciseId), ["squat_wall_sit", "squat_bodyweight", "squat_sumo"])
        XCTAssertEqual(worked.currentMilestone?.exerciseId, "squat_bodyweight")
        XCTAssertEqual(worked.currentMilestone?.firstReachedAt, date(daysAgo: 0))
        XCTAssertEqual(worked.startMilestone?.exerciseId, "squat_wall_sit")
        XCTAssertTrue(worked.hasAdvanced)

        // The same history for an intermediate, who still gets Sumo Squat, sits on Sumo Squat everywhere.
        let (intermediate, intermediateSquat) = try journey(history, level: .intermediate)
        XCTAssertEqual(intermediate.chainPositions.first { $0.pattern == .squat }?.currentExercise?.id, "squat_sumo")
        XCTAssertEqual(intermediateSquat.currentMilestone?.exerciseId, "squat_sumo")
        XCTAssertEqual(intermediateSquat.currentMilestone?.firstReachedAt, date(daysAgo: 64))
    }

    /// An existing beginner who did Bird Dog from ten to six weeks ago, then Dead Bug weekly until
    /// yesterday, is moved back down to Bird Dog - a rung they worked before climbing past it. The weeks
    /// on Dead Bug are not read as weeks on Bird Dog: until they work Bird Dog again it has no current
    /// milestone, and once they do it is current from that session, a fresh start
    /// rather than a ten-week stall. Both rungs keep the dates they were first reached as history.
    func testExistingBeginnerMovedBackToBirdDogIsNotReadAsAStall() async throws {
        let library = try await offeredLibrary()
        let history = [70, 63, 56, 49, 42].map { workLog("core_bird_dog", pattern: .core, reps: 10, daysAgo: $0) }
            + [35, 28, 21, 14, 7, 1].map { workLog("core_dead_bug", pattern: .core, reps: 10, daysAgo: $0) }

        func analytics(_ logs: [WorkoutLog], level: FitnessLevel = .beginner) -> ProgressAnalytics {
            ProgressAnalytics.from(logs: logs, library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar)
        }
        func core(_ analytics: ProgressAnalytics) throws -> ChainJourney {
            try XCTUnwrap(analytics.deep.strengthJourney.chains.first { $0.pattern == .core })
        }

        let moved = analytics(history)
        XCTAssertEqual(moved.chainPositions.first { $0.pattern == .core }?.currentExercise?.id, "core_bird_dog")
        let journey = try core(moved)
        XCTAssertEqual(journey.currentExerciseId, "core_bird_dog")
        XCTAssertEqual(journey.milestones.map(\.exerciseId), ["core_bird_dog", "core_dead_bug"])
        XCTAssertEqual(journey.milestones.map(\.firstReachedAt), [date(daysAgo: 70), date(daysAgo: 35)],
                       "both rungs keep the date they were first reached")
        XCTAssertNil(journey.currentMilestone, "Bird Dog is not current again until it is worked after Dead Bug")
        XCTAssertFalse(journey.hasAdvanced)

        let returned = analytics(history + [workLog("core_bird_dog", pattern: .core, reps: 10, daysAgo: 0)])
        let returnedJourney = try core(returned)
        XCTAssertEqual(returnedJourney.currentMilestone?.exerciseId, "core_bird_dog")
        XCTAssertEqual(returnedJourney.currentMilestone?.firstReachedAt, date(daysAgo: 0), "current from the first session back on it")
        XCTAssertEqual(returnedJourney.milestones.first?.firstReachedAt, date(daysAgo: 70))

        // An intermediate still gets Dead Bug and has genuinely sat on it for five weeks.
        let intermediate = try core(analytics(history, level: .intermediate))
        XCTAssertEqual(intermediate.currentMilestone?.exerciseId, "core_dead_bug")
        XCTAssertEqual(intermediate.currentMilestone?.firstReachedAt, date(daysAgo: 35))
    }

    /// An existing intermediate or advanced user who climbed the old squat ladder - Wall Sit, then Sumo
    /// Squat, then Bodyweight Squat until yesterday - is served Sumo Squat now that it sits above
    /// Bodyweight Squat. The five weeks on Bodyweight Squat are time on a rung they moved on to, so they
    /// are not read as a ten-week stall on Sumo Squat: it has no current milestone until
    /// they work it again, and then reads as a climb from Wall Sit.
    func testReorderedSquatClimbIsNotReadAsAStallOnSumoSquat() async throws {
        let library = try await offeredLibrary()
        let history = [84, 77].map { workLog("squat_wall_sit", pattern: .squat, seconds: 45, daysAgo: $0) }
            + [70, 63, 56, 49, 42].map { workLog("squat_sumo", pattern: .squat, reps: 20, daysAgo: $0) }
            + [35, 28, 21, 14, 7, 1].map { workLog("squat_bodyweight", pattern: .squat, reps: 15, daysAgo: $0) }

        for level in [FitnessLevel.intermediate, .advanced] {
            func analytics(_ logs: [WorkoutLog]) -> ProgressAnalytics {
                ProgressAnalytics.from(logs: logs, library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar)
            }

            let reordered = analytics(history)
            XCTAssertEqual(reordered.chainPositions.first { $0.pattern == .squat }?.currentExercise?.id, "squat_sumo", "\(level)")
            let squat = try XCTUnwrap(reordered.deep.strengthJourney.chains.first { $0.pattern == .squat })
            XCTAssertEqual(squat.milestones.map(\.exerciseId), ["squat_wall_sit", "squat_bodyweight", "squat_sumo"], "\(level)")
            XCTAssertEqual(squat.milestones.map(\.firstReachedAt), [date(daysAgo: 84), date(daysAgo: 35), date(daysAgo: 70)],
                           "\(level): every rung keeps the date it was first reached")
            XCTAssertNil(squat.currentMilestone, "\(level): weeks on Bodyweight Squat are not weeks on Sumo Squat")
            XCTAssertFalse(squat.hasAdvanced, "\(level)")

            let returned = analytics(history + [workLog("squat_sumo", pattern: .squat, reps: 20, daysAgo: 0)])
            let returnedSquat = try XCTUnwrap(returned.deep.strengthJourney.chains.first { $0.pattern == .squat })
            XCTAssertEqual(returnedSquat.currentMilestone?.exerciseId, "squat_sumo", "\(level)")
            XCTAssertEqual(returnedSquat.currentMilestone?.firstReachedAt, date(daysAgo: 0), "\(level)")
            XCTAssertEqual(returnedSquat.startMilestone?.exerciseId, "squat_wall_sit", "\(level)")
        }
    }

    /// A session back on a rung the user reached earlier does not interrupt a real stall: an intermediate
    /// on Sumo Squat every week for ten weeks, with one Wall Sit session in between, is still current on
    /// Sumo Squat from the day they first reached it.
    func testASessionOnAnEarlierRungDoesNotHideARealStall() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("squat_wall_sit", pattern: .squat, seconds: 45, daysAgo: 77)]
            + [70, 63, 56, 49, 42, 35, 28, 21, 7, 1].map { workLog("squat_sumo", pattern: .squat, reps: 12, daysAgo: $0) }
            + [workLog("squat_wall_sit", pattern: .squat, seconds: 45, daysAgo: 14)]
        let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .intermediate, phase: .discipline, asOf: asOf, calendar: calendar)
        let squat = try XCTUnwrap(analytics.deep.strengthJourney.chains.first { $0.pattern == .squat })
        XCTAssertEqual(squat.currentMilestone?.exerciseId, "squat_sumo")
        XCTAssertEqual(squat.currentMilestone?.firstReachedAt, date(daysAgo: 70))
    }

    func testDeadBugUserKeepsItAsAnIntermediateAndMovesToBirdDogAsABeginner() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("core_bird_dog", pattern: .core, reps: 10, daysAgo: 6),
            workLog("core_dead_bug", pattern: .core, reps: 10, daysAgo: 2),
        ]
        XCTAssertEqual(selection(chain: "core_stability", level: .intermediate, logs: logs, library: library)?.exercise.id, "core_dead_bug")
        XCTAssertEqual(selection(chain: "core_stability", level: .beginner, logs: logs, library: library)?.exercise.id, "core_bird_dog")
        let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .discipline, asOf: asOf, calendar: calendar)
        XCTAssertEqual(analytics.chainPositions.first { $0.pattern == .core }?.currentExercise?.id, "core_bird_dog")
    }

    /// A user who trained crawls before the primal pillar retired is served no crawl at any level - no
    /// locomotion movement is offered at all - and the past session still counts toward their history.
    func testRetiredCrawlHistoryIsServedNoCrawlAndKeepsTheHistory() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 4),
            workLog("primal_bear_crawl", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 2),
        ]
        for level in FitnessLevel.allCases {
            XCTAssertNil(selection(.locomotion, level: level, logs: logs, library: library), "\(level): no crawl is served")
        }
        let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .discipline, asOf: asOf, calendar: calendar)
        XCTAssertEqual(analytics.pillarBalance.first { $0.pillar == .primal }?.exerciseCount, 2, "the past sessions still count")
    }

    /// A foundation cleared on a movement the user no longer gets stays cleared: Core on Hollow Hold, an
    /// advanced-only entry rung, and Squat on Wall Sit before the user moved on to Cossack Squat. Each was
    /// cleared the way the rep grammar clears a rung - four 60-second holds, the top of a beginner's range.
    func testClearedFoundationsStayClearedWhateverTheyWereClearedOn() async throws {
        let library = try await offeredLibrary()
        let logs = [
            try clearingLog("core_hollow_hold", in: library, level: .beginner, daysAgo: 4),
            try clearingLog("squat_wall_sit", in: library, level: .beginner, daysAgo: 3),
            workLog("squat_cossack", pattern: .squat, reps: 10, daysAgo: 2),
        ]
        let progress = PhaseEvaluator.progress(logs: logs, weeklyGoal: 3, library: library, level: .beginner, asOf: asOf, calendar: calendar)
        let core = try XCTUnwrap(progress.foundations.first { $0.foundation == .core })
        XCTAssertTrue(core.isCleared, "a foundation cleared on a movement the user no longer gets stays cleared")
        let legs = try XCTUnwrap(progress.foundations.first { $0.foundation == .legs })
        XCTAssertEqual(legs.lines.first { $0.line.pattern == .squat }?.isCleared, true)
    }

    // MARK: - Strength Phase lifts it for everyone

    func testEarningTheStrengthPhaseOpensEveryMovementAndTheMapUnlocksTheRungs() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("squat_bodyweight", pattern: .squat, reps: 20, daysAgo: 1)]
        let beginner = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .discipline, asOf: asOf, calendar: calendar)
        let earned = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .strength, asOf: asOf, calendar: calendar)
        let before = try XCTUnwrap(beginner.progressionMap.ladders.first { $0.pattern == .squat })
        let after = try XCTUnwrap(earned.progressionMap.ladders.first { $0.pattern == .squat })
        XCTAssertEqual(before.rungs.filter { !$0.isLocked }.map(\.exerciseId), ["squat_wall_sit", "squat_bodyweight"])
        XCTAssertTrue(after.rungs.allSatisfy { !$0.isLocked }, "every rung opens at once once Strength is earned")
    }

    /// An untrained line previews the lowest-id counting chain the user gets a rung of, preferring one
    /// that ends in a Strength-Phase skill. A beginner or intermediate user gets nothing on the Hollow
    /// chain, so their Core preview is Forearm Plank then Side Plank; an advanced user previews the Hollow
    /// chain up to the L-Sit.
    func testUntrainedCorePreviewIsThePlankChainForStapleUsersAndTheHollowChainForAdvanced() async throws {
        let library = try await offeredLibrary()
        for (level, expected) in [
            (FitnessLevel.beginner, ["core_forearm_plank", "core_side_plank"]),
            (.intermediate, ["core_forearm_plank", "core_side_plank"]),
            (.advanced, ["core_hollow_hold", "core_hollow_rock", "core_tuck_l_sit", "core_one_leg_l_sit", "core_l_sit"]),
        ] {
            let analytics = ProgressAnalytics.from(logs: [], library: library, level: level, phase: .discipline, asOf: asOf, calendar: calendar)
            let core = try XCTUnwrap(analytics.progressionMap.ladders.first { $0.pattern == .core })
            XCTAssertFalse(core.hasStarted)
            XCTAssertEqual(core.rungs.map(\.exerciseId), expected, "\(level)")
        }
    }

    // MARK: - The one-time note

    @MainActor
    private func readyViewModel(for user: User) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: OnDeviceWorkoutEngine(exerciseService: try! MockExerciseService()),
            workoutLogService: MockWorkoutLogService(logs: [])
        )
    }

    @MainActor
    func testTheNoteIsEligibleOnlyForRestrictedDisciplineUsers() async throws {
        for (level, phase, expected) in [
            (FitnessLevel.beginner, Phase.discipline, true),
            (.intermediate, .discipline, true),
            (.advanced, .discipline, false),
            (.beginner, .strength, false),
            (.intermediate, .strength, false),
            (.advanced, .strength, false),
        ] {
            let viewModel = readyViewModel(for: user(level: level, phase: phase))
            await viewModel.load()
            XCTAssertEqual(viewModel.isClassicsUpdateNoteEligible, expected, "\(level)/\(phase)")
        }
        XCTAssertFalse(readyViewModel(for: user(level: .beginner)).isClassicsUpdateNoteEligible, "nothing is eligible before the user loads")
    }

    func testTheNoteUsesTheCaptainsCopyVerbatim() {
        XCTAssertEqual(
            ClassicsUpdateNoteCopy.full,
            "Your sessions now focus on the classics. More movements unlock when you earn the Strength Phase."
        )
    }

    func testTheNoteFlagGatesEachAudience() {
        // An install that predates the change: onboarded, never passed through onboarding on this build.
        let suite = "StapleMovementsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "AppState.isOnboarded")
        let existing = AppState(userDefaults: defaults)
        XCTAssertTrue(existing.shouldShowClassicsUpdateNote, "an install that predates the change is owed the note")
        existing.markClassicsUpdateNoteSeen()
        existing.markClassicsUpdateNoteSeen()
        XCTAssertFalse(existing.shouldShowClassicsUpdateNote, "once shown it is never shown again")
        XCTAssertFalse(AppState(userDefaults: defaults).shouldShowClassicsUpdateNote, "and it stays retired on relaunch")

        // A brand-new install: finishing onboarding marks it seen, so it never reaches them.
        let freshSuite = "StapleMovementsTests.fresh.\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuite)!
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
        let fresh = AppState(userDefaults: freshDefaults)
        XCTAssertTrue(fresh.shouldShowClassicsUpdateNote)
        fresh.isOnboarded = true
        XCTAssertFalse(fresh.shouldShowClassicsUpdateNote, "onboarding on this build never shows a brand-new user the note")
        XCTAssertFalse(AppState(userDefaults: freshDefaults).shouldShowClassicsUpdateNote)
    }
}
