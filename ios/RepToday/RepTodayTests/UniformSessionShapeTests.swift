import XCTest
@testable import RepToday

/// US-M04: Uniform three-part vocabulary, length-scaled bookends.
///
/// This suite adds **no engine behavior** - US-M01..US-M03 already built the structure it pins. It is
/// the story's validation test: it sweeps every requested length in `5, 10, 15, 20, 30, 45, 60` through
/// the real `SessionAssembly.assemble` pipeline and proves that every session, at every length, is
/// describable with one uniform vocabulary - **Warm-Up -> Strength -> Cooldown** (with a dedicated
/// **Primal** block as an extra fourth block only at the extended 41-60 min lengths) - so no future
/// contributor or UI re-derives a strength-vs-mobility "blend split".
///
/// Concretely it asserts, off the blocks the assembly actually produced (not off a re-derived plan):
///
///   1. **Uniform shape.** The ordered block categories are exactly `.warmup` first, then the single
///      `.strength` training block, then (only at 41-60 min) the `.primal` block, then (only past the
///      cooldown threshold) the closing `.cooldown` - and **never** a `.mobility` block anywhere. There
///      is no mobility middle block between the bookends at any length.
///   2. **Length-scaled, non-forced bookends.** The warm-up is seeded at the length-scaled
///      `warmupExerciseCount` (1 / 2 / 3 / 4 across the bands) and the cooldown appears **iff** the
///      session runs past `cooldownThresholdMinutes` - so the shortest 5/10-min sessions are lean,
///      warm-up-only, and are not force-fitted with a cooldown they should not carry.
///   3. **Strength leads the clock.** Strength holds the majority of *training* time (warm-up and
///      cooldown excluded) at every length: mobility contributes zero training seconds, and where an
///      extended blend carves a dedicated primal minority (US-E02) strength still stays > ~0.80 of the
///      training clock, consistent with `extendedPrimalTrainingShare = 0.15`.
///
/// `StrengthPrimaryRegressionTests` sweeps the same lengths for the *strength-lead / no-mobility-middle*
/// invariant across three generation regimes; this suite is the complementary check that the surviving
/// shape reads cleanly as the uniform three-/four-part vocabulary US-M04 names, and that the bookends
/// stay length-scaled rather than forced.
final class UniformSessionShapeTests: XCTestCase {

    // MARK: - Fixtures (mirror StrengthPrimaryRegressionTests so the sweep exercises the real pipeline)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    /// The seven lengths the story validates: two single-focus (5, 10), three light/full blends
    /// (15, 20, 30), and two extended blends (45, 60) - so every session shape the engine builds is
    /// covered.
    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func user(sitsLong: Bool = false) -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .intermediate,
                primaryGoal: .stayActive,
                sitsLong: sitsLong,
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

