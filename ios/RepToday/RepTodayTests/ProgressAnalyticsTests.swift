import XCTest
@testable import RepToday

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

    // MARK: - Progression map (US-SP05)

    private func ladder(_ logs: [WorkoutLog], phase: Phase = .discipline, _ pattern: MovementPattern) -> PatternLadder? {
        analytics(logs, phase: phase).progressionMap.ladders.first { $0.pattern == pattern }
    }

    /// The push ladder for a user worked to a mid-chain tier: the full chain is shown entry-first, the
    /// frontier is the current rung, lower rungs are cleared, higher rungs ahead, and the Strength
    /// summit is locked with the "earn the Strength Phase" affordance in its state note - previewable,
    /// never omitted. Mirrors the PRD Validation Test (at a mid tier, harder tiers ahead, gated skill
    /// locked). No rung carries a start/select handle - the type has no such field.
    func testPushLadderMarksFrontierClearedAheadAndLockedSummit() {
        let logs = [log(weeksAgo: 0, [logged("push_c", .strength, .push, reps: [15])])]
        let push = ladder(logs, .push)

        XCTAssertNotNil(push)
        XCTAssertTrue(push!.hasStarted)
        // Entry-first through the summit: all four tiers of the active chain, in order.
        XCTAssertEqual(push!.rungs.map(\.exerciseId), ["push_a", "push_b", "push_c", "push_d"])

        let byId = Dictionary(uniqueKeysWithValues: push!.rungs.map { ($0.exerciseId, $0) })
        XCTAssertEqual(byId["push_a"]?.state, .cleared)
        XCTAssertEqual(byId["push_b"]?.state, .cleared)
        XCTAssertEqual(byId["push_c"]?.state, .current)
        XCTAssertEqual(byId["push_d"]?.state, .ahead)
        XCTAssertEqual(push!.currentRung?.exerciseId, "push_c")

        // The Strength summit is a locked strength skill for a Discipline user; the discipline rungs
        // are never locked.
        XCTAssertTrue(byId["push_d"]!.isStrengthSkill)
        XCTAssertTrue(byId["push_d"]!.isLocked)
        XCTAssertFalse(byId["push_c"]!.isLocked)
        XCTAssertFalse(byId["push_a"]!.isLocked)
    }

    /// The locked marking is the engine's own phase gate, not a parallel re-derivation: the same summit
    /// that is locked for a Discipline user is unlocked for a user who has earned the Strength Phase,
    /// exactly as `ExercisePoolFilter.isPhaseAllowed` would decide.
    func testLockedRungAgreesWithPhaseGate() {
        let logs = [log(weeksAgo: 0, [logged("push_c", .strength, .push, reps: [15])])]

        let disciplineSummit = ladder(logs, phase: .discipline, .push)?.rungs.first { $0.exerciseId == "push_d" }
        XCTAssertEqual(disciplineSummit?.isLocked, true)

        let strengthSummit = ladder(logs, phase: .strength, .push)?.rungs.first { $0.exerciseId == "push_d" }
        XCTAssertEqual(strengthSummit?.isLocked, false)          // earned - no longer locked
        XCTAssertEqual(strengthSummit?.isStrengthSkill, true)    // still a strength skill

        // Independently confirm the map's `isLocked` matches the gate for every rung.
        for phase in [Phase.discipline, .strength] {
            for rung in ladder(logs, phase: phase, .push)!.rungs {
                let exercise = library.first { $0.id == rung.exerciseId }!
                XCTAssertEqual(rung.isLocked, !ExercisePoolFilter.isPhaseAllowed(exercise, phase: phase),
                               "rung \(rung.exerciseId) at phase \(phase) disagreed with the gate")
            }
        }
    }

    /// A pattern the user has never trained still previews its ladder (nothing cleared, no current
    /// marker) and defaults to the pattern's canonical strength chain so the locked summit is visible
    /// from day one - the strength journey is visible before it is started.
    func testUntrainedPatternPreviewsCanonicalLadderWithNoCurrentMarker() {
        let core = ladder([], .core)   // no logs at all

        XCTAssertNotNil(core)
        XCTAssertFalse(core!.hasStarted)
        XCTAssertNil(core!.currentRung)
        // The only core chain in the fixture carries the strength summit; every rung is ahead.
        XCTAssertEqual(core!.rungs.map(\.exerciseId), ["plank_a", "plank_b"])
        XCTAssertTrue(core!.rungs.allSatisfy { $0.state == .ahead })
        XCTAssertEqual(core!.rungs.first { $0.exerciseId == "plank_b" }?.isLocked, true)
    }

    /// One ladder per foundational pattern, in `PhaseEvaluator.foundationalPatterns` order, even when
    /// the catalog has no chain for a pattern (that ladder is simply empty rather than missing).
    func testProgressionMapHasOneLadderPerFoundationInOrder() {
        let map = analytics([]).progressionMap
        XCTAssertEqual(map.ladders.map(\.pattern), [.push, .squat, .hinge, .core])
        // The fixture has no hinge chain, so its ladder is present but empty.
        XCTAssertEqual(map.ladders.first { $0.pattern == .hinge }?.rungs.isEmpty, true)
    }

    /// The map's current-position marking reuses the chain-position frontier - the two surfaces can
    /// never disagree about where the user stands.
    func testMapCurrentRungMatchesChainPositionFrontier() {
        let logs = [
            log(weeksAgo: 1, [logged("push_c", .strength, .push, reps: [10])]),
            log(weeksAgo: 0, [logged("push_a", .strength, .push, reps: [20])]),
        ]
        let result = analytics(logs)
        let frontierId = result.chainPositions.first { $0.pattern == .push }?.currentExercise?.id
        let currentRungId = result.progressionMap.ladders.first { $0.pattern == .push }?.currentRung?.exerciseId
        XCTAssertEqual(currentRungId, frontierId)
        XCTAssertEqual(currentRungId, "push_c")
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

    // MARK: - Strength journey (premium, US-AN01)

    /// The tier-advancement timeline is read from real history: each reached tier stamped with the
    /// earliest date it was performed, entry-first, with the dated span between first and current.
    func testStrengthJourneyTimelineDatesAndDuration() {
        let logs = [
            // Wall reached 6 weeks ago, knee 3 weeks ago, standard this week - a real climb.
            log(weeksAgo: 6, [logged("push_a", .strength, .push, reps: [15])]),
            log(weeksAgo: 3, [logged("push_b", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, [logged("push_c", .strength, .push, reps: [10])]),
        ]
        let push = analytics(logs).deep.strengthJourney.chains.first { $0.pattern == .push }

        XCTAssertNotNil(push)
        XCTAssertEqual(push?.milestones.map(\.exerciseId), ["push_a", "push_b", "push_c"])
        XCTAssertEqual(push?.milestones.map(\.tier), [1, 2, 3])
        XCTAssertEqual(push?.startMilestone?.displayName, "Wall Push-up")
        XCTAssertEqual(push?.currentMilestone?.displayName, "Standard Push-up")
        XCTAssertEqual(push?.hasAdvanced, true)
        // First reached at week 6, current at week 0 -> a six-week climb.
        XCTAssertEqual(push?.weeksClimbed, 6)
        XCTAssertEqual(push?.startMilestone?.firstReachedAt, date(weeksAgo: 6))
        XCTAssertEqual(push?.currentMilestone?.firstReachedAt, date(weeksAgo: 0))
    }

    /// `firstReachedAt` is the *earliest* logged instance of a tier, not the most recent - re-doing a
    /// tier later never moves its milestone date forward.
    func testStrengthJourneyUsesEarliestReachedDate() {
        let logs = [
            log(weeksAgo: 4, [logged("push_a", .strength, .push, reps: [15])]),
            log(weeksAgo: 1, [logged("push_a", .strength, .push, reps: [18])]), // same tier, later
            log(weeksAgo: 0, [logged("push_b", .strength, .push, reps: [12])]),
        ]
        let push = analytics(logs).deep.strengthJourney.chains.first { $0.pattern == .push }

        XCTAssertEqual(push?.startMilestone?.exerciseId, "push_a")
        XCTAssertEqual(push?.startMilestone?.firstReachedAt, date(weeksAgo: 4))
    }

    /// A locked Strength tier is never reported as reached, even if it somehow appears in the logs -
    /// the journey only counts reachable tiers, matching the chain-position/progression-map rule.
    func testStrengthJourneyNeverReportsLockedTierAsReached() {
        // push_d is a Strength-gated tier; a Discipline user's journey must exclude it.
        let logs = [
            log(weeksAgo: 2, [logged("push_c", .strength, .push, reps: [12])]),
            log(weeksAgo: 0, [logged("push_d", .strength, .push, reps: [5])]),
        ]
        let disciplineJourney = analytics(logs, phase: .discipline).deep.strengthJourney.chains.first { $0.pattern == .push }
        XCTAssertNotNil(disciplineJourney)
        XCTAssertFalse(disciplineJourney!.milestones.contains { $0.exerciseId == "push_d" },
                       "a locked Strength tier must never appear as a reached milestone")
        XCTAssertEqual(disciplineJourney?.currentMilestone?.exerciseId, "push_c")

        // A Strength-phase user, for whom that tier is unlocked, does reach it.
        let strengthJourney = analytics(logs, phase: .strength).deep.strengthJourney.chains.first { $0.pattern == .push }
        XCTAssertTrue(strengthJourney!.milestones.contains { $0.exerciseId == "push_d" })
    }

    /// A single worked tier is a valid journey (current position) but is not an "advancement".
    func testStrengthJourneySingleTierHasNotAdvanced() {
        let logs = [log(weeksAgo: 0, [logged("squat_a", .strength, .squat, reps: [15])])]
        let squat = analytics(logs).deep.strengthJourney.chains.first { $0.pattern == .squat }

        XCTAssertEqual(squat?.milestones.count, 1)
        XCTAssertEqual(squat?.hasAdvanced, false)
        XCTAssertNil(squat?.weeksClimbed)
    }

    /// The journey reuses the same active chain the chain-position surface derives - the frontier's
    /// chain - so the two can never disagree, and untrained patterns contribute no journey.
    func testStrengthJourneyMatchesActiveChainAndOmitsUntrained() {
        let logs = [
            log(weeksAgo: 1, [logged("push_a", .strength, .push, reps: [15])]),
            log(weeksAgo: 0, [logged("push_c", .strength, .push, reps: [10])]),
        ]
        let result = analytics(logs)
        let pushPosition = result.chainPositions.first { $0.pattern == .push }
        let pushJourney = result.deep.strengthJourney.chains.first { $0.pattern == .push }

        XCTAssertEqual(pushJourney?.chainId, pushPosition?.currentExercise?.progressionChainId)
        XCTAssertEqual(pushJourney?.currentMilestone?.exerciseId, pushPosition?.currentExercise?.id)
        // Only push was trained: no journey for squat/hinge/core.
        XCTAssertEqual(result.deep.strengthJourney.chains.map(\.pattern), [.push])
    }

    /// Skipped or set-less instances never fabricate a milestone.
    func testStrengthJourneyExcludesSkippedAndSetless() {
        let logs = [
            log(weeksAgo: 1, [logged("push_a", .strength, .push, reps: [15])]),
            log(weeksAgo: 0, [logged("push_c", .strength, .push, skipped: true)]), // skipped
            log(weeksAgo: 0, [logged("push_b", .strength, .push)]),                // no sets
        ]
        let push = analytics(logs).deep.strengthJourney.chains.first { $0.pattern == .push }

        XCTAssertEqual(push?.milestones.map(\.exerciseId), ["push_a"])
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
        XCTAssertTrue(result.deep.strengthJourney.isEmpty)
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
