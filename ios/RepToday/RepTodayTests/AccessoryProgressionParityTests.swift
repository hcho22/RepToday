import XCTest
@testable import RepToday

/// US-RC03 (Accessory progression and Adaptive Overload integrity): a wide-circuit **accessory** - a
/// pattern's second-chain frontier promoted once every active station is at the round cap (US-RC01) -
/// must progress and be dosed *exactly* like a primary station. There is no separate "accessory"
/// code path: US-RC01 built every accessory as an honest frontier of its own chain drawn through the
/// same engine functions a primary flows through, so this suite is a **standing parity guard** rather
/// than coverage for new machinery.
///
/// The three behaviors the PRD names, each pinned on the shared path:
/// - **Advancement (Step 5).** `ProgressionChainSelection.selectAll` ranks *every* chain for a
///   pattern through the same `selectInChain`; an accessory is simply a lower-ranked result of that
///   one call. So when an accessory chain clears its frontier tier's `advancementCriteria`, it
///   advances by the identical rule that advances a primary - proven here by advancing a primary
///   (horizontal push) and an accessory (vertical push) in a single `selectAll` call.
/// - **Adaptive Overload (Step 6).** `SessionAssembly`'s `appendTrainingItem` doses every training
///   station - the seeded primary, the other patterns' primaries, and every accessory - through one
///   `AdaptiveOverload.target` call, so a target is always capacity-relative to *its own* movement.
///   Proven here on a real assembled block: an easier second-chain accessory earns more reps than a
///   harder primary, and each station's prescription equals `AdaptiveOverload.target` recomputed.
/// - **Variety window (Step 5).** The `varietyWindow` no-repeat preference is a leading sort key over
///   all of `selectAll`'s candidates, so a recently-worked accessory chain is de-preferred exactly as
///   any station is - proven here by flipping the window and watching the ranking move.
///
/// All fixtures use the real bundled `Exercises.json` (via `MockExerciseService`), whose push pattern
/// carries two chains - `push_horizontal` (wall -> incline -> knee -> standard -> diamond -> archer ->
/// one-arm) and `push_vertical` (floor-dips -> pike) - the PRD's own validation shape.
final class AccessoryProgressionParityTests: XCTestCase {

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

