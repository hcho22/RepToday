import XCTest
@testable import RepToday

/// US-RC04 (Accept and pin the bounded depth mismatch): going wider (US-RC01) draws a pattern's
/// **second progression chain** as an accessory, and the two chains can have different depths - the
/// shipped push pattern's horizontal chain runs eight tiers (wall -> ... -> one-arm) while its vertical
/// chain runs two (floor-dips -> pike). So an advanced user maxed on horizontal push works a primary
/// that is *harder* than the deepest the vertical accessory can reach. That mismatch is **deliberately
/// accepted, not gated** (ADR-0004): the accessory stays an honest frontier of its own chain rather
/// than being seeded up to the primary's difficulty to "match."
///
/// This suite is a **standing guard** on the two facts that keep the mismatch bounded and honest - it
/// added no production code, because both are already structural from US-RC01:
///
/// - **Bounded by the user's staples.** Every chain's prescribable frontier is clamped to the movements
///   the user gets (`MovementAccess`, ADR-0007: beginner and intermediate users get staples only, an
///   advanced user the discipline-phase catalog), applied to *both* the primary and the accessory by the
///   one `eligiblePool` pass inside `planBlocks`. For a beginner the two push chains both top out at
///   difficulty 2 (standard push-up and floor-dips), so the maxed mismatch is **zero**. For an
///   intermediate the horizontal chain tops out at diamond (difficulty 3) while the vertical tops out at
///   floor-dips (difficulty 2, pike is advanced only), and for an advanced user in the discipline phase at
///   archer (difficulty 4; one-arm is phase-gated to Strength) against pike (difficulty 3): the maxed
///   mismatch is exactly **one** difficulty tier in both - and can never widen past what the user gets.
/// - **Never seeded above an earned tier.** An *untouched* second chain is entered at its gentlest
///   eligible tier (`selectInChain`'s no-history entry, `progressionOrder` 0 when the Start-Seed band
///   withheld nothing), never seeded up to the pattern frontier the user cleared on the *other* chain.
///   So an advanced user deep on horizontal push still meets vertical push at floor-dips (order 0), the
///   earned-progression invariant holding for accessories exactly as for primaries.
///
/// All fixtures use the real bundled `Exercises.json` (via `MockExerciseService`) and read stations off
/// the fit-independent `planBlocks` reserve, so movement access is exercised end-to-end (the pool
/// filter that enforces it runs inside `planBlocks`) and the proof does not depend on which stations the
/// timing fit happens to promote. Sibling of `AccessoryProgressionParityTests` (US-RC03).
final class AccessoryDepthMismatchTests: XCTestCase {

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

