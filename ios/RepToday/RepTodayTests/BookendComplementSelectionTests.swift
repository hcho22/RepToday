import XCTest
@testable import RepToday

/// US-SZ03 (ADR-0018): day-matched bookends, replacing US-M02's prefer-then-fill lead.
///
/// Every warm-up and cooldown stretch complements the Training Day's group - push on a Push Day, pull on
/// a Pull Day, squat or hinge on a Legs Day - read off each stretch's `complements` metadata. The variety
/// order (a Different workout press's moves last, then no recent repeats, then least recently done) picks
/// among the matching stretches, and an unmatched stretch fills a bookend only once the matches the user
/// is offered run out, so a bookend is never emptied.
///
/// Coverage, run end-to-end over the real bundled library:
///   (a) on every day, length, level and phase, a bookend holds as many matching stretches as it has room
///       for, and an unmatched one only after every offered match is in the session - with the catalog's
///       one real shortfall pinned (a Discipline beginner or intermediate is offered three pull stretches);
///   (b) a pool with too few matches falls back without emptying or shortening a bookend;
///   (c) the variety order and a Different workout press pick among the matches, a press bringing in one
///       unmatched stretch only when it would otherwise rebuild the session it replaces;
///   (d) the coverage invariant and the mapping on all 26 mobility movements;
///   (e) determinism and `asOf`-purity.
final class BookendComplementSelectionTests: XCTestCase {