    private func assemble(minutes: Int, user: User, library: [Exercise]) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: [],
            sessionPolicy: .default,
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - Share helpers (reuse the engine's own work model)

    /// Planned wall-clock of one materialized block (`Σ sets × workPerSet + (sets - 1) × rest`),
    /// measured with the engine's own per-set work model.
    private func plannedSeconds(_ block: WorkoutBlock) -> Int {
        block.exercises.reduce(0) { sum, p in
            sum + p.sets * SessionAssembly.workSecondsPerSet(of: p) + max(0, p.sets - 1) * p.restSeconds
        }
    }

    /// Planned training seconds per pillar (warm-up and cooldown bookends excluded), keyed by the
    /// block's pillar.
    private func trainingSecondsByPillar(_ workout: Workout) -> [Pillar: Int] {
        var totals: [Pillar: Int] = [:]
        for block in workout.blocks where block.category != .warmup && block.category != .cooldown {
            guard let pillar = SessionAssembly.pillar(of: block.category) else { continue }
            totals[pillar, default: 0] += plannedSeconds(block)
        }
        return totals
    }

    // MARK: - 1. Uniform Warm-Up -> Strength -> (Primal) -> Cooldown shape

    /// Every generated session, at every length, maps cleanly onto the three-part vocabulary (four-part
    /// at 41-60 min): a `.warmup` bookend, exactly one `.strength` training block, a `.primal` block only
    /// at the extended lengths, and a closing `.cooldown` only past the cooldown threshold - in that
    /// order, and with **no** `.mobility` block anywhere. This is the structural half of US-M04: there is
    /// no mobility middle block to re-read as a strength-vs-mobility split at any length.
    func testEveryLengthMapsOntoTheUniformThreePartShape() async throws {
        let library = try await library()
        for minutes in lengths {
            let workout = assemble(minutes: minutes, user: user(), library: library)
            let categories = workout.blocks.map(\.category)
            let expectsCooldown = minutes > SessionAssembly.cooldownThresholdMinutes
            let expectsPrimal = minutes >= 41

            // No mobility middle block at any length - mobility survives only as the bookends.
            XCTAssertFalse(
                categories.contains(.mobility),
                "\(minutes) min must have no mobility training block (mobility is bookend-only)"
            )
            // The only categories that may appear are the four uniform-vocabulary blocks.
            XCTAssertTrue(
                categories.allSatisfy { [.warmup, .strength, .primal, .cooldown].contains($0) },
                "\(minutes) min produced an off-vocabulary block: \(categories)"
            )

            // Exactly the expected blocks are present.
            XCTAssertEqual(
                categories.filter { $0 == .warmup }.count, 1,
                "\(minutes) min must open with exactly one warm-up bookend"
            )
            XCTAssertEqual(
                categories.filter { $0 == .strength }.count, 1,
                "\(minutes) min must contain exactly one strength training block"
            )
            XCTAssertEqual(
                categories.filter { $0 == .primal }.count, expectsPrimal ? 1 : 0,
                "\(minutes) min primal-block presence must match the extended-length shape"
            )
            XCTAssertEqual(
                categories.filter { $0 == .cooldown }.count, expectsCooldown ? 1 : 0,
                "\(minutes) min cooldown presence must match the cooldown threshold"
            )

            // Ordering: warm-up first, cooldown (when present) last, strength before any primal block.
            XCTAssertEqual(categories.first, .warmup, "\(minutes) min must open with the warm-up")
            if expectsCooldown {
                XCTAssertEqual(categories.last, .cooldown, "\(minutes) min must close with the cooldown")
            } else {
                XCTAssertNotEqual(categories.last, .cooldown, "\(minutes) min must not close with a cooldown")
            }
            if expectsPrimal {
                let strengthIndex = try XCTUnwrap(categories.firstIndex(of: .strength))
                let primalIndex = try XCTUnwrap(categories.firstIndex(of: .primal))
                XCTAssertLessThan(
                    strengthIndex, primalIndex,
                    "\(minutes) min strength block must lead the dedicated primal block"
                )
            }

            // No empty blocks reach the player.
            XCTAssertTrue(
                workout.blocks.allSatisfy { !$0.exercises.isEmpty },
                "\(minutes) min emitted an empty block"
            )
        }
    }

    // MARK: - 2. Bookends stay lean and length-scaled; cooldown not forced on the shortest sessions

    /// The warm-up is seeded at the length-scaled `warmupExerciseCount` (1 / 2 / 3 / 4 across the bands),
    /// one set per movement, and the cooldown appears **iff** the session runs past
    /// `cooldownThresholdMinutes`. So the shortest 5/10-min sessions are lean and warm-up-only - never
    /// force-fitted with a cooldown they should not carry - while a longer session opens fuller. Asserts
    /// the actual shipped contract rather than imposing a new one.
    func testBookendsAreLengthScaledAndNotForcedOntoShortSessions() async throws {
        let library = try await library()
        for minutes in lengths {
            let workout = assemble(minutes: minutes, user: user(), library: library)

            let warmup = try XCTUnwrap(
                workout.blocks.first { $0.category == .warmup },
                "\(minutes) min must have a warm-up"
            )
            let expectedWarmupCount = SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes)
            XCTAssertEqual(
                warmup.exercises.count, expectedWarmupCount,
                "\(minutes) min warm-up must be seeded at the length-scaled count"
            )
            // Bookends are one set per movement - a stretch is never multi-set.
            XCTAssertTrue(
                warmup.exercises.allSatisfy { $0.sets == 1 },
                "\(minutes) min warm-up bookend must be one set per movement"
            )

            let cooldown = workout.blocks.first { $0.category == .cooldown }
            if minutes > SessionAssembly.cooldownThresholdMinutes {
                let cooldown = try XCTUnwrap(cooldown, "\(minutes) min must carry a cooldown")
                XCTAssertFalse(cooldown.exercises.isEmpty, "\(minutes) min cooldown must not be empty")
                XCTAssertLessThanOrEqual(
                    cooldown.exercises.count, SessionAssembly.maxCooldownExercises,
                    "\(minutes) min cooldown must stay within the lean bookend ceiling"
                )
                XCTAssertTrue(
                    cooldown.exercises.allSatisfy { $0.sets == 1 },
                    "\(minutes) min cooldown bookend must be one set per movement"
                )
            } else {
                XCTAssertNil(cooldown, "\(minutes) min must not be force-fitted with a cooldown")
            }
        }
    }