    /// A session `daysAgo` that worked one push exercise `id` with the given per-set `reps`, so the
    /// engine reads `id` as the user's frontier on that chain.
    private func repsLog(id: String, reps: [Int], daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: [
                LoggedExercise(
                    id: UUID(),
                    exerciseId: id,
                    pillar: .strength,
                    movementPattern: .push,
                    completedSets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) },
                    skipped: false
                )
            ]
        )
    }

    /// Every training station the strength block seeds (its active stations plus its whole reserve),
    /// read straight off `planBlocks` *before* the timing fit decides which to promote. Every accessory
    /// lives here regardless of the fit, and the movement access that bounds the mismatch has already
    /// been applied by `eligiblePool` inside `planBlocks`.
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

    /// The push horizontal (primary) and vertical (accessory) stations in a session, by chain id -
    /// read by chain rather than by rank so an assertion never hinges on the freshness ordering.
    private func pushChains(
        in stations: [PlannedItem]
    ) throws -> (horizontal: PlannedItem, vertical: PlannedItem) {
        let horizontal = try XCTUnwrap(
            stations.first { $0.exercise.progressionChainId == "push_horizontal" },
            "a long session must carry the horizontal-push chain"
        )
        let vertical = try XCTUnwrap(
            stations.first { $0.exercise.progressionChainId == "push_vertical" },
            "a long session must carry the vertical-push chain as its second-chain accessory"
        )
        return (horizontal, vertical)
    }

    // MARK: - Beginner / intermediate: accessory frontier sits in the primary's band (zero mismatch)

    /// Beginner (staples only): with both push chains worked to their staple frontier, the primary
    /// (horizontal, standard, difficulty 2) and the accessory (vertical, floor-dips, difficulty 2) land at
    /// the **same** difficulty and the mismatch is **zero** - the vertical chain's harder pike tier is
    /// advanced only, and diamond is not a beginner staple, so both chains top out at 2.
    func testBeginnerAccessoryFrontierMatchesPrimaryBandWithZeroMismatch() async throws {
        let library = try await library()
        // Horizontal worked at standard (order 3, difficulty 2 - the top of a beginner's staples); vertical
        // worked at floor-dips (order 0, difficulty 2 - the vertical chain's only beginner staple).
        let logs = [
            repsLog(id: "push_standard", reps: [8, 8, 8], daysAgo: 2),
            repsLog(id: "push_floor_dips", reps: [8, 8, 8], daysAgo: 1),
        ]
        let stations = strengthStations(minutes: 60, level: .beginner, library: library, logs: logs)
        let (primary, accessory) = try pushChains(in: stations)

        XCTAssertEqual(primary.exercise.id, "push_standard", "fixture sanity: horizontal is at its beginner-cap frontier")
        XCTAssertEqual(accessory.exercise.id, "push_floor_dips", "fixture sanity: vertical is at its beginner-cap frontier")

        // Both draw from the very same set of staples, so neither can be out of reach relative to the other.
        XCTAssertTrue(MovementAccess.isAvailable(primary.exercise, level: .beginner, phase: .discipline), "the primary is a beginner staple")
        XCTAssertTrue(MovementAccess.isAvailable(accessory.exercise, level: .beginner, phase: .discipline), "the accessory is a beginner staple too")
        XCTAssertEqual(
            accessory.exercise.difficulty, primary.exercise.difficulty,
            "at a beginner's staples both chains top out at the same difficulty - the depth mismatch is zero"
        )
    }

    /// Intermediate (staples plus the intermediate ones): horizontal tops out at diamond (difficulty 3)
    /// while vertical tops out at floor-dips (difficulty 2 - pike is advanced only), so the maxed
    /// mismatch is exactly **one** tier: bounded, honest, and the accessory is never seeded up to match.
    func testIntermediateAccessoryFrontierIsAtMostOneTierBelowPrimary() async throws {
        let library = try await library()
        let logs = [
            repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 2),
            repsLog(id: "push_floor_dips", reps: [8, 8, 8], daysAgo: 1),
        ]
        let stations = strengthStations(minutes: 60, level: .intermediate, library: library, logs: logs)
        let (primary, accessory) = try pushChains(in: stations)

        XCTAssertEqual(primary.exercise.id, "push_diamond", "fixture sanity: horizontal is at its intermediate frontier")
        XCTAssertEqual(accessory.exercise.id, "push_floor_dips", "fixture sanity: vertical is at its intermediate frontier (pike is advanced only)")

        XCTAssertTrue(MovementAccess.isAvailable(primary.exercise, level: .intermediate, phase: .discipline))
        XCTAssertTrue(MovementAccess.isAvailable(accessory.exercise, level: .intermediate, phase: .discipline))
        XCTAssertEqual(
            primary.exercise.difficulty - accessory.exercise.difficulty, 1,
            "an intermediate's maxed mismatch is exactly one difficulty tier"
        )
    }

    // MARK: - Advanced: the maxed mismatch is bounded to one tier, and stays honest

    /// Advanced (the whole discipline-phase catalog), maxed on the deep horizontal chain: the primary is
    /// archer (difficulty 4 - one-arm push-up, difficulty 5, is Strength-phase-gated so a discipline user
    /// tops out at archer) and the maxed vertical accessory is pike (difficulty 3). The accepted mismatch
    /// is therefore exactly **one** difficulty tier, and the test pins that it never exceeds one.
    ///
    /// This is the whole point of ADR-0004: the vertical accessory is *not* nudged up to difficulty 4 to
    /// match the primary; it stays the honest top of its own shallower chain, one tier below.
    func testAdvancedMaxedChainAccessoryIsAtMostOneTierBelowInSteadyState() async throws {
        let library = try await library()
        // Horizontal maxed at archer (the deepest discipline-phase tier); vertical maxed at pike.
        let logs = [
            repsLog(id: "push_archer", reps: [8, 8, 8], daysAgo: 2),
            repsLog(id: "push_pike", reps: [8, 8, 8], daysAgo: 1),
        ]
        let stations = strengthStations(minutes: 60, level: .advanced, library: library, logs: logs)
        let (primary, accessory) = try pushChains(in: stations)

        XCTAssertEqual(
            primary.exercise.id, "push_archer",
            "fixture sanity: horizontal tops out at archer for a discipline-phase advanced user (one-arm is Strength-gated)"
        )
        XCTAssertEqual(accessory.exercise.id, "push_pike", "fixture sanity: the vertical accessory is maxed at pike")

        // The accessory is easier than the primary (the accepted mismatch), but bounded to one tier and
        // never seeded up to match.
        XCTAssertLessThan(
            accessory.exercise.difficulty, primary.exercise.difficulty,
            "the shallower accessory chain tops out below the deep primary - the accepted depth mismatch"
        )
        XCTAssertLessThanOrEqual(
            primary.exercise.difficulty - accessory.exercise.difficulty, 1,
            "the accepted mismatch is bounded to a single difficulty tier for a maxed advanced user"
        )
    }

    // MARK: - The earned-progression invariant holds for accessories (no unearned seeding)

    /// The core invariant (AC3): an **untouched** second chain is entered at its base tier, never seeded
    /// up to the frontier the user cleared on the *other* chain. An advanced user maxed on horizontal
    /// push, with **no** vertical-push history, still meets the vertical accessory at floor-dips (order
    /// 0) - not at pike (order 1), which nothing in their logs earned.
    ///
    /// Non-vacuity: were an accessory ever seeded at the pattern's cleared frontier (rather than per its
    /// own chain history), this advanced-on-horizontal user would be handed pike here and both the
    /// base-id and the base-order assertions would fail.
    func testUntouchedSecondChainEntersAtBaseTierNeverSeededHigher() async throws {
        let library = try await library()
        // Horizontal maxed at archer; vertical completely untouched.
        let logs = [repsLog(id: "push_archer", reps: [8, 8, 8], daysAgo: 1)]
        let stations = strengthStations(minutes: 60, level: .advanced, library: library, logs: logs)
        let (primary, accessory) = try pushChains(in: stations)

        XCTAssertEqual(primary.exercise.id, "push_archer", "fixture sanity: the user is deep on the horizontal chain")
        XCTAssertEqual(
            accessory.exercise.id, "push_floor_dips",
            "the untouched vertical chain enters at its base tier, not seeded up to the primary's frontier"
        )
        XCTAssertEqual(
            accessory.exercise.progressionOrder, 0,
            "an untouched accessory is entered at progression order 0 - the earned-progression invariant"
        )
        XCTAssertLessThan(
            accessory.exercise.difficulty, primary.exercise.difficulty,
            "the freshly-entered accessory is far easier than the maxed primary, never seeded to match it"
        )
    }

    /// A broad standing guard for AC3 across every level and both long lengths: **no** strength station -
    /// active or reserve, primary or accessory - is ever a movement the user does not get. This is what
    /// bounds the depth mismatch structurally: since both chains are clamped to the same set of staples,
    /// an accessory can never sit above where the user's access allows.
    ///
    /// Non-vacuity: bound to `MovementAccess`, so were the gate ever removed or an accessory path added
    /// that skipped it, a beginner would draw a non-staple tier (pike, diamond) and this guard would fail.
    func testNoAccessoryIsEverSeededBeyondTheUsersStaples() async throws {
        let library = try await library()
        for level in FitnessLevel.allCases {
            for minutes in [45, 60] {
                // Give a rich push history so both chains are populated and near their frontier, exercising
                // the widest set of accessory candidates the reserve can hold.
                let logs = [
                    repsLog(id: "push_archer", reps: [8, 8, 8], daysAgo: 3),
                    repsLog(id: "push_pike", reps: [8, 8, 8], daysAgo: 2),
                ]
                let stations = strengthStations(minutes: minutes, level: level, library: library, logs: logs)
                XCTAssertFalse(stations.isEmpty, "a \(minutes)-min \(level) session must plan strength stations")
                for station in stations {
                    XCTAssertTrue(
                        MovementAccess.isAvailable(station.exercise, level: level, phase: .discipline),
                        "\(level) \(minutes)min: station \(station.exercise.id) is not a movement a \(level) user gets"
                    )
                }
            }
        }
    }
}
