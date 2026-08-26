import XCTest
@testable import RepToday

/// US-AC05: the `patternEmphasis` Session Policy lever biases Step 3's stalest-first ordering toward or
/// away from a movement pattern *as a pure preference*, never breaking session structure.
///
/// The lever is a per-`MovementPattern` **multiplier on staleness** (see `SessionPolicy.patternEmphasis`
/// and `PatternFocus.rank`), clamped to `[0.5, 2.0]` and threaded into `SessionAssembly` only through
/// `orderedStrengthPatterns`. Shaped like the `sitsLong` bias: a reorder layered on the existing
/// ordering, so it can never remove a movement, starve a pool, make a block uneven, change a block's
/// uniform round count (ADR-0003), or reintroduce a mobility middle block.
///
/// Coverage mirrors the PRD acceptance criteria and Validation Test:
///   (a) **neutral is a no-op** - an explicit neutral emphasis assembles byte-for-byte identically to
///       the pre-lever `SessionPolicy.default`, across every length and fitness level. (The algorithm-
///       level neutral==unweighted proof lives in `MovementPatternFocusTests`.)
///   (b) the Validation Test proper - a push-high / squat-low policy leads with push *more often* than
///       a neutral policy across a spread of histories, while a de-emphasized squat leads *less often*;
///   (c) the hard structural invariants hold under emphasis across all lengths and all fitness levels:
///       identical block structure to neutral, no starved (empty) training block, every training block
///       internally even and inside the `2...4` round cap, and no mobility middle block ever.
final class PatternEmphasisPolicyTests: XCTestCase {

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

