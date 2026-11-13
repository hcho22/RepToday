import XCTest
@testable import RepToday

/// Tests pipeline Step 7 of the deterministic engine: assembling a Training Day into a complete,
/// timing-fit `Workout` (`SessionAssembly`, ADR-0012/ADR-0013).
///
/// Run end-to-end over the real bundled library so the whole pipeline is exercised: every session opens
/// with a warm-up and closes with a cooldown past 10 minutes; the bookends are length-scaled; the planned
/// wall-clock lands within `toleranceSeconds` of the request or runs honestly short; generation is under
/// 100ms; the output is fully formed and capacity-relative; the Session Policy, cold-start and Return
/// overrides reach the session; and assembly is deterministic. `TrainingDaySessionTests` owns the slot
/// plan inside the circuit; `TrainingDayFitHarnessTests` the full fit matrix.
final class SessionAssemblyTests: XCTestCase {

    // MARK: - Fixtures

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        sitsLong: Bool = false,
        injuries: [String] = []
    ) -> User {
        TrainingDayFixtures.user(level: level, phase: phase, injuries: injuries, sitsLong: sitsLong)
    }

    private func assemble(
        minutes: Int,
        user: User? = nil,
        logs: [WorkoutLog] = [],
        policy: SessionPolicy = .default,
        day: TrainingDay? = nil
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user ?? self.user(),
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    /// A few days of Training Day history: Push and Pull completed, so the Rotation serves Legs, and a
    /// stretch used, so the bookends read variety.
    private func someHistory() -> [WorkoutLog] {
        [
            TrainingDayFixtures.log([
                TrainingDayFixtures.station("push_standard", pattern: .push, value: 20, earned: 20),
                TrainingDayFixtures.station("core_forearm_plank", pattern: .core, role: .core, value: 30, earned: 30, isHold: true),
                TrainingDayFixtures.station("mobility_cat_cow", pattern: .mobility, pillar: .mobility, role: nil, value: 10, sets: 1),
            ], completedAt: TrainingDayFixtures.date(daysAgo: 3)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 2)),
        ]
    }

    /// `workout` completed as prescribed, logged the way the player writes it: every station with its
    /// role and the Earned Reps it was served from, each set at the served number.
    private func logged(
        _ workout: Workout,
        at date: Date,
        difficulty: PerceivedDifficulty? = .justRight,
        wasReturn: Bool = false
    ) -> WorkoutLog {
        var log = TrainingDayFixtures.log(
            workout.blocks.flatMap(\.exercises).map { item in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: item.exercise.id,
                    pillar: item.exercise.pillar,
                    movementPattern: item.exercise.movementPattern,
                    completedSets: Array(repeating: CompletedSet(reps: item.reps, durationSeconds: item.durationSeconds), count: item.sets),
                    skipped: false,
                    role: item.role,
                    earnedReps: item.earnedReps,
                    earnedDurationSeconds: item.earnedDurationSeconds
                )
            },
            completedAt: date,
            difficulty: difficulty,
            requestedMinutes: workout.requestedMinutes
        )
        log.wasReturn = wasReturn
        return log
    }

    private func circuit(_ workout: Workout) -> [PrescribedExercise] {
        workout.blocks.filter { $0.category == .strength }.flatMap(\.exercises)
    }

    /// The session lands within `toleranceSeconds` of `minutes`, or runs short only because the same plan,
    /// re-fit, has no lever left (`isSaturated`) - an honest shortfall. It never overruns.
    private func assertFillsOrRunsHonestlyShort(
        _ workout: Workout,
        minutes: Int,
        user: User,
        logs: [WorkoutLog],
        policy: SessionPolicy = .default,
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
            user: user,
            library: library,
            recentLogs: logs,
            sessionPolicy: policy,
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
        SessionAssembly.fit(&plan, targetSeconds: minutes * 60)
        XCTAssertTrue(plan.isSaturated, "\(label): runs \(-gap)s short with fit levers left", file: file, line: line)
    }

    /// A run-to-run-stable description of a workout's content (ids vary by design).
    private func structuralSignature(_ workout: Workout) -> String {
        workout.blocks.map { block in
            let items = block.exercises.map { p in
                "\(p.exercise.id):\(p.sets):\(p.reps.map(String.init) ?? "-"):\(p.durationSeconds.map(String.init) ?? "-"):\(p.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)p\(block.transitionSeconds ?? 0)[\(items)]"
        }.joined(separator: "|")
    }

    // MARK: - Warm-up always opens the session

    func testEverySessionOpensWithAWarmUp() throws {
        for day in TrainingDay.rotation {
            for minutes in lengths {
                let workout = assemble(minutes: minutes, logs: someHistory(), day: day)
                let first = try XCTUnwrap(workout.blocks.first, "\(day) \(minutes) min produced no blocks")
                XCTAssertEqual(first.category, .warmup, "\(day) \(minutes) min must open with a warm-up")
                XCTAssertFalse(first.exercises.isEmpty, "\(day) \(minutes) min warm-up must have an exercise")
            }
        }
    }

    /// The originally-reported failure profile - a fresh desk worker - gets a strength circuit at 5 and 10
    /// minutes: a mobility warm-up, then the day's circuit, and no mobility movement outside the warm-up.
    func testShortSessionsTrainStrengthForAFreshDeskWorker() throws {
        for day in TrainingDay.rotation {
            for minutes in [5, 10] {
                let workout = assemble(minutes: minutes, user: user(sitsLong: true), day: day)
                let label = "\(day) \(minutes) min"
                XCTAssertEqual(workout.focusPillar, .strength, label)
                XCTAssertEqual(workout.blocks.map(\.category), [.warmup, .strength], label)
                let warmup = try XCTUnwrap(workout.blocks.first)
                XCTAssertTrue(warmup.exercises.allSatisfy { $0.exercise.pillar == .mobility }, label)
                XCTAssertFalse(circuit(workout).isEmpty, label)
                XCTAssertFalse(circuit(workout).contains { $0.exercise.pillar == .mobility }, label)
            }
        }
    }

    // MARK: - Bookends scale with session length

    /// The warm-up is seeded at the length-scaled count, every one a distinct one-set stretch.
    func testWarmUpIsSeededAtTheLengthScaledCount() throws {
        for minutes in lengths {
            let workout = assemble(minutes: minutes, logs: someHistory())
            let warmup = try XCTUnwrap(workout.blocks.first)
            XCTAssertEqual(warmup.category, .warmup)
            XCTAssertEqual(warmup.exercises.count, SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes), "\(minutes) min")
            XCTAssertTrue(warmup.exercises.allSatisfy { $0.sets == 1 }, "\(minutes) min: warm-up is one set each")
            XCTAssertEqual(Set(warmup.exercises.map(\.exercise.id)).count, warmup.exercises.count, "\(minutes) min: distinct")
            XCTAssertTrue(warmup.exercises.allSatisfy { $0.exercise.pillar == .mobility }, "\(minutes) min: mobility")
        }
    }

    /// The length bands themselves (decision 7, ADR-0018), bound to literals so a drifted boundary fails
    /// here: warm-up 1 stretch up to 10 minutes and 2 beyond; cooldown none up to 10, 1 at 15-20, 2 from
    /// 30; main slots 1 at 5, 2 at 10-15, 3 at 20-30, 4 at 45, 5 at 60; Core Sprinkles none up to 10, 1 at
    /// 15-30, 2 at 45-60, and one more with Abs wherever core appears.
    func testLengthBandsAreLeanAndLengthScaled() {
        let warmup = [5: 1, 10: 1, 15: 2, 20: 2, 30: 2, 45: 2, 60: 2]
        let cooldown = [5: 0, 10: 0, 15: 1, 20: 1, 30: 2, 45: 2, 60: 2]
        let mains = [5: 1, 10: 2, 15: 2, 20: 3, 30: 3, 45: 4, 60: 5]
        let core = [5: 0, 10: 0, 15: 1, 20: 1, 30: 1, 45: 2, 60: 2]
        let coreWithAbs = [5: 0, 10: 0, 15: 2, 20: 2, 30: 2, 45: 3, 60: 3]
        for minutes in lengths {
            XCTAssertEqual(SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes), warmup[minutes], "\(minutes)")
            XCTAssertEqual(SessionAssembly.cooldownExerciseCount(forRequestedMinutes: minutes), cooldown[minutes], "\(minutes)")
            XCTAssertEqual(SessionAssembly.mainSlotCount(forRequestedMinutes: minutes), mains[minutes], "\(minutes)")
            XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: minutes), core[minutes], "\(minutes)")
            XCTAssertEqual(SessionAssembly.coreSprinkleCount(forRequestedMinutes: minutes, focusAreas: [.abs]), coreWithAbs[minutes], "\(minutes)")
        }
        XCTAssertEqual(SessionAssembly.maxWarmupExercises, 2)
        XCTAssertEqual(SessionAssembly.maxCooldownExercises, 2)
    }

    /// Even the fullest bookends - a 60-minute session's two warm-up and two cooldown stretches - never
    /// reuse a stretch and leave day-to-day variety headroom in the mobility pool.
    func testFullBookendsDoNotStarveTheMobilityPool() throws {
        let mobilityTotal = library.filter { $0.pillar == .mobility }.count
        for day in TrainingDay.rotation {
            let workout = assemble(minutes: 60, logs: someHistory(), day: day)
            let cooldown = try XCTUnwrap(workout.blocks.first { $0.category == .cooldown }, "\(day): 60 min has a cooldown")
            XCTAssertEqual(cooldown.exercises.count, 2, "\(day)")
            let mobilityIds = workout.blocks.flatMap(\.exercises).filter { $0.exercise.pillar == .mobility }.map(\.exercise.id)
            XCTAssertEqual(Set(mobilityIds).count, mobilityIds.count, "\(day): a stretch is reused across bookends")
            XCTAssertGreaterThanOrEqual(mobilityTotal - mobilityIds.count, 2, "\(day): no variety headroom left")
        }
    }

    // MARK: - Cooldown only past 10 minutes

    func testCooldownPresentOnlyWhenOverTenMinutes() {
        for minutes in lengths {
            let workout = assemble(minutes: minutes, logs: someHistory())
            let hasCooldown = workout.blocks.contains { $0.category == .cooldown }
            if minutes > 10 {
                XCTAssertTrue(hasCooldown, "\(minutes) min should end with a cooldown")
                XCTAssertEqual(workout.blocks.last?.category, .cooldown, "\(minutes) min cooldown must be last")
            } else {
                XCTAssertFalse(hasCooldown, "\(minutes) min should not have a cooldown")
            }
        }
    }

    /// The cooldown is static holds: on every day and length that carries one, every cooldown stretch is
    /// a hold.
    func testCooldownIsStaticHolds() {
        for day in TrainingDay.rotation {
            for minutes in [15, 20, 30, 45, 60] {
                let cooldown = assemble(minutes: minutes, logs: someHistory(), day: day)
                    .blocks.first { $0.category == .cooldown }?.exercises ?? []
                XCTAssertFalse(cooldown.isEmpty, "\(day) \(minutes) min")
                XCTAssertTrue(cooldown.allSatisfy { $0.exercise.isHold }, "\(day) \(minutes) min: \(cooldown.map(\.exercise.id))")
            }
        }
    }

    // MARK: - Timing fit

    /// A session that would still run past the tolerance with every rep at the short-session floor drops
    /// a station and runs short instead (ADR-0018): a cold-start intermediate's 15-minute Pull Day with
    /// Abs gives up the Abs extra Core Sprinkle, keeping its two main slots and the base Core Sprinkle.
    func testAnOverlongSessionDropsTheAbsExtraCoreSprinkleFirst() {
        var coldStart = TrainingDayFixtures.user(level: .intermediate, focusAreas: [.abs])
        coldStart.coldStart = User.ColdStart(sessionsLogged: 0, active: true)
        var plan = SessionAssembly.planSession(
            requestedMinutes: 15, user: coldStart, library: library, recentLogs: [],
            sessionPolicy: .seeded(forFitnessLevel: .intermediate), trainingDay: .pull,
            asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar
        )
        XCTAssertEqual(plan.stations.filter { $0.role == .core }.count, 2, "Abs asks for two Core Sprinkles at 15 minutes")
        let before = plan.stations.map(\.exercise.id)
        SessionAssembly.fit(&plan, targetSeconds: 15 * 60)
        XCTAssertLessThanOrEqual(plan.totalSeconds - 15 * 60, SessionAssembly.toleranceSeconds)
        XCTAssertEqual(plan.stations.filter { $0.role == .core }.count, 1)
        XCTAssertEqual(plan.stations.filter { $0.role != .core }.count, 2)
        XCTAssertEqual(plan.stations.map(\.exercise.id), Array(before.dropLast()), "the last-added Core Sprinkle goes")
    }

    /// With no Abs extra to give up, the drop takes the Core Sprinkles a length has no room for and then
    /// the last main slot, one at a time, never the first main station: a 60-minute Legs Day squeezed
    /// into 10 minutes keeps a prefix of its main slots.
    func testAnOverlongSessionDropsTheLastMainSlotsAndNeverTheFirst() throws {
        var plan = SessionAssembly.planSession(
            requestedMinutes: 60, user: user(level: .beginner), library: library, recentLogs: [], trainingDay: .legs,
            asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar
        )
        let mains = plan.stations.filter { $0.role != .core }.map(\.exercise.id)
        XCTAssertEqual(mains.count, 5)
        SessionAssembly.fit(&plan, targetSeconds: 10 * 60)
        XCTAssertLessThanOrEqual(plan.totalSeconds - 10 * 60, SessionAssembly.toleranceSeconds)
        XCTAssertFalse(plan.stations.contains { $0.role == .core })
        let kept = plan.stations.map(\.exercise.id)
        XCTAssertFalse(kept.isEmpty)
        XCTAssertEqual(kept, Array(mains.prefix(kept.count)), "main slots go from the last one")
    }


    /// Every length, Training Day and history - with and without the desk-worker bias - lands within the
    /// tolerance of the request, or runs honestly short.
    func testEveryLengthFillsWithinToleranceOrRunsHonestlyShort() {
        for (name, logs) in [("history", someHistory()), ("fresh", [WorkoutLog]())] {
            for sitsLong in [false, true] {
                let person = user(sitsLong: sitsLong)
                for day in TrainingDay.rotation {
                    for minutes in lengths {
                        let workout = assemble(minutes: minutes, user: person, logs: logs, day: day)
                        assertFillsOrRunsHonestlyShort(
                            workout, minutes: minutes, user: person, logs: logs,
                            "\(name) sitsLong=\(sitsLong) \(day) \(minutes) min"
                        )
                    }
                }
            }
        }
    }

    /// A long-tenured user whose holds have grown far past the range: every hold is served at most the
    /// top of the level's range (per side, for a per-side hold), and the session still fits.
    func testTimingFitHoldsForCapacityGrownHolds() {
        let holds = library.filter { $0.isHold && $0.pillar == .strength }
        XCTAssertTrue(holds.contains { $0.sidesPerSet > 1 }, "the catalog must carry per-side holds for this to test anything")
        let grown = TrainingDayFixtures.log(
            holds.map { TrainingDayFixtures.station($0.id, pattern: $0.movementPattern, value: 300, earned: 300, isHold: true) },
            completedAt: TrainingDayFixtures.date(daysAgo: 2),
            difficulty: .tooEasy
        )
        for level in FitnessLevel.allCases {
            let person = user(level: level)
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = assemble(minutes: minutes, user: person, logs: [grown], day: day)
                    for item in circuit(workout) where item.exercise.isHold {
                        let seconds = item.durationSeconds ?? 0
                        XCTAssertLessThanOrEqual(
                            seconds, RepGrammar.earnedRange(for: item.exercise, level: level).upperBound,
                            "\(level) \(day) \(minutes) min: \(item.exercise.id) held \(seconds)s per side, past the top of the range"
                        )
                    }
                    assertFillsOrRunsHonestlyShort(workout, minutes: minutes, user: person, logs: [grown], "\(level) \(day) \(minutes) min")
                }
            }
        }
    }

    // MARK: - Sets and rests

    /// Every circuit station runs four sets with one shared rest after a round, at most the round-rest cap
    /// for the length and level; every stretch is one set with the bookend rest.
    func testCircuitStationsShareFourSetsAndOneRoundRest() {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = assemble(minutes: minutes, user: user(level: level), logs: someHistory(), day: day)
                    let label = "\(level) \(day) \(minutes) min"
                    for block in workout.blocks {
                        if SessionAssembly.isCircuit(block.category) {
                            XCTAssertTrue(block.exercises.allSatisfy { $0.sets == RepGrammar.setsPerStation }, label)
                            let rests = Set(block.exercises.map(\.restSeconds))
                            XCTAssertEqual(rests.count, 1, "\(label): round rest \(rests.sorted())")
                            XCTAssertLessThanOrEqual(
                                rests.first ?? 0, SessionAssembly.roundRestCap(for: level, requestedMinutes: minutes), label
                            )
                            XCTAssertGreaterThanOrEqual(rests.first ?? 0, SessionAssembly.baseRoundRestSeconds, label)
                        } else {
                            XCTAssertTrue(block.exercises.allSatisfy { $0.sets == 1 && $0.restSeconds == SessionAssembly.mobilityRestSeconds }, label)
                        }
                    }
                }
            }
        }
    }

    /// The rest rails (decision 17): the rest after a round starts at 15 seconds and grows to 60 on a
    /// session of 30 minutes or less, or to the level cap (beginner 2:00, intermediate 1:30, advanced 1:00)
    /// on a 45 or 60 minute one; the pause between stations is 15 seconds and grows to at most 60; no rest
    /// the player opens runs past two minutes.
    func testRestRailsFollowLengthAndLevel() {
        XCTAssertEqual(SessionAssembly.baseRoundRestSeconds, 15)
        XCTAssertEqual(SessionAssembly.transitionSeconds, 15)
        XCTAssertEqual(SessionAssembly.maxTransitionSeconds, 60)
        XCTAssertEqual(SessionAssembly.maxRestSeconds, 120)
        XCTAssertLessThanOrEqual(SessionAssembly.mobilityRestSeconds, SessionAssembly.maxRestSeconds)
        for minutes in [5, 10, 15, 20, 30] {
            for level in FitnessLevel.allCases {
                XCTAssertEqual(SessionAssembly.roundRestCap(for: level, requestedMinutes: minutes), 60, "\(level) \(minutes)")
            }
        }
        for minutes in [45, 60] {
            XCTAssertEqual(SessionAssembly.roundRestCap(for: .beginner, requestedMinutes: minutes), 120)
            XCTAssertEqual(SessionAssembly.roundRestCap(for: .intermediate, requestedMinutes: minutes), 90)
            XCTAssertEqual(SessionAssembly.roundRestCap(for: .advanced, requestedMinutes: minutes), 60)
        }
        XCTAssertLessThanOrEqual(SessionAssembly.roundRestCap(for: .beginner, requestedMinutes: 60), SessionAssembly.maxRestSeconds)
    }

    /// A long session fills by reps and rest, never by more sets: at 45 and 60 minutes a fresh user's
    /// circuit keeps four sets per station while its reps are padded above where they started, or the rest
    /// after a round or the pause between stations grows past its 15-second start. (With four or five main
    /// movements an advanced user's wide range can fill a 45-minute session by reps alone, ADR-0018.)
    func testLongSessionsFillWithRestNotSets() throws {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in [45, 60] {
                    let workout = assemble(minutes: minutes, user: user(level: level), day: day)
                    let block = try XCTUnwrap(workout.blocks.first { $0.category == .strength })
                    let label = "\(level) \(day) \(minutes) min"
                    XCTAssertTrue(block.exercises.allSatisfy { $0.sets == RepGrammar.setsPerStation }, label)
                    let rest = block.exercises[0].restSeconds
                    let pause = block.transitionSeconds ?? SessionAssembly.transitionSeconds
                    let padded = block.exercises.contains { item in
                        guard let earned = item.earnedReps ?? item.earnedDurationSeconds else { return false }
                        return (item.reps ?? item.durationSeconds ?? 0) > earned
                    }
                    XCTAssertTrue(
                        padded || rest > SessionAssembly.baseRoundRestSeconds || pause > SessionAssembly.transitionSeconds,
                        "\(label): rest \(rest)s, pause \(pause)s - the fit padded no reps and grew neither"
                    )
                }
            }
        }
    }

    // MARK: - Latency under 100ms

    func testGenerationLatencyUnder100ms() {
        let logs = someHistory()
        _ = assemble(minutes: 60, logs: logs)
        let start = DispatchTime.now()
        _ = assemble(minutes: 60, logs: logs)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }

    // MARK: - Fully-formed, playable output

    /// Every prescription is playable and capacity-relative: a hold carries seconds and a rep movement
    /// reps; a main or core station is served between the short-session floor and the top of the level's
    /// range; a Practice station at its Practice value; a stretch at its bookend value; all zero-equipment.
    func testOutputIsFullyFormedAndCapacityRelative() {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let workout = assemble(minutes: minutes, user: user(level: level), logs: someHistory(), day: day)
                    let label = "\(level) \(day) \(minutes) min"
                    XCTAssertEqual(workout.requestedMinutes, minutes)
                    for block in workout.blocks {
                        XCTAssertFalse(block.exercises.isEmpty, "\(label): block '\(block.title)' is empty")
                        for item in block.exercises {
                            let exercise = item.exercise
                            XCTAssertTrue(exercise.equipment.isEmpty, "Zero-Equipment Floor")
                            XCTAssertEqual(item.durationSeconds != nil, exercise.isHold, "\(label): \(exercise.id)")
                            XCTAssertEqual(item.reps != nil, !exercise.isHold, "\(label): \(exercise.id)")
                            let value = item.reps ?? item.durationSeconds ?? 0
                            let kind = RepGrammar.kind(of: exercise)
                            switch item.role {
                            case .variation?:
                                XCTFail("\(label): the shipping catalog carries no Variation, so none is ever served")
                            case .main?, .core?:
                                XCTAssertGreaterThanOrEqual(value, RepGrammar.shortSessionFloor(for: kind), "\(label): \(exercise.id)")
                                XCTAssertLessThanOrEqual(value, RepGrammar.earnedRange(for: kind, level: level).upperBound, "\(label): \(exercise.id)")
                                XCTAssertNotNil(item.earnedReps ?? item.earnedDurationSeconds, "\(label): \(exercise.id) records no Earned Reps")
                            case .practice?:
                                let atPractice = value == RepGrammar.practiceValue(for: kind)
                                let atVolume = value >= RepGrammar.shortSessionFloor(for: kind)
                                    && value <= RepGrammar.earnedRange(for: kind, level: level).upperBound
                                XCTAssertTrue(atPractice || atVolume, "\(label): \(exercise.id) practice at \(value)")
                                XCTAssertNil(item.earnedReps ?? item.earnedDurationSeconds, "\(label): Practice records no Earned Reps")
                            case .recovery?, nil:
                                XCTAssertEqual(value, SessionAssembly.bookendValue(for: exercise), "\(label): \(exercise.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testNoExerciseRepeatsAcrossBlocks() {
        for day in TrainingDay.rotation {
            for minutes in lengths {
                let ids = assemble(minutes: minutes, logs: someHistory(), day: day).blocks.flatMap { $0.exercises.map(\.exercise.id) }
                XCTAssertEqual(Set(ids).count, ids.count, "\(day) \(minutes) min: an exercise appeared twice")
            }
        }
    }

    /// An injury removes the ladders it makes unsafe and keeps the rest: a knee flag takes the squat-side
    /// ladders off a Legs Day, which still trains its hinge ladders.
    func testAnInjuryRemovesItsLaddersAndKeepsTheRest() {
        let knees = user(injuries: ["knees"])
        let contraindicated = InjuryContraindication.contraindicatedPatterns(for: ["knees"])
        XCTAssertTrue(contraindicated.contains(.squat))
        for minutes in [15, 30, 60] {
            let stations = circuit(assemble(minutes: minutes, user: knees, day: .legs))
            XCTAssertFalse(stations.contains { contraindicated.contains($0.exercise.movementPattern) }, "\(minutes) min: \(stations.map(\.exercise.id))")
            XCTAssertTrue(stations.contains { $0.role == .main && $0.exercise.movementPattern == .hinge }, "\(minutes) min")
        }
    }

    // MARK: - Session Policy levers

    /// Passing `SessionPolicy.default` reproduces the unpoliced assembly exactly.
    func testDefaultPolicyReproducesUnpolicedOutput() {
        let logs = someHistory()
        for minutes in [10, 20, 30, 60] {
            let unpoliced = SessionAssembly.assemble(
                requestedMinutes: minutes, user: user(), library: library, recentLogs: logs,
                asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar
            )
            XCTAssertEqual(structuralSignature(assemble(minutes: minutes, logs: logs, policy: .default)), structuralSignature(unpoliced), "\(minutes) min")
        }
    }

    /// `progressionRate` paces the climb end-to-end: after one qualifying session at 15, the neutral pace
    /// climbs Wall Push-Up's Earned Reps to 20, while the slowest pace (0.5) needs a second session first.
    func testProgressionRatePacesTheClimbInAssembly() throws {
        let logs = [TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_wall", pattern: .push, value: 15, earned: 15)],
            completedAt: TrainingDayFixtures.date(daysAgo: 2)
        )]
        func earned(rate: Double) throws -> Int? {
            var policy = SessionPolicy.default
            policy.progressionRate = rate
            let workout = assemble(minutes: 30, user: user(level: .beginner), logs: logs, policy: policy, day: .push)
            return try XCTUnwrap(circuit(workout).first { $0.exercise.id == "push_wall" }, "Wall Push-Up is the current rung").earnedReps
        }
        XCTAssertEqual(try earned(rate: 1.0), 20)
        XCTAssertEqual(try earned(rate: SessionPolicy.minProgressionRate), 15)
    }

    // MARK: - Step 0 cold-start override

    private func coldStartUser(level: FitnessLevel = .beginner, sessionsLogged: Int = 0, active: Bool = true) -> User {
        var person = user(level: level)
        person.coldStart = User.ColdStart(sessionsLogged: sessionsLogged, active: active)
        return person
    }

    private func coldStartPolicy(cappedMaxDifficulty: Int) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.coldStartContract = SessionPolicy.ColdStartContract(forceContrastSpread: false, cappedMaxDifficulty: cappedMaxDifficulty)
        return policy
    }

    /// An advanced user who cleared Standard Push-Up: their frontier is the next rung.
    private var clearedStandardPushUp: [WorkoutLog] {
        [TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 50, earned: 50)],
            completedAt: TrainingDayFixtures.date(daysAgo: 2)
        )]
    }

    /// The capped pool removes every over-cap movement while Step 0 is active, and is a no-op once
    /// cold-start is retired or the policy carries no contract.
    func testColdStartCappedPoolRemovesTooHardMovements() {
        let policy = coldStartPolicy(cappedMaxDifficulty: 2)
        XCTAssertTrue(library.contains { $0.difficulty > 2 }, "library must have >2-difficulty movements")

        let active = coldStartUser(level: .advanced)
        let capped = ColdStartOverride.cappedPool(library, user: active, sessionPolicy: policy)
        XCTAssertFalse(capped.isEmpty, "the cap must never empty the pool")
        XCTAssertTrue(capped.allSatisfy { $0.difficulty <= 2 }, "every capped movement is at or below the cap")

        let warm = coldStartUser(level: .advanced, sessionsLogged: 6, active: false)
        XCTAssertEqual(ColdStartOverride.cappedPool(library, user: warm, sessionPolicy: policy).count, library.count)
        XCTAssertEqual(ColdStartOverride.cappedPool(library, user: active, sessionPolicy: .default).count, library.count)
    }

    /// End-to-end difficulty cap: an advanced user who cleared Standard Push-Up is served Diamond Push-Up
    /// (difficulty 3) by the plain engine, but the cold-start cap keeps every main station, Core Sprinkle
    /// and stretch at or below it.
    func testColdStartSessionRespectsTheDifficultyCap() {
        let advanced = coldStartUser(level: .advanced)
        let baseline = assemble(minutes: 30, user: advanced, logs: clearedStandardPushUp, day: .push)
        XCTAssertTrue(circuit(baseline).contains { $0.exercise.id == "push_diamond" }, "without the cap the frontier is Diamond Push-Up")

        let capped = assemble(minutes: 30, user: advanced, logs: clearedStandardPushUp, policy: coldStartPolicy(cappedMaxDifficulty: 2), day: .push)
        XCTAssertTrue(capped.blocks.flatMap(\.exercises).allSatisfy { $0.exercise.difficulty <= 2 }, "\(capped.blocks.flatMap(\.exercises).map(\.exercise.id))")
        XCTAssertFalse(circuit(capped).contains { $0.exercise.id == "push_diamond" })
    }

    /// A warmed-up user (cold-start retired) is unaffected by Step 0: a lingering contract is a no-op.
    func testWarmedUpUserIsUnaffectedByColdStart() {
        let warm = coldStartUser(level: .intermediate, sessionsLogged: 6, active: false)
        for minutes in [10, 20, 60] {
            XCTAssertEqual(
                structuralSignature(assemble(minutes: minutes, user: warm, logs: someHistory(), policy: coldStartPolicy(cappedMaxDifficulty: 2))),
                structuralSignature(assemble(minutes: minutes, user: warm, logs: someHistory())),
                "\(minutes) min: a retired cold-start user must run the plain pipeline"
            )
        }
    }

    // MARK: - Return override and Re-entry Ramp

    /// A Return caps the eligible difficulty at the gentle end: the same strong history that serves
    /// Diamond Push-Up to a present user serves nothing above `returnMaxDifficulty` after a gap.
    func testReturnCapsDifficultyBelowThePreGapTier() {
        let present = assemble(minutes: 30, user: user(level: .advanced), logs: clearedStandardPushUp, day: .push)
        XCTAssertFalse(present.wasReturn)
        XCTAssertTrue(circuit(present).contains { $0.exercise.id == "push_diamond" })

        let lapsed = [TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 50, earned: 50)],
            completedAt: TrainingDayFixtures.date(daysAgo: 10)
        )]
        let returned = assemble(minutes: 30, user: user(level: .advanced), logs: lapsed, day: .push)
        XCTAssertTrue(returned.wasReturn, "a 10-day gap is a Return")
        XCTAssertTrue(
            returned.blocks.flatMap(\.exercises).allSatisfy { $0.exercise.difficulty <= ReturnOverride.returnMaxDifficulty },
            "\(returned.blocks.flatMap(\.exercises).map(\.exercise.id))"
        )
        XCTAssertFalse(circuit(returned).contains { $0.role == .practice }, "a Return offers no Practice Movement")
    }

    /// The Return session and its Re-entry Ramp hold the *served* number under Earned Reps and walk it
    /// back up, while Earned Reps themselves stay at the pre-Return capacity: an advanced user last at 30
    /// Standard Push-Ups (Earned Reps 35 after that session) returns after a gap; each session logged at
    /// what it served never lowers the next one's Earned Reps, the served number never decreases, and once
    /// the ramp is over the session is served at or above Earned Reps again.
    func testReturnAndReentryRampHoldAgainstPreReturnCapacity() throws {
        let advanced = user(level: .advanced)
        let preReturn = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 30, earned: 30)],
            completedAt: TrainingDayFixtures.date(daysAgo: 20)
        )
        var history = [preReturn]
        // At 60 minutes, so the fit never has to cut reps below Earned Reps to fit the length.
        func standard() throws -> (workout: Workout, item: PrescribedExercise) {
            let workout = assemble(minutes: 60, user: advanced, logs: history, day: .push)
            return (workout, try XCTUnwrap(circuit(workout).first { $0.exercise.id == "push_standard" }, "Standard Push-Up stays served"))
        }

        var served: [Int] = []
        for (index, daysAgo) in [4, 3, 2, 1].enumerated() {
            let (workout, item) = try standard()
            XCTAssertEqual(workout.wasReturn, index == 0, "only the first session back is the Return")
            XCTAssertEqual(item.earnedReps, 35, "session \(index): Earned Reps stay at the pre-Return capacity")
            XCTAssertLessThan(item.reps ?? 0, 35, "session \(index): the ramp serves under Earned Reps")
            served.append(item.reps ?? 0)
            history.append(logged(workout, at: TrainingDayFixtures.date(daysAgo: daysAgo), wasReturn: index == 0))
        }
        XCTAssertEqual(served, served.sorted(), "the ramp never takes the served number down: \(served)")

        let (after, item) = try standard()
        XCTAssertFalse(after.wasReturn)
        XCTAssertEqual(item.earnedReps, 35)
        XCTAssertGreaterThanOrEqual(item.reps ?? 0, 35, "the ramp is over: served at or above Earned Reps")
    }

    /// A held session never counts as capacity, so a user who lapses twice is held against the Earned
    /// Reps from before the *first* Return: the second Return serves what the first did.
    func testASecondLapseIsHeldAgainstTheCapacityFromBeforeTheFirstReturn() throws {
        let advanced = user(level: .advanced)
        let preReturn = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 30, earned: 30)],
            completedAt: TrainingDayFixtures.date(daysAgo: 40)
        )
        let firstReturn = assemble(minutes: 30, user: advanced, logs: [preReturn], day: .push)
        XCTAssertTrue(firstReturn.wasReturn)
        let first = try XCTUnwrap(circuit(firstReturn).first { $0.exercise.id == "push_standard" })

        let history = [preReturn, logged(firstReturn, at: TrainingDayFixtures.date(daysAgo: 30), wasReturn: true)]
        let secondReturn = assemble(minutes: 30, user: advanced, logs: history, day: .push)
        XCTAssertTrue(secondReturn.wasReturn, "a second lapse")
        let second = try XCTUnwrap(circuit(secondReturn).first { $0.exercise.id == "push_standard" })
        XCTAssertEqual(second.earnedReps, first.earnedReps, "both Returns read the pre-lapse Earned Reps")
        XCTAssertEqual(second.reps, first.reps, "and serve the same held number")
    }

    /// "Too hard" still steps a move back during a Re-entry Ramp: a ramp session rated too hard with the
    /// move marked "couldn't finish" takes a step off its Earned Reps, and the next ramp session serves no
    /// more than the last; a later "too easy" earns the step back.
    func testReentryRampStillStepsBackAMoveRatedTooHard() throws {
        let advanced = user(level: .advanced)
        let preReturn = TrainingDayFixtures.log(
            [TrainingDayFixtures.station("push_standard", pattern: .push, value: 30, earned: 30)],
            completedAt: TrainingDayFixtures.date(daysAgo: 20)
        )
        func standard(_ logs: [WorkoutLog]) throws -> (Workout, PrescribedExercise) {
            let workout = assemble(minutes: 30, user: advanced, logs: logs, day: .push)
            return (workout, try XCTUnwrap(circuit(workout).first { $0.exercise.id == "push_standard" }))
        }
        let (returnSession, _) = try standard([preReturn])
        let afterReturn = [preReturn, logged(returnSession, at: TrainingDayFixtures.date(daysAgo: 3), wasReturn: true)]
        let (ramp1, ramp1Item) = try standard(afterReturn)
        XCTAssertEqual(ramp1Item.earnedReps, 35)

        var tooHard = logged(ramp1, at: TrainingDayFixtures.date(daysAgo: 2), difficulty: .tooHard)
        let index = try XCTUnwrap(tooHard.exercises.firstIndex { $0.exerciseId == "push_standard" })
        tooHard.exercises[index].couldNotFinish = true
        let (ramp2, ramp2Item) = try standard(afterReturn + [tooHard])
        XCTAssertEqual(ramp2Item.earnedReps, 30, "too hard takes a step off Earned Reps")
        XCTAssertLessThanOrEqual(ramp2Item.reps ?? 0, ramp1Item.reps ?? 0)

        let tooEasy = logged(ramp2, at: TrainingDayFixtures.date(daysAgo: 1), difficulty: .tooEasy)
        let (_, ramp3Item) = try standard(afterReturn + [tooHard, tooEasy])
        XCTAssertEqual(ramp3Item.earnedReps, 35, "too easy earns the step back")
    }

    /// The Return override is suppressed while cold-start is active: a cold-start session is never
    /// flagged as a Return, even when the raw gap reads as one.
    func testReturnSuppressedDuringColdStart() {
        let logs = [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 10))]
        XCTAssertTrue(ReturnOverride.isReturn(recentLogs: logs, asOf: TrainingDayFixtures.asOf, calendar: TrainingDayFixtures.calendar))
        let workout = assemble(minutes: 10, user: coldStartUser(), logs: logs, policy: coldStartPolicy(cappedMaxDifficulty: 2))
        XCTAssertFalse(workout.wasReturn, "cold start owns the first sessions, not the Return path")
        XCTAssertEqual(workout.focusPillar, .strength)
    }

    // MARK: - Determinism (content, not ids)

    /// Steady-state, cold-start and Return assembly each generate byte-identically on repeat.
    func testAssemblyIsDeterministicInEveryRegime() {
        let lapsed = [TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 10))]
        let regimes: [(String, User, [WorkoutLog], SessionPolicy)] = [
            ("steady", user(), someHistory(), .default),
            ("cold-start", coldStartUser(sessionsLogged: 2), [], coldStartPolicy(cappedMaxDifficulty: 2)),
            ("return", user(), lapsed, .default),
        ]
        for (name, person, logs, policy) in regimes {
            for minutes in [8, 20, 60] {
                let first = structuralSignature(assemble(minutes: minutes, user: person, logs: logs, policy: policy))
                for _ in 0..<5 {
                    XCTAssertEqual(structuralSignature(assemble(minutes: minutes, user: person, logs: logs, policy: policy)), first, "\(name) \(minutes) min")
                }
            }
        }
    }

    // MARK: - PRD validation test (intermediate user, some history, 20 minutes)

    func testPRDValidationTwentyMinuteSession() {
        let person = user(level: .intermediate)
        let logs = someHistory()
        let start = DispatchTime.now()
        let workout = assemble(minutes: 20, user: person, logs: logs)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        XCTAssertEqual(workout.trainingDay, .legs, "Push and Pull are done, so the Rotation serves Legs")
        XCTAssertEqual(workout.blocks.map(\.title), ["Warm-Up", "Legs Day", "Cooldown"])
        assertFillsOrRunsHonestlyShort(workout, minutes: 20, user: person, logs: logs, "20 min")
        XCTAssertLessThan(elapsedMs, 100, "assembly took \(elapsedMs)ms, over the 100ms budget")
    }

    // MARK: - Evidence transcript

    /// Prints a human-readable transcript (between EVIDENCE markers) of the Training Day sessions the
    /// engine generates for every length, level and day, for a fresh and a seasoned history: each
    /// station's role, sets, served number and Earned Reps, the round rest and pause, and how the planned
    /// wall-clock lands against the request. Asserts the transcript's claims: four sets per station, every
    /// number on the grid of five, rests inside their rails, no stretched work window, and every session
    /// within the tolerance or honestly short.
    func testEvidenceTrainingDayTranscriptAcrossLevelsDaysAndLengths() throws {
        var lines = ["TRAINING DAY SESSIONS (ADR-0012/ADR-0013) - engine generation transcript"]
        lines.append("transition=\(SessionAssembly.transitionSeconds)s  baseRoundRest=\(SessionAssembly.baseRoundRestSeconds)s  maxRest=\(SessionAssembly.maxRestSeconds)s  tolerance=\(SessionAssembly.toleranceSeconds)s")
        var worstShortfall = 0
        for (name, logs) in [("seasoned", someHistory()), ("fresh", [WorkoutLog]())] {
            for level in FitnessLevel.allCases {
                let person = user(level: level)
                lines.append("")
                lines.append("================ HISTORY: \(name)  LEVEL: \(level) ================")
                for day in TrainingDay.rotation {
                    for minutes in lengths {
                        let workout = assemble(minutes: minutes, user: person, logs: logs, day: day)
                        let planned = SessionAssembly.plannedSeconds(of: workout)
                        let gap = planned - minutes * 60
                        worstShortfall = min(worstShortfall, gap)
                        lines.append(String(format: "  [%@ %2d min] planned %d:%02d (%+ds)", day.rawValue, minutes, planned / 60, planned % 60, gap))
                        for block in workout.blocks {
                            let isCircuit = SessionAssembly.isCircuit(block.category)
                            if isCircuit {
                                lines.append("      \(block.title) - round rest \(block.exercises.first?.restSeconds ?? 0)s, pause \(block.transitionSeconds ?? SessionAssembly.transitionSeconds)s")
                            } else {
                                lines.append("      \(block.title) - \(block.exercises.count) stretch(es), one set each")
                            }
                            for item in block.exercises {
                                let value = try XCTUnwrap(item.reps ?? item.durationSeconds)
                                let earned = (item.earnedReps ?? item.earnedDurationSeconds).map { " (earned \($0))" } ?? ""
                                let role = item.role.map { "\($0)" } ?? "stretch"
                                lines.append("          - \(item.exercise.displayName) [\(role)]: \(item.sets) x \(value)\(item.exercise.isHold ? "s" : "")\(earned)")
                                XCTAssertEqual(value % RepGrammar.step, 0, "\(name) \(level) \(day) \(minutes) min: \(item.exercise.id) off the grid")
                                XCTAssertNil(item.stretchSeconds, "\(item.exercise.id) carries a stretched work window")
                                XCTAssertLessThanOrEqual(item.restSeconds, SessionAssembly.maxRestSeconds)
                                if isCircuit { XCTAssertEqual(item.sets, RepGrammar.setsPerStation) }
                            }
                        }
                        assertFillsOrRunsHonestlyShort(workout, minutes: minutes, user: person, logs: logs, "\(name) \(level) \(day) \(minutes) min")
                    }
                }
            }
        }
        lines.append("")
        lines.append("LARGEST SHORTFALL ACROSS ALL HISTORIES x LEVELS x DAYS x LENGTHS: \(worstShortfall)s")
        print("\n===EVIDENCE-BEGIN===\n\(lines.joined(separator: "\n"))\n===EVIDENCE-END===\n")
    }
}
