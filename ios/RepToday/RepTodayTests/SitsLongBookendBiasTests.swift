import XCTest
@testable import RepToday

/// US-M03: the desk-worker `sitsLong` signal *biases* bookend selection toward posture/hip openers -
/// never picks a different training movement or target, and never reintroduces a mobility middle block.
///
/// Since US-M01 removed the Movement Practice accessory (the block `sitsLong` used to size), the flag's
/// only remaining job in the engine is a pure ordering **preference** on the warm-up/cooldown mobility
/// pools: `SessionAssembly.postureHipLean` stable-promotes posture/hip openers (stretches whose US-M02
/// `complements` name a hip-dominant pattern, `SessionAssembly.postureHipPatterns` = squat/hinge) ahead
/// of the rest, *underneath* the US-M02 lead-complement promotion (which keeps final authority over the
/// lead slot). The implementation chose the simplest of the PRD's "and/or" options - **reorder only, no
/// extra stretch** - because it changes no block's count, so it structurally cannot re-inflate a short
/// session or create a mobility middle block.
///
/// Coverage mirrors the PRD acceptance criteria and validation test:
///   (a) the posture/hip-opener predicate is exactly the squat/hinge-complementing subset of the real
///       mobility catalog, and is a non-trivial, non-total slice of it;
///   (b) the PRD validation test proper: two otherwise-identical no-history profiles (`sitsLong` true /
///       false) at 5 and 20 min - the `sitsLong` bookends lean toward posture/hip openers while block
///       count/structure stays identical, no mobility middle block appears, and the 5-min session is not
///       re-inflated;
///   (c) `sitsLong` is not a sizing lever: across 5/20/45/60 min the training middle (strength, and the
///       extended primal block) holds the same movements at the same per-set targets for both profiles,
///       each block stays internally even, and the bookend *counts* are identical too (the reorder-only
///       choice adds no stretch). A block's uniform **round count** may differ, but only where the
///       bookends genuinely cost different seconds - since US-CC08 a rep-based stretch carries the
///       generous runtime pace and a hold stretch does not, so a desk worker's warm-up can be materially
///       longer and the fit pays for it out of a round (accepted, see that test);
///   (d) determinism and `asOf`-purity: the bias is a pure, stable reorder, so identical inputs (and
///       staleness-preserving `asOf` shifts) yield byte-identical `sitsLong` bookends.
final class SitsLongBookendBiasTests: XCTestCase {

