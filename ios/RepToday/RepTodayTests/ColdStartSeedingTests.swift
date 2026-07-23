import XCTest
@testable import RepToday

/// Tests the cold-start Starting Difficulty seeding (US-G01): onboarding maps the self-reported
/// `fitnessLevel` to a capped `coldStartContract.cappedMaxDifficulty` and layers the contract onto
/// the neutral starting policy, and the engine then serves the *gentle end* of the capped band.
///
/// The pure seeding half (`SessionPolicy.ColdStartContract.cappedMaxDifficulty(for:)` and the
/// `seeded(...)` factories) is asserted directly; the gentle-end / cap-respecting half is validated
/// end-to-end through `SessionAssembly` over the real bundled library, per the PRD validation.
final class ColdStartSeedingTests: XCTestCase {

    // MARK: - Fixtures

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

    /// A fresh, freshly-onboarded user at the given fitness level: cold-start active, no history,
    /// no `why` bias, so the engine runs cold-start Step 0 against the seeded policy.
    private func freshUser(level: FitnessLevel) -> User {
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
                weeklyGoal: 3, score: 50, workoutsThisWeek: 0,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            ),
            coldStart: .fresh
        )
    }

    // MARK: - The capped band per fitness level (US-G01)

    func testCappedMaxDifficultyPerFitnessLevel() {
        XCTAssertEqual(SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: .beginner), 2)
        XCTAssertEqual(SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: .intermediate), 3)
        XCTAssertEqual(SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: .advanced), 4)
    }

    /// The capped band never exceeds the steady-state difficulty cap the pool filter applies, so the
    /// cold-start cap can only ever be as tight or tighter than the eventual band.
    func testCappedBandNeverExceedsSteadyStateCap() {
        for level in FitnessLevel.allCases {
            let coldCap = SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: level)
            let steadyTop = ExercisePoolFilter.difficultyCap(for: level).upperBound
            XCTAssertLessThanOrEqual(
                coldCap, steadyTop,
                "\(level) cold-start cap \(coldCap) must not exceed the steady-state cap \(steadyTop)"
            )
        }
    }

    /// The seeded contract forces First-Week Contrast (US-G02) and carries the level's capped band.
    func testSeededContractForcesContrastAndCarriesTheCap() {
        for level in FitnessLevel.allCases {
            let contract = SessionPolicy.ColdStartContract.seeded(for: level)
            XCTAssertTrue(contract.forceContrastSpread, "a cold-start contract forces First-Week Contrast")
            XCTAssertEqual(
                contract.cappedMaxDifficulty,
                SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: level)
            )
        }
    }

    /// The seeded starting policy is the neutral default with only the cold-start contract layered on -
    /// every other lever untouched, so retiring cold-start (US-G04) returns exactly `default` behavior.
    func testSeededPolicyLayersContractOntoNeutralDefault() {
        for level in FitnessLevel.allCases {
            let policy = SessionPolicy.seeded(forFitnessLevel: level)
            XCTAssertEqual(policy.coldStartContract, SessionPolicy.ColdStartContract.seeded(for: level))

            // Everything else is untouched: proving it by clearing the contract yields the default.
            var stripped = policy
            stripped.coldStartContract = nil
            XCTAssertEqual(stripped, SessionPolicy.default, "seeding must move no lever other than the cold-start contract")
        }
    }

    // MARK: - Band-entry selection, end-to-end (US-G01 validation, re-based on US-O02)

    /// PRD validation: three fresh users (beginner/intermediate/advanced) each get a first session that
    /// never exceeds their cap and opens at the *entry* of their band.
    ///
    /// US-O02 raised the band's floor from a flat `1` to a fitness-level Start Seed, so "the gentle end"
    /// is now the gentle end of `[startingDifficultyFloor, cappedMaxDifficulty]` rather than the
    /// library's absolute entry tier: a beginner still opens at difficulty 1, while an active user opens
    /// at their seeded floor (clamped down to the hardest movement a pattern actually offers, since
    /// banding never empties a pattern). The cap half of the contract is unchanged.
    func testFirstSessionCapsDifficultyAndOpensAtTheBandEntry() async throws {
        let library = try await library()

        for level in FitnessLevel.allCases {
            let cap = SessionPolicy.ColdStartContract.cappedMaxDifficulty(for: level)
            let user = freshUser(level: level)
            let policy = SessionPolicy.seeded(forFitnessLevel: level)

            let workout = SessionAssembly.assemble(
                requestedMinutes: 8, user: user, library: library,
                recentLogs: [], sessionPolicy: policy, asOf: asOf, calendar: calendar
            )

            let prescriptions = workout.blocks.flatMap(\.exercises)
            XCTAssertFalse(prescriptions.isEmpty, "\(level) first session must be non-empty")

            // Never over the cap.
            for prescription in prescriptions {
                XCTAssertLessThanOrEqual(
                    prescription.exercise.difficulty, cap,
                    "\(level) first session prescribed \(prescription.exercise.id) (difficulty "
                        + "\(prescription.exercise.difficulty)) above the cap \(cap)"
                )
            }

            // Band entry: with no history, the strength/primal movements are the gentlest tier inside
            // the seeded band, never the top of the cap. Warm-up/cooldown are excluded since they are
            // fixed structural mobility blocks, never floored or band-selected (US-O02).
            let trainingDifficulties = workout.blocks
                .filter { $0.category == .strength || $0.category == .primal }
                .flatMap(\.exercises)
                .map(\.exercise.difficulty)
            XCTAssertFalse(trainingDifficulties.isEmpty, "\(level) must have at least one training block")

            // The band the Start Seed left the engine to choose from; its entry is the gentlest tier the
            // session may open at.
            let banded = ColdStartOverride.startBandedPool(
                ColdStartOverride.cappedPool(
                    ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: []),
                    user: user,
                    sessionPolicy: policy
                ),
                user: user,
                sessionPolicy: policy
            )
            let bandEntry = banded
                .filter { $0.pillar == .strength || $0.pillar == .primal }
                .map(\.difficulty)
                .min()!
            let easiest = trainingDifficulties.min()!
            XCTAssertGreaterThanOrEqual(
                easiest, bandEntry,
                "\(level) first session must open at its band entry (\(bandEntry)), not below it at "
                    + "difficulty \(easiest)"
            )
            if level == .beginner {
                XCTAssertEqual(
                    easiest, 1,
                    "a beginner's band is unfloored, so their first session still opens at difficulty 1"
                )
            }
            XCTAssertLessThan(
                trainingDifficulties.max()!, cap + 1,
                "\(level) first session must never open at or above the top of the cap"
            )
        }
    }
}
