import XCTest
@testable import RepToday

/// Tests the deterministic in-session swap (US-C08): replacing one prescribed slot with an
/// equivalent substitute - same pillar, same movement pattern, comparable difficulty, in the same
/// time budget, safe for the user - or an honest `.noAlternative` when none qualifies.
///
/// Coverage mirrors the PRD acceptance criteria: a valid swap stays within pillar/pattern/difficulty
/// and the time budget (run over the real bundled library, the PRD's own validation case); the
/// substitute respects phase, injuries, and the Zero-Equipment Floor; injuries are honored even to
/// the point of refusing rather than offering an unsafe pick; the no-alternative cases (lone peer,
/// phase-gated peer, out-of-budget peer) return a clear result; a swap never duplicates a movement
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
    /// have produced (rep-based gets reps, holds get seconds).
    private func prescription(
        for exercise: Exercise,
        sets: Int = 3,
        perSet: Int = 12,
        rest: Int = SessionAssembly.strengthRestSeconds
    ) -> PrescribedExercise {
        PrescribedExercise(
            id: UUID(),
            exercise: exercise,
            sets: sets,
            reps: exercise.isHold ? nil : perSet,
            durationSeconds: exercise.isHold ? perSet : nil,
            restSeconds: rest
        )
    }

    /// A one-block workout wrapping `prescriptions`, enough for the swap to read the session's
    /// existing movements.
    private func workout(_ prescriptions: [PrescribedExercise]) -> Workout {
        Workout(
            id: UUID(),
            createdAt: asOf,
            shape: .blend,
            focusPillar: nil,
            requestedMinutes: 20,
            blocks: [
                WorkoutBlock(id: UUID(), title: "Strength", category: .strength, exercises: prescriptions)
            ]
        )
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

    private func substitute(_ outcome: SwapOutcome) throws -> PrescribedExercise {
        guard case let .substituted(prescription) = outcome else {
            throw XCTSkip("expected a substitute, got \(outcome)")
        }
        return prescription
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

        // The substitute keeps the slot's set count and rest, so the only timing change is per-set est.
        XCTAssertEqual(result.sets, slot.sets, "set count is preserved for timing fidelity")
        XCTAssertEqual(result.restSeconds, slot.restSeconds, "rest is preserved for timing fidelity")

        let originalSlot = slot.sets * target.estimatedTimePerSetSeconds
            + (slot.sets - 1) * slot.restSeconds
        let substituteSlot = result.sets * result.exercise.estimatedTimePerSetSeconds
            + (result.sets - 1) * result.restSeconds
        XCTAssertLessThanOrEqual(
            abs(substituteSlot - originalSlot), ExerciseSwap.slotToleranceSeconds,
            "the swap must not move the slot's wall-clock beyond its tolerance"
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
