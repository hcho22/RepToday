import XCTest
@testable import RepToday

/// US-M03: the desk-worker `sitsLong` signal *biases* bookend selection toward posture/hip openers -
/// never picks a different training movement or earned level, and never adds a stretch.
///
/// The flag's only job in the engine is an ordering **preference** on the warm-up/cooldown mobility
/// pools: `SessionAssembly.postureHipLean` stable-promotes posture/hip openers (stretches whose US-M02
/// `complements` name a hip-dominant pattern, `SessionAssembly.postureHipPatterns` = squat/hinge) ahead
/// of the rest, *underneath* the US-M02 lead-complement promotion (which keeps final authority over the
/// lead slot). It is reorder-only: no bookend count changes, so it cannot re-inflate a short session.
///
/// Coverage:
///   (a) the posture/hip-opener predicate is exactly the squat/hinge-complementing subset of the real
///       mobility catalog, and is a non-trivial, non-total slice of it;
///   (b) two otherwise-identical no-history profiles (`sitsLong` true / false) at 5 and 20 min: the
///       `sitsLong` bookends lean toward posture/hip openers while block structure and bookend counts
///       stay identical, and the 5-min session is not re-inflated;
///   (c) `sitsLong` is not a training lever: on every Training Day and length the circuit holds the same
///       movements in the same roles at the same Earned Reps for both profiles. The served reps and the
///       rests may differ, because the bookends can cost different seconds and the fit pads or rests to
///       absorb that - but only then: equal bookend seconds give an identical circuit;
///   (d) determinism and `asOf`-purity: the bias is a pure, stable reorder.
final class SitsLongBookendBiasTests: XCTestCase {

    // MARK: - Fixtures

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A no-history profile identical in every field but `sitsLong`, so any difference in the assembled
    /// session is attributable to the bias alone.
    private func user(sitsLong: Bool) -> User {
        TrainingDayFixtures.user(level: .intermediate, sitsLong: sitsLong)
    }

