import XCTest
@testable import RepToday

/// US-M02: pattern-matched, prefer-then-fill bookends.
///
/// The warm-up and cooldown each *lead* with a stretch whose `complements: [MovementPattern]` metadata
/// contains the Training Day's lead pattern (push on a Push Day, pull on a Pull Day, squat on a Legs
/// Day), then fill the remaining slots with the staleness / no-repeat variety ordering. The match is a
/// **preference, never an exclusive filter**: when no complementary stretch is available the general
/// mobility pool fills the bookend, which is therefore never starved or emptied.
///
/// Coverage, run end-to-end over the real bundled library:
///   (a) the leading warm-up and cooldown stretch complements the day's lead pattern on every Training Day;
///   (b) a general-pool fallback appears - never an empty bookend - when no complementary stretch is
///       available (a library whose stretches complement no such pattern);
///   (c) the >= 6-complementary-stretches-per-pattern coverage invariant, plus the whole mapping being
///       tagged on all 26 mobility movements;
///   (d) determinism and `asOf`-purity: identical inputs (and staleness-preserving `asOf` shifts) yield
///       byte-identical bookend orderings.
final class BookendComplementSelectionTests: XCTestCase {

    // MARK: - Fixtures

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// The pattern each Training Day's bookends lead with.
    private let leadPattern: [TrainingDay: MovementPattern] = [.push: .push, .pull: .pull, .legs: .squat]

    private func assemble(
        minutes: Int,
        day: TrainingDay,
        library: [Exercise],
        logs: [WorkoutLog] = [],
        asOf: Date = TrainingDayFixtures.asOf
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(),
            library: library,
            recentLogs: logs,
            trainingDay: day,
            asOf: asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    private func block(_ workout: Workout, _ category: ExerciseCategory) -> WorkoutBlock? {
        workout.blocks.first { $0.category == category }
    }

    // MARK: - (a) The leading bookend stretch complements the day's lead pattern

    /// On every Training Day, at every length that carries both bookends, the first warm-up stretch and
    /// the first cooldown stretch each complement the day's lead pattern, and the circuit trains that day.
    func testLeadingBookendStretchComplementsTheDaysLeadPattern() async throws {
        let library = try await library()
        for day in TrainingDay.rotation {
            let target = try XCTUnwrap(leadPattern[day])
            for minutes in [15, 20, 30, 45, 60] {
                let workout = assemble(minutes: minutes, day: day, library: library)
                let label = "\(day) \(minutes) min"

                let strength = try XCTUnwrap(block(workout, .strength), "\(label): no circuit")
                XCTAssertEqual(strength.title, day.displayName, label)
                XCTAssertTrue(
                    strength.exercises.contains { $0.exercise.movementPattern == target },
                    "\(label): the circuit does not train \(target)"
                )

                let warmup = try XCTUnwrap(block(workout, .warmup), "\(label): a session opens with a warm-up")
                let firstWarm = try XCTUnwrap(warmup.exercises.first?.exercise, "\(label): the warm-up is never empty")
                XCTAssertEqual(firstWarm.pillar, .mobility, "\(label): the leading warm-up item is a stretch")
                XCTAssertTrue(
                    firstWarm.complements?.contains(target) == true,
                    "\(label): warm-up leads with '\(firstWarm.id)', which does not complement \(target)"
                )

                let cooldown = try XCTUnwrap(block(workout, .cooldown), "\(label): a cooldown closes the session")
                let firstCool = try XCTUnwrap(cooldown.exercises.first?.exercise, "\(label): the cooldown is never empty")
                XCTAssertTrue(
                    firstCool.complements?.contains(target) == true,
                    "\(label): cooldown leads with '\(firstCool.id)', which does not complement \(target)"
                )
            }
        }
    }

    // MARK: - (b) General-pool fallback, never an empty bookend

    /// When no stretch in the pool complements the lead pattern, the bias is a no-op and the general
    /// mobility ordering fills the bookend: the warm-up and cooldown are still present, still at their
    /// length-scaled counts, and simply lead with the freshest general stretch. The library's stretches
    /// are stripped of `squat` (the metadata is the only lever the bias reads), the state a fully-consumed
    /// complementary pool would leave a Legs Day in.
    func testFallsBackToGeneralPoolWhenNoComplementaryStretchIsAvailable() async throws {
        let base = try await library()
        let target = MovementPattern.squat
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

        let workout = assemble(minutes: 20, day: .legs, library: stripped)

        let warmup = try XCTUnwrap(block(workout, .warmup), "the warm-up is still built")
        XCTAssertEqual(
            warmup.exercises.count,
            SessionAssembly.warmupExerciseCount(forRequestedMinutes: 20),
            "the fallback warm-up keeps its length-scaled count, not a starved one"
        )
        let cooldown = try XCTUnwrap(block(workout, .cooldown), "the cooldown is still built")
        XCTAssertEqual(
            cooldown.exercises.count,
            SessionAssembly.cooldownExerciseCount(forRequestedMinutes: 20),
            "the fallback cooldown keeps its length-scaled count"
        )
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

    /// A history that has used a few stretches, so the ordering is driven by staleness as well as the
    /// complement bias.
    private func mobilityHistory(asOf: Date) -> [WorkoutLog] {
        let stretches = ["mobility_cat_cow", "mobility_worlds_greatest", "mobility_childs_pose"]
        return stretches.enumerated().map { index, id in
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station(id, pattern: .mobility, pillar: .mobility, role: nil, value: 10, sets: 1)],
                completedAt: TrainingDayFixtures.calendar.date(byAdding: .day, value: -(index + 1), to: asOf)!
            )
        }
    }