    private func user(level: FitnessLevel) -> User {
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

    /// A session `daysAgo` that worked one push exercise `id` with the given per-set `reps`.
    private func repsLog(
        id: String,
        reps: [Int],
        daysAgo: Int,
        skipped: Bool = false,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: difficulty,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
                    skipped: skipped
                )
            ]
        )
    }

    /// Every training station the strength block seeds (its one active station plus its whole reserve),
    /// read straight off `planBlocks` *before* the timing fit decides which of them to promote. Every
    /// accessory lives here regardless of the fit, and each already carries its Step 6 target, so this
    /// is the fit-independent place to inspect how an accessory was selected and dosed.
    private func strengthStations(
        minutes: Int,
        level: FitnessLevel,
        library: [Exercise],
        logs: [WorkoutLog]
    ) -> [PlannedItem] {
        let blocks = SessionAssembly.planBlocks(
            requestedMinutes: minutes,
            user: user(level: level),
            library: library,
            recentLogs: logs,
            asOf: asOf,
            calendar: calendar
        )
        guard let strength = blocks.first(where: { $0.category == .strength }) else { return [] }
        return strength.items + strength.reserve
    }

    // MARK: - Behavior 1: an accessory advances its own chain, identical to a primary (Step 5)

    /// The PRD's central assertion for advancement parity, proven at the shared Step 5 seam: a single
    /// `selectAll` call advances *both* the primary chain (horizontal push, cleared knee push-ups) and
    /// the accessory chain (vertical push, cleared floor dips) by the same `selectInChain` rule.
    ///
    /// Setup mirrors the PRD validation: horizontal push is at its frontier (knee, order 2) and vertical
    /// push enters as the accessory. Both chains clear their frontier tier's criteria in the logs;
    /// horizontal was worked more recently, so it ranks first (primary) and vertical ranks behind it
    /// (accessory) - yet both advance one tier, because advancement is a per-chain property of the one
    /// code path, not something only the top-ranked chain gets.
    func testAccessoryAdvancesItsOwnChainByTheSameRuleAsAPrimary() async throws {
        let library = try await library()

        // Horizontal frontier knee (order 2) cleared "3x12"; vertical entry floor-dips (order 0) cleared
        // "3x12". Horizontal worked more recently, so it is the primary and vertical is the accessory.
        let logs = [
            repsLog(id: "push_floor_dips", reps: [12, 12, 12], daysAgo: 3),
            repsLog(id: "push_knee", reps: [12, 12, 13], daysAgo: 1),
        ]

        let ranked = ProgressionChainSelection.selectAll(
            pattern: .push, library: library, pool: library, recentLogs: logs
        )
        XCTAssertGreaterThan(ranked.count, 1, "push must offer a primary and at least one accessory chain")

        // Primary: horizontal advanced knee -> standard.
        let primary = try XCTUnwrap(ranked.first)
        XCTAssertEqual(primary.chainId, "push_horizontal", "the recently-worked chain leads as the primary")
        XCTAssertEqual(primary.exercise.id, "push_standard", "the primary advanced to the next tier")
        XCTAssertTrue(primary.didAdvance)

        // Accessory: vertical advanced floor-dips -> pike, by the identical rule, ranked behind the primary.
        let verticalIndex = try XCTUnwrap(
            ranked.firstIndex { $0.chainId == "push_vertical" },
            "the vertical chain must appear as an accessory candidate"
        )
        XCTAssertGreaterThan(verticalIndex, 0, "the vertical chain is the accessory (not the primary)")
        let accessory = ranked[verticalIndex]
        XCTAssertEqual(accessory.exercise.id, "push_pike", "the accessory advanced to its own next tier")
        XCTAssertTrue(
            accessory.didAdvance,
            "an accessory clearing its criteria must advance exactly like the primary did"
        )
    }

    /// The end-to-end shape of the PRD validation: assemble, clear the accessory's tier, assemble again,
    /// and watch the accessory chain advance across sessions - read off the fit-independent `planBlocks`
    /// reserve so the proof does not depend on which stations the timing fit happens to promote.
    func testAssembledSessionAdvancesAnAccessoryChainAcrossSessions() async throws {
        let library = try await library()

        // Session 1: horizontal push high (diamond cleared -> the primary sits at archer), vertical push
        // untouched, so the vertical accessory enters fresh at floor-dips (order 0).
        let session1Logs = [repsLog(id: "push_diamond", reps: [10, 10, 10], daysAgo: 1)]
        let stations1 = strengthStations(minutes: 60, level: .advanced, library: library, logs: session1Logs)
        let vertical1 = try XCTUnwrap(
            stations1.first { $0.exercise.progressionChainId == "push_vertical" },
            "a 60-min advanced session must carry the vertical-push accessory in its reserve"
        )
        XCTAssertEqual(vertical1.exercise.id, "push_floor_dips", "the untouched vertical chain enters at its base tier")

        // Session 2: add a log clearing the vertical accessory's tier ("3x12" for floor-dips).
        let session2Logs = session1Logs + [repsLog(id: "push_floor_dips", reps: [12, 12, 13], daysAgo: 0)]
        let stations2 = strengthStations(minutes: 60, level: .advanced, library: library, logs: session2Logs)
        let vertical2 = try XCTUnwrap(
            stations2.first { $0.exercise.progressionChainId == "push_vertical" },
            "the vertical-push accessory must still be present next session"
        )
        XCTAssertEqual(
            vertical2.exercise.id, "push_pike",
            "clearing the accessory's criteria advances its own chain next session, just like a primary"
        )
        XCTAssertGreaterThan(
            vertical2.exercise.progressionOrder, vertical1.exercise.progressionOrder,
            "the accessory advanced up its chain rather than repeating or being re-seeded"
        )
    }

    // MARK: - Behavior 2: Adaptive Overload is capacity-relative to the accessory's own movement (Step 6)

    /// An *easier* second-chain accessory earns *more* reps than a *harder* primary, because
    /// `appendTrainingItem` doses both through the one `AdaptiveOverload.target` call - capacity-relative
    /// to each movement, never a fixed number. Read off `planBlocks` (fit-independent), so the accessory
    /// is dosed whether or not the timing fit later promotes it.
    ///
    /// Setup: horizontal push cleared to a hard frontier (diamond -> primary sits at archer, difficulty 4,
    /// default 5 reps), vertical push fresh (accessory enters at floor-dips, difficulty 2, default 10
    /// reps). Neither the archer nor the floor-dips has its own logged capacity, so each is dosed off its
    /// movement's own default - the easier accessory proportionally higher. The default `SessionPolicy`
    /// carries no cold-start contract, so the Start Seed is neutral and the target is exactly the
    /// movement's own default (clamped), which is what makes the equality assertions below exact.
    func testEasierAccessoryEarnsMoreRepsThanAHarderPrimary() async throws {
        let library = try await library()
        let logs = [repsLog(id: "push_diamond", reps: [10, 10, 10], daysAgo: 1)]
        let stations = strengthStations(minutes: 60, level: .advanced, library: library, logs: logs)

        let primary = try XCTUnwrap(
            stations.first { $0.exercise.id == "push_archer" },
            "horizontal push should have advanced diamond -> archer as its primary"
        )
        let accessory = try XCTUnwrap(
            stations.first { $0.exercise.id == "push_floor_dips" },
            "vertical push should enter fresh at floor-dips as the accessory"
        )

        // The easier accessory (difficulty 2) earns more reps than the harder primary (difficulty 4):
        // dosing is capacity-relative to the movement, not a shared fixed number.
        XCTAssertLessThan(
            accessory.exercise.difficulty, primary.exercise.difficulty,
            "fixture sanity: the accessory movement is genuinely easier (lower difficulty) than the primary"
        )
        let primaryReps = try XCTUnwrap(primary.reps)
        let accessoryReps = try XCTUnwrap(accessory.reps)
        XCTAssertGreaterThan(
            accessoryReps, primaryReps,
            "the easier second-chain accessory must earn proportionally more reps than the harder primary"
        )

        // And each station is dosed by the very same Step 6 rule, recomputed here - proof there is no
        // separate accessory dosing path (the accessory's number is not a fixed filler value).
        XCTAssertEqual(
            primaryReps,
            AdaptiveOverload.target(for: primary.exercise, recentLogs: logs).reps,
            "the primary is dosed by AdaptiveOverload.target"
        )
        XCTAssertEqual(
            accessoryReps,
            AdaptiveOverload.target(for: accessory.exercise, recentLogs: logs).reps,
            "the accessory is dosed by the identical AdaptiveOverload.target call"
        )
    }

    // MARK: - Behavior 3: the varietyWindow de-prefers a recently-used accessory like any station (Step 5)

    /// A recently-worked chain is de-preferred by the same `varietyWindow` no-repeat rule whether it
    /// would rank as a primary or an accessory. Here the vertical chain (floor-dips worked yesterday, not
    /// cleared) would win the active-chain preference, but because floor-dips is inside the variety
    /// window it is pushed behind the fresh horizontal entry - so the window alone demotes it to the
    /// accessory slot. Shrinking the window to 0 removes that avoidance and the ranking flips back,
    /// isolating the `varietyWindow` as the cause.
    func testVarietyWindowDePrefersARecentlyUsedAccessoryLikeAnyStation() async throws {
        let library = try await library()
        // Vertical floor-dips worked yesterday but not cleared (only 2 clean sets vs the "3x12" it needs),
        // so the vertical pick stays floor-dips; horizontal push is untouched, entering fresh at wall.
        let logs = [repsLog(id: "push_floor_dips", reps: [8, 8, 8], daysAgo: 1)]

        // Default window (3): floor-dips is recently used -> the vertical chain is de-preferred, so the
        // fresh horizontal entry leads and vertical is the accessory.
        let windowed = ProgressionChainSelection.selectAll(
            pattern: .push, library: library, pool: library, recentLogs: logs, varietyWindow: 3
        )
        XCTAssertEqual(windowed.first?.chainId, "push_horizontal", "the fresh chain leads when the accessory is recently used")
        let windowedVerticalIndex = try XCTUnwrap(windowed.firstIndex { $0.chainId == "push_vertical" })
        XCTAssertGreaterThan(
            windowedVerticalIndex, 0,
            "the recently-used vertical chain is de-preferred to the accessory slot by the variety window"
        )

        // Window 0: no recent-use avoidance -> the actively-worked vertical chain wins, proving it was
        // the variety window (not some other rule) that demoted the accessory above.
        let unwindowed = ProgressionChainSelection.selectAll(
            pattern: .push, library: library, pool: library, recentLogs: logs, varietyWindow: 0
        )
        XCTAssertEqual(
            unwindowed.first?.chainId, "push_vertical",
            "with the variety window off, the recently-worked chain is no longer de-preferred"
        )
    }
}