    // MARK: - 3. Strength keeps the majority of the training clock at every length

    /// Strength holds the majority of *training* time (bookends excluded) at every length: mobility
    /// contributes zero training seconds, and where an extended blend carves a dedicated primal minority
    /// (US-E02) strength still stays above ~0.80 of the training clock - consistent with
    /// `extendedPrimalTrainingShare = 0.15`. This is the "strength leads the clock everywhere" half of
    /// US-M04's expected result.
    func testStrengthKeepsTheMajorityOfTrainingTimeAtEveryLength() async throws {
        let library = try await library()
        for minutes in lengths {
            let workout = assemble(minutes: minutes, user: user(), library: library)
            let totals = trainingSecondsByPillar(workout)
            let strengthSeconds = totals[.strength] ?? 0
            let primalSeconds = totals[.primal] ?? 0
            let totalTraining = totals.values.reduce(0, +)

            XCTAssertGreaterThan(totalTraining, 0, "\(minutes) min produced no training time")
            XCTAssertEqual(
                totals[.mobility] ?? 0, 0,
                "\(minutes) min must emit no mobility training seconds (mobility is bookend-only)"
            )

            let strengthShare = Double(strengthSeconds) / Double(totalTraining)
            XCTAssertGreaterThan(
                strengthShare, 0.5,
                "\(minutes) min: strength must hold the majority of training time (share \(strengthShare))"
            )
            // Strength leads any dedicated primal block, and stays well above the archived accessory model.
            XCTAssertGreaterThan(
                strengthSeconds, primalSeconds,
                "\(minutes) min: strength must lead any dedicated primal block"
            )
            XCTAssertGreaterThan(
                strengthShare, 0.80,
                "\(minutes) min: strength share \(strengthShare) must stay above the extended primal minority"
            )
        }
    }

    // MARK: - Determinism (this validation guard does not read the wall clock)

    /// The uniform-shape sweep is a pure function of the injected `asOf`: the block-category signature at
    /// each length is byte-identical run to run, so nothing the assertions above read touches the wall
    /// clock.
    func testUniformShapeSweepIsDeterministic() async throws {
        let library = try await library()
        for minutes in lengths {
            let first = assemble(minutes: minutes, user: user(), library: library).blocks.map(\.category)
            for _ in 0..<5 {
                let again = assemble(minutes: minutes, user: user(), library: library).blocks.map(\.category)
                XCTAssertEqual(again, first, "\(minutes) min block shape is not deterministic")
            }
        }
    }
}