    // MARK: - Fixtures

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    private func assemble(
        minutes: Int,
        day: TrainingDay,
        library: [Exercise],
        user: User = TrainingDayFixtures.user(),
        logs: [WorkoutLog] = [],
        variation: SessionVariation = .none,
        asOf: Date = TrainingDayFixtures.asOf
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user,
            library: library,
            recentLogs: logs,
            variation: variation,
            trainingDay: day,
            asOf: asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    private func block(_ workout: Workout, _ category: ExerciseCategory) -> WorkoutBlock? {
        workout.blocks.first { $0.category == category }
    }

    private func bookendStretches(_ workout: Workout) -> [Exercise] {
        workout.blocks
            .filter { $0.category == .warmup || $0.category == .cooldown }
            .flatMap { $0.exercises.map(\.exercise) }
    }

    private func matches(_ exercise: Exercise, _ day: TrainingDay) -> Bool {
        SessionAssembly.complements(exercise, anyOf: day.patterns)
    }

    // MARK: - (a) Every bookend stretch matches the day while the catalog has enough

    /// On every Training Day, length, level and phase, with and without a history: the bookends hold
    /// `min(room, offered matches)` matching stretches, and an unmatched stretch appears only once every
    /// match the user is offered is already in the session. Bookend counts are the length's.
    func testEveryBookendStretchMatchesTheDayWhileMatchesRemain() async throws {
        let library = try await library()
        let history = [TrainingDayFixtures.log(
            ["mobility_cat_cow", "mobility_childs_pose", "mobility_cobra", "mobility_butterfly"].map {
                TrainingDayFixtures.station($0, pattern: .mobility, pillar: .mobility, role: nil, value: 10, sets: 1)
            },
            completedAt: TrainingDayFixtures.date(daysAgo: 1)
        )]
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                let user = TrainingDayFixtures.user(level: level, phase: phase)
                for logs in [[], history] {
                    let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: logs)
                    for day in TrainingDay.rotation {
                        let offered = pool.filter { $0.pillar == .mobility && matches($0, day) }
                        for minutes in lengths {
                            let workout = assemble(minutes: minutes, day: day, library: library, user: user, logs: logs)
                            let label = "\(level) \(phase) \(day) \(minutes) min history:\(!logs.isEmpty)"
                            XCTAssertEqual(block(workout, .warmup)?.exercises.count, SessionAssembly.warmupExerciseCount(forRequestedMinutes: minutes), label)
                            XCTAssertEqual(block(workout, .cooldown)?.exercises.count ?? 0, SessionAssembly.cooldownExerciseCount(forRequestedMinutes: minutes), label)

                            let stretches = bookendStretches(workout)
                            let matched = stretches.filter { matches($0, day) }
                            XCTAssertEqual(matched.count, min(stretches.count, offered.count), "\(label): \(stretches.map(\.id))")
                            if matched.count < stretches.count {
                                XCTAssertEqual(Set(matched.map(\.id)), Set(offered.map(\.id)), "\(label): a fallback while a match was left")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Where the catalog actually runs short: Push and Legs Days always fill every bookend stretch from
    /// the matches, at every level; a Pull Day does for an advanced or Strength-Phase user, while a
    /// Discipline beginner or intermediate is offered three pull stretches (Arm Circles, Child's Pose,
    /// Supine Twist), so their 30-60 minute Pull Day's fourth bookend stretch is the one fallback.
    func testOnlyABeginnerOrIntermediatePullDayFromThirtyMinutesFallsBack() async throws {
        let library = try await library()
        for level in FitnessLevel.allCases {
            for phase in [Phase.discipline, .strength] {
                let user = TrainingDayFixtures.user(level: level, phase: phase)
                for day in TrainingDay.rotation {
                    for minutes in lengths {
                        let stretches = bookendStretches(assemble(minutes: minutes, day: day, library: library, user: user))
                        let fallbacks = stretches.filter { !matches($0, day) }.count
                        let staplesOnly = level != .advanced && phase == .discipline
                        let expected = day == .pull && staplesOnly && minutes >= 30 ? 1 : 0
                        XCTAssertEqual(fallbacks, expected, "\(level) \(phase) \(day) \(minutes) min: \(stretches.map(\.id))")
                    }
                }
            }
        }
        let pullStaples = MovementAccess.available(in: library, level: .beginner, phase: .discipline)
            .filter { $0.pillar == .mobility && matches($0, .pull) }
        XCTAssertEqual(Set(pullStaples.map(\.id)), ["mobility_arm_circles", "mobility_childs_pose", "mobility_supine_twist"])
    }

    // MARK: - (b) Too few matches falls back without emptying a bookend

    /// A library whose stretches leave only one pull match: a 30-minute Pull Day still opens and closes
    /// with full, length-scaled bookends, the one match is in them, and the rest come from the general
    /// pool. With none at all, the bookends are still full.
    func testAPoolWithTooFewMatchesFallsBackWithoutEmptyingABookend() async throws {
        let base = try await library()
        for kept in [["mobility_childs_pose"], []] {
            let thinned = base.map { exercise -> Exercise in
                guard exercise.pillar == .mobility, !kept.contains(exercise.id) else { return exercise }
                var copy = exercise
                copy.complements = (exercise.complements ?? []).filter { $0 != .pull }
                return copy
            }
            let workout = assemble(minutes: 30, day: .pull, library: thinned)
            let label = "kept \(kept)"
            XCTAssertEqual(block(workout, .warmup)?.exercises.count, 2, label)
            XCTAssertEqual(block(workout, .cooldown)?.exercises.count, 2, label)
            let stretches = bookendStretches(workout)
            XCTAssertEqual(Set(stretches.map(\.id)).count, 4, "\(label): a stretch repeated")
            XCTAssertEqual(stretches.filter { matches($0, .pull) }.map(\.id), kept, label)
            XCTAssertTrue(stretches.allSatisfy { $0.pillar == .mobility }, label)
        }
    }

    // MARK: - (c) The variety order and a press pick among the matches

    /// Stretches done yesterday go behind fresh ones, but only among the matches: a Legs Day with every
    /// fresh match still available never reaches for an unmatched stretch, and none of yesterday's.
    func testTheVarietyOrderPicksAmongTheMatches() async throws {
        let library = try await library()
        let first = assemble(minutes: 30, day: .legs, library: library)
        let yesterday = TrainingDayFixtures.log(
            bookendStretches(first).map {
                TrainingDayFixtures.station($0.id, pattern: .mobility, pillar: .mobility, role: nil, value: 10, sets: 1)
            },
            completedAt: TrainingDayFixtures.date(daysAgo: 1)
        )
        let next = assemble(minutes: 30, day: .legs, library: library, logs: [yesterday])
        let stretches = bookendStretches(next)
        XCTAssertTrue(stretches.allSatisfy { matches($0, .legs) }, "\(stretches.map(\.id))")
        XCTAssertTrue(Set(stretches.map(\.id)).isDisjoint(with: bookendStretches(first).map(\.id)), "\(stretches.map(\.id))")
    }

    /// A Different workout press ranks every match it has not shown, then every match it has, ahead of any
    /// unmatched stretch: a Legs Day, with ten matches, presses to bookends that are new and still all match.
    func testADifferentWorkoutPressPicksAmongTheMatches() async throws {
        let library = try await library()
        let shown = assemble(minutes: 30, day: .legs, library: library)
        let pressed = assemble(minutes: 30, day: .legs, library: library, variation: SessionVariation.none.advanced(past: shown))
        let stretches = bookendStretches(pressed)
        XCTAssertTrue(stretches.allSatisfy { matches($0, .legs) }, "\(stretches.map(\.id))")
        XCTAssertTrue(Set(stretches.map(\.id)).isDisjoint(with: bookendStretches(shown).map(\.id)), "\(stretches.map(\.id))")
    }

    /// A press whose session changes elsewhere shows a match again rather than reach for an unmatched
    /// stretch: a Discipline beginner's 15 and 20 minute Pull Day already holds all three pull stretches
    /// they are offered, and its press keeps them, changing through the Core Sprinkle instead.
    func testAPressThatChangesElsewhereKeepsShownMatchesOverUnmatchedStretches() async throws {
        let library = try await library()
        let user = TrainingDayFixtures.user(level: .beginner)
        for minutes in [15, 20] {
            let label = "\(minutes) min"
            let shown = assemble(minutes: minutes, day: .pull, library: library, user: user)
            let shownStretches = bookendStretches(shown)
            XCTAssertEqual(Set(shownStretches.map(\.id)), ["mobility_arm_circles", "mobility_childs_pose", "mobility_supine_twist"], label)

            let pressed = assemble(
                minutes: minutes, day: .pull, library: library, user: user,
                variation: SessionVariation.none.advanced(past: shown)
            )
            XCTAssertNotEqual(SessionVariation.exerciseIds(in: pressed), SessionVariation.exerciseIds(in: shown), "\(label): the press changed nothing")
            XCTAssertEqual(Set(bookendStretches(pressed).map(\.id)), Set(shownStretches.map(\.id)), label)
        }
    }

    /// A press takes the matches it has not shown first and fills the rest from the matches it has, never
    /// an unmatched stretch: a Discipline beginner's 20 minute Push Day shows three of the four push
    /// stretches they are offered, and its press brings the fourth beside two of those.
    func testAPressTakesTheUnshownMatchThenShownMatches() async throws {
        let library = try await library()
        let user = TrainingDayFixtures.user(level: .beginner)
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: [])
        let offered = Set(pool.filter { $0.pillar == .mobility && matches($0, .push) }.map(\.id))
        let shown = assemble(minutes: 20, day: .push, library: library, user: user)
        let shownIds = Set(bookendStretches(shown).map(\.id))
        let unshown = offered.subtracting(shownIds)
        XCTAssertEqual(offered.count, 4)
        XCTAssertEqual(unshown.count, 1, "\(shownIds)")

        let pressed = assemble(minutes: 20, day: .push, library: library, user: user, variation: SessionVariation.none.advanced(past: shown))
        let pressedStretches = bookendStretches(pressed)
        XCTAssertEqual(pressedStretches.count, shownIds.count)
        XCTAssertTrue(pressedStretches.allSatisfy { matches($0, .push) }, "\(pressedStretches.map(\.id))")
        XCTAssertTrue(unshown.isSubset(of: pressedStretches.map(\.id)), "\(pressedStretches.map(\.id))")
    }

    /// Only a press that staying inside the matches would leave rebuilding the session it replaces brings in
    /// an unmatched stretch, and then exactly one: a Discipline beginner or intermediate's 45 and 60 minute Push Day
    /// already holds all four push stretches they are offered, both push ladders and both core ladders, and
    /// on main a press changed that session, so it still does - by swapping one bookend stretch for an
    /// unmatched one it has not shown and keeping the other three matches. The default session stays all
    /// matches.
    func testAPressThatWouldShowNothingNewSwapsInOneUnmatchedStretch() async throws {
        let library = try await library()
        for level in [FitnessLevel.beginner, .intermediate] {
            let user = TrainingDayFixtures.user(level: level)
            let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: [])
            let offered = pool.filter { $0.pillar == .mobility && matches($0, .push) }
            for minutes in [45, 60] {
                let label = "\(level) \(minutes) min"
                let shown = assemble(minutes: minutes, day: .push, library: library, user: user)
                let shownStretches = bookendStretches(shown)
                XCTAssertTrue(shownStretches.allSatisfy { matches($0, .push) }, label)
                XCTAssertEqual(Set(shownStretches.map(\.id)), Set(offered.map(\.id)), "\(label): every push stretch offered is in the default")

                let pressed = assemble(
                    minutes: minutes, day: .push, library: library, user: user,
                    variation: SessionVariation.none.advanced(past: shown)
                )
                XCTAssertNotEqual(SessionVariation.exerciseIds(in: pressed), SessionVariation.exerciseIds(in: shown), "\(label): the press changed nothing")
                let pressedStretches = bookendStretches(pressed)
                XCTAssertEqual(pressedStretches.count, shownStretches.count, label)
                let unmatched = pressedStretches.filter { !matches($0, .push) }
                XCTAssertEqual(unmatched.count, 1, "\(label): \(pressedStretches.map(\.id))")
                XCTAssertFalse(shownStretches.map(\.id).contains(unmatched.first?.id ?? ""), label)
                XCTAssertTrue(
                    Set(pressedStretches.filter { matches($0, .push) }.map(\.id)).isSubset(of: shownStretches.map(\.id)),
                    "\(label): \(pressedStretches.map(\.id))"
                )
            }
        }
    }

    /// The default session followed by `count` Different workout presses, folded as the Ready Screen folds
    /// them.
    private func pressSequence(_ count: Int, minutes: Int, day: TrainingDay, user: User, library: [Exercise]) -> [Workout] {
        var variation = SessionVariation.none
        var shown = assemble(minutes: minutes, day: day, library: library, user: user)
        var result = [shown]
        for _ in 0..<count {
            variation = variation.advanced(past: shown)
            shown = assemble(minutes: minutes, day: day, library: library, user: user, variation: variation)
            result.append(shown)
        }
        return result
    }

    /// Press after press, a Discipline beginner's 15 and 20 minute Pull Day stays all-pull: the first press
    /// rotates the Core Sprinkle, the second differs from the session it replaces only by going back to the
    /// default (so it never needs an unmatched stretch), and the sequence alternates between the two.
    func testRepeatedPressesOnABeginnerShortPullDayStayAllPull() async throws {
        let library = try await library()
        let user = TrainingDayFixtures.user(level: .beginner)
        for minutes in [15, 20] {
            let sequence = pressSequence(5, minutes: minutes, day: .pull, user: user, library: library)
            let ids = sequence.map(SessionVariation.exerciseIds(in:))
            for (index, workout) in sequence.enumerated() {
                let stretches = bookendStretches(workout)
                XCTAssertTrue(stretches.allSatisfy { matches($0, .pull) }, "\(minutes) min press \(index): \(stretches.map(\.id))")
            }
            XCTAssertNotEqual(ids[1], ids[0], "\(minutes) min: the first press changed nothing")
            for index in 2..<ids.count {
                XCTAssertEqual(ids[index], ids[index - 2], "\(minutes) min press \(index)")
            }
        }
    }

    /// Press after press, a Discipline beginner's 45 and 60 minute Push Day alternates: the first press would
    /// rebuild the default, so it swaps exactly one bookend stretch for an unmatched one; the next press
    /// would rebuild the default, not the session it replaces, so it returns the default; and so on.
    func testRepeatedPressesOnABeginnerLongPushDayAlternateWithOneUnmatchedSwap() async throws {
        let library = try await library()
        let user = TrainingDayFixtures.user(level: .beginner)
        for minutes in [45, 60] {
            let sequence = pressSequence(5, minutes: minutes, day: .push, user: user, library: library)
            let ids = sequence.map(SessionVariation.exerciseIds(in:))
            for (index, workout) in sequence.enumerated() {
                let label = "\(minutes) min press \(index)"
                let unmatched = bookendStretches(workout).filter { !matches($0, .push) }
                XCTAssertEqual(unmatched.count, index.isMultiple(of: 2) ? 0 : 1, "\(label): \(bookendStretches(workout).map(\.id))")
                XCTAssertEqual(ids[index], ids[index % 2], label)
            }
            XCTAssertEqual(ids[1].subtracting(ids[0]).count, 1, "\(minutes) min: \(ids[1].subtracting(ids[0]))")
        }
    }

    /// The cooldown is static holds, chosen first so the day's matching holds close the session even when
    /// few match: a beginner's Push Day (four push stretches offered, three of them holds) closes on two
    /// matching holds and warms up on the other two matches.
    func testTheCooldownTakesTheMatchingHolds() async throws {
        let library = try await library()
        let workout = assemble(minutes: 30, day: .push, library: library, user: TrainingDayFixtures.user(level: .beginner))
        let cooldown = try XCTUnwrap(block(workout, .cooldown)).exercises.map(\.exercise)
        let warmup = try XCTUnwrap(block(workout, .warmup)).exercises.map(\.exercise)
        XCTAssertTrue(cooldown.allSatisfy { $0.isHold && matches($0, .push) }, "\(cooldown.map(\.id))")
        XCTAssertTrue(warmup.allSatisfy { matches($0, .push) }, "\(warmup.map(\.id))")
    }

    // MARK: - (d) Coverage invariant

    /// Every strength pattern resolves to at least six complementary mobility movements across the
    /// catalog, and all 26 mobility movements carry the `complements` field - a mistyped display name in
    /// the mapping would silently drop coverage, which this pins.
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

    // MARK: - (e) Determinism and asOf-purity

    /// A history that has used a few stretches, so the ordering is driven by staleness as well as the
    /// day match.
    private func mobilityHistory(asOf: Date) -> [WorkoutLog] {
        let stretches = ["mobility_cat_cow", "mobility_worlds_greatest", "mobility_childs_pose"]
        return stretches.enumerated().map { index, id in
            TrainingDayFixtures.log(
                [TrainingDayFixtures.station(id, pattern: .mobility, pillar: .mobility, role: nil, value: 10, sets: 1)],
                completedAt: TrainingDayFixtures.calendar.date(byAdding: .day, value: -(index + 1), to: asOf)!
            )
        }
    }

    /// Day matching adds no nondeterminism: identical inputs produce byte-identical bookends across
    /// repeated assembly.
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

    /// `asOf`-purity: the selection reads no wall clock, only relative staleness. Shifting every input
    /// date - the logs and the reference `asOf` - by the same offset preserves all staleness, so the
    /// bookend ordering is byte-identical; a hidden absolute-clock read would perturb it.
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
