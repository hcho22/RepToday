import XCTest
@testable import FitSnack

/// Tests the Progress tab's legibility layer (US-M02): pillar balance, chain position, personal
/// bests, and the premium-gated deep analytics.
///
/// Like the other engine/consistency logic, `ProgressAnalytics` is a pure, deterministic function of
/// `(logs, library, asOf, calendar)`. These tests drive it over a small synthetic library so chains,
/// hold-vs-rep, and orders are fully controlled, and assert every surface is counted the way
/// `SessionSummary` counts coverage - only non-skipped exercises with a recorded set.
final class ProgressAnalyticsTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed Gregorian/UTC calendar with a Sunday week start, matching `ConsistencyScoreTests` so week
    /// bucketing is deterministic.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: asOf)!
    }

    /// A push chain whose three discipline tiers top out under a strength-gated fourth tier, a
    /// single-tier squat, a two-tier core hold chain whose top tier is strength-gated, a single
    /// mobility hold, and a two-tier primal chain. Enough to exercise every surface, including the
    /// phase-reachability of chain position.
    private var library: [Exercise] {
        [
            Self.ex("push_a", .discipline, .push, chain: "pushc", order: 0, prog: "push_b", name: "Wall Push-up"),
            Self.ex("push_b", .discipline, .push, chain: "pushc", order: 1, prog: "push_c", name: "Knee Push-up"),
            Self.ex("push_c", .discipline, .push, chain: "pushc", order: 2, prog: "push_d", name: "Standard Push-up"),
            Self.ex("push_d", .strength, .push, chain: "pushc", order: 3, prog: nil, name: "One-Arm Push-up"),
            Self.ex("squat_a", .discipline, .squat, chain: "squatc", order: 0, prog: nil, name: "Bodyweight Squat"),
            Self.ex("plank_a", .discipline, .core, chain: "corec", order: 0, prog: "plank_b", isHold: true, name: "Forearm Plank"),
            Self.ex("plank_b", .strength, .core, chain: "corec", order: 1, prog: nil, isHold: true, name: "L-Sit"),
            Self.ex("mob_a", .discipline, .mobility, chain: "mobc", order: 0, prog: nil, isHold: true, name: "Cat-Cow"),
            Self.ex("prim_a", .discipline, .locomotion, chain: "primc", order: 0, prog: "prim_b", name: "Bear Crawl"),
            Self.ex("prim_b", .discipline, .locomotion, chain: "primc", order: 1, prog: nil, name: "Crab Walk"),
        ]
    }

    private static func ex(
        _ id: String, _ phase: Phase, _ pattern: MovementPattern,
        chain: String, order: Int, prog: String?, isHold: Bool = false,
        difficulty: Int = 2, name: String
    ) -> Exercise {
        let pillar: Pillar = pattern == .mobility ? .mobility : (pattern == .locomotion ? .primal : .strength)
        return Exercise(
            id: id, displayName: name, pillar: pillar, movementPattern: pattern,
            category: pillar == .mobility ? .mobility : .strength,
            difficulty: difficulty, phase: phase, equipment: [], isHold: isHold,
            defaultReps: isHold ? nil : 10, defaultDurationSeconds: isHold ? 30 : nil,
            estimatedTimePerSetSeconds: 40, metValue: 4,
            progressionChainId: chain, progressionOrder: order,
            regressionId: nil, progressionId: prog, advancementCriteria: "3x12", apartmentFriendly: true
        )
    }

    private func logged(_ id: String, _ pillar: Pillar, _ pattern: MovementPattern, reps: [Int] = [], holds: [Int] = [], skipped: Bool = false) -> LoggedExercise {
        let sets = reps.map { CompletedSet(reps: $0, durationSeconds: nil) }
            + holds.map { CompletedSet(reps: nil, durationSeconds: $0) }
        return LoggedExercise(id: UUID(), exerciseId: id, pillar: pillar, movementPattern: pattern, completedSets: sets, skipped: skipped)
    }

    private func log(weeksAgo: Int, dayOffset: Int = 0, minutes: Int = 12, rating: PerceivedDifficulty? = nil, _ exercises: [LoggedExercise]) -> WorkoutLog {
        WorkoutLog(
            id: UUID(), workoutId: UUID(), completedAt: date(weeksAgo: weeksAgo, dayOffset: dayOffset),
            requestedMinutes: 15, durationMinutes: minutes, wasReturn: false,
            shape: .singleFocus, focusPillar: nil, perceivedDifficulty: rating, exercises: exercises
        )
    }

    private func analytics(_ logs: [WorkoutLog], phase: Phase = .discipline) -> ProgressAnalytics {
        ProgressAnalytics.from(logs: logs, library: library, phase: phase, asOf: asOf, calendar: calendar)
    }

    // MARK: - Pillar balance

    /// The three pillars split by worked-exercise count; the shares sum to 1.
    func testPillarBalanceSplitsByWorkedExercises() {
        let logs = [
            log(weeksAgo: 0, [logged("push_b", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, dayOffset: 1, [logged("mob_a", .mobility, .mobility, holds: [30])]),
            log(weeksAgo: 0, dayOffset: 2, [logged("prim_a", .primal, .locomotion, reps: [8])]),
        ]
        let balance = analytics(logs).pillarBalance

        XCTAssertEqual(balance.count, 3)
        for pillar in [Pillar.strength, .mobility, .primal] {
            XCTAssertEqual(balance.first { $0.pillar == pillar }?.fraction ?? 0, 1.0 / 3.0, accuracy: 0.0001)
            XCTAssertEqual(balance.first { $0.pillar == pillar }?.exerciseCount, 1)
        }
        XCTAssertEqual(balance.map(\.fraction).reduce(0, +), 1.0, accuracy: 0.0001)
    }

    /// A skipped exercise and one with no recorded set never count toward balance (no over-claiming).
    func testPillarBalanceExcludesSkippedAndSetless() {
        let logs = [
            log(weeksAgo: 0, [
                logged("push_b", .strength, .push, reps: [12]),
                logged("squat_a", .strength, .squat, reps: [10], skipped: true),
                logged("mob_a", .mobility, .mobility), // no recorded set
            ])
        ]
        let balance = analytics(logs).pillarBalance

        XCTAssertEqual(balance.first { $0.pillar == .strength }?.fraction ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(balance.first { $0.pillar == .mobility }?.exerciseCount, 0)
    }

    // MARK: - Chain position

    /// A worked mid-chain tier reports its frontier position and that a harder tier is in reach; an
    /// untrained foundation reports "not started".
    func testChainPositionFrontierAndNextTier() {
        let logs = [log(weeksAgo: 0, [logged("push_b", .strength, .push, reps: [12])])]
        let positions = analytics(logs).chainPositions

        let push = positions.first { $0.pattern == .push }
        XCTAssertEqual(push?.currentExercise?.id, "push_b")
        XCTAssertEqual(push?.tier, 2)          // progressionOrder 1 -> tier 2
        XCTAssertEqual(push?.chainLength, 3)
        XCTAssertEqual(push?.hasNextTier, true) // push_c exists above

        let hinge = positions.first { $0.pattern == .hinge }
        XCTAssertEqual(hinge?.hasStarted, false)
    }

    /// A single-tier foundation at the top of its chain reports no next tier.
    func testChainPositionSingleTierHasNoNextTier() {
        let logs = [log(weeksAgo: 0, [logged("squat_a", .strength, .squat, reps: [15])])]
        let squat = analytics(logs).chainPositions.first { $0.pattern == .squat }

        XCTAssertEqual(squat?.currentExercise?.id, "squat_a")
        XCTAssertEqual(squat?.tier, 1)
        XCTAssertEqual(squat?.chainLength, 1)
        XCTAssertEqual(squat?.hasNextTier, false)
    }

    /// The frontier is the highest-order worked tier in the active chain, even if a lower tier was
    /// worked more recently.
    func testChainPositionFrontierIsHighestOrderWorked() {
        let logs = [
            log(weeksAgo: 1, [logged("push_c", .strength, .push, reps: [10])]),
            log(weeksAgo: 0, [logged("push_a", .strength, .push, reps: [20])]),
        ]
        let push = analytics(logs).chainPositions.first { $0.pattern == .push }

        XCTAssertEqual(push?.currentExercise?.id, "push_c")
        XCTAssertEqual(push?.tier, 3)
        XCTAssertEqual(push?.hasNextTier, false)
    }

    /// A Discipline user sitting at the top *discipline* tier of a chain that continues into a locked
    /// Strength tier never over-claims: the length counts only reachable tiers and no next tier is "in
    /// reach". A Strength user on the same history sees the extra tier counted and reachable.
    func testChainPositionIsPhaseAware() {
        let logs = [log(weeksAgo: 0, [logged("push_c", .strength, .push, reps: [15])])]

        let disciplinePush = analytics(logs, phase: .discipline).chainPositions.first { $0.pattern == .push }
        XCTAssertEqual(disciplinePush?.currentExercise?.id, "push_c")
        XCTAssertEqual(disciplinePush?.tier, 3)          // frontier at the top of the 3 discipline tiers
        XCTAssertEqual(disciplinePush?.chainLength, 3)   // push_d (strength) is not counted
        XCTAssertEqual(disciplinePush?.hasNextTier, false) // the only tier above is still locked

        let strengthPush = analytics(logs, phase: .strength).chainPositions.first { $0.pattern == .push }
        XCTAssertEqual(strengthPush?.tier, 3)
        XCTAssertEqual(strengthPush?.chainLength, 4)     // push_d now reachable and counted
        XCTAssertEqual(strengthPush?.hasNextTier, true)  // one-arm push-up is in reach
    }

    // MARK: - Personal bests

    func testPersonalBests() {
        let logs = [
            log(weeksAgo: 0, dayOffset: 0, minutes: 12, [logged("push_b", .strength, .push, reps: [12, 15])]),
            log(weeksAgo: 0, dayOffset: 1, minutes: 25, [logged("push_a", .strength, .push, reps: [20])]),
            log(weeksAgo: 0, dayOffset: 2, minutes: 10, [logged("plank_a", .strength, .core, holds: [30, 45])]),
            log(weeksAgo: 1, dayOffset: 0, minutes: 8, [logged("push_b", .strength, .push, reps: [10])]),
        ]
        let bests = analytics(logs).personalBests

        XCTAssertEqual(bests.totalSessions, 4)
        XCTAssertEqual(bests.longestSessionMinutes, 25)
        XCTAssertEqual(bests.mostSessionsInAWeek, 3) // three sessions in the current week
        XCTAssertEqual(bests.totalMinutesMoved, 12 + 25 + 10 + 8)
        XCTAssertEqual(bests.bestReps?.value, 20)
        XCTAssertEqual(bests.bestReps?.displayName, "Wall Push-up")
        XCTAssertEqual(bests.bestHold?.value, 45)
        XCTAssertEqual(bests.bestHold?.displayName, "Forearm Plank")
    }

    /// With no rep or hold history the named bests are nil rather than zero.
    func testPersonalBestsNilWithoutTypedHistory() {
        let bests = analytics([]).personalBests
        XCTAssertNil(bests.bestReps)
        XCTAssertNil(bests.bestHold)
        XCTAssertEqual(bests.totalSessions, 0)
    }

    // MARK: - Deep analytics (premium)

    /// Pattern balance is finer than pillar balance and omits patterns with no history.
    func testDeepPatternBalanceOmitsUntrainedPatterns() {
        let logs = [
            log(weeksAgo: 0, [
                logged("push_b", .strength, .push, reps: [12]),
                logged("mob_a", .mobility, .mobility, holds: [30]),
            ])
        ]
        let patterns = analytics(logs).deep.patternBalance.map(\.pattern)

        XCTAssertEqual(Set(patterns), [.push, .mobility])
        XCTAssertFalse(patterns.contains(.squat))
    }

    /// Weekly volume sums completed sets per week, oldest first.
    func testDeepWeeklyVolume() {
        let logs = [
            log(weeksAgo: 1, [logged("push_b", .strength, .push, reps: [10])]),          // 1 set
            log(weeksAgo: 0, [logged("push_b", .strength, .push, reps: [12, 15])]),      // 2 sets
        ]
        let volume = analytics(logs).deep.weeklyVolume

        XCTAssertEqual(volume.count, 2)
        XCTAssertEqual(volume.first?.setsCompleted, 1) // oldest (a week ago)
        XCTAssertEqual(volume.last?.setsCompleted, 2)  // this week
        XCTAssertEqual(volume.last?.sessionCount, 1)
    }

    /// The difficulty mix counts each rating and ignores unrated sessions.
    func testDeepDifficultyMix() {
        let logs = [
            log(weeksAgo: 0, dayOffset: 0, rating: .tooEasy, [logged("push_b", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, dayOffset: 1, rating: .justRight, [logged("push_b", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, dayOffset: 2, rating: .justRight, [logged("push_b", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, dayOffset: 3, rating: nil, [logged("push_b", .strength, .push, reps: [12])]),
        ]
        let mix = analytics(logs).deep.difficultyMix

        XCTAssertEqual(mix.tooEasy, 1)
        XCTAssertEqual(mix.justRight, 2)
        XCTAssertEqual(mix.tooHard, 0)
        XCTAssertEqual(mix.ratedCount, 3)
    }

    // MARK: - Empty history

    func testEmptyHistoryYieldsEmptyAnalytics() {
        let result = analytics([])

        XCTAssertEqual(result.pillarBalance.count, 3)
        XCTAssertTrue(result.pillarBalance.allSatisfy { $0.exerciseCount == 0 && $0.fraction == 0 })
        XCTAssertEqual(result.chainPositions.count, ProgressAnalytics.foundationalPatterns.count)
        XCTAssertTrue(result.chainPositions.allSatisfy { !$0.hasStarted })
        XCTAssertTrue(result.deep.patternBalance.isEmpty)
        XCTAssertTrue(result.deep.weeklyVolume.isEmpty)
        XCTAssertEqual(result.deep.difficultyMix.ratedCount, 0)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let logs = [
            log(weeksAgo: 0, [logged("push_b", .strength, .push, reps: [12, 15])]),
            log(weeksAgo: 1, [logged("mob_a", .mobility, .mobility, holds: [30])]),
        ]
        XCTAssertEqual(analytics(logs), analytics(logs))
    }
}
