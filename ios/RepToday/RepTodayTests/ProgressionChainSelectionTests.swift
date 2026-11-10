import XCTest
@testable import RepToday

/// Tests pipeline Step 5 of the deterministic engine (US-C05): picking the right progression-chain
/// exercise for the user's demonstrated ability.
///
/// Two halves: the `selectInChain` tests pin the per-chain position logic (entry with no history,
/// frontier = highest-order tier worked toward progression, advance only when the rung is cleared under
/// the rep grammar - four sets at the top of the user's range, at earned reps (US-TD03) - never past an
/// ineligible/gated next tier, step down at the bottom of the range, clamp when the frontier itself is
/// ineligible); the `select(pattern:)` tests pin per-pattern integration (the no-repeat variety rule,
/// the active-chain preference, the no-history default) and run the PRD's own validation case over the
/// real bundled library.
final class ProgressionChainSelectionTests: XCTestCase {

    // MARK: - Fixtures

    /// The level most fixtures run at: a beginner's reps range is 15-30, per side 5-15, holds 20-60s.
    private let level = FitnessLevel.beginner

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

    /// Builds a fully-linked chain from `(id, difficulty)` tiers: `progressionOrder` follows the array,
    /// and `regressionId`/`progressionId` wire neighbors together.
    private func makeChain(
        _ chainId: String,
        _ tiers: [(id: String, difficulty: Int)],
        pattern: MovementPattern = .push,
        isHold: Bool = false,
        isPerSide: Bool = false
    ) -> [Exercise] {
        tiers.enumerated().map { index, tier in
            Exercise(
                id: tier.id,
                displayName: tier.id,
                pillar: .strength,
                movementPattern: pattern,
                category: .strength,
                difficulty: tier.difficulty,
                phase: .discipline,
                equipment: [],
                isHold: isHold,
                defaultReps: isHold ? nil : 10,
                defaultDurationSeconds: isHold ? 20 : nil,
                isPerSide: isPerSide ? true : nil,
                estimatedTimePerSetSeconds: 40,
                metValue: 4,
                progressionChainId: chainId,
                progressionOrder: index,
                regressionId: index > 0 ? tiers[index - 1].id : nil,
                progressionId: index < tiers.count - 1 ? tiers[index + 1].id : nil,
                advancementCriteria: "4 clean sets at the top of your rep range",
                apartmentFriendly: true
            )
        }
    }

    /// One logged station: per-set `values` (reps, or seconds for a hold), the Earned Reps it was
    /// prescribed at (the smallest set when not given - a station records prescribed = performed), and
    /// its role.
    private func station(
        id: String,
        values: [Int],
        earned: Int? = nil,
        pattern: MovementPattern = .push,
        isHold: Bool = false,
        role: StationRole = .main,
        skipped: Bool = false
    ) -> LoggedExercise {
        let earned = skipped ? nil : (earned ?? values.min())
        return LoggedExercise(
            id: UUID(),
            exerciseId: id,
            pillar: .strength,
            movementPattern: pattern,
            completedSets: skipped ? [] : values.map { isHold ? CompletedSet(reps: nil, durationSeconds: $0) : CompletedSet(reps: $0, durationSeconds: nil) },
            skipped: skipped,
            role: role,
            earnedReps: isHold ? nil : earned,
            earnedDurationSeconds: isHold ? earned : nil
        )
    }