    /// The prefer-then-fill reorder adds no nondeterminism: identical inputs produce byte-identical
    /// bookends across repeated assembly.
    func testBookendSelectionIsDeterministic() async throws {
        let library = try await library()
        let logs = mobilityHistory(asOf: TrainingDayFixtures.asOf)
        for day in TrainingDay.rotation {
            let first = assemble(minutes: 30, day: day, library: library, logs: logs)
            let second = assemble(minutes: 30, day: day, library: library, logs: logs)
            for category in [ExerciseCategory.warmup, .cooldown] {
                let a = block(first, category)?.exercises.map { $0.exercise.id }
                let b = block(second, category)?.exercises.map { $0.exercise.id }
                XCTAssertEqual(a, b, "\(day) \(category) bookend ordering is not deterministic")
            }
        }
    }

    /// `asOf`-purity: the bias reads no wall clock, only relative staleness. Shifting every input date -
    /// the logs and the reference `asOf` - by the same offset preserves all staleness, so the bookend
    /// ordering is byte-identical; a hidden absolute-clock read would perturb it.
    func testBookendSelectionIsAsOfPure() async throws {
        let library = try await library()
        let baseAsOf = TrainingDayFixtures.asOf
        let shiftedAsOf = TrainingDayFixtures.calendar.date(byAdding: .day, value: 37, to: baseAsOf)!

        let baseWorkout = assemble(
            minutes: 30, day: .push, library: library, logs: mobilityHistory(asOf: baseAsOf), asOf: baseAsOf
        )
        let shiftedWorkout = assemble(
            minutes: 30, day: .push, library: library, logs: mobilityHistory(asOf: shiftedAsOf), asOf: shiftedAsOf
        )

        for category in [ExerciseCategory.warmup, .cooldown] {
            let a = block(baseWorkout, category)?.exercises.map { $0.exercise.id }
            let b = block(shiftedWorkout, category)?.exercises.map { $0.exercise.id }
            XCTAssertEqual(a, b, "\(category) bookend ordering depends on the absolute clock, not just relative staleness")
        }
    }
}
