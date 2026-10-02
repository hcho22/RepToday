import XCTest
@testable import RepToday

/// ADR-0007: beginner and intermediate users get staple movements only while in the Discipline Phase,
/// advanced users keep today's variety, the Strength Phase opens everything, and three crawls are
/// withdrawn until version 2.
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
        "primal_bear_crawl",
    ]
    /// Training staples for intermediate users only.
    private let intermediateTraining: Set<String> = [
        "push_diamond", "pull_floor_row", "squat_sumo", "lunge_split_squat",
        "hinge_bridge_march", "hinge_single_leg_rdl", "core_side_plank", "core_dead_bug",
        "primal_crab_walk",
    ]
    /// Training movements for advanced users only (Strength-Phase skills excluded).
    private let advancedTraining: Set<String> = [
        "push_pike", "push_archer",
        "pull_reverse_snow_angel", "pull_ytw", "pull_floor_row_single_arm",
        "squat_cossack", "squat_shrimp",
        "hinge_long_lever_bridge",
        "core_bear_hold", "core_hollow_hold", "core_hollow_rock", "core_tuck_l_sit",
        "primal_ground_to_standing", "primal_bear_shoulder_tap",
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
    /// Withdrawn from the app for everyone until version 2.
    private let withdrawn: Set<String> = ["primal_gorilla_walk", "primal_lizard_crawl", "primal_underswitch"]

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
                primaryGoal: .stayActive, sitsLong: false, injuries: injuries, typicalAvailableMinutes: 15
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

    // MARK: - Pool contents

    func testCatalogPartitionsIntoTheDecidedLists() async throws {
        let all = try fullFileLibrary()
        let partition = [beginnerTraining, intermediateTraining, advancedTraining, strengthPhaseMovements,
                         stapleStretches, advancedStretches, withdrawn]
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
            else if withdrawn.contains(exercise.id) { expected = .version2 }
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
        XCTAssertEqual(count(.beginner, training: true), 16)
        XCTAssertEqual(count(.beginner, training: false), 16)
        XCTAssertEqual(count(.intermediate, training: true), 25)
        XCTAssertEqual(count(.intermediate, training: false), 16)
        XCTAssertEqual(count(.advanced, training: true), 39)
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

    // MARK: - Version 2 withdrawals

    func testWithdrawnCrawlsAreKeptForVersionTwoButNeverServedByTheCatalogService() async throws {
        let service = try MockExerciseService()
        let offered = ids(try await service.exercises())
        XCTAssertTrue(offered.isDisjoint(with: withdrawn), "the service never serves a withdrawn movement")
        XCTAssertEqual(offered.count, 73)
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
        // Recoverable: the whole chain is still in the file and the service can hand it back for version 2.
        let archived = try await service.withdrawnExercises()
        XCTAssertEqual(ids(archived), withdrawn)
        XCTAssertEqual(archived.map(\.progressionChainId), Array(repeating: "primal_ground_flow", count: 3))
    }

    func testWithdrawnCrawlsNeverAppearInAnySessionForAnyUser() throws {
        let library = try fullFileLibrary() // withdrawn movements deliberately present
        XCTAssertTrue(ids(library).isSuperset(of: withdrawn))
        // A history that has worked every withdrawn crawl, the strongest pull toward re-serving them.
        let logs = [
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 5),
            workLog("primal_lizard_crawl", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 4),
            workLog("primal_underswitch", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 3),
        ]
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                for minutes in [5, 10, 15, 20, 30, 45, 60] {
                    for history in [[], logs] {
                        let workout = SessionAssembly.assemble(
                            requestedMinutes: minutes, user: user(level: level, phase: phase), library: library,
                            recentLogs: history, asOf: asOf, calendar: calendar
                        )
                        let served = Set(workout.blocks.flatMap(\.exercises).map(\.exercise.id))
                        XCTAssertTrue(
                            served.isDisjoint(with: withdrawn),
                            "\(level)/\(phase)/\(minutes) min served a withdrawn crawl: \(served.intersection(withdrawn))"
                        )
                    }
                }
            }
        }
    }

    func testWithdrawnCrawlsAreNeverASwapSubstitute() throws {
        let library = try fullFileLibrary()
        let advanced = user(level: .advanced, phase: .strength)
        let workout = SessionAssembly.assemble(
            requestedMinutes: 60, user: advanced, library: library, recentLogs: [], asOf: asOf, calendar: calendar
        )
        for block in workout.blocks {
            for slot in block.exercises {
                if case .substituted(let replacement) = ExerciseSwap.swap(
                    slot, in: workout, user: advanced, library: library, recentLogs: []
                ) {
                    XCTAssertFalse(withdrawn.contains(replacement.exercise.id), "swap handed back a withdrawn crawl")
                }
            }
        }
    }

    func testWithdrawnCrawlLogsStillCountInHistoryButNothingNamesThem() async throws {
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
            XCTAssertEqual(primal?.exerciseCount, 2, "past crawl work still counts toward pillar balance")
            XCTAssertEqual(analytics.deep.patternBalance.first { $0.pattern == .locomotion }?.exerciseCount, 2)
            XCTAssertEqual(analytics.deep.weeklyVolume.reduce(0) { $0 + $1.sessionCount }, 3)

            // Nothing names a withdrawn movement.
            let named = analytics.progressionMap.ladders.flatMap { $0.rungs.map(\.exerciseId) }
                + analytics.chainPositions.compactMap { $0.currentExercise?.id }
                + analytics.deep.strengthJourney.chains.flatMap { $0.milestones.map(\.exerciseId) }
                + [analytics.personalBests.bestReps?.exerciseId, analytics.personalBests.bestHold?.exerciseId].compactMap { $0 }
            XCTAssertTrue(Set(named).isDisjoint(with: withdrawn), "\(level): a surface named a withdrawn crawl")
            XCTAssertEqual(analytics.personalBests.bestReps?.exerciseId, "push_standard")

            // And the Coach's derived bundle, built from those same values, is clean as well.
            let bundle = CoachContextBundle.make(
                phase: .discipline, requestedMinutes: 15, chainPositions: analytics.chainPositions,
                consistencyTrend: [], recentLogs: logs, strengthJourney: analytics.deep.strengthJourney,
                asOf: asOf, calendar: calendar
            )
            let encoded = String(data: try JSONEncoder().encode(bundle), encoding: .utf8)?.lowercased() ?? ""
            for term in ["gorilla", "lizard", "underswitch"] {
                XCTAssertFalse(encoded.contains(term), "\(level): the Coach bundle names \(term)")
            }
        }
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
        let cleared: [(String, MovementPattern, Bool, Int)] = [
            ("push_wall", .push, false, 15),
            ("pull_wall_scapular_pull", .pull, false, 12),
            ("squat_wall_sit", .squat, true, 45),
            ("hinge_glute_bridge", .hinge, false, 20),
            ("core_forearm_plank", .core, true, 45),
        ]
        for (id, _, _, _) in cleared {
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
        let clearing = cleared.map { id, pattern, isHold, value in
            workLog(id, pattern: pattern, reps: isHold ? nil : value, seconds: isHold ? value : nil, daysAgo: 0)
        }
        let progress = PhaseEvaluator.progress(logs: showUps + clearing, weeklyGoal: 3, library: library, asOf: asOf, calendar: calendar)
        XCTAssertTrue(progress.foundations.allSatisfy(\.isCleared), "every foundation clears from staples alone")
        XCTAssertTrue(progress.hasEarnedStrength)
    }

    // MARK: - Sessions fit, stay even, and stay inside 2-4 rounds

    func testSessionsAtEveryLengthAndLevelFitStayEvenAndInsideTheRoundCap() async throws {
        let library = try await offeredLibrary()
        for level in FitnessLevel.allCases {
            for minutes in [5, 10, 15, 20, 30, 45, 60] {
                let workout = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: [], asOf: asOf, calendar: calendar
                )
                let planned = SessionAssembly.plannedSeconds(of: workout)
                XCTAssertLessThanOrEqual(
                    abs(planned - minutes * 60), SessionAssembly.toleranceSeconds,
                    "\(level) \(minutes) min planned \(planned)s, outside the +/-\(SessionAssembly.toleranceSeconds)s tolerance"
                )
                for block in workout.blocks where SessionAssembly.isCircuit(block.category) {
                    XCTAssertEqual(Set(block.exercises.map(\.sets)).count, 1, "\(level) \(minutes) min: \(block.title) is uneven")
                    for slot in block.exercises {
                        XCTAssertTrue((2...4).contains(slot.sets), "\(level) \(minutes) min: \(slot.exercise.id) at \(slot.sets) rounds")
                    }
                }
                for slot in workout.blocks.flatMap(\.exercises) {
                    XCTAssertTrue(
                        MovementAccess.isAvailable(slot.exercise, level: level, phase: .discipline),
                        "\(level) \(minutes) min served \(slot.exercise.id), which that level does not get"
                    )
                }
            }
        }
    }

    /// With the Gorilla Walk chain gone the primal block has one chain, and for a beginner one movement
    /// (Bear Crawl). The session must still land inside the tolerance with strength absorbing the leftover.
    func testBeginnerExtendedSessionWithBearCrawlOnlyLandsInsideTheTolerance() async throws {
        let library = try await offeredLibrary()
        for minutes in [45, 60] {
            let workout = SessionAssembly.assemble(
                requestedMinutes: minutes, user: user(level: .beginner), library: library,
                recentLogs: [], asOf: asOf, calendar: calendar
            )
            let primal = try XCTUnwrap(workout.blocks.first { $0.category == .primal }, "\(minutes) min is an extended blend with a primal block")
            XCTAssertEqual(primal.exercises.map(\.exercise.id), ["primal_bear_crawl"], "a beginner's primal block is Bear Crawl alone")
            let planned = SessionAssembly.plannedSeconds(of: workout)
            XCTAssertLessThanOrEqual(abs(planned - minutes * 60), SessionAssembly.toleranceSeconds, "\(minutes) min planned \(planned)s")
            let strength = try XCTUnwrap(workout.blocks.first { $0.category == .strength })
            XCTAssertGreaterThan(
                SessionAssembly.blockSeconds(of: strength), SessionAssembly.blockSeconds(of: primal),
                "strength absorbs the time the single-station primal block cannot"
            )
        }
    }

    func testSessionsFitForUsersWhoseHistorySitsOnMovementsTheyNoLongerGet() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("squat_cossack", pattern: .squat, reps: 10, daysAgo: 6),
            workLog("core_hollow_hold", pattern: .core, seconds: 30, daysAgo: 5),
            workLog("push_archer", pattern: .push, reps: 8, daysAgo: 4),
            workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 3),
        ]
        for level in [FitnessLevel.beginner, .intermediate] {
            for minutes in [5, 10, 15, 20, 30, 45, 60] {
                let workout = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: logs, asOf: asOf, calendar: calendar
                )
                XCTAssertLessThanOrEqual(
                    abs(SessionAssembly.plannedSeconds(of: workout) - minutes * 60), SessionAssembly.toleranceSeconds
                )
                XCTAssertTrue(workout.blocks.flatMap(\.exercises).allSatisfy {
                    MovementAccess.isAvailable($0.exercise, level: level, phase: .discipline)
                })
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
            for minutes in [10, 20, 45, 60] {
                let workout = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: [], asOf: asOf, calendar: calendar
                )
                let stretches = workout.blocks.filter { $0.category == .warmup || $0.category == .cooldown }
                    .flatMap(\.exercises).map(\.exercise.id)
                XCTAssertFalse(stretches.isEmpty)
                XCTAssertTrue(Set(stretches).isSubset(of: stapleStretches), "\(level) \(minutes) min: \(Set(stretches).subtracting(stapleStretches))")
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
            recentLogs: logs
        )
    }

    /// What Step 5 serves a user of `level` for a whole pattern (every chain ranked, best first).
    private func selection(
        _ pattern: MovementPattern, level: FitnessLevel, logs: [WorkoutLog], library: [Exercise]
    ) -> ChainSelection? {
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user(level: level), recentLogs: logs)
        return ProgressionChainSelection.select(pattern: pattern, library: library, pool: pool, recentLogs: logs)
    }

    func testCossackSquatUserMovesToTheClosestSquatTheyGet() async throws {
        let library = try await offeredLibrary()
        let logs = [
            workLog("squat_bodyweight", pattern: .squat, reps: 20, daysAgo: 8),
            workLog("squat_cossack", pattern: .squat, reps: 4, daysAgo: 1), // below its criteria: still on it
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

    func testGorillaWalkUserIsServedTheRemainingCrawlChainAndKeepsTheHistory() async throws {
        let library = try await offeredLibrary()
        let logs = [workLog("primal_gorilla_walk", pillar: .primal, pattern: .locomotion, reps: 20, daysAgo: 2)]
        for level in FitnessLevel.allCases {
            let chosen = selection(.locomotion, level: level, logs: logs, library: library)
            XCTAssertEqual(chosen?.exercise.id, "primal_bear_crawl", "\(level): the crawl they get is Bear Crawl")
            XCTAssertEqual(chosen?.chainId, "primal_locomotion")
        }
        let analytics = ProgressAnalytics.from(logs: logs, library: library, level: .beginner, phase: .discipline, asOf: asOf, calendar: calendar)
        XCTAssertEqual(analytics.pillarBalance.first { $0.pillar == .primal }?.exerciseCount, 1, "the past session still counts")
    }

    func testClearedFoundationsStayClearedWhateverTheyWereClearedOn() async throws {
        let library = try await offeredLibrary()
        // Core was cleared on Hollow Hold, an advanced-only entry rung; Squat on Wall Sit, then Cossack.
        let logs = [
            workLog("core_hollow_hold", pattern: .core, seconds: 45, daysAgo: 4),
            workLog("squat_wall_sit", pattern: .squat, seconds: 45, daysAgo: 3),
            workLog("squat_cossack", pattern: .squat, reps: 10, daysAgo: 2),
        ]
        let progress = PhaseEvaluator.progress(logs: logs, weeklyGoal: 3, library: library, asOf: asOf, calendar: calendar)
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

    // MARK: - The one-time note

    private func readyViewModel(for user: User) -> ReadyViewModel {
        ReadyViewModel(
            userService: MockUserService(user: user),
            sessionPolicyService: MockSessionPolicyService(),
            workoutEngine: MockWorkoutEngine(exerciseService: try! MockExerciseService()),
            workoutLogService: MockWorkoutLogService(logs: [])
        )
    }

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