    private func assemble(
        minutes: Int,
        sitsLong: Bool,
        library: [Exercise],
        day: TrainingDay = .push,
        asOf: Date = TrainingDayFixtures.asOf
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user(sitsLong: sitsLong),
            library: library,
            recentLogs: [],
            trainingDay: day,
            asOf: asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    private func block(_ workout: Workout, _ category: ExerciseCategory) -> WorkoutBlock? {
        workout.blocks.first { $0.category == category }
    }

    /// The exercises across the session's mobility bookends (warm-up + cooldown).
    private func bookendExercises(_ workout: Workout) -> [Exercise] {
        workout.blocks
            .filter { $0.category == .warmup || $0.category == .cooldown }
            .flatMap { $0.exercises.map(\.exercise) }
    }

    private func hipOpenerCount(_ workout: Workout) -> Int {
        bookendExercises(workout).filter(SessionAssembly.isPostureHipOpener).count
    }

    private func circuit(_ workout: Workout) -> [PrescribedExercise] {
        workout.blocks.filter { $0.category == .strength }.flatMap(\.exercises)
    }

    /// What `sitsLong` must never perturb: each circuit station's movement, role and Earned Reps, in order.
    private func earnedSignature(_ workout: Workout) -> [String] {
        circuit(workout).map { item in
            let earned = item.earnedReps ?? item.earnedDurationSeconds
            return "\(item.exercise.id):\(item.role.map { "\($0)" } ?? "-"):\(earned.map(String.init) ?? "-")"
        }
    }

    /// The whole circuit as served: movement, sets, served number, rest, and the block's pause.
    private func servedSignature(_ workout: Workout) -> [String] {
        let pause = workout.blocks.first { $0.category == .strength }?.transitionSeconds ?? 0
        return circuit(workout).map { item in
            "\(item.exercise.id):\(item.sets)x\(item.reps ?? item.durationSeconds ?? 0)r\(item.restSeconds)p\(pause)"
        }
    }

    /// The planned seconds the mobility bookends consume - the one channel through which `sitsLong` can
    /// reach the circuit at all.
    private func bookendSeconds(_ workout: Workout) -> Int {
        workout.blocks
            .filter { $0.category == .warmup || $0.category == .cooldown }
            .reduce(0) { $0 + SessionAssembly.blockSeconds(of: $1) }
    }

    // MARK: - (a) The posture/hip-opener predicate over the real catalog

    /// The predicate is exactly the squat/hinge-complementing subset of the mobility catalog, derived
    /// from the existing US-M02 metadata rather than a new tag - and it is a genuine, non-total slice:
    /// some stretches qualify and some do not, so the bias actually reorders rather than being a no-op or
    /// a whole-pool move.
    func testPostureHipOpenerPredicateIsTheSquatHingeComplementSubset() async throws {
        let mobility = try await library().filter { $0.pillar == .mobility }
        XCTAssertEqual(mobility.count, 26, "the library carries 26 mobility movements")

        let openers = mobility.filter(SessionAssembly.isPostureHipOpener)
        let expected = mobility.filter { ($0.complements ?? []).contains { $0 == .squat || $0 == .hinge } }
        XCTAssertEqual(
            Set(openers.map(\.id)), Set(expected.map(\.id)),
            "posture/hip openers must be exactly the squat/hinge-complementing stretches"
        )

        // Non-trivial and non-total: the reorder has something to move and something to leave behind.
        XCTAssertGreaterThanOrEqual(openers.count, 6, "there must be a real pool of hip openers to lead with")
        XCTAssertLessThan(openers.count, mobility.count, "not every stretch is a hip opener, or the bias would be a no-op")

        // Spot-check a canonical hip opener and a canonical non-opener so a metadata drift is caught.
        let byName = Dictionary(uniqueKeysWithValues: mobility.map { ($0.displayName, $0) })
        XCTAssertEqual(byName["Pigeon Pose"].map(SessionAssembly.isPostureHipOpener), true, "Pigeon is a hip opener")
        XCTAssertEqual(byName["Arm Circles"].map(SessionAssembly.isPostureHipOpener), false, "Arm Circles is not a hip opener")
    }

    // MARK: - (b) The PRD validation test: lean, identical structure, lean short sessions

    /// Two otherwise-identical no-history profiles, `sitsLong` true and false, at 5 and 20 min:
    ///   - the `sitsLong` bookends lean toward posture/hip openers (strictly more hip openers), and never
    ///     fewer than the non-desk profile (the invariant the stable partition guarantees);
    ///   - the block count and structure are otherwise identical (Warm-Up -> Strength [-> Cooldown]);
    ///   - neither profile grows a mobility *middle* block;
    ///   - the 5-min session is not re-inflated: its warm-up stays at the length-scaled single movement
    ///     and it carries no cooldown.
    func testSitsLongLeansBookendsTowardHipOpenersWithoutChangingStructure() async throws {
        let library = try await library()

        for minutes in [5, 20] {
            let desk = assemble(minutes: minutes, sitsLong: true, library: library)
            let general = assemble(minutes: minutes, sitsLong: false, library: library)

            // Structure is identical: same block categories in the same order.
            XCTAssertEqual(
                desk.blocks.map(\.category), general.blocks.map(\.category),
                "\(minutes) min: sitsLong changed the block structure"
            )
            // No mobility *middle* block appears for either profile.
            for workout in [desk, general] {
                XCTAssertFalse(
                    workout.blocks.contains { $0.category == .mobility },
                    "\(minutes) min: a mobility middle block appeared"
                )
            }
            // The bookend counts match block-for-block: the reorder adds no stretch and sizes nothing.
            for category in [ExerciseCategory.warmup, .cooldown] {
                XCTAssertEqual(
                    block(desk, category)?.exercises.count,
                    block(general, category)?.exercises.count,
                    "\(minutes) min: sitsLong changed the \(category) count"
                )
            }

            // The lean: the desk profile's bookends carry more hip openers, and never fewer.
            let deskHips = hipOpenerCount(desk)
            let generalHips = hipOpenerCount(general)
            XCTAssertGreaterThanOrEqual(deskHips, generalHips, "\(minutes) min: sitsLong must never reduce hip openers")
            XCTAssertGreaterThan(
                deskHips, generalHips,
                "\(minutes) min: sitsLong=true bookends (\(deskHips) hip openers) do not lean over sitsLong=false (\(generalHips))"
            )
        }

        // The shortest session is not re-inflated with stretching, for either profile.
        for sitsLong in [true, false] {
            let five = assemble(minutes: 5, sitsLong: sitsLong, library: library)
            XCTAssertEqual(
                block(five, .warmup)?.exercises.count,
                SessionAssembly.warmupExerciseCount(forRequestedMinutes: 5),
                "sitsLong=\(sitsLong): the 5-min warm-up is not lean"
            )
            XCTAssertEqual(block(five, .warmup)?.exercises.count, 1, "sitsLong=\(sitsLong): the 5-min warm-up is a single movement")
            XCTAssertNil(block(five, .cooldown), "sitsLong=\(sitsLong): the 5-min session gains no cooldown")
        }
    }

    // MARK: - (c) sitsLong is not a training lever

    /// On every Training Day and length, the circuit holds the **same movements in the same roles at the
    /// same Earned Reps** for both profiles: the bias reaches only the bookend ordering, so no station is
    /// swapped and no progression number moves.
    ///
    /// The served reps and the rests may differ: the bias changes which stretches fill the fixed-count
    /// bookends, a rep-based stretch carries the generous pace while a hold does not, so the bookends can
    /// cost different seconds and the fit pads reps or grows rest to land the same length. That is the only
    /// channel - equal bookend seconds must give an identical circuit as served.
    func testSitsLongChangesNoTrainingMovementOrEarnedLevel() async throws {
        let library = try await library()
        for day in TrainingDay.rotation {
            for minutes in [5, 10, 15, 20, 30, 45, 60] {
                let desk = assemble(minutes: minutes, sitsLong: true, library: library, day: day)
                let general = assemble(minutes: minutes, sitsLong: false, library: library, day: day)
                let label = "\(day) \(minutes) min"

                XCTAssertEqual(desk.blocks.map(\.category), general.blocks.map(\.category), "\(label): block structure")
                XCTAssertFalse(earnedSignature(desk).isEmpty, "\(label): no circuit")
                XCTAssertEqual(
                    earnedSignature(desk), earnedSignature(general),
                    "\(label): sitsLong changed a training movement, role or Earned Reps (it must only bias bookends)"
                )
                for workout in [desk, general] {
                    XCTAssertTrue(circuit(workout).allSatisfy { $0.sets == RepGrammar.setsPerStation }, label)
                }
                if bookendSeconds(desk) == bookendSeconds(general) {
                    XCTAssertEqual(
                        servedSignature(desk), servedSignature(general),
                        "\(label): sitsLong moved the served circuit without the bookends costing anything different"
                    )
                }
            }
        }
    }

    // MARK: - (d) Determinism and asOf-purity of the bias

    /// The bias is a pure, stable reorder: identical inputs produce byte-identical `sitsLong` bookends.
    func testSitsLongBookendsAreDeterministic() async throws {
        let library = try await library()
        let first = assemble(minutes: 30, sitsLong: true, library: library)
        let second = assemble(minutes: 30, sitsLong: true, library: library)
        for category in [ExerciseCategory.warmup, .cooldown] {
            XCTAssertEqual(
                block(first, category)?.exercises.map { $0.exercise.id },
                block(second, category)?.exercises.map { $0.exercise.id },
                "\(category): the sitsLong bookend ordering is not deterministic"
            )
        }
    }

    /// `asOf`-purity: the bias reads no wall clock. Shifting the reference `asOf` (with no history to
    /// re-age) leaves the `sitsLong` bookends byte-identical; a hidden absolute-clock read would perturb
    /// them.
    func testSitsLongBookendsAreAsOfPure() async throws {
        let library = try await library()
        let shifted = TrainingDayFixtures.calendar.date(byAdding: .day, value: 37, to: TrainingDayFixtures.asOf)!
        let base = assemble(minutes: 30, sitsLong: true, library: library)
        let later = assemble(minutes: 30, sitsLong: true, library: library, asOf: shifted)
        for category in [ExerciseCategory.warmup, .cooldown] {
            XCTAssertEqual(
                block(base, category)?.exercises.map { $0.exercise.id },
                block(later, category)?.exercises.map { $0.exercise.id },
                "\(category): the sitsLong bookend ordering depends on the absolute clock"
            )
        }
    }
}
