import XCTest
@testable import RepToday

/// US-M02: pattern-matched, prefer-then-fill bookends.
///
/// The warm-up and cooldown each *lead* with a stretch whose new `complements: [MovementPattern]`
/// metadata contains the day's lead strength pattern (Step 3), then fill the remaining slots with the
/// existing staleness / no-repeat variety ordering. The match is a **preference, never an exclusive
/// filter**: when no complementary stretch is available the general mobility pool fills the bookend,
/// which is therefore never starved or emptied.
///
/// Coverage mirrors the PRD acceptance criteria, run end-to-end over the real bundled library:
///   (a) the leading warm-up and cooldown stretch complements the lead pattern for squat / push / core
///       (the PRD validation set), verified against the strength block's actual lead;
///   (b) a general-pool fallback appears - never an empty bookend - when no complementary stretch is
///       available (a library whose stretches complement no such pattern);
///   (c) the >= 6-complementary-stretches-per-pattern coverage invariant, plus the whole mapping being
///       tagged on all 26 mobility movements;
///   (d) determinism and `asOf`-purity: identical inputs (and staleness-preserving `asOf` shifts) yield
///       byte-identical bookend orderings, so the prefer-then-fill reorder adds no nondeterminism.
final class BookendComplementSelectionTests: XCTestCase {

    // MARK: - Fixtures (mirror SessionAssemblyTests so the sweep exercises the real pipeline)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func date(daysAgo: Int, from reference: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: reference ?? asOf)!
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

