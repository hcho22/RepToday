import XCTest
@testable import RepToday

/// US-AC05: the `patternEmphasis` Session Policy lever under the fixed Push -> Pull -> Legs Rotation.
///
/// The Rotation decides the day and each day's ladders are fixed, so the engine does not read pattern
/// emphasis: a coach lever that is "mostly inert under a fixed rotation" (the Training Days PRD). The
/// field still exists, is still written through the coach's bounded write path and still decodes, so
/// what this suite pins is that holding any emphasis - neutral, a coach-sized nudge, or a wildly
/// out-of-range value - never changes the session the engine assembles.
///
/// Coverage:
///   (a) an explicit neutral emphasis assembles byte-for-byte identically to `SessionPolicy.default`;
///   (b) a push-high / squat-low emphasis assembles the same session as neutral on every Training Day,
///       length and fitness level - it reorders nothing;
///   (c) an out-of-range emphasis (huge, negative, zero) is equally inert and the session stays well formed.
final class PatternEmphasisPolicyTests: XCTestCase {

    private let lengths = [5, 10, 15, 20, 30, 45, 60]

    private var library: [Exercise] = []

    override func setUp() async throws {
        library = try await MockExerciseService().exercises()
    }

    private func policy(emphasis: [MovementPattern: Double]) -> SessionPolicy {
        var policy = SessionPolicy.default
        for (pattern, value) in emphasis {
            policy.patternEmphasis[pattern] = value
        }
        return policy
    }

    /// A real history: each group trained once at the bottom of its range, so the session reads Earned
    /// Reps, ladder staleness and bookend variety rather than a fresh-start default.
    private var history: [WorkoutLog] {
        [
            TrainingDayFixtures.trainingLog(.push, completedAt: TrainingDayFixtures.date(daysAgo: 5)),
            TrainingDayFixtures.trainingLog(.pull, completedAt: TrainingDayFixtures.date(daysAgo: 4)),
            TrainingDayFixtures.trainingLog(.legs, completedAt: TrainingDayFixtures.date(daysAgo: 3)),
        ]
    }

    private func assemble(minutes: Int, level: FitnessLevel, day: TrainingDay, policy: SessionPolicy) -> Workout {
        SessionAssembly.assemble(
            requestedMinutes: minutes,
            user: TrainingDayFixtures.user(level: level),
            library: library,
            recentLogs: history,
            sessionPolicy: policy,
            trainingDay: day,
            asOf: TrainingDayFixtures.asOf,
            calendar: TrainingDayFixtures.calendar
        )
    }

    /// Everything about a workout except its fresh ids: block order, and each station's movement, role,
    /// sets, served number, Earned Reps and rest, plus each block's pause.
    private func signature(_ workout: Workout) -> [String] {
        workout.blocks.map { block in
            let items = block.exercises.map { item in
                "\(item.exercise.id):\(item.role.map { "\($0)" } ?? "-"):\(item.sets)x\(item.reps ?? item.durationSeconds ?? 0)"
                    + "e\((item.earnedReps ?? item.earnedDurationSeconds).map(String.init) ?? "-")r\(item.restSeconds)"
            }.joined(separator: ",")
            return "\(block.category.rawValue)p\(block.transitionSeconds ?? 0)[\(items)]"
        }
    }

    private func assertInert(_ emphasis: [MovementPattern: Double], _ name: String) {
        for level in FitnessLevel.allCases {
            for day in TrainingDay.rotation {
                for minutes in lengths {
                    let label = "\(name) \(level) \(day) \(minutes) min"
                    let neutral = assemble(minutes: minutes, level: level, day: day, policy: .default)
                    let emphasized = assemble(minutes: minutes, level: level, day: day, policy: policy(emphasis: emphasis))
                    XCTAssertEqual(signature(emphasized), signature(neutral), "\(label): emphasis changed the session")
                    let circuit = emphasized.blocks.filter { $0.category == .strength }.flatMap(\.exercises)
                    XCTAssertFalse(circuit.isEmpty, "\(label): no circuit")
                    XCTAssertTrue(circuit.allSatisfy { $0.sets == RepGrammar.setsPerStation }, label)
                }
            }
        }
    }

    // MARK: - (a) Neutral is a byte-for-byte no-op

    func testNeutralEmphasisMatchesDefaultPolicyByteForByte() {
        assertInert(SessionPolicy.neutralPatternEmphasis, "neutral")
    }

    // MARK: - (b) A coach-sized emphasis reorders nothing

    /// The strongest in-range nudge a coach can write - push at the top rail, squat at the bottom - leaves
    /// every session exactly as neutral builds it: the Rotation picked the day and the day's ladders are
    /// fixed, so there is no pattern order left for emphasis to move.
    func testInRangeEmphasisLeavesEverySessionUnchanged() {
        assertInert([.push: SessionPolicy.maxEmphasis, .squat: SessionPolicy.minEmphasis], "push-high squat-low")
        assertInert([.hinge: SessionPolicy.maxEmphasis, .pull: SessionPolicy.minEmphasis], "hinge-high pull-low")
    }

    // MARK: - (c) Out-of-range emphasis is equally inert

    func testOutOfRangeEmphasisLeavesEverySessionUnchangedAndWellFormed() {
        assertInert([.push: 1_000_000, .squat: -5, .hinge: 0], "wild")
    }
}
