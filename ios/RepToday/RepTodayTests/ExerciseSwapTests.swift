import XCTest
@testable import RepToday

/// Tests the deterministic in-session swap (US-C08): replacing one prescribed slot with an
/// equivalent substitute - same pillar, same movement pattern, comparable difficulty, in the same
/// time budget, safe for the user - or an honest `.noAlternative` when none qualifies.
///
/// A Training Day station keeps its shape through a swap: the substitute runs the slot's four rounds and
/// rest, and it keeps the slot's role (US-TD02). A main or core substitute is served at its own Earned
/// Reps for the user's level, shifted by whatever the fit padded or cut on the slot it replaces; a
/// Practice substitute runs at Practice reps; a stretch runs at its catalog length. Every other contract
/// is unchanged: the substitute respects phase, injuries and the Zero-Equipment Floor, refuses rather
/// than offering an unsafe or out-of-budget pick, never duplicates a movement already in the session, is
/// sized by every Step 6 lever the session was, and is deterministic.
final class ExerciseSwapTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar = TrainingDayFixtures.calendar
    private var asOf: Date { TrainingDayFixtures.asOf }

    private func date(daysAgo: Int) -> Date {
        TrainingDayFixtures.date(daysAgo: daysAgo)
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        injuries: [String] = []
    ) -> User {
        TrainingDayFixtures.user(level: level, phase: phase, injuries: injuries, asOf: asOf)
    }

    /// A slot shaped the way the assembler builds one. A circuit station runs `RepGrammar.setsPerStation`
    /// rounds at the round rest, serves `perSet` (default: the bottom of the intermediate range, where a
    /// movement with no history opens) and records `earned` (default: what it serves) when it is a main
    /// or core station. A stretch is one set at its catalog length (`bookendValue`) with no role.
    private func prescription(
        for exercise: Exercise,
        sets: Int? = nil,
        perSet: Int? = nil,
        earned: Int? = nil,
        role: StationRole? = .main,
        rest: Int = SessionAssembly.baseRoundRestSeconds
    ) -> PrescribedExercise {
        let isStretch = exercise.pillar == .mobility
        let value = perSet ?? (isStretch
            ? SessionAssembly.bookendValue(for: exercise)
            : RepGrammar.earnedRange(for: exercise, level: .intermediate).lowerBound)
        let role = isStretch ? nil : role
        let recordsEarned = role == .main || role == .core
        let earnedValue = recordsEarned ? (earned ?? value) : nil
        return PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets ?? (isStretch ? 1 : RepGrammar.setsPerStation),
            reps: exercise.isHold ? nil : value,
            durationSeconds: exercise.isHold ? value : nil,
            restSeconds: rest,
            role: role,
            earnedReps: exercise.isHold ? nil : earnedValue,
            earnedDurationSeconds: exercise.isHold ? earnedValue : nil
        )
    }

    /// A one-block workout wrapping `prescriptions`, enough for the swap to read the session's
    /// existing movements. `wasReturn` stamps the session the way the assembler does, so a swap can be
    /// exercised on a Return.
    private func workout(
        _ prescriptions: [PrescribedExercise],
        wasReturn: Bool = false,
        title: String = "Push Day",
        category: ExerciseCategory = .strength
    ) -> Workout {
        Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: 30,
            wasReturn: wasReturn,
            blocks: [
                WorkoutBlock(id: UUID(), title: title, category: category, exercises: prescriptions)
            ]
        )
    }

    /// A Training Day log in which `exercise` ran as a main station: four sets at `value`, earned `earned`.
    private func log(
        _ exercise: Exercise,
        value: Int,
        earned: Int? = nil,
        daysAgo: Int,
        difficulty: PerceivedDifficulty? = .justRight,
        wasReturn: Bool = false
    ) -> WorkoutLog {
        var log = TrainingDayFixtures.log(
            [TrainingDayFixtures.station(
                exercise.id, pattern: exercise.movementPattern, pillar: exercise.pillar,
                value: value, earned: earned ?? value, isHold: exercise.isHold
            )],
            completedAt: date(daysAgo: daysAgo),
            difficulty: difficulty
        )
        log.wasReturn = wasReturn
        return log
    }

    /// A session with no stations at all, for the Return / ramp bookkeeping that only counts sessions.
    private func emptyLog(daysAgo: Int, wasReturn: Bool = false) -> WorkoutLog {
        var log = TrainingDayFixtures.log([], completedAt: date(daysAgo: daysAgo))
        log.wasReturn = wasReturn
        return log
    }

    /// The planned wall-clock of one slot, measured exactly as the engine sizes a session: each set at
    /// the work its own target really costs, plus the rests between them.
    private func slotSeconds(of prescription: PrescribedExercise) -> Int {
        prescription.sets * SessionAssembly.workSecondsPerSet(of: prescription)
            + max(0, prescription.sets - 1) * prescription.restSeconds
    }

    private func tolerance(of slot: PrescribedExercise) -> Int {
        ExerciseSwap.slotTolerance(workSeconds: slot.sets * SessionAssembly.workSecondsPerSet(of: slot))
    }

    /// A minimal fixture exercise, so a no-alternative / out-of-budget scenario can be constructed
    /// without depending on the shape of the real library.
    private func makeExercise(
        id: String,
        pillar: Pillar = .strength,
        pattern: MovementPattern = .push,
        difficulty: Int = 2,
        phase: Phase = .discipline,
        isHold: Bool = false,
        defaultValue: Int? = nil,
        estPerSet: Int = 40
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: pattern,
            complements: pillar == .mobility ? [.push] : nil,
            category: pillar == .mobility ? .warmup : .strength,
            difficulty: difficulty,
            phase: phase,
            equipment: [],
            isHold: isHold,
            defaultReps: isHold ? nil : (defaultValue ?? 10),
            defaultDurationSeconds: isHold ? (defaultValue ?? 30) : nil,
            estimatedTimePerSetSeconds: estPerSet,
            metValue: 3.0,
            progressionChainId: "chain_\(id)",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "4 clean sets at the top of your rep range",
            apartmentFriendly: true
        )
    }

    /// Unwraps a `.substituted` outcome, *failing* the test when the swap declined. A `.noAlternative`
    /// is a real regression in every test that calls this - it must never be skipped away, or the
    /// assertions that follow silently stop running.
    private func substitute(
        _ outcome: SwapOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PrescribedExercise {
        guard case let .substituted(prescription) = outcome else {
            XCTFail("expected a substitute, got \(outcome)", file: file, line: line)
            throw SwapTestFailure.expectedSubstitute
        }
        return prescription
    }

    private enum SwapTestFailure: Error {
        case expectedSubstitute
    }

    // MARK: - Valid swap within constraints (PRD validation)

    func testValidSwapStaysWithinPillarPatternDifficultyAndBudget() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(level: .intermediate), library: library, recentLogs: [])
        )

        XCTAssertNotEqual(result.exercise.id, target.id, "a swap must return a different movement")
        XCTAssertEqual(result.exercise.pillar, .strength, "same pillar as the swapped exercise")
        XCTAssertEqual(result.exercise.movementPattern, .push, "same movement pattern (push)")
        XCTAssertLessThanOrEqual(
            abs(result.exercise.difficulty - target.difficulty), ExerciseSwap.difficultyBandWidth,
            "substitute difficulty must stay within the band"
        )
        XCTAssertTrue(result.exercise.equipment.isEmpty, "substitute must be bodyweight")
        XCTAssertEqual(result.exercise.phase, .discipline, "discipline user gets a discipline movement")
    }

    func testSwapPreservesTheSlotsShapeAndTimeBudget() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )

        XCTAssertEqual(result.sets, RepGrammar.setsPerStation, "a circuit station keeps its four rounds")
        XCTAssertEqual(result.restSeconds, slot.restSeconds, "rest is preserved for timing fidelity")
        // Measured the way the engine sizes a session: each side at the target it actually carries.
        XCTAssertLessThanOrEqual(
            abs(slotSeconds(of: result) - slotSeconds(of: slot)), tolerance(of: slot),
            "the swap must not move the slot's wall-clock beyond its tolerance"
        )
    }

    /// The budget check prices both sides at their *own* targets, so a slot an advanced user has climbed
    /// to the top of their range cannot be swapped for a movement whose flat estimate happens to match
    /// while its actual work does not: the newcomer opens at the bottom of the range.
    func testSwapRejectsAPeerThatOnlyMatchesAtItsDefaultSizedEstimate() async throws {
        let library = try await library()
        let diamond = try XCTUnwrap(library.first { $0.id == "push_diamond" })
        let pike = try XCTUnwrap(library.first { $0.id == "push_pike" })

        // Identical estimates and defaults, so a flat comparison reports zero drift.
        XCTAssertEqual(diamond.estimatedTimePerSetSeconds, pike.estimatedTimePerSetSeconds)
        XCTAssertEqual(diamond.defaultReps, pike.defaultReps)
        let top = RepGrammar.earnedRange(for: diamond, level: .advanced).upperBound
        let grown = prescription(for: diamond, perSet: top, earned: top)

        let outcome = ExerciseSwap.swap(
            grown, in: workout([grown]), user: user(level: .advanced), library: [diamond, pike], recentLogs: []
        )
        XCTAssertEqual(
            outcome, .noAlternative,
            "a newcomer at the bottom of its range is not a comparable time cost for a slot at the top"
        )
    }

    /// Whatever the swap does hand back lands inside the tolerance measured against the session's own
    /// work model, keeps the slot's four rounds and its role - across every strength movement the real
    /// library offers, served at the bottom, middle and top of an advanced user's range.
    ///
    /// The substitute has no history, so it opens at the bottom of its own range; the further up the
    /// range the slot sits, the more its peers decline as out of budget - a newcomer at 15 reps is not
    /// four rounds of 50. Declining is the honest answer, so the loop tolerates `.noAlternative`, and the
    /// exact coverage at each point is pinned (and the declined movements printed) so a change to it is a
    /// deliberate one.
    func testEverySubstituteTheLibraryOffersStaysInsideTheSlotBudget() async throws {
        let library = try await library()
        let user = user(level: .advanced)
        let strength = library.filter { $0.pillar == .strength }

        for (point, expectedSwapped) in [("bottom", 35), ("middle", 25), ("top", 15)] {
            var swapped = 0
            var declined: [String] = []
            for movement in strength {
                let range = RepGrammar.earnedRange(for: movement, level: .advanced)
                let value: Int
                switch point {
                case "bottom": value = range.lowerBound
                case "middle": value = RepGrammar.floored((range.lowerBound + range.upperBound) / 2)
                default: value = range.upperBound
                }
                let slot = prescription(for: movement, perSet: value, earned: value)
                guard case let .substituted(result) = ExerciseSwap.swap(
                    slot, in: workout([slot]), user: user, library: library, recentLogs: []
                ) else {
                    declined.append(movement.id)
                    continue
                }
                swapped += 1
                XCTAssertLessThanOrEqual(
                    abs(slotSeconds(of: result) - slotSeconds(of: slot)), tolerance(of: slot),
                    "swapping \(movement.id) for \(result.exercise.id) at the \(point) moved the slot out of budget"
                )
                XCTAssertEqual(result.sets, RepGrammar.setsPerStation, "\(movement.id) at the \(point) left four rounds")
                XCTAssertEqual(result.role, .main, "\(movement.id) at the \(point) lost its role")
            }
            print("swap coverage at the \(point) of the range: \(swapped)/\(strength.count); declined \(declined)")
            XCTAssertEqual(
                swapped, expectedSwapped,
                "swap coverage at the \(point) was \(swapped)/\(strength.count), expected \(expectedSwapped)"
            )
        }
    }

    /// The same sweep in the shape a real warm-up and cooldown slot has: one set of a stretch at its
    /// catalog length. A stretch swaps for a stretch at *its* catalog length, so the slot stays one set and
    /// the only question is whether the two catalog lengths are close enough - and every stretch in the
    /// catalog has an in-band peer that is.
    func testEveryStretchSubstituteStaysInBudgetInTheBookendShape() async throws {
        let library = try await library()
        let mobility = library.filter { $0.pillar == .mobility }
        XCTAssertFalse(mobility.isEmpty, "the sweep needs mobility movements to price")

        var swapped = 0
        var declined: [String] = []
        for movement in mobility {
            let slot = prescription(for: movement)
            let bookend = workout([slot], title: "Warm-Up", category: .warmup)
            guard case let .substituted(result) = ExerciseSwap.swap(
                slot, in: bookend, user: user(level: .advanced), library: library, recentLogs: []
            ) else {
                declined.append(movement.id)
                continue
            }
            swapped += 1
            XCTAssertEqual(result.sets, 1, "a bookend stretch stays one set")
            XCTAssertNil(result.role, "a bookend stretch carries no station role")
            XCTAssertEqual(
                result.durationSeconds ?? result.reps, SessionAssembly.bookendValue(for: result.exercise),
                "a stretch substitute runs at its own catalog length"
            )
            XCTAssertLessThanOrEqual(
                abs(slotSeconds(of: result) - slotSeconds(of: slot)), tolerance(of: slot),
                "swapping \(movement.id) for \(result.exercise.id) moved the bookend out of budget"
            )
        }
        print("bookend swap coverage: \(swapped)/\(mobility.count); declined \(declined)")
        XCTAssertEqual(swapped, mobility.count, "bookend coverage was \(swapped)/\(mobility.count)")
    }

    /// Every one-set bookend - the warm-up and the cooldown - is a stretch at one set by construction, so
    /// a swap never reaches for a two-set stretch to make up time: a stretch whose catalog length is far
    /// from the slot's is declined rather than restructured.
    func testSwapNeverMovesTheSetCountOfAOneSetBlock() async throws {
        // A 100-second stretch beside a peer that runs 30 seconds. At one set the peer is 70s away, past
        // the slot's widened one-set tolerance (30 + 0.3 x 100 = 60s); at two sets it would be within it.
        let stretch = makeExercise(id: "stretch_long", pillar: .mobility, pattern: .mobility, isHold: true, defaultValue: 100)
        let peer = makeExercise(id: "stretch_peer", pillar: .mobility, pattern: .mobility, isHold: true, defaultValue: 30)
        let slot = prescription(for: stretch)
        XCTAssertEqual(slot.durationSeconds, 100)

        for (title, category) in [("Warm-Up", ExerciseCategory.warmup), ("Cooldown", .cooldown)] {
            XCTAssertEqual(
                ExerciseSwap.swap(
                    slot, in: workout([slot], title: title, category: category),
                    user: user(), library: [stretch, peer], recentLogs: []
                ),
                .noAlternative,
                "a \(title) stretch may not grow a set, so an out-of-budget peer is refused outright"
            )
        }
    }

    /// The Start Seed (US-O02) never reaches a stretch, so a swapped *mobility* movement opens at its own
    /// catalog length for an advanced cold-start user, exactly as the warm-up and cooldown the assembler
    /// built for them did.
    func testSwapDoesNotApplyTheStartSeedToAMobilitySubstitute() async throws {
        let library = try await library()
        let fold = try XCTUnwrap(library.first { $0.id == "mobility_forward_fold" })
        let slot = prescription(for: fold)

        let result = try substitute(
            ExerciseSwap.swap(
                slot,
                in: workout([slot], title: "Warm-Up", category: .warmup),
                user: user(level: .advanced),
                library: library,
                recentLogs: [],
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced)
            )
        )
        XCTAssertEqual(result.exercise.pillar, .mobility)
        XCTAssertEqual(
            result.durationSeconds ?? result.reps, SessionAssembly.bookendValue(for: result.exercise),
            "a mobility substitute opens at its own catalog length, unseeded, like every other stretch"
        )
    }

    // MARK: - The substitute keeps the slot's role

    /// A main substitute with no history opens where any new movement does - the bottom of the user's
    /// range - and records that as its Earned Reps, so the log it writes reads what was earned.
    func testMainSubstituteIsServedAtItsOwnEarnedRepsForTheUsersLevel() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )

        XCTAssertEqual(result.role, .main, "a main slot stays a main slot")
        let range = RepGrammar.earnedRange(for: result.exercise, level: .intermediate)
        let served = try XCTUnwrap(result.exercise.isHold ? result.durationSeconds : result.reps)
        XCTAssertNil(result.exercise.isHold ? result.reps : result.durationSeconds, "exactly one of reps / seconds")
        XCTAssertEqual(served, range.lowerBound, "a movement with no history opens at the bottom of the range")
        XCTAssertEqual(result.exercise.isHold ? result.earnedDurationSeconds : result.earnedReps, range.lowerBound)
    }

    /// A Practice slot stays a Practice slot (US-TD04): the substitute runs at Practice reps, records no
    /// Earned Reps, and so never moves progression - whatever the user has logged on it.
    func testPracticeSubstituteRunsAtPracticeReps() async throws {
        let library = try await library()
        let diamond = try XCTUnwrap(library.first { $0.id == "push_diamond" })
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let practice = prescription(for: diamond, perSet: RepGrammar.practiceValue(for: .reps), role: .practice)
        XCTAssertNil(practice.earnedReps)

        // The only peer has history at 25, which a main slot would serve; a Practice slot ignores it.
        let result = try substitute(
            ExerciseSwap.swap(
                practice, in: workout([practice]), user: user(), library: [diamond, standard],
                recentLogs: [log(standard, value: 25, daysAgo: 2)]
            )
        )
        XCTAssertEqual(result.exercise.id, standard.id)
        XCTAssertEqual(result.role, .practice, "a Practice slot stays a Practice slot")
        XCTAssertEqual(result.reps, RepGrammar.practiceValue(for: RepGrammar.kind(of: standard)))
        XCTAssertNil(result.earnedReps, "a Practice substitute records no Earned Reps")
        XCTAssertNil(result.earnedDurationSeconds)
        XCTAssertEqual(result.sets, RepGrammar.setsPerStation)
    }

    /// A Practice substitute runs at *its own* kind's Practice value: a per-side rep movement at 5 per
    /// side in place of a 10-rep slot, and a hold at 15 seconds whatever its catalog length.
    func testPracticeSubstituteRunsAtItsOwnKindsPracticeValue() throws {
        let slotMove = makeExercise(id: "core_slot", pattern: .core)
        var perSide = makeExercise(id: "core_side_reps", pattern: .core)
        perSide.isPerSide = true
        let practice = prescription(for: slotMove, perSet: RepGrammar.practiceValue(for: .reps), role: .practice)

        let perSidePick = try substitute(
            ExerciseSwap.swap(practice, in: workout([practice]), user: user(), library: [slotMove, perSide], recentLogs: [])
        )
        XCTAssertEqual(perSidePick.reps, RepGrammar.practiceValue(for: .repsPerSide))
        XCTAssertEqual(perSidePick.role, .practice)

        let holdSlotMove = makeExercise(id: "core_hold_slot", pattern: .core, isHold: true, defaultValue: 20)
        let longHold = makeExercise(id: "core_long_hold", pattern: .core, isHold: true, defaultValue: 45)
        let holdPractice = prescription(for: holdSlotMove, perSet: RepGrammar.practiceValue(for: .hold), role: .practice)
        let holdPick = try substitute(
            ExerciseSwap.swap(holdPractice, in: workout([holdPractice]), user: user(), library: [holdSlotMove, longHold], recentLogs: [])
        )
        XCTAssertEqual(holdPick.durationSeconds, RepGrammar.practiceValue(for: .hold), "Practice seconds, not the catalog's 45")
        XCTAssertNil(holdPick.reps)
        XCTAssertEqual(holdPick.role, .practice)
        XCTAssertNil(holdPick.earnedDurationSeconds)
    }

    /// A Core Sprinkle stays a core station and records its Earned Reps like a main one.
    func testCoreSubstituteKeepsTheCoreRole() async throws {
        let library = try await library()
        let plank = try XCTUnwrap(library.first { $0.id == "core_forearm_plank" })
        let slot = prescription(for: plank, perSet: 20, role: .core)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )
        XCTAssertEqual(result.exercise.movementPattern, .core)
        XCTAssertEqual(result.role, .core)
        XCTAssertNotNil(result.exercise.isHold ? result.earnedDurationSeconds : result.earnedReps)
    }

    /// A main slot the fit padded above its Earned Reps hands the substitute the same padding: the
    /// substitute is served the same number of steps above *its own* Earned Reps, and records those - so
    /// the session stays as long as it was fitted and Padding still never moves progression.
    func testPaddedMainSlotHandsItsPaddingToTheSubstitute() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let knee = try XCTUnwrap(library.first { $0.id == "push_knee" })
        let padded = prescription(for: standard, perSet: 25, earned: 15)

        let result = try substitute(
            ExerciseSwap.swap(padded, in: workout([padded]), user: user(), library: [standard, knee], recentLogs: [])
        )
        XCTAssertEqual(result.exercise.id, knee.id)
        XCTAssertEqual(result.earnedReps, 15, "the substitute has no history, so it earned the bottom of the range")
        XCTAssertEqual(result.reps, 25, "two steps of padding carried onto the substitute")
    }

    /// A short session's cut carries over the same way, never below the short-session floor.
    func testCutMainSlotHandsItsCutToTheSubstitute() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let knee = try XCTUnwrap(library.first { $0.id == "push_knee" })
        let cut = prescription(for: standard, perSet: 10, earned: 20)

        let result = try substitute(
            ExerciseSwap.swap(
                cut, in: workout([cut]), user: user(), library: [standard, knee],
                recentLogs: [log(knee, value: 25, daysAgo: 2)]
            )
        )
        XCTAssertEqual(result.exercise.id, knee.id)
        let earned = try XCTUnwrap(result.earnedReps)
        XCTAssertEqual(earned, 30, "25 performed at earned climbs a step")
        XCTAssertEqual(result.reps, earned - 10, "two steps of cut carried onto the substitute")

        let deepCut = prescription(for: standard, perSet: 10, earned: 30)
        let floored = try substitute(
            ExerciseSwap.swap(deepCut, in: workout([deepCut]), user: user(), library: [standard, knee], recentLogs: [])
        )
        XCTAssertEqual(floored.reps, RepGrammar.shortSessionFloor(for: .reps), "never below the short-session floor")
    }

    /// The substitute's padding stops at the top of the *user's* level range: the same padded slot serves
    /// an intermediate substitute at most 30 and an advanced one up to 50.
    func testSubstitutePaddingStopsAtTheTopOfTheUsersLevelRange() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let knee = try XCTUnwrap(library.first { $0.id == "push_knee" })
        let history = [log(knee, value: 25, earned: 25, daysAgo: 2)]

        func served(level: FitnessLevel) throws -> Int {
            let padded = prescription(for: standard, perSet: 30, earned: 15)
            return try XCTUnwrap(try substitute(
                ExerciseSwap.swap(padded, in: workout([padded]), user: user(level: level), library: [standard, knee], recentLogs: history)
            ).reps)
        }

        XCTAssertEqual(try served(level: .intermediate), 30, "30 earned + 15 padding, held at the intermediate top")
        XCTAssertEqual(try served(level: .advanced), 45, "30 earned + 15 padding fits under the advanced top")
    }

    // MARK: - Injuries are respected

    func testSwapRefusesWhenEveryPeerIsInjuryUnsafe() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        // A shoulder injury contraindicates the whole push pattern, so no push substitute is safe -
        // the engine returns no-alternative rather than handing back an injurious movement.
        let outcome = ExerciseSwap.swap(
            slot, in: workout([slot]), user: user(injuries: ["shoulders"]), library: library, recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "an injured pattern must yield no substitute, not an unsafe one")
    }

    func testInjuryOnAnotherPatternStillAllowsASafeSwap() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        // A knee injury rules out squats but leaves push untouched; the push slot still swaps cleanly.
        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(injuries: ["knees"]), library: library, recentLogs: [])
        )
        XCTAssertEqual(result.exercise.movementPattern, .push, "a knee injury must not derail a push swap")
    }

    // MARK: - No-alternative cases

    func testNoAlternativeWhenTheOnlyPeerIsPhaseGated() async throws {
        let library = try await library()
        // Restrict the catalog so push has just the standard push-up and the Strength-Phase one-arm
        // push-up. A discipline user cannot receive the gated skill, so there is no safe substitute.
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let oneArm = try XCTUnwrap(library.first { $0.id == "push_one_arm" })
        let slot = prescription(for: standard)

        let outcome = ExerciseSwap.swap(
            slot, in: workout([slot]), user: user(phase: .discipline), library: [standard, oneArm], recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "a phase-gated lone peer must not be offered to a discipline user")
    }

    func testNoAlternativeWhenThePatternHasASingleExercise() {
        let only = makeExercise(id: "push_solo")
        let slot = prescription(for: only)

        let outcome = ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: [only], recentLogs: [])
        XCTAssertEqual(outcome, .noAlternative, "no peer at all means no substitute")
    }

    func testNoAlternativeWhenEveryPeerBlowsTheTimeBudget() {
        // Same pillar/pattern/difficulty and bodyweight, but the only peer takes far longer per set,
        // so swapping it would move the session well beyond the slot tolerance: rejected.
        let target = makeExercise(id: "push_quick", estPerSet: 30)
        let slowPeer = makeExercise(id: "push_marathon", estPerSet: 200)
        let slot = prescription(for: target)

        let outcome = ExerciseSwap.swap(
            slot, in: workout([slot]), user: user(), library: [target, slowPeer], recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "an out-of-budget peer must be rejected, not stretch the session")
    }

    // MARK: - Never duplicate a movement already in the session

    func testSwapNeverReturnsAMovementAlreadyInTheSession() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let floorDips = try XCTUnwrap(library.first { $0.id == "push_floor_dips" })
        let standardSlot = prescription(for: standard)
        let dipsSlot = prescription(for: floorDips)

        // Both push movements are already in the session; swapping the standard push-up must not hand
        // back the floor dips that are already present.
        let result = try substitute(
            ExerciseSwap.swap(
                standardSlot, in: workout([standardSlot, dipsSlot]), user: user(), library: library, recentLogs: []
            )
        )
        XCTAssertEqual(result.exercise.movementPattern, .push)
        XCTAssertNotEqual(result.exercise.id, floorDips.id, "must not duplicate a movement already in the session")
        XCTAssertNotEqual(result.exercise.id, standard.id, "must not return the swapped movement itself")
    }

    // MARK: - The substitute is sized by the same Step 6 levers as the slot it replaces

    /// A push slot whose only in-band peer (`push_knee`) already has Earned Reps, so every Step 6 lever
    /// has something to act on: 15 performed at 15 earned, which climbs to 20.
    private func leveredSwapFixture(
        library: [Exercise]
    ) throws -> (slot: PrescribedExercise, peer: Exercise, logs: [WorkoutLog]) {
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let peer = try XCTUnwrap(library.first { $0.id == "push_knee" })
        return (prescription(for: target), peer, [log(peer, value: 15, daysAgo: 10)])
    }

    /// The main slot the assembler serves `exercise` at for an intermediate user, unfitted: its Earned
    /// Reps, held under them on a Return or ramp session - the same Step 6 call `SessionAssembly` makes.
    private func servedSlot(for exercise: Exercise, recentLogs: [WorkoutLog], wasReturn: Bool) -> PrescribedExercise {
        let target = AdaptiveOverload.target(
            for: exercise, level: .intermediate, recentLogs: recentLogs,
            reentryScale: ReturnOverride.reentryScale(isReturn: wasReturn, recentLogs: recentLogs)
        )
        return prescription(
            for: exercise, perSet: target.value,
            earned: RepGrammar.served(earned: target.earned, for: RepGrammar.kind(of: exercise), level: .intermediate)
        )
    }

    /// A Return holds every assembled slot below Earned Reps (US-E06); a swapped-in slot must be held
    /// back too, or one tap hands the returning user the single hardest slot in a session whose whole
    /// point is to be uniformly gentle. The Earned Reps it records are not lowered.
    func testSwapOnAReturnCarriesTheReentryEase() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let catalog = [fixture.slot.exercise, fixture.peer]

        let steadySlot = servedSlot(for: fixture.slot.exercise, recentLogs: fixture.logs, wasReturn: false)
        let returnSlot = servedSlot(for: fixture.slot.exercise, recentLogs: fixture.logs, wasReturn: true)
        let steady = try substitute(
            ExerciseSwap.swap(
                steadySlot, in: workout([steadySlot], wasReturn: false),
                user: user(), library: catalog, recentLogs: fixture.logs
            )
        )
        let returning = try substitute(
            ExerciseSwap.swap(
                returnSlot, in: workout([returnSlot], wasReturn: true),
                user: user(), library: catalog, recentLogs: fixture.logs
            )
        )

        XCTAssertEqual(returning.exercise.id, steady.exercise.id, "the same movement is chosen either way")
        XCTAssertEqual(steady.reps, 20)
        XCTAssertLessThan(
            try XCTUnwrap(returning.reps), try XCTUnwrap(steady.reps),
            "a substitute on a Return must carry the eased volume, not the full Earned Reps"
        )
        XCTAssertEqual(
            returning.reps,
            AdaptiveOverload.target(
                for: returning.exercise, level: .intermediate, recentLogs: fixture.logs,
                reentryScale: ReturnOverride.reentryFloorScale
            ).reps,
            "the ease applied is the Return's own floor scale"
        )
        XCTAssertEqual(returning.earnedReps, steady.earnedReps, "a Return eases what is served, not what was earned")
    }

    /// The peer's Earned Reps before a Return, the Return, and the first two ramp sessions after it, so
    /// the next session is the ramp's last (one session to go).
    private func lastRampSessionLogs(peer: Exercise) -> [WorkoutLog] {
        [
            log(peer, value: 15, daysAgo: 10),
            emptyLog(daysAgo: 5, wasReturn: true),
            emptyLog(daysAgo: 4),
            emptyLog(daysAgo: 3),
        ]
    }

    /// The Re-entry Ramp sessions that follow a Return are eased too, by the ramp's own partial scale.
    func testSwapDuringTheReentryRampCarriesThePartialEase() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let logs = lastRampSessionLogs(peer: fixture.peer)
        XCTAssertEqual(ReturnOverride.rampSessionsRemaining(recentLogs: logs), 1)
        let slot = servedSlot(for: fixture.slot.exercise, recentLogs: logs, wasReturn: false)

        let result = try substitute(
            ExerciseSwap.swap(
                slot, in: workout([slot], wasReturn: false),
                user: user(), library: [fixture.slot.exercise, fixture.peer], recentLogs: logs
            )
        )
        XCTAssertLessThan(try XCTUnwrap(result.reps), try XCTUnwrap(result.earnedReps), "served at least a step under earned")
        XCTAssertLessThan(
            try XCTUnwrap(result.reps),
            try XCTUnwrap(AdaptiveOverload.target(for: result.exercise, level: .intermediate, recentLogs: logs).reps),
            "a swap mid-ramp must not hand back the full Earned Reps"
        )
        let partiallyEased = AdaptiveOverload.target(
            for: result.exercise, level: .intermediate, recentLogs: logs,
            reentryScale: ReturnOverride.reentryScale(isReturn: false, recentLogs: logs)
        ).reps
        XCTAssertEqual(result.reps, partiallyEased, "a swap mid-ramp carries the ramp's partial ease, once")
    }

    /// A Return or ramp session already serves every main slot under its Earned Reps, so the gap between
    /// a held slot's served number and its Earned Reps is the ease, not a cut the fit took. The substitute
    /// is eased by its own Step 6 target and should not take that gap a second time.
    ///
    /// Known production bug, pinned with a strict expected failure so it flags once fixed:
    /// `ExerciseSwap.overloadTarget` adds `slotValue - slotEarned` to the substitute's already-eased
    /// target. Here the Return serves `push_standard` at 20 against 30 earned, the substitute's own eased
    /// target is 20, and the double ease takes it to 10 - which then lands outside the slot's budget, so the
    /// swap declines and a returning user gets no alternative at all.
    func testSwapOnAReturnEasesTheSubstituteOnlyOnce() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let knee = try XCTUnwrap(library.first { $0.id == "push_knee" })
        let logs = [log(standard, value: 30, daysAgo: 12), log(knee, value: 30, daysAgo: 11)]
        let slot = servedSlot(for: standard, recentLogs: logs, wasReturn: true)
        XCTAssertEqual(slot.reps, 20, "30 earned, held at 0.7 on the Return")
        XCTAssertEqual(slot.earnedReps, 30)
        let expected = AdaptiveOverload.target(
            for: knee, level: .intermediate, recentLogs: logs, reentryScale: ReturnOverride.reentryFloorScale
        ).reps
        XCTAssertEqual(expected, 20)

        let outcome = ExerciseSwap.swap(
            slot, in: workout([slot], wasReturn: true), user: user(), library: [standard, knee], recentLogs: logs
        )
        guard case let .substituted(result) = outcome else {
            return XCTFail("a returning user's swap declined: the substitute was eased twice and fell out of budget")
        }
        XCTAssertEqual(result.reps, expected, "the substitute is eased once, by its own Return target")
    }

    /// A swap mid-ramp follows a step back taken inside the ramp: "too hard" with the move marked
    /// "couldn't finish" on a ramp session takes a step off its Earned Reps, so the substitute is
    /// served lower than after the same ramp session rated "just right".
    func testSwapDuringTheReentryRampHonoursAStepBackInsideTheRamp() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let peer = fixture.peer

        func swapped(ramp1Difficulty: PerceivedDifficulty, tapped: Bool?) throws -> PrescribedExercise {
            var ramp1 = log(peer, value: 20, earned: 25, daysAgo: 2, difficulty: ramp1Difficulty)
            ramp1.exercises[0].couldNotFinish = tapped
            let logs = [
                log(peer, value: 25, earned: 25, daysAgo: 20),
                log(peer, value: 15, earned: 25, daysAgo: 3, wasReturn: true),
                ramp1,
            ]
            let slot = servedSlot(for: fixture.slot.exercise, recentLogs: logs, wasReturn: false)
            return try substitute(
                ExerciseSwap.swap(
                    slot, in: workout([slot], wasReturn: false),
                    user: user(), library: [fixture.slot.exercise, peer], recentLogs: logs
                )
            )
        }

        let steady = try swapped(ramp1Difficulty: .justRight, tapped: nil)
        let steppedBack = try swapped(ramp1Difficulty: .tooHard, tapped: true)
        XCTAssertEqual(steady.earnedReps, 25, "a held ramp session below earned neither climbs nor steps back")
        XCTAssertEqual(steppedBack.earnedReps, 20, "too hard on the ramp session takes a step off")
        XCTAssertLessThan(try XCTUnwrap(steppedBack.reps), try XCTUnwrap(steady.reps))
    }

    /// The general property the tests above are instances of: *every* Step 6 lever the session was sized
    /// with visibly moves the substitute's target. A lever the swap seam forgets to thread makes its row
    /// here collapse onto the neutral target, so one cannot go missing silently.
    func testEveryStep6LeverMovesTheSubstitutesTarget() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let catalog = [fixture.slot.exercise, fixture.peer]

        func reps(policy: SessionPolicy = .default, wasReturn: Bool = false, logs: [WorkoutLog]? = nil) throws -> Int {
            let logs = logs ?? fixture.logs
            let slot = servedSlot(for: fixture.slot.exercise, recentLogs: logs, wasReturn: wasReturn)
            let result = try substitute(
                ExerciseSwap.swap(
                    slot, in: workout([slot], wasReturn: wasReturn),
                    user: user(), library: catalog, recentLogs: logs, sessionPolicy: policy
                )
            )
            return try XCTUnwrap(result.reps)
        }

        let neutral = try reps()
        XCTAssertEqual(neutral, 20, "one qualifying session at the neutral pace climbs a step")

        // The slowest pace takes two qualifying sessions per climb, so one is not enough yet.
        var slower = SessionPolicy.default
        slower.progressionRate = SessionPolicy.minProgressionRate
        XCTAssertLessThan(try reps(policy: slower), neutral, "progressionRate must reach the swap")

        XCTAssertLessThan(try reps(wasReturn: true), neutral, "the Return ease (US-E06) must reach the swap")

        XCTAssertLessThan(try reps(logs: lastRampSessionLogs(peer: fixture.peer)), neutral,
                          "the Re-entry Ramp (US-E06) must reach the swap")

        // "Too hard" at the bottom of the range on push_standard steps the user down onto the peer
        // (ADR-0011), which is then served from the bottom of its range rather than its climbed 20.
        let tooHardAtTheFloor = log(fixture.slot.exercise, value: 15, daysAgo: 1, difficulty: .tooHard)
        XCTAssertEqual(
            try reps(logs: fixture.logs + [tooHardAtTheFloor]),
            RepGrammar.earnedRange(for: fixture.peer, level: .intermediate).lowerBound,
            "a step down at the floor (ADR-0011) must reach the swap"
        )

        // The Start Seed's volume half (US-O02) only reaches a *no-history* target: a fresh advanced
        // user's substitute opens above the bottom of its range.
        let hollow = try XCTUnwrap(library.first { $0.id == "core_hollow_hold" })
        let plank = try XCTUnwrap(library.first { $0.id == "core_forearm_plank" })
        let freshSlot = prescription(for: hollow, perSet: 20, role: .core)
        let seeded = try substitute(
            ExerciseSwap.swap(
                freshSlot, in: workout([freshSlot]), user: user(level: .advanced), library: [hollow, plank],
                recentLogs: [], sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced)
            )
        )
        XCTAssertEqual(seeded.exercise.id, plank.id)
        XCTAssertGreaterThan(
            try XCTUnwrap(seeded.durationSeconds), RepGrammar.earnedRange(for: plank, level: .advanced).lowerBound,
            "the Start Seed (US-O02) must reach the swap"
        )
    }

    // MARK: - Determinism

    func testSwapIsDeterministic() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)
        let session = workout([slot])
        let user = user()

        let first = try substitute(
            ExerciseSwap.swap(slot, in: session, user: user, library: library, recentLogs: [])
        )
        for _ in 0..<25 {
            let next = try substitute(
                ExerciseSwap.swap(slot, in: session, user: user, library: library, recentLogs: [])
            )
            XCTAssertEqual(next.exercise.id, first.exercise.id, "swap selection must be deterministic")
            XCTAssertEqual(next.reps, first.reps)
            XCTAssertEqual(next.durationSeconds, first.durationSeconds)
        }
    }
}