    /// A completed strength session `daysAgo` working each of `patterns` (one representative movement
    /// per pattern), used to control which strength pattern is stalest.
    private func strengthLog(_ patterns: [MovementPattern], daysAgo: Int, from reference: Date? = nil) -> WorkoutLog {
        let repId: [MovementPattern: String] = [
            .push: "push_wall", .squat: "squat_wall_sit", .hinge: "hinge_glute_bridge",
            .core: "core_forearm_plank", .pull: "pull_superman",
        ]
        return WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo, from: reference),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: .strength,
            perceivedDifficulty: .justRight,
            exercises: patterns.map { pattern in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: repId[pattern]!,
                    pillar: .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 12, durationSeconds: nil)],
                    skipped: false
                )
            }
        )
    }

    /// History that forces `target` to be the day's lead strength pattern: every *other* strength
    /// pattern is worked yesterday (fresh), leaving `target` never-worked and therefore maximally
    /// stale, so Step 3 leads with it. No mobility is logged, so the whole mobility pool is fresh and
    /// the bookend ordering is driven purely by the prefer-then-fill bias plus the deterministic
    /// tie-breaks.
    private func forcingLead(_ target: MovementPattern, from reference: Date? = nil) -> [WorkoutLog] {
        let others = [MovementPattern.push, .squat, .hinge, .core, .pull].filter { $0 != target }
        return [strengthLog(others, daysAgo: 1, from: reference)]
    }

    private func assemble(
        minutes: Int,
        user: User,
        library: [Exercise],
        logs: [WorkoutLog],
        asOf: Date? = nil
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            asOf: asOf ?? self.asOf,
            calendar: calendar
        )
    }

    private func block(_ workout: Workout, _ category: ExerciseCategory) -> WorkoutBlock? {
        workout.blocks.first { $0.category == category }
    }

    // MARK: - (a) The leading bookend stretch complements the lead pattern

    /// The PRD validation set: for lead patterns squat, push, and core, the first warm-up stretch and
    /// the first cooldown stretch each complement the day's lead strength pattern. 20 minutes keeps the
    /// warm-up lean (2 movements) so at least one complementary hold always survives for the cooldown,
    /// even for `core`, whose complementary-hold count is the smallest.
    func testLeadingBookendStretchComplementsTheLeadPattern() async throws {
        let library = try await library()
        for target in [MovementPattern.squat, .push, .core] {
            let workout = assemble(minutes: 20, user: user(), library: library, logs: forcingLead(target))

            // The forcing worked: the strength block actually leads with `target`.
            let strength = try XCTUnwrap(block(workout, .strength), "\(target): a 20-min session has a strength block")
            XCTAssertEqual(
                strength.exercises.first?.exercise.movementPattern, target,
                "\(target): forcing history did not make it the strength lead"
            )

            let warmup = try XCTUnwrap(block(workout, .warmup), "\(target): a session opens with a warm-up")
            let firstWarm = try XCTUnwrap(warmup.exercises.first?.exercise, "\(target): the warm-up is never empty")
            XCTAssertEqual(firstWarm.pillar, .mobility, "\(target): the leading warm-up item is a stretch")
            XCTAssertTrue(
                firstWarm.complements?.contains(target) == true,
                "\(target): warm-up leads with '\(firstWarm.id)', which does not complement \(target)"
            )

            let cooldown = try XCTUnwrap(block(workout, .cooldown), "\(target): a 20-min session has a cooldown")
            let firstCool = try XCTUnwrap(cooldown.exercises.first?.exercise, "\(target): the cooldown is never empty")
            XCTAssertTrue(
                firstCool.complements?.contains(target) == true,
                "\(target): cooldown leads with '\(firstCool.id)', which does not complement \(target)"
            )
        }
    }

    // MARK: - (b) General-pool fallback, never an empty bookend

    /// When no stretch in the pool complements the lead pattern, the bias is a no-op and the general
    /// mobility ordering fills the bookend: the warm-up and cooldown are still present, still at their
    /// length-scaled count, and simply lead with the freshest general stretch. This exhausts the
    /// complementary set by handing the assembler a library whose mobility stretches no longer complement
    /// the lead pattern (the metadata is the only lever the bias reads), which is exactly the state a
    /// fully-consumed complementary pool would leave the ordering in.
    func testFallsBackToGeneralPoolWhenNoComplementaryStretchIsAvailable() async throws {
        let base = try await library()
        let target = MovementPattern.squat
        // Strip `squat` from every mobility stretch: now nothing complements the lead pattern.
        let stripped = base.map { exercise -> Exercise in
            guard exercise.pillar == .mobility else { return exercise }
            var copy = exercise
            copy.complements = (exercise.complements ?? []).filter { $0 != target }
            return copy
        }
        XCTAssertFalse(
            stripped.contains { $0.pillar == .mobility && $0.complements?.contains(target) == true },
            "the stripped library must contain no stretch complementing \(target)"
        )

        let workout = assemble(minutes: 20, user: user(), library: stripped, logs: forcingLead(target))

        let strength = try XCTUnwrap(block(workout, .strength))
        XCTAssertEqual(strength.exercises.first?.exercise.movementPattern, target, "the lead is still \(target)")

        // The bookends are never starved: present, non-empty, and at their length-scaled count.
        let warmup = try XCTUnwrap(block(workout, .warmup), "the warm-up is still built")
        XCTAssertEqual(
            warmup.exercises.count,
            SessionAssembly.warmupExerciseCount(forRequestedMinutes: 20),
            "the fallback warm-up keeps its length-scaled count, not a starved one"
        )
        let cooldown = try XCTUnwrap(block(workout, .cooldown), "the cooldown is still built")
        XCTAssertFalse(cooldown.exercises.isEmpty, "the fallback cooldown is never emptied")

        // And, with nothing to complement, the leading stretch is simply the general-pool pick.
        XCTAssertFalse(
            warmup.exercises.first?.exercise.complements?.contains(target) == true,
            "with no complementary stretch, the warm-up leads from the general pool"
        )
    }

    // MARK: - (c) Coverage invariant: >= 6 complementary stretches per strength pattern

    /// Every strength pattern resolves to at least six complementary mobility movements (so prefer-then-
    /// fill never starves), and all 26 mobility movements carry the `complements` field - a mistyped
    /// display name in the mapping would silently drop coverage, which this pins.
    func testEveryStrengthPatternHasAtLeastSixComplementaryStretches() async throws {
        let library = try await library()
        let mobility = library.filter { $0.pillar == .mobility }
        XCTAssertEqual(mobility.count, 26, "the library carries 26 mobility movements")

        for exercise in mobility {
            XCTAssertNotNil(exercise.complements, "mobility '\(exercise.id)' must carry a complements tag (US-M02)")
        }

        for pattern in [MovementPattern.squat, .hinge, .push, .pull, .core] {
            let count = mobility.filter { $0.complements?.contains(pattern) == true }.count
            XCTAssertGreaterThanOrEqual(
                count, 6,
                "strength pattern \(pattern) resolves to only \(count) complementary stretches (< 6)"
            )
        }

        // Pin two multi-pattern entries so a mapping typo that drops a pattern is caught.
        let byName = Dictionary(uniqueKeysWithValues: mobility.map { ($0.displayName, $0) })
        XCTAssertEqual(
            byName["World's Greatest Stretch"]?.complements.map(Set.init),
            Set<MovementPattern>([.squat, .hinge, .push]),
            "World's Greatest Stretch complements squat, hinge, push"
        )
        XCTAssertEqual(
            byName["Thoracic Rotations"]?.complements.map(Set.init),
            Set<MovementPattern>([.push, .pull, .core]),
            "Thoracic Rotations complements push, pull, core"
        )
    }

    // MARK: - (d) Determinism and asOf-purity

    /// The prefer-then-fill reorder adds no nondeterminism: identical inputs produce byte-identical
    /// bookends across repeated assembly.
    func testBookendSelectionIsDeterministic() async throws {
        let library = try await library()
        let logs = forcingLead(.squat)
        let first = assemble(minutes: 30, user: user(), library: library, logs: logs)
        let second = assemble(minutes: 30, user: user(), library: library, logs: logs)

        for category in [ExerciseCategory.warmup, .cooldown] {
            let a = block(first, category)?.exercises.map { $0.exercise.id }
            let b = block(second, category)?.exercises.map { $0.exercise.id }
            XCTAssertEqual(a, b, "\(category) bookend ordering is not deterministic")
        }
    }

    /// `asOf`-purity: the bias reads no wall clock, only relative staleness. Shifting every input date -
    /// the logs and the reference `asOf` - by the same offset preserves all staleness, so the bookend
    /// ordering is byte-identical; a hidden absolute-clock read would perturb it.
    func testBookendSelectionIsAsOfPure() async throws {
        let library = try await library()

        let baseAsOf = asOf
        let shiftedAsOf = calendar.date(byAdding: .day, value: 37, to: baseAsOf)!

        let baseWorkout = assemble(
            minutes: 30, user: user(), library: library,
            logs: forcingLead(.push, from: baseAsOf), asOf: baseAsOf
        )
        let shiftedWorkout = assemble(
            minutes: 30, user: user(), library: library,
            logs: forcingLead(.push, from: shiftedAsOf), asOf: shiftedAsOf
        )

        for category in [ExerciseCategory.warmup, .cooldown] {
            let a = block(baseWorkout, category)?.exercises.map { $0.exercise.id }
            let b = block(shiftedWorkout, category)?.exercises.map { $0.exercise.id }
            XCTAssertEqual(a, b, "\(category) bookend ordering depends on the absolute clock, not just relative staleness")
        }
    }
}
