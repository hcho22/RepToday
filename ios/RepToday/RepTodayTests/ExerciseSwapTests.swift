import XCTest
@testable import RepToday

/// Tests the deterministic in-session swap (US-C08): replacing one prescribed slot with an
/// equivalent substitute - same pillar, same movement pattern, comparable difficulty, in the same
/// time budget, safe for the user - or an honest `.noAlternative` when none qualifies.
///
/// Coverage mirrors the PRD acceptance criteria: a valid swap stays within pillar/pattern/difficulty
/// and the time budget (run over the real bundled library, the PRD's own validation case, and swept at
/// four levels of capacity growth rather than only at the defaults, where the budget check is a no-op);
/// the substitute's set count is the lever that keeps a grown slot in budget, spent only when the slot's
/// own count will not fit and only on the blocks the assembler itself adjusts; the substitute respects
/// phase, injuries, and the Zero-Equipment Floor; injuries are honored even to the point of refusing
/// rather than offering an unsafe pick; the no-alternative cases (lone peer, phase-gated peer, a peer no
/// permitted set count brings into budget) return a clear result; a swap never duplicates a movement
/// already in the session; and swapping is deterministic.
final class ExerciseSwapTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(
        level: FitnessLevel = .intermediate,
        phase: Phase = .discipline,
        injuries: [String] = []
    ) -> User {
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
                injuries: injuries,
                typicalAvailableMinutes: 15
            ),
            phase: phase,
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

    /// A prescribed slot for `exercise` at the given structure, mirroring what the assembler would
    /// have produced (rep-based gets reps, holds get seconds). `perSet` defaults to the movement's own
    /// per-set default - the target Step 6 hands a user with no history of it - so a slot is never in a
    /// state the engine could not have produced for the fixture's own (empty) log set.
    private func prescription(
        for exercise: Exercise,
        sets: Int = 3,
        perSet: Int? = nil,
        rest: Int = SessionAssembly.strengthRestSeconds
    ) -> PrescribedExercise {
        let value = perSet
            ?? (exercise.isHold ? exercise.defaultDurationSeconds : exercise.defaultReps)
            ?? 12
        return PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: exercise.isHold ? nil : value,
            durationSeconds: exercise.isHold ? value : nil,
            restSeconds: rest
        )
    }

    /// A one-block workout wrapping `prescriptions`, enough for the swap to read the session's
    /// existing movements. `wasReturn` stamps the session the way the assembler does, so a swap can be
    /// exercised on a Return.
    private func workout(_ prescriptions: [PrescribedExercise], wasReturn: Bool = false) -> Workout {
        Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: 20,
            wasReturn: wasReturn,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: prescriptions)
            ]
        )
    }

    /// A log in which `worked` were each performed for `sets` sets at `perSet`, so a movement has the
    /// demonstrated capacity the Step 6 levers act on.
    private func log(_ worked: [Exercise], sets: Int, perSet: Int, daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: nil,
            perceivedDifficulty: .justRight,
            exercises: worked.map { exercise in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: exercise.id,
                    pillar: exercise.pillar,
                    movementPattern: exercise.movementPattern,
                    completedSets: Array(
                        repeating: CompletedSet(
                            reps: exercise.isHold ? nil : perSet,
                            durationSeconds: exercise.isHold ? perSet : nil
                        ),
                        count: sets
                    ),
                    skipped: false
                )
            }
        )
    }

    /// The planned wall-clock of one slot, measured exactly as the engine sizes a session: each set at
    /// the work its own target really costs, plus the rests between them.
    private func slotSeconds(of prescription: PrescribedExercise) -> Int {
        prescription.sets * SessionAssembly.workSecondsPerSet(of: prescription)
            + max(0, prescription.sets - 1) * prescription.restSeconds
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
        estPerSet: Int = 40
    ) -> Exercise {
        Exercise(
            id: id,
            displayName: id,
            pillar: pillar,
            movementPattern: pattern,
            category: .strength,
            difficulty: difficulty,
            phase: phase,
            equipment: [],
            isHold: isHold,
            defaultReps: isHold ? nil : 10,
            defaultDurationSeconds: isHold ? 30 : nil,
            estimatedTimePerSetSeconds: estPerSet,
            metValue: 3.0,
            progressionChainId: "chain_\(id)",
            progressionOrder: 0,
            regressionId: nil,
            progressionId: nil,
            advancementCriteria: "3x12 clean reps",
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

        let outcome = ExerciseSwap.swap(
            slot,
            in: workout([slot]),
            user: user(level: .intermediate),
            library: library,
            recentLogs: []
        )
        let result = try substitute(outcome)

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

    func testSwapPreservesTheSlotsTimeBudget() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target, sets: 3, rest: SessionAssembly.strengthRestSeconds)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )

        // A default-sized slot is in budget at its own set count, so the substitute keeps it; rest is
        // always preserved.
        XCTAssertEqual(result.sets, slot.sets, "an in-budget slot keeps its set count")
        XCTAssertEqual(result.restSeconds, slot.restSeconds, "rest is preserved for timing fidelity")

        // Measured the way the engine sizes a session: each side at the target it actually carries,
        // not at the two movements' default-sized estimates.
        XCTAssertLessThanOrEqual(
            abs(slotSeconds(of: result) - slotSeconds(of: slot)), ExerciseSwap.slotToleranceSeconds,
            "the swap must not move the slot's wall-clock beyond its tolerance"
        )
    }

    /// The budget check prices both sides at their *own* targets, so a capacity-grown slot cannot be
    /// swapped for a movement whose flat estimate happens to match while its actual work does not.
    /// Before this, both sides were compared at `estimatedTimePerSetSeconds` and this swap sailed
    /// through with a drift of zero while the session lost minutes.
    func testSwapRejectsAPeerThatOnlyMatchesAtItsDefaultSizedEstimate() async throws {
        let library = try await library()
        let diamond = try XCTUnwrap(library.first { $0.id == "push_diamond" })
        let pike = try XCTUnwrap(library.first { $0.id == "push_pike" })

        // Two movements with identical estimates and defaults (45s / 8 reps), so a flat comparison
        // reports zero drift - but the slot is prescribed at 20 reps, well above the 8-rep default.
        XCTAssertEqual(diamond.estimatedTimePerSetSeconds, pike.estimatedTimePerSetSeconds)
        XCTAssertEqual(diamond.defaultReps, pike.defaultReps)
        let grown = prescription(for: diamond, sets: 3, perSet: 20)

        // The substitute has no history, so it would open at its own 8-rep default: far less work per
        // set than the 20-rep slot it replaces.
        let outcome = ExerciseSwap.swap(
            grown,
            in: workout([grown]),
            user: user(),
            library: [diamond, pike],
            recentLogs: []
        )
        XCTAssertEqual(
            outcome, .noAlternative,
            "a newcomer's starting target is not a comparable time cost for a capacity-grown slot"
        )
    }

    /// Whatever the swap does hand back, it lands inside the tolerance measured against the session's
    /// own work model - across every rep-based and hold slot the real library can produce, at four levels
    /// of capacity growth.
    ///
    /// The growth sweep is the point. At the movement's own default the target-scaled budget check is a
    /// *no-op* (both sides are priced at their authored estimates), which is exactly the configuration in
    /// which an earlier version of this sweep passed while real coverage at grown targets had collapsed
    /// to near zero. Growing the slot is what makes the substitute's own no-history default diverge from
    /// the target the slot carries, which is the case the set-count lever exists for.
    func testEverySubstituteTheLibraryOffersStaysInsideTheSlotBudget() async throws {
        let library = try await library()
        let user = user(level: .advanced)

        for growth in [1.0, 1.25, 1.5, 2.0] {
            var swapped = 0
            for movement in library {
                let baseline = (movement.isHold ? movement.defaultDurationSeconds : movement.defaultReps) ?? 10
                let slot = prescription(
                    for: movement,
                    perSet: max(1, Int((Double(baseline) * growth).rounded()))
                )
                guard case let .substituted(result) = ExerciseSwap.swap(
                    slot, in: workout([slot]), user: user, library: library, recentLogs: []
                ) else { continue }
                swapped += 1
                XCTAssertLessThanOrEqual(
                    abs(slotSeconds(of: result) - slotSeconds(of: slot)),
                    ExerciseSwap.slotToleranceSeconds,
                    "swapping \(movement.id) for \(result.exercise.id) at x\(growth) moved the slot out of budget"
                )
                XCTAssertTrue(
                    (SessionAssembly.minTrainingSets...SessionAssembly.maxTrainingSets).contains(result.sets),
                    "swapping \(movement.id) at x\(growth) left the assembler's set-count rails"
                )
            }
            // A movement whose pattern has no in-band peer reachable inside the budget legitimately
            // declines, so the loop tolerates `.noAlternative` - but coverage has to hold up at *every*
            // growth level, not just at the defaults where the budget check does nothing. Before the
            // set-count lever, x1.5 dropped to 18/42 of the strength/primal catalog and x2.0 to 3/42.
            XCTAssertGreaterThan(
                swapped * 4, library.count * 3,
                "at x\(growth) only \(swapped)/\(library.count) movements could be swapped - the pool has collapsed"
            )
        }
    }

    /// The set count is the lever that keeps a capacity-grown slot swappable: a substitute the user has
    /// never logged opens at its own default, and the assembler's own `minTrainingSets...maxTrainingSets`
    /// rails absorb the difference instead of the swap refusing outright.
    func testSwapRepicksTheSetCountToKeepAGrownSlotInBudget() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        // A user well into the tier: `push_standard` advances at "3x12" off an 8-rep default, so this is
        // an ordinary place to be, not an exotic one - and at a fixed 3 sets every push peer was refused.
        let grown = prescription(for: standard, sets: 3, perSet: 12)

        let result = try substitute(
            ExerciseSwap.swap(grown, in: workout([grown]), user: user(), library: library, recentLogs: [])
        )

        XCTAssertNotEqual(result.exercise.id, standard.id)
        XCTAssertTrue(
            (SessionAssembly.minTrainingSets...SessionAssembly.maxTrainingSets).contains(result.sets),
            "the re-pick must stay inside the assembler's own set-count rails"
        )
        XCTAssertLessThanOrEqual(
            abs(slotSeconds(of: result) - slotSeconds(of: grown)),
            ExerciseSwap.slotToleranceSeconds,
            "the re-picked set count must bring the slot inside its budget"
        )
    }

    /// The lever is only used when it is needed: a slot already in budget at its own set count keeps it,
    /// so a swap never silently restructures a slot it had no reason to touch.
    func testSwapKeepsTheOriginalSetCountWhenItIsAlreadyInBudget() async throws {
        let library = try await library()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: standard, sets: 3)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )
        XCTAssertEqual(result.sets, slot.sets, "an in-budget slot keeps its set count")
    }

    /// The warm-up and the cooldown are one set of a stretch by construction (`allowSetAdjust: false`),
    /// so the swap must not reach for the set lever there even when it would improve the fit - a
    /// four-set warm-up stretch is not a session the assembler could have produced.
    func testSwapNeverMovesTheSetCountOfAStructuralBookend() async throws {
        // A single-set stretch slot grown to 90s (100s of work) beside a peer that opens at its own 30s
        // default (40s of work): the only way into budget is two sets of the peer (40 + 15 + 40 = 95s),
        // so the same swap must succeed in a training block and be refused in a bookend.
        let stretch = makeExercise(id: "stretch_long", pillar: .mobility, pattern: .mobility, isHold: true)
        let peer = makeExercise(id: "stretch_peer", pillar: .mobility, pattern: .mobility, isHold: true)
        let catalog = [stretch, peer]
        let slot = prescription(for: stretch, sets: 1, perSet: 90, rest: SessionAssembly.mobilityRestSeconds)

        func session(title: String, category: ExerciseCategory) -> Workout {
            Workout(
                id: UUID(),
                createdAt: asOf,
                shape: .blend,
                focusPillar: nil,
                requestedMinutes: 20,
                wasReturn: false,
                blocks: [WorkoutBlock(id: UUID(), title: title, category: category, exercises: [slot])]
            )
        }

        XCTAssertEqual(
            ExerciseSwap.swap(
                slot,
                in: session(title: "Warm-Up", category: .warmup),
                user: user(), library: catalog, recentLogs: []
            ),
            .noAlternative,
            "a warm-up slot may not spend the set lever, so an out-of-budget peer is refused outright"
        )

        let adjusted = try substitute(
            ExerciseSwap.swap(
                slot,
                in: session(title: "Movement Practice", category: .mobility),
                user: user(), library: catalog, recentLogs: []
            )
        )
        XCTAssertEqual(adjusted.sets, 2, "a set-adjustable block spends the lever to stay in budget")
    }

    /// The Start Seed (US-O02) is scoped to strength and primal in the assembler, so a swapped *mobility*
    /// movement must open at its own default for an advanced cold-start user, exactly as the warm-up,
    /// Movement Practice and cooldown the assembler built for them did.
    func testSwapDoesNotApplyTheStartSeedToAMobilitySubstitute() async throws {
        let library = try await library()
        let fold = try XCTUnwrap(library.first { $0.id == "mobility_forward_fold" })
        let slot = prescription(for: fold, sets: 1, rest: SessionAssembly.mobilityRestSeconds)

        let result = try substitute(
            ExerciseSwap.swap(
                slot,
                in: workout([slot]),
                user: user(level: .advanced),
                library: library,
                recentLogs: [],
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced)
            )
        )
        XCTAssertEqual(result.exercise.pillar, .mobility)
        XCTAssertEqual(
            result.durationSeconds ?? result.reps,
            result.exercise.isHold ? result.exercise.defaultDurationSeconds : result.exercise.defaultReps,
            "a mobility substitute opens at its own default, unseeded, like every other stretch"
        )
    }

    func testSubstituteCarriesACapacityRelativePerSetTarget() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        let result = try substitute(
            ExerciseSwap.swap(slot, in: workout([slot]), user: user(), library: library, recentLogs: [])
        )

        // Exactly one of reps / durationSeconds, matching the substitute's isHold, within the rails -
        // never a fixed heroic number.
        if result.exercise.isHold {
            XCTAssertNotNil(result.durationSeconds)
            XCTAssertNil(result.reps)
            XCTAssertLessThanOrEqual(result.durationSeconds!, AdaptiveOverload.maxHoldSeconds)
        } else {
            XCTAssertNotNil(result.reps)
            XCTAssertNil(result.durationSeconds)
            XCTAssertLessThanOrEqual(result.reps!, AdaptiveOverload.maxReps)
        }
    }

    // MARK: - Injuries are respected

    func testSwapRefusesWhenEveryPeerIsInjuryUnsafe() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        // A shoulder injury contraindicates the whole push pattern, so no push substitute is safe -
        // the engine returns no-alternative rather than handing back an injurious movement.
        let outcome = ExerciseSwap.swap(
            slot,
            in: workout([slot]),
            user: user(injuries: ["shoulders"]),
            library: library,
            recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "an injured pattern must yield no substitute, not an unsafe one")
    }

    func testInjuryOnAnotherPatternStillAllowsASafeSwap() async throws {
        let library = try await library()
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let slot = prescription(for: target)

        // A knee injury rules out squats but leaves push untouched; the push slot still swaps cleanly.
        let result = try substitute(
            ExerciseSwap.swap(
                slot, in: workout([slot]), user: user(injuries: ["knees"]), library: library, recentLogs: []
            )
        )
        XCTAssertEqual(result.exercise.movementPattern, .push, "a knee injury must not derail a push swap")
        XCTAssertNotEqual(result.exercise.movementPattern, .squat, "never substitute into the injured pattern")
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
            slot,
            in: workout([slot]),
            user: user(phase: .discipline),
            library: [standard, oneArm],
            recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "a phase-gated lone peer must not be offered to a discipline user")
    }

    func testNoAlternativeWhenThePatternHasASingleExercise() async throws {
        let only = makeExercise(id: "push_solo")
        let slot = prescription(for: only)

        let outcome = ExerciseSwap.swap(
            slot,
            in: workout([slot]),
            user: user(),
            library: [only],
            recentLogs: []
        )
        XCTAssertEqual(outcome, .noAlternative, "no peer at all means no substitute")
    }

    func testNoAlternativeWhenEveryPeerBlowsTheTimeBudget() async throws {
        // Same pillar/pattern/difficulty and bodyweight, but the only peer takes far longer per set,
        // so swapping it would move the session well beyond the slot tolerance: rejected.
        let target = makeExercise(id: "push_quick", estPerSet: 30)
        let slowPeer = makeExercise(id: "push_marathon", estPerSet: 200)
        let slot = prescription(for: target, sets: 1)

        let outcome = ExerciseSwap.swap(
            slot,
            in: workout([slot]),
            user: user(),
            library: [target, slowPeer],
            recentLogs: []
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
                standardSlot,
                in: workout([standardSlot, dipsSlot]),
                user: user(),
                library: library,
                recentLogs: []
            )
        )
        XCTAssertEqual(result.exercise.movementPattern, .push)
        XCTAssertNotEqual(result.exercise.id, floorDips.id, "must not duplicate a movement already in the session")
        XCTAssertNotEqual(result.exercise.id, standard.id, "must not return the swapped movement itself")
    }

    // MARK: - The substitute is sized by the same Step 6 levers as the slot it replaces

    /// A push slot whose only in-band peer (`push_knee`) already has demonstrated capacity, so every
    /// Step 6 lever has something to act on. One set keeps the slot's own budget check out of the way.
    private func leveredSwapFixture(
        library: [Exercise]
    ) throws -> (slot: PrescribedExercise, peer: Exercise, logs: [WorkoutLog]) {
        let target = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let peer = try XCTUnwrap(library.first { $0.id == "push_knee" })
        return (
            prescription(for: target, sets: 1),
            peer,
            [log([peer], sets: 3, perSet: 12, daysAgo: 3)]
        )
    }

    /// A Return holds every assembled slot below full volume (US-E06); a swapped-in slot must be held
    /// back too, or one tap hands the returning user the single hardest slot in a session whose whole
    /// point is to be uniformly gentle.
    func testSwapOnAReturnCarriesTheReentryEase() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let catalog = [fixture.slot.exercise, fixture.peer]

        let steady = try substitute(
            ExerciseSwap.swap(
                fixture.slot,
                in: workout([fixture.slot], wasReturn: false),
                user: user(),
                library: catalog,
                recentLogs: fixture.logs
            )
        )
        let returning = try substitute(
            ExerciseSwap.swap(
                fixture.slot,
                in: workout([fixture.slot], wasReturn: true),
                user: user(),
                library: catalog,
                recentLogs: fixture.logs
            )
        )

        XCTAssertEqual(returning.exercise.id, steady.exercise.id, "the same movement is chosen either way")
        XCTAssertLessThan(
            try XCTUnwrap(returning.reps), try XCTUnwrap(steady.reps),
            "a substitute on a Return must carry the eased volume, not the full capacity target"
        )
        XCTAssertEqual(
            returning.reps,
            AdaptiveOverload.target(
                for: returning.exercise,
                recentLogs: fixture.logs,
                reentryScale: ReturnOverride.reentryFloorScale
            ).reps,
            "the ease applied is the Return's own floor scale"
        )
    }

    /// The Re-entry Ramp sessions that follow a Return are eased too, by the ramp's own partial scale.
    func testSwapDuringTheReentryRampCarriesThePartialEase() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        var ramping = SessionPolicy.default
        ramping.reentry = SessionPolicy.Reentry(rampSessionsRemaining: 1)

        let result = try substitute(
            ExerciseSwap.swap(
                fixture.slot,
                in: workout([fixture.slot], wasReturn: false),
                user: user(),
                library: [fixture.slot.exercise, fixture.peer],
                recentLogs: fixture.logs,
                sessionPolicy: ramping
            )
        )
        XCTAssertEqual(
            result.reps,
            AdaptiveOverload.target(
                for: result.exercise,
                recentLogs: fixture.logs,
                reentryScale: ReturnOverride.reentryScale(isReturn: false, reentry: ramping.reentry)
            ).reps,
            "a swap mid-ramp must carry the ramp's partial ease, not the full capacity target"
        )
    }

    /// The general property the two tests above are instances of: *every* Step 6 lever the session was
    /// sized with visibly moves the substitute's target. A lever the swap seam forgets to thread makes
    /// its row here collapse onto the neutral target, so a third one cannot go missing silently.
    func testEveryStep6LeverMovesTheSubstitutesTarget() async throws {
        let library = try await library()
        let fixture = try leveredSwapFixture(library: library)
        let catalog = [fixture.slot.exercise, fixture.peer]

        func reps(policy: SessionPolicy = .default, wasReturn: Bool = false) throws -> Int {
            let result = try substitute(
                ExerciseSwap.swap(
                    fixture.slot,
                    in: workout([fixture.slot], wasReturn: wasReturn),
                    user: user(),
                    library: catalog,
                    recentLogs: fixture.logs,
                    sessionPolicy: policy
                )
            )
            return try XCTUnwrap(result.reps)
        }

        let neutral = try reps()

        var faster = SessionPolicy.default
        faster.progressionRate = 3.0
        XCTAssertGreaterThan(try reps(policy: faster), neutral, "progressionRate (US-E03) must reach the swap")

        XCTAssertLessThan(try reps(wasReturn: true), neutral, "the Return ease (US-E06) must reach the swap")

        var ramping = SessionPolicy.default
        ramping.reentry = SessionPolicy.Reentry(rampSessionsRemaining: 1)
        XCTAssertLessThan(try reps(policy: ramping), neutral, "the Re-entry Ramp (US-E06) must reach the swap")

        // The Start Seed's volume half (US-O02) only reaches a *no-history* target, so it is pinned on
        // the untouched peer: a fresh advanced user's substitute opens above the movement's own default.
        let fresh = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let freshSlot = prescription(for: fresh, sets: 1)
        let seeded = try substitute(
            ExerciseSwap.swap(
                freshSlot,
                in: workout([freshSlot]),
                user: user(level: .advanced),
                library: catalog,
                recentLogs: [],
                sessionPolicy: SessionPolicy.seeded(forFitnessLevel: .advanced)
            )
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(seeded.reps), try XCTUnwrap(seeded.exercise.defaultReps),
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
        }
    }
}