    private func log(daysAgo: Int, _ stations: [LoggedExercise], difficulty: PerceivedDifficulty? = .justRight) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 30,
            durationMinutes: 30,
            shape: .blend,
            focusPillar: .strength,
            perceivedDifficulty: difficulty,
            exercises: stations
        )
    }

    /// A session `daysAgo` that worked `id` at the given per-set `reps` (rep-based movement).
    private func repsLog(
        id: String,
        reps: [Int],
        earned: Int? = nil,
        pattern: MovementPattern = .push,
        daysAgo: Int,
        skipped: Bool = false,
        difficulty: PerceivedDifficulty? = .justRight
    ) -> WorkoutLog {
        log(daysAgo: daysAgo, [station(id: id, values: reps, earned: earned, pattern: pattern, skipped: skipped)], difficulty: difficulty)
    }

    /// A session that clears `id` for a beginner: four sets of 30, the top of the range, at earned 30.
    private func clearingLog(id: String, daysAgo: Int) -> WorkoutLog {
        repsLog(id: id, reps: [30, 30, 30, 30], daysAgo: daysAgo)
    }

    /// Four sets of 15 at earned 15: worked at the bottom of a beginner's range, nowhere near clearing.
    private func bottomLog(id: String, daysAgo: Int, difficulty: PerceivedDifficulty? = .justRight) -> WorkoutLog {
        repsLog(id: id, reps: [15, 15, 15, 15], daysAgo: daysAgo, difficulty: difficulty)
    }

    private func selectInChain(
        _ chain: [Exercise],
        eligible: Set<String>? = nil,
        logs: [WorkoutLog],
        level: FitnessLevel = .beginner
    ) -> ChainSelection? {
        ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: eligible ?? Set(chain.map(\.id)),
            recentLogs: logs,
            level: level
        )
    }

    private func threeTierChain() -> [Exercise] {
        makeChain("c", [(id: "c0", difficulty: 1), (id: "c1", difficulty: 2), (id: "c2", difficulty: 3)])
    }

    // MARK: - selectInChain: position

    func testNoHistoryStartsAtChainEntry() {
        let selection = selectInChain(threeTierChain(), logs: [])
        XCTAssertEqual(selection?.exercise.id, "c0")
        XCTAssertEqual(selection?.order, 0)
        XCTAssertEqual(selection?.didAdvance, false)
    }

    /// A chain the user has never worked is entered at the gentlest tier the Start Seed band did not
    /// withhold - not at the chain's entry tier. A withheld tier was never on offer, so skipping past
    /// it is not skipping ahead.
    func testNoHistoryChainSkipsPastTiersTheStartSeedWithheld() {
        let chain = threeTierChain()
        let selection = ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: Set(chain.map(\.id)),
            recentLogs: [],
            level: level,
            withheldByStartSeed: ["c0"]
        )
        XCTAssertEqual(selection?.exercise.id, "c1", "entered past the withheld c0")
        XCTAssertEqual(selection?.didAdvance, false, "a lateral entry is not an advancement")
    }

    /// When every eligible tier was withheld, the entry is the chain's *gentlest* eligible tier,
    /// never its hardest. Reaching for the top of what survived would invert the very restriction
    /// that narrowed the pool (a Return cap, an injury filter) in the first place.
    func testNoHistoryChainWithEveryTierWithheldEntersAtItsGentlestTier() {
        let chain = makeChain("c", [(id: "c0", difficulty: 1), (id: "c1", difficulty: 2)])
        let selection = ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: Set(chain.map(\.id)),
            recentLogs: [],
            level: level,
            withheldByStartSeed: ["c0", "c1"]
        )
        XCTAssertEqual(selection?.exercise.id, "c0")
    }

    /// The default keeps the plain chain-local behavior: nothing withheld means the chain entry.
    func testNothingWithheldDefaultsToTheChainEntry() {
        let chain = makeChain("c", [(id: "c0", difficulty: 1), (id: "c1", difficulty: 3)])
        XCTAssertEqual(selectInChain(chain, logs: []).map(\.exercise.id), "c0")
    }

    /// A rung clears only with four sets at the top of the range: three sets at the top, or four sets a
    /// step short of it, keep the user on the rung.
    func testStaysAtFrontierWhenTheRungIsNotCleared() {
        for reps in [[30, 30, 30], [25, 25, 25, 25]] {
            let selection = selectInChain(threeTierChain(), logs: [repsLog(id: "c1", reps: reps, daysAgo: 1)])
            XCTAssertEqual(selection?.exercise.id, "c1", "\(reps) does not clear c1")
            XCTAssertEqual(selection?.didAdvance, false)
        }
    }

    func testAdvancesToNextTierWhenFourSetsReachTheTopOfTheRange() {
        let selection = selectInChain(threeTierChain(), logs: [clearingLog(id: "c1", daysAgo: 1)])
        XCTAssertEqual(selection?.exercise.id, "c2")
        XCTAssertEqual(selection?.order, 2)
        XCTAssertEqual(selection?.didAdvance, true)
    }

    /// Padding fills a long session up to the top of the range, but a rung clears only when the
    /// station's Earned Reps had reached the top too: four padded sets of 30 at earned 25 hold the rung.
    func testPaddedSetsAtTheTopDoNotClearTheRung() {
        let padded = repsLog(id: "c1", reps: [30, 30, 30, 30], earned: 25, daysAgo: 1)
        XCTAssertEqual(selectInChain(threeTierChain(), logs: [padded])?.exercise.id, "c1")
    }

    /// The top of the range is the user's level's: 30 reps clears a beginner's or an intermediate's
    /// rung, while an advanced user's range runs to 50.
    func testTheTopOfTheRangeIsTheUsersLevels() {
        let atThirty = [clearingLog(id: "c1", daysAgo: 1)]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: atThirty, level: .beginner)?.exercise.id, "c2")
        XCTAssertEqual(selectInChain(threeTierChain(), logs: atThirty, level: .intermediate)?.exercise.id, "c2")
        XCTAssertEqual(selectInChain(threeTierChain(), logs: atThirty, level: .advanced)?.exercise.id, "c1")

        let atFifty = [repsLog(id: "c1", reps: [50, 50, 50, 50], daysAgo: 1)]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: atFifty, level: .advanced)?.exercise.id, "c2")
    }

    func testAdvancesOnlyOneTierEvenWhenAnEarlierTierWasCleared() {
        // Cleared the entry c0 -> offered exactly c1, never leaping to c2.
        XCTAssertEqual(selectInChain(threeTierChain(), logs: [clearingLog(id: "c0", daysAgo: 1)])?.exercise.id, "c1")
    }

    // MARK: - Step down at the bottom of the range (ADR-0011, ADR-0013)

    func testTooHardAtTheBottomOfTheRangeStepsOneRungDownTheChain() {
        let logs = [
            bottomLog(id: "c2", daysAgo: 1, difficulty: .tooHard),
            clearingLog(id: "c1", daysAgo: 5),
        ]
        let selection = selectInChain(threeTierChain(), logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c1", "already at the bottom, too hard serves the rung below")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testTooHardAboveTheBottomStaysOnTheRung() {
        let logs = [repsLog(id: "c2", reps: [20, 20, 20, 20], daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c2", "above the bottom it only takes a step off")
    }

    func testASkipAtTheBottomStepsDownToo() {
        let logs = [
            repsLog(id: "c2", reps: [], daysAgo: 1, skipped: true),
            bottomLog(id: "c2", daysAgo: 3),
            clearingLog(id: "c1", daysAgo: 6),
        ]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c1")
    }

    /// On the real catalog: an intermediate climbs push_standard 15, 20, 25, 30, clearing it at the top
    /// of the range and reaching push_diamond at 15, which they rate too hard. The step down serves
    /// push_standard at the bottom of the range, not at the 30 it last logged - that 30 would clear it
    /// again and send them straight back to diamond every other session. The user holds on standard and
    /// climbs back by the normal rules, one step a session, until a session at 30 clears it again.
    func testTheOldClearOfTheLowerRungDoesNotClimbStraightBack() async throws {
        let library = try await MockExerciseService().exercises()
        let level = FitnessLevel.intermediate
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let chain = library.filter { $0.progressionChainId == standard.progressionChainId }
        var logs = [15, 20, 25, 30].enumerated().map { index, reps in
            repsLog(id: "push_standard", reps: Array(repeating: reps, count: 4), daysAgo: 20 - index)
        }

        // What Step 5 serves and the prescription Step 6 serves it at, the way every caller sizes a station.
        func served() throws -> (id: String, target: OverloadTarget) {
            let selection = try XCTUnwrap(selectInChain(chain, logs: logs, level: level))
            let target = AdaptiveOverload.target(
                for: selection.exercise,
                level: level,
                recentLogs: logs,
                steppedDownSince: ProgressionChainSelection.stepDownDate(
                    onto: selection.exercise,
                    library: library,
                    recentLogs: logs,
                    level: level
                )
            )
            return (selection.exercise.id, target)
        }
        func record(_ session: (id: String, target: OverloadTarget), daysAgo: Int, _ difficulty: PerceivedDifficulty) {
            let reps = Array(repeating: session.target.value, count: session.target.sets)
            logs.append(repsLog(id: session.id, reps: reps, earned: session.target.earned, daysAgo: daysAgo, difficulty: difficulty))
        }

        let diamond = try served()
        XCTAssertEqual(diamond.id, "push_diamond")
        XCTAssertEqual(diamond.target.reps, 15, "a newly reached rung opens at the bottom of the range")
        record(diamond, daysAgo: 15, .tooHard)

        var trace: [(id: String, reps: Int)] = []
        for daysAgo in [14, 13, 12, 11] {
            let session = try served()
            trace.append((session.id, session.target.value))
            record(session, daysAgo: daysAgo, .justRight)
        }
        XCTAssertEqual(trace.map(\.id), Array(repeating: "push_standard", count: 4),
                       "the user holds on the easier rung instead of alternating")
        XCTAssertEqual(trace.map(\.reps), [15, 20, 25, 30], "served at the bottom, then the normal climb")
        XCTAssertEqual(try served().id, "push_diamond", "a later clear of the lower rung earns the way back")
    }

    func testClearingTheLowerRungAfterTheStepDownClimbsBack() {
        let logs = [
            clearingLog(id: "c1", daysAgo: 1),
            bottomLog(id: "c2", daysAgo: 3, difficulty: .tooHard),
            clearingLog(id: "c1", daysAgo: 7),
        ]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c2", "a later clear of the lower rung earns the way back")
    }

    func testWorkingTheLowerRungWithoutClearingItStaysThere() {
        let logs = [
            bottomLog(id: "c1", daysAgo: 1),
            bottomLog(id: "c2", daysAgo: 3, difficulty: .tooHard),
            clearingLog(id: "c1", daysAgo: 7),
        ]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c1")
    }

    func testTooHardAtTheBottomOnTheLowerRungStepsDownAgain() {
        let logs = [
            bottomLog(id: "c1", daysAgo: 1, difficulty: .tooHard),
            bottomLog(id: "c2", daysAgo: 3, difficulty: .tooHard),
            clearingLog(id: "c1", daysAgo: 7),
            clearingLog(id: "c0", daysAgo: 9),
        ]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c0")
    }

    func testTooHardAtTheBottomStepsDownFromTheServedRungWhenTheFrontierIsOutOfReach() {
        // The logged frontier c2 is a rung this user no longer gets, so they are served c1.
        let reachedC2 = repsLog(id: "c2", reps: [20, 20, 20, 20], daysAgo: 9)
        let eligible: Set = ["c0", "c1"]
        XCTAssertEqual(selectInChain(threeTierChain(), eligible: eligible, logs: [reachedC2])?.exercise.id, "c1")

        // "Too hard" at the bottom of the range on that served rung still steps one rung down.
        let logs = [bottomLog(id: "c1", daysAgo: 1, difficulty: .tooHard), reachedC2]
        XCTAssertEqual(selectInChain(threeTierChain(), eligible: eligible, logs: logs)?.exercise.id, "c0")
    }

    func testTheEntryRungAtTheBottomStaysOnTheEntryRung() {
        let logs = [bottomLog(id: "c0", daysAgo: 1, difficulty: .tooHard)]
        XCTAssertEqual(selectInChain(threeTierChain(), logs: logs)?.exercise.id, "c0", "there is no rung below the entry")
    }

    // MARK: - "Couldn't finish" never counts toward advancement (ADR-0011)

    func testAMoveMarkedCouldNotFinishNeverAdvances() {
        var marked = repsLog(id: "c1", reps: [30, 30, 30, 30], daysAgo: 1, difficulty: .tooHard)
        marked.exercises[0].couldNotFinish = true
        XCTAssertEqual(selectInChain(threeTierChain(), logs: [marked])?.exercise.id, "c1",
                       "the logged sets reached the top, but the user said they could not finish them")

        var unmarked = marked
        unmarked.exercises[0].couldNotFinish = nil
        unmarked.perceivedDifficulty = .justRight
        XCTAssertEqual(selectInChain(threeTierChain(), logs: [unmarked])?.exercise.id, "c2")
    }

    /// "Too hard" with nothing tapped eases every move off, as the completion screen says: `push_standard`
    /// logged at four sets of 30 eases to 25 next session and does not move up to `push_diamond`. A "too
    /// hard" session that tapped a different move holds the untapped one where it is: no step back, and -
    /// since no session rated too hard clears a rung (decision 15) - no advancement either.
    func testTooHardWithNothingTappedNeverAdvances() async throws {
        let library = try await MockExerciseService().exercises()
        let standard = try XCTUnwrap(library.first { $0.id == "push_standard" })
        let chain = library.filter { $0.progressionChainId == standard.progressionChainId }

        var untapped = repsLog(id: "push_standard", reps: [30, 30, 30, 30], daysAgo: 1, difficulty: .tooHard)
        untapped.exercises[0].couldNotFinish = false
        XCTAssertEqual(selectInChain(chain, logs: [untapped])?.exercise.id, "push_standard",
                       "too hard with nothing tapped never moves the user up")
        XCTAssertEqual(AdaptiveOverload.target(for: standard, level: level, recentLogs: [untapped]).reps, 25,
                       "it eases standard from 30 to 25")

        var otherTapped = log(daysAgo: 1, [
            station(id: "push_standard", values: [30, 30, 30, 30]),
            station(id: "squat_bodyweight", values: [30, 30, 30, 30], pattern: .squat),
        ], difficulty: .tooHard)
        otherTapped.exercises[0].couldNotFinish = false
        otherTapped.exercises[1].couldNotFinish = true
        XCTAssertEqual(selectInChain(chain, logs: [otherTapped])?.exercise.id, "push_standard",
                       "a session rated too hard clears nothing")
        XCTAssertEqual(AdaptiveOverload.target(for: standard, level: level, recentLogs: [otherTapped]).reps, 30,
                       "the untapped move holds at 30 rather than easing")
    }

    func testFrontierIsHighestOrderWorked() {
        // Worked c0 (cleared) and c2 (not cleared). Frontier is the highest worked, c2, and it is
        // not cleared, so selection stays on c2 - it does not regress to advancing off c0.
        let logs = [
            clearingLog(id: "c0", daysAgo: 3),
            bottomLog(id: "c2", daysAgo: 1),
        ]
        let selection = selectInChain(threeTierChain(), logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c2")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testSkippedFrontierWorkDoesNotCount() {
        let chain = makeChain("c", [(id: "c0", difficulty: 1), (id: "c1", difficulty: 2)])
        // c1 only ever appears skipped -> not "worked", so the frontier is unset and we start at entry.
        let logs = [repsLog(id: "c1", reps: [], daysAgo: 1, skipped: true)]
        XCTAssertEqual(selectInChain(chain, logs: logs)?.exercise.id, "c0")
    }

    /// A Practice station previews the next rung at practice reps (US-TD02); it never sets the frontier,
    /// so practicing c2 keeps the user on c1, and it never clears a rung either, even at the top.
    func testPracticeStationsNeverMoveTheFrontier() {
        let practicedNext = log(daysAgo: 1, [
            station(id: "c1", values: [20, 20, 20, 20]),
            station(id: "c2", values: [10, 10, 10, 10], role: .practice),
        ])
        let selection = selectInChain(threeTierChain(), logs: [practicedNext])
        XCTAssertEqual(selection?.exercise.id, "c1", "practicing the next rung never puts the user on it")
        XCTAssertEqual(selection?.didAdvance, false)

        let practiceAtTheTop = log(daysAgo: 1, [station(id: "c1", values: [30, 30, 30, 30], role: .practice)])
        XCTAssertEqual(selectInChain(threeTierChain(), logs: [bottomLog(id: "c1", daysAgo: 4), practiceAtTheTop])?.exercise.id, "c1",
                       "a Practice station never clears a rung")
    }

    func testHoldChainAdvancesAtTheTopOfTheHoldRange() {
        let chain = makeChain("hold_c", [(id: "h0", difficulty: 1), (id: "h1", difficulty: 2)], isHold: true)
        let short = log(daysAgo: 1, [station(id: "h0", values: [55, 55, 55, 55], isHold: true)])
        XCTAssertEqual(selectInChain(chain, logs: [short])?.exercise.id, "h0", "55 seconds is short of a beginner's 60")

        let cleared = log(daysAgo: 1, [station(id: "h0", values: [60, 60, 60, 60], isHold: true)])
        let selection = selectInChain(chain, logs: [cleared])
        XCTAssertEqual(selection?.exercise.id, "h1")
        XCTAssertEqual(selection?.didAdvance, true)
    }

    func testPerSideChainAdvancesAtFifteenPerSide() {
        let chain = makeChain("side_c", [(id: "s0", difficulty: 1), (id: "s1", difficulty: 2)], isPerSide: true)
        XCTAssertEqual(selectInChain(chain, logs: [repsLog(id: "s0", reps: [10, 10, 10, 10], daysAgo: 1)])?.exercise.id, "s0")
        XCTAssertEqual(selectInChain(chain, logs: [repsLog(id: "s0", reps: [15, 15, 15, 15], daysAgo: 1)])?.exercise.id, "s1")
    }

    // MARK: - selectInChain: eligibility

    func testDoesNotAdvanceWhenNextTierIsNotEligible() {
        // Cleared c1, but c2 is out of the eligible pool -> stays on c1 rather than leaking c2.
        let selection = selectInChain(threeTierChain(), eligible: ["c0", "c1"], logs: [clearingLog(id: "c1", daysAgo: 1)])
        XCTAssertEqual(selection?.exercise.id, "c1")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testClampsDownWhenFrontierTierIsNotEligible() {
        // Frontier c2 is no longer eligible (e.g. skip-filtered) -> clamp down to the highest
        // eligible tier at or below it, c1.
        let selection = selectInChain(threeTierChain(), eligible: ["c0", "c1"], logs: [bottomLog(id: "c2", daysAgo: 1)])
        XCTAssertEqual(selection?.exercise.id, "c1")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testReturnsNilWhenNoTierIsEligible() {
        let chain = makeChain("c", [(id: "c0", difficulty: 1), (id: "c1", difficulty: 2)])
        XCTAssertNil(selectInChain(chain, eligible: [], logs: []))
    }

    // MARK: - selectAll: every chain ranked

    /// `selectAll` resolves every chain of the pattern to its own frontier, best first, and `select` is
    /// exactly its first entry.
    func testSelectAllRanksOneCandidatePerChainAndSelectIsItsFirst() {
        let library = makeChain("a", [(id: "a0", difficulty: 1), (id: "a1", difficulty: 2)])
            + makeChain("b", [(id: "b0", difficulty: 2)])
            + makeChain("z", [(id: "z0", difficulty: 1)], pattern: .squat)
        let logs = [clearingLog(id: "a0", daysAgo: 1)]
        let ranked = ProgressionChainSelection.selectAll(
            pattern: .push, library: library, pool: library, recentLogs: logs, level: level
        )
        XCTAssertEqual(ranked.map(\.exercise.id), ["a1", "b0"], "one candidate per push chain, the active chain first")
        XCTAssertEqual(
            ProgressionChainSelection.select(pattern: .push, library: library, pool: library, recentLogs: logs, level: level),
            ranked.first
        )
    }

    // MARK: - select(pattern:): no-repeat and active-chain

    /// Two push chains. The user worked chain A's entry yesterday (not cleared), so A's pick is its
    /// own entry - which was used last session. The variety rule prefers chain B's fresh pick.
    func testSelectAvoidsAnExerciseUsedInTheLastThreeSessions() {
        let library = makeChain("a", [(id: "a0", difficulty: 1)])
            + makeChain("b", [(id: "b0", difficulty: 1)])
        let logs = [repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 1)] // a0 used, not cleared
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs, level: level
        )
        XCTAssertEqual(selection?.exercise.id, "b0")
    }

    /// With no fresh alternative (a single chain), the recently-used exercise is still returned -
    /// variety never beats having an exercise to prescribe.
    func testSelectReturnsRecentlyUsedWhenNoFreshAlternativeExists() {
        let library = makeChain("a", [(id: "a0", difficulty: 1)])
        let logs = [repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 1)]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level
            )?.exercise.id,
            "a0"
        )
    }

    /// Among equally-fresh candidates, the chain the user is actively progressing wins, and that
    /// chain advances when its frontier is cleared.
    func testSelectPrefersTheActivelyWorkedChainAndAdvancesIt() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1),
            (id: "a1", difficulty: 2),
        ]) + makeChain("b", [
            (id: "b0", difficulty: 1),
            (id: "b1", difficulty: 2),
        ])
        // Cleared a0 yesterday (four sets at the top of the range); chain B untouched. a1 (advancement) and b0 (entry) are both fresh,
        // but A is the active chain, so a1 is chosen.
        let logs = [clearingLog(id: "a0", daysAgo: 1)]
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs, level: level
        )
        XCTAssertEqual(selection?.exercise.id, "a1")
        XCTAssertEqual(selection?.didAdvance, true)
    }

    /// With no history, the pattern defaults to the gentlest entry across its chains (lowest
    /// difficulty), deterministically.
    func testSelectWithNoHistoryPicksTheGentlestEntry() {
        let library = makeChain("a", [(id: "a0", difficulty: 2)])
            + makeChain("b", [(id: "b0", difficulty: 1)])
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: [], level: level
        )
        XCTAssertEqual(selection?.exercise.id, "b0") // difficulty 1 beats difficulty 2
        XCTAssertEqual(selection?.didAdvance, false)
    }

    /// Freshness never buys a regression. A chain the Start Seed band held out of reach - so it
    /// accrued no history - must not win the variety preference with an entry tier the user was
    /// never actually offered. This is the post-handoff cliff guard: during cold start the band
    /// hides the gentle chains entirely, and the session the band lifts is exactly when their
    /// untouched entry tiers become the only "fresh" candidates.
    func testSelectPrefersRepeatingOverAChainTheBandWithheld() {
        let library = makeChain("banded", [
            (id: "banded_easy", difficulty: 1),
            (id: "banded_mid", difficulty: 2),
        ]) + makeChain("worked", [(id: "worked_hard", difficulty: 3)])

        // The user worked the hard chain last session; the banded chain was never prescribable.
        let logs = [repsLog(id: "worked_hard", reps: [15, 15, 15, 15], daysAgo: 1)]
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs, level: level,
            withheldByStartSeed: ["banded_easy", "banded_mid"]
        )

        XCTAssertEqual(
            selection?.exercise.id, "worked_hard",
            "a never-offered gentler chain must not out-rank the movement the user actually trains"
        )

        // With nothing withheld - a beginner, whose band is unfloored - freshness wins again, which
        // is exactly the plain pre-band behavior.
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level
            )?.exercise.id,
            "banded_easy",
            "an empty withheld set must reproduce the chain-local behavior exactly"
        )
    }

    /// Setting withheld candidates aside is about *never having been offered*, not about novelty: a
    /// fresh candidate inside the band still wins, so variety is untouched in the steady state.
    ///
    /// The fixture puts a genuinely withheld candidate in the running - `w0` is a real chain the band
    /// held out of reach - so the set-aside actually narrows the field here. It pins both halves at
    /// once: drop the set-aside and the never-offered `w0` wins on difficulty; drop the freshness
    /// preference and `a0`, worked last session, wins on active-chain recency.
    func testSelectStillPrefersAFreshCandidateInsideTheBand() {
        let library = makeChain("w", [(id: "w0", difficulty: 1)])
            + makeChain("a", [(id: "a0", difficulty: 3)])
            + makeChain("b", [(id: "b0", difficulty: 3)])
        let logs = [repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 1)]

        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level,
                withheldByStartSeed: ["w0"]
            )?.exercise.id,
            "b0"
        )
    }

    /// A chain that tops out beneath the user's best tier is *not* retired. The band is a fixed
    /// level-derived range, not the user's own ceiling, so a chain sitting inside it keeps competing
    /// for the variety window however far past it the user has climbed elsewhere in the pattern.
    func testSelectKeepsAnInBandChainTheUserHasClimbedPast() {
        let library = makeChain("tall", [
            (id: "tall_mid", difficulty: 3),
            (id: "tall_top", difficulty: 4),
        ]) + makeChain("short", [(id: "short_top", difficulty: 3)])

        // The user is working the tall chain at its top tier; the short chain tops out below them.
        let logs = [repsLog(id: "tall_top", reps: [15, 15, 15, 15], daysAgo: 1)]

        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level,
                withheldByStartSeed: ["tall_mid"] // only the sub-band tier is withheld
            )?.exercise.id,
            "short_top",
            "an in-band chain must stay in the rotation instead of being retired by a hard tier "
                + "elsewhere in the pattern"
        )
    }

    /// Setting candidates aside narrows the variety preference, it never cancels it. When the pool
    /// caps every chain beneath the band - a Return, an injury filter - the band is unreachable
    /// rather than violated, so the fresh-but-gentler candidate must still beat the one worked last
    /// session instead of the no-repeat window silently switching itself off.
    func testVarietyStillAppliesWhenEveryCandidateWasWithheld() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1),
            (id: "a_hard", difficulty: 3),
        ]) + makeChain("b", [(id: "b0", difficulty: 1)])
        // The pool now offers only the difficulty-1 tiers, all of which the band withheld.
        let pool = library.filter { $0.difficulty == 1 }
        let logs = [
            repsLog(id: "a_hard", reps: [15, 15, 15, 15], daysAgo: 2),
            repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 1),
        ]

        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: pool, recentLogs: logs, level: level,
                withheldByStartSeed: ["a0", "b0"]
            )?.exercise.id,
            "b0",
            "an unreachable band must not disable the no-repeat window"
        )
    }

    func testSelectReturnsNilWhenPatternHasNoEligibleTier() {
        let library = makeChain("a", [(id: "a0", difficulty: 1)])
        XCTAssertNil(
            ProgressionChainSelection.select(pattern: .push, library: library, pool: [], recentLogs: [], level: level)
        )
    }

    // MARK: - select(pattern:): tunable varietyWindow (US-E03)

    /// The `varietyWindow` lever tunes how many recent sessions the no-repeat rule looks back over.
    /// a0 was worked two sessions ago (not cleared, so chain A's pick stays a0) with a newer,
    /// unrelated session on top. A window of 1 does not reach a0's session, so the actively-worked
    /// chain A wins with a0; a window of 2 reaches it, marking a0 recently used, so the fresh chain
    /// B is preferred instead.
    func testVarietyWindowControlsHowManyRecentSessionsAreAvoided() {
        let library = makeChain("a", [(id: "a0", difficulty: 1)])
            + makeChain("b", [(id: "b0", difficulty: 1)])
        let logs = [
            repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 2), // a0 used, not cleared
            repsLog(id: "unrelated", reps: [15, 15, 15, 15], pattern: .core, daysAgo: 1), // newer, distinct
        ]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level, varietyWindow: 1
            )?.exercise.id,
            "a0"
        )
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level, varietyWindow: 2
            )?.exercise.id,
            "b0"
        )
    }

    /// The default `varietyWindow` parameter equals an explicit `recentSessionWindow`, so a caller
    /// that omits it keeps the pre-policy behavior exactly.
    func testDefaultVarietyWindowMatchesRecentSessionWindow() {
        let library = makeChain("a", [(id: "a0", difficulty: 1)])
            + makeChain("b", [(id: "b0", difficulty: 1)])
        let logs = [repsLog(id: "a0", reps: [15, 15, 15, 15], daysAgo: 1)]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level
            ),
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, level: level,
                varietyWindow: ProgressionChainSelection.recentSessionWindow
            )
        )
    }

    // MARK: - Determinism

    func testSelectionIsDeterministic() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1),
            (id: "a1", difficulty: 2),
        ]) + makeChain("b", [
            (id: "b0", difficulty: 1),
        ])
        let logs = [clearingLog(id: "a0", daysAgo: 2)]
        let first = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs, level: level
        )
        for _ in 0..<50 {
            XCTAssertEqual(
                ProgressionChainSelection.select(
                    pattern: .push, library: library, pool: library, recentLogs: logs, level: level
                ),
                first
            )
        }
    }

    // MARK: - Real bundled library (PRD US-C05 validation test)

    /// The PRD's own validation test, run end-to-end over the real bundled `Exercises.json`:
    ///
    ///   Setup:  Logs show the user cleared knee push-ups (push_knee, chain order 2): four sets at the
    ///           top of a beginner's range, at earned reps
    ///   Steps:  Generate a push-focused session (resolve the push pattern through Step 5)
    ///   Expect: The engine offers the next chain exercise (push_standard) rather than repeating
    ///           knee push-ups.
    ///   Fail:   It repeats the cleared exercise or skips ahead past an un-cleared tier.
    func testPRDValidationAdvancesPastClearedKneePushUps() async throws {
        let library = try await MockExerciseService().exercises()
        let user = beginnerDisciplineUser()

        // Cleared the way the rep grammar clears a rung: four sets at the top of a beginner's range.
        let logs = [clearingLog(id: "push_knee", daysAgo: 1)]
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: logs)

        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: pool, recentLogs: logs, level: .beginner
        )
        XCTAssertEqual(selection?.exercise.id, "push_standard", "offers the next tier, not the cleared one")
        XCTAssertNotEqual(selection?.exercise.id, "push_knee", "must not repeat the cleared exercise")
        XCTAssertEqual(selection?.order, 3)
        XCTAssertEqual(selection?.didAdvance, true)
    }

    /// A brand-new beginner gets the chain entry for push over the real library: push_wall
    /// (push_horizontal order 0, difficulty 1).
    func testPRDFreshBeginnerGetsPushEntryOverRealLibrary() async throws {
        let library = try await MockExerciseService().exercises()
        let user = beginnerDisciplineUser()
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: [])

        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: pool, recentLogs: [], level: .beginner
        )
        XCTAssertEqual(selection?.exercise.id, "push_wall")
        XCTAssertEqual(selection?.order, 0)
        XCTAssertEqual(selection?.didAdvance, false)
    }

    private func beginnerDisciplineUser() -> User {
        TrainingDayFixtures.user(level: .beginner)
    }
}