    // MARK: - Fixtures (mirror SessionAssemblyTests / BookendComplementSelectionTests)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 12))!
    }

    private func library() async throws -> [Exercise] {
        try await MockExerciseService().exercises()
    }

    /// A no-history profile identical in every field but `sitsLong`, so any difference in the assembled
    /// session is attributable to the bias alone.
    private func user(sitsLong: Bool) -> User {
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

    private func assemble(minutes: Int, sitsLong: Bool, library: [Exercise], asOf: Date? = nil) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user(sitsLong: sitsLong),
            library: library,
            recentLogs: [],
            asOf: asOf ?? self.asOf,
            calendar: calendar
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

    private func trainingBlocks(_ workout: Workout) -> [WorkoutBlock] {
        workout.blocks.filter { $0.category != .warmup && $0.category != .cooldown }
    }

    /// A stable signature of the *shape* of the training middle: block category + each exercise id and
    /// its per-set target (reps / hold seconds), in order. This is what `sitsLong` must never perturb -
    /// the movements chosen and the capacity-relative target Step 6 prescribed for each.
    ///
    /// It deliberately omits the block's **round count**, which since US-CC08 can legitimately differ
    /// between the two profiles: the bias changes *which* stretches fill the fixed-count bookends, and
    /// rep-based stretches carry the generous runtime pace while hold stretches do not, so a desk
    /// worker's warm-up can cost real extra seconds - which the timing fit pays for out of rounds. The
    /// causal link is asserted rather than assumed in `testSitsLongChangesNoTrainingMovementOrTarget`.
    private func trainingShapeSignature(_ workout: Workout) -> [String] {
        trainingBlocks(workout).map { block in
            let items = block.exercises
                .map { "\($0.exercise.id):\($0.reps.map(String.init) ?? "-")/\($0.durationSeconds.map(String.init) ?? "-")" }
                .joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }
    }

    /// The uniform round count of each training block, in block order.
    private func roundCounts(_ workout: Workout) -> [Int] {
        trainingBlocks(workout).map { $0.exercises.first?.sets ?? 0 }
    }

    /// The planned seconds the mobility bookends consume - the one channel through which `sitsLong` can
    /// reach the training middle at all.
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

    // MARK: - (c) sitsLong is not a sizing lever

    /// `sitsLong` is not a lever on the training middle: at every length, the strength block - and, at
    /// 41-60 min, the dedicated primal block - contains the **same movements at the same per-set
    /// targets** for both profiles. The bias reaches only the mobility bookend *ordering*, so no training
    /// block gains or loses an exercise, and Step 6's capacity-relative reps/holds are untouched. This is
    /// the criterion that pins "`sitsLong` no longer sizes any block".
    ///
    /// **What may differ, and why (US-CC08, accepted).** The block's uniform **round count** can. The
    /// bias changes which stretches fill the fixed-count bookends, and since US-CC08 a rep-based stretch
    /// carries the generous runtime pace while a hold stretch does not, so a desk worker's warm-up can
    /// genuinely cost more seconds (at 45 min the shipped catalog picks two rep-based openers and the
    /// warm-up runs ~32s longer). The fit pays that out of the training middle, which under the even-round
    /// model means a whole round - so a desk worker can run one fewer strength round at 45 min, for the
    /// same total minutes and a longer warm-up. That was always incidental rather than structural (the
    /// bias adds no stretch and changes no count, so it cannot re-inflate a short session or create a
    /// mobility middle block); before US-CC08 the gap was ~10s and simply happened not to cross a round
    /// boundary. So this test asserts the invariant plus its *mechanism* - a round count may differ only
    /// where the bookends really do cost different seconds - rather than a byte-identity that was a
    /// coincidence of the shipped catalog's pricing.
    func testSitsLongChangesNoTrainingMovementOrTarget() async throws {
        let library = try await library()
        for minutes in [5, 20, 45, 60] {
            let desk = assemble(minutes: minutes, sitsLong: true, library: library)
            let general = assemble(minutes: minutes, sitsLong: false, library: library)

            XCTAssertEqual(
                trainingShapeSignature(desk), trainingShapeSignature(general),
                "\(minutes) min: sitsLong changed a training movement or its per-set target (it must only bias bookends)"
            )
            // Every training block stays internally even for both profiles: the bias can move a round
            // count, never make a circuit uneven (US-CC03).
            for workout in [desk, general] {
                for block in trainingBlocks(workout) where SessionAssembly.isCircuit(block.category) {
                    XCTAssertEqual(
                        Set(block.exercises.map(\.sets)).count, 1,
                        "\(minutes) min: \(block.title) is not internally uniform"
                    )
                }
                // And, again, no mobility middle block at any length under either flag.
                XCTAssertFalse(
                    workout.blocks.contains { $0.category == .mobility },
                    "\(minutes) min: a mobility middle block appeared"
                )
            }
            // The one permitted difference has exactly one cause: the bookends really cost different
            // seconds. Equal bookend seconds must still produce identical round counts, so the bias can
            // never reach the training middle through any other channel.
            if bookendSeconds(desk) == bookendSeconds(general) {
                XCTAssertEqual(
                    roundCounts(desk), roundCounts(general),
                    "\(minutes) min: sitsLong moved a round count without the bookends costing anything different"
                )
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
        let shifted = calendar.date(byAdding: .day, value: 37, to: asOf)!
        let base = assemble(minutes: 30, sitsLong: true, library: library, asOf: asOf)
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