    /// The steady-state neutral policy (no cold-start contract, so Step 0 is a no-op and Step 3's
    /// staleness/emphasis ordering actually drives the lead) with the given per-pattern emphasis.
    private func policy(emphasis: [MovementPattern: Double] = [:]) -> SessionPolicy {
        var policy = SessionPolicy.default
        for (pattern, value) in emphasis {
            policy.patternEmphasis[pattern] = value
        }
        return policy
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: asOf)!
    }

    /// A completed log whose worked exercises follow `patterns` in order (the first is the lead).
    private func log(patterns: [MovementPattern], daysAgo: Int) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 20,
            durationMinutes: 20,
            shape: .blend,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: patterns.map { pattern in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "ex-\(pattern.rawValue)-\(daysAgo)",
                    pillar: pattern == .mobility ? .mobility : .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: false
                )
            }
        )
    }

    private func assemble(
        minutes: Int,
        level: FitnessLevel,
        library: [Exercise],
        recentLogs: [WorkoutLog] = [],
        emphasis: [MovementPattern: Double] = [:]
    ) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: user(level: level),
            library: library,
            recentLogs: recentLogs,
            sessionPolicy: policy(emphasis: emphasis),
            asOf: asOf,
            calendar: calendar
        )
    }

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    /// A stable, full signature of the assembled workout - block category and every station's id, per-set
    /// target (reps / hold seconds), and round count, in order. Byte-identity of this signature is the
    /// "neutral reproduces current behavior exactly" guarantee.
    private func signature(_ workout: Workout) -> [String] {
        workout.blocks.map { block in
            let items = block.exercises
                .map { "\($0.exercise.id):\($0.reps.map(String.init) ?? "-")/\($0.durationSeconds.map(String.init) ?? "-"):\($0.sets)" }
                .joined(separator: ",")
            return "\(block.category.rawValue)[\(items)]"
        }
    }

    /// The lead strength pattern: the first station of the first strength block (the seeded active
    /// station, which is the pattern `orderedStrengthPatterns` led with).
    private func leadStrengthPattern(_ workout: Workout) -> MovementPattern? {
        workout.blocks.first { $0.category == .strength }?.exercises.first?.exercise.movementPattern
    }

    // MARK: - (a) Neutral is a byte-for-byte no-op

    /// An explicit neutral emphasis assembles identically to the pre-lever `SessionPolicy.default` across
    /// every length and fitness level - the "neutral matches pre-change output byte-for-byte" guarantee.
    func testNeutralEmphasisMatchesDefaultPolicyByteForByte() async throws {
        let library = try await library()
        // A representative non-trivial history so the comparison exercises real staleness ordering, not
        // just the empty-log canonical default.
        let logs = [
            log(patterns: [.core, .hinge], daysAgo: 1),
            log(patterns: [.push], daysAgo: 3),
            log(patterns: [.squat], daysAgo: 6),
        ]
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let neutral = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: logs, sessionPolicy: policy(emphasis: SessionPolicy.neutralPatternEmphasis),
                    asOf: asOf, calendar: calendar
                )
                let baseline = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: logs, sessionPolicy: .default, asOf: asOf, calendar: calendar
                )
                XCTAssertEqual(
                    signature(neutral), signature(baseline),
                    "\(level) \(minutes)-min: neutral emphasis drifted from the default-policy baseline"
                )
            }
        }
    }

    // MARK: - (b) The Validation Test: emphasized leads with push more often

    /// The PRD Validation Test. A push-high / squat-low policy vs a neutral policy, assembled over a
    /// spread of histories in which squat is moderately staler than push (the near-tie band a gentle
    /// emphasis can flip). The emphasized policy leads with push in strictly more sessions, and the
    /// de-emphasized squat leads in strictly fewer - while never starving, unbalancing, or filtering.
    func testEmphasizedPolicyLeadsWithPushMoreOftenThanNeutral() async throws {
        let library = try await library()
        let emphasis: [MovementPattern: Double] = [.push: SessionPolicy.maxEmphasis, .squat: SessionPolicy.minEmphasis]

        // Each history: the most recent session (1 day ago) leads with core (so core is the held-back
        // no-repeat pattern, leaving push/squat free to lead) and works every *other* pattern fresh -
        // hinge/pull/locomotion too, so only push and squat are stale (an untouched primal locomotion
        // would otherwise be maximally stale and lead). push worked 3 days ago and squat worked
        // `squatDays` ago - staler than push, so neutral leads with squat.
        var neutralPushLeads = 0, emphasizedPushLeads = 0
        var neutralSquatLeads = 0, emphasizedSquatLeads = 0

        for squatDays in [4, 5, 6, 8, 12] {
            let logs = [
                log(patterns: [.core, .hinge, .pull, .locomotion], daysAgo: 1),
                log(patterns: [.push], daysAgo: 3),
                log(patterns: [.squat], daysAgo: squatDays),
            ]
            let neutral = assemble(minutes: 20, level: .intermediate, library: library, recentLogs: logs)
            let emphasized = assemble(minutes: 20, level: .intermediate, library: library, recentLogs: logs, emphasis: emphasis)

            if leadStrengthPattern(neutral) == .push { neutralPushLeads += 1 }
            if leadStrengthPattern(emphasized) == .push { emphasizedPushLeads += 1 }
            if leadStrengthPattern(neutral) == .squat { neutralSquatLeads += 1 }
            if leadStrengthPattern(emphasized) == .squat { emphasizedSquatLeads += 1 }
        }

        XCTAssertGreaterThan(
            emphasizedPushLeads, neutralPushLeads,
            "push emphasis must make push lead more often (emphasized \(emphasizedPushLeads) vs neutral \(neutralPushLeads))"
        )
        XCTAssertLessThan(
            emphasizedSquatLeads, neutralSquatLeads,
            "squat de-emphasis must make squat lead less often (emphasized \(emphasizedSquatLeads) vs neutral \(neutralSquatLeads))"
        )
    }

    // MARK: - (c) Structural invariants hold under emphasis across all lengths and levels

    /// Under a strong push-high / squat-low emphasis, across every length and fitness level: the block
    /// structure is identical to the neutral session, no training block is starved (empty), every
    /// training block is internally even and inside the `2...4` round cap (ADR-0003), and no mobility
    /// middle block ever appears. This is the "never starved / uneven / filtered / mobility-middle"
    /// failure-indicator set from the Validation Test.
    func testEmphasisNeverBreaksStructureAcrossLengthsAndLevels() async throws {
        let library = try await library()
        let emphasis: [MovementPattern: Double] = [.push: SessionPolicy.maxEmphasis, .squat: SessionPolicy.minEmphasis]
        // A history where squat is the stalest strength pattern, so a de-emphasis genuinely reorders the
        // pattern list (the interesting case for "does the reorder break anything").
        let logs = [
            log(patterns: [.push, .hinge], daysAgo: 1),
            log(patterns: [.core], daysAgo: 2),
            log(patterns: [.squat], daysAgo: 9),
        ]

        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let neutral = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: logs, sessionPolicy: .default, asOf: asOf, calendar: calendar
                )
                let emphasized = SessionAssembly.assemble(
                    requestedMinutes: minutes, user: user(level: level), library: library,
                    recentLogs: logs, sessionPolicy: policy(emphasis: emphasis), asOf: asOf, calendar: calendar
                )
                let label = "\(level) \(minutes)-min"

                // Identical block structure: same categories in the same order - emphasis reorders
                // patterns, never the session's block skeleton.
                XCTAssertEqual(
                    emphasized.blocks.map(\.category), neutral.blocks.map(\.category),
                    "\(label): emphasis changed the block structure"
                )

                // No mobility *middle* block for either profile.
                for workout in [neutral, emphasized] {
                    XCTAssertFalse(
                        workout.blocks.contains { $0.category == .mobility },
                        "\(label): a mobility middle block appeared"
                    )
                }

                // Every training block: non-empty (not starved), internally even, inside 2...4.
                let training = emphasized.blocks.filter { SessionAssembly.isCircuit($0.category) }
                XCTAssertFalse(training.isEmpty, "\(label): emphasis produced no training block")
                for block in training {
                    XCTAssertFalse(
                        block.exercises.isEmpty,
                        "\(label): training block \(block.title) is starved (no stations)"
                    )
                    let roundCounts = Set(block.exercises.map(\.sets))
                    XCTAssertEqual(
                        roundCounts.count, 1,
                        "\(label): training block \(block.title) is uneven with rounds \(roundCounts.sorted())"
                    )
                    for exercise in block.exercises {
                        XCTAssertGreaterThanOrEqual(
                            exercise.sets, 2,
                            "\(label): \(block.title)/\(exercise.exercise.id) has \(exercise.sets) rounds, below the floor of 2"
                        )
                        XCTAssertLessThanOrEqual(
                            exercise.sets, 4,
                            "\(label): \(block.title)/\(exercise.exercise.id) has \(exercise.sets) rounds, above the cap of 4"
                        )
                    }
                }
            }
        }
    }

    /// An out-of-range emphasis is clamped at the engine boundary, never treated as a filter: a wildly
    /// out-of-range value (0 / negative / huge) produces a well-formed session with the same structural
    /// guarantees as an in-range one - the ordering is only ever reordered, never inverted or emptied.
    func testOutOfRangeEmphasisIsClampedAndNeverFilters() async throws {
        let library = try await library()
        let wild: [MovementPattern: Double] = [.push: 1_000_000, .squat: -5, .hinge: 0]
        let logs = [
            log(patterns: [.core], daysAgo: 1),
            log(patterns: [.squat], daysAgo: 7),
        ]
        for minutes in lengths {
            for level in FitnessLevel.allCases {
                let workout = assemble(minutes: minutes, level: level, library: library, recentLogs: logs, emphasis: wild)
                let label = "\(level) \(minutes)-min"
                let training = workout.blocks.filter { SessionAssembly.isCircuit($0.category) }
                XCTAssertFalse(training.isEmpty, "\(label): a clamped-wild emphasis starved the training middle")
                for block in training {
                    XCTAssertFalse(block.exercises.isEmpty, "\(label): \(block.title) has no stations")
                    XCTAssertEqual(Set(block.exercises.map(\.sets)).count, 1, "\(label): \(block.title) is uneven")
                    for exercise in block.exercises {
                        XCTAssertTrue(
                            (2...4).contains(exercise.sets),
                            "\(label): \(block.title)/\(exercise.exercise.id) has \(exercise.sets) rounds, outside 2...4"
                        )
                    }
                }
                XCTAssertFalse(
                    workout.blocks.contains { $0.category == .mobility },
                    "\(label): a mobility middle block appeared under a clamped-wild emphasis"
                )
            }
        }
    }
}
