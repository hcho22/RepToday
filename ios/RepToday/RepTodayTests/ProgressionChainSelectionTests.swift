import XCTest
@testable import RepToday

/// Tests pipeline Step 5 of the deterministic engine (US-C05): picking the right progression-chain
/// exercise for the user's demonstrated ability.
///
/// Three halves: `AdvancementCriteria` tests pin the parse of the free-text criteria and the
/// logged-performance "cleared?" check (reps and holds); `selectInChain` tests pin the per-chain
/// position logic (entry with no history, frontier = highest-order worked, advance only when
/// criteria are met, never past an ineligible/gated next tier, clamp when the frontier itself is
/// ineligible); the `select(pattern:)` tests pin per-pattern integration (the no-repeat-last-3
/// variety rule, the active-chain preference, the no-history default) and run the PRD's own
/// validation case over the real bundled library.
final class ProgressionChainSelectionTests: XCTestCase {

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

    /// Builds a fully-linked chain from `(id, difficulty, criteria)` tiers: `progressionOrder`
    /// follows the array, and `regressionId`/`progressionId` wire neighbors together.
    private func makeChain(
        _ chainId: String,
        _ tiers: [(id: String, difficulty: Int, criteria: String)],
        pattern: MovementPattern = .push,
        pillar: Pillar = .strength,
        isHold: Bool = false,
        phases: [Phase]? = nil
    ) -> [Exercise] {
        tiers.enumerated().map { index, tier in
            Exercise(
                id: tier.id,
                displayName: tier.id,
                pillar: pillar,
                movementPattern: pattern,
                category: .strength,
                difficulty: tier.difficulty,
                phase: phases?[index] ?? .discipline,
                equipment: [],
                isHold: isHold,
                defaultReps: isHold ? nil : 10,
                defaultDurationSeconds: isHold ? 20 : nil,
                estimatedTimePerSetSeconds: 40,
                metValue: 4,
                progressionChainId: chainId,
                progressionOrder: index,
                regressionId: index > 0 ? tiers[index - 1].id : nil,
                progressionId: index < tiers.count - 1 ? tiers[index + 1].id : nil,
                advancementCriteria: tier.criteria,
                apartmentFriendly: true
            )
        }
    }

    /// A session `daysAgo` that worked `id` with the given per-set `reps` (rep-based movement).
    private func repsLog(
        id: String,
        reps: [Int],
        pattern: MovementPattern = .push,
        daysAgo: Int,
        skipped: Bool = false,
        difficulty: PerceivedDifficulty? = nil
    ) -> WorkoutLog {
        log(
            daysAgo: daysAgo,
            [(id: id, pattern: pattern,
              sets: reps.map { CompletedSet(reps: $0, durationSeconds: nil) }, skipped: skipped)],
            difficulty: difficulty
        )
    }

    /// A session `daysAgo` that worked `id` with the given per-set hold `seconds`.
    private func holdLog(
        id: String,
        seconds: [Int],
        pattern: MovementPattern = .push,
        daysAgo: Int
    ) -> WorkoutLog {
        log(
            daysAgo: daysAgo,
            [(id: id, pattern: pattern,
              sets: seconds.map { CompletedSet(reps: nil, durationSeconds: $0) }, skipped: false)]
        )
    }

    /// A session `daysAgo` built from raw per-exercise entries.
    private func log(
        daysAgo: Int,
        _ entries: [(id: String, pattern: MovementPattern, sets: [CompletedSet], skipped: Bool)],
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
            exercises: entries.map { entry in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: entry.id,
                    pillar: entry.pattern == .mobility ? .mobility : .strength,
                    movementPattern: entry.pattern,
                    completedSets: entry.sets,
                    skipped: entry.skipped
                )
            }
        )
    }

    private func loggedExercise(id: String, sets: [CompletedSet], skipped: Bool = false) -> LoggedExercise {
        LoggedExercise(
            id: UUID(),
            exerciseId: id,
            pillar: .strength,
            movementPattern: .push,
            completedSets: sets,
            skipped: skipped
        )
    }

    private func selectInChain(
        _ chain: [Exercise],
        eligible: Set<String>? = nil,
        logs: [WorkoutLog]
    ) -> ChainSelection? {
        ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: eligible ?? Set(chain.map(\.id)),
            recentLogs: logs
        )
    }

    // MARK: - AdvancementCriteria parsing

    func testCriteriaParsesSetsByTarget() {
        XCTAssertEqual(AdvancementCriteria(parsing: "3x15 clean reps"), AdvancementCriteria(sets: 3, target: 15))
        XCTAssertEqual(AdvancementCriteria(parsing: "3x5 clean reps per side"), AdvancementCriteria(sets: 3, target: 5))
    }

    func testCriteriaParsesHoldSecondsAsTarget() {
        // The trailing "s" needs no special handling - the number is the target either way.
        XCTAssertEqual(AdvancementCriteria(parsing: "3x30s hold"), AdvancementCriteria(sets: 3, target: 30))
        XCTAssertEqual(AdvancementCriteria(parsing: "3x30s hold per side"), AdvancementCriteria(sets: 3, target: 30))
    }

    func testCriteriaParsesStandaloneNumberAsSingleSet() {
        XCTAssertEqual(AdvancementCriteria(parsing: "hold 45s"), AdvancementCriteria(sets: 1, target: 45))
        XCTAssertEqual(AdvancementCriteria(parsing: "12 reps per side"), AdvancementCriteria(sets: 1, target: 12))
        XCTAssertEqual(AdvancementCriteria(parsing: "flow 12 slow reps"), AdvancementCriteria(sets: 1, target: 12))
    }

    func testCriteriaPrefersSetsByTargetTokenOverAnEarlierStandaloneNumber() {
        // A leading standalone number does not pre-empt a later "NxM" token.
        XCTAssertEqual(AdvancementCriteria(parsing: "do 2 then 3x12 reps"), AdvancementCriteria(sets: 3, target: 12))
    }

    func testCriteriaReturnsNilWhenTextHasNoNumber() {
        XCTAssertNil(AdvancementCriteria(parsing: "as many as you can"))
        XCTAssertNil(AdvancementCriteria(parsing: ""))
    }

    // MARK: - AdvancementCriteria met?

    func testCriteriaMetForRepsRequiresEnoughQualifyingSets() {
        let criteria = AdvancementCriteria(sets: 3, target: 12)
        let cleared = loggedExercise(id: "x", sets: [
            CompletedSet(reps: 12, durationSeconds: nil),
            CompletedSet(reps: 14, durationSeconds: nil),
            CompletedSet(reps: 12, durationSeconds: nil),
        ])
        XCTAssertTrue(criteria.isMet(by: cleared, isHold: false))

        // One short set drops the qualifying count below the required 3.
        let short = loggedExercise(id: "x", sets: [
            CompletedSet(reps: 12, durationSeconds: nil),
            CompletedSet(reps: 11, durationSeconds: nil),
            CompletedSet(reps: 12, durationSeconds: nil),
        ])
        XCTAssertFalse(criteria.isMet(by: short, isHold: false))
    }

    func testCriteriaMetForHoldsUsesDurationSeconds() {
        let criteria = AdvancementCriteria(sets: 3, target: 30)
        let cleared = loggedExercise(id: "x", sets: [
            CompletedSet(reps: nil, durationSeconds: 30),
            CompletedSet(reps: nil, durationSeconds: 31),
            CompletedSet(reps: nil, durationSeconds: 30),
        ])
        XCTAssertTrue(criteria.isMet(by: cleared, isHold: true))
        // Counting reps instead of seconds for a hold would (wrongly) read every set as 0.
        XCTAssertFalse(criteria.isMet(by: cleared, isHold: false))
    }

    // MARK: - selectInChain: position

    func testNoHistoryStartsAtChainEntry() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        let selection = selectInChain(chain, logs: [])
        XCTAssertEqual(selection?.exercise.id, "c0")
        XCTAssertEqual(selection?.order, 0)
        XCTAssertEqual(selection?.didAdvance, false)
    }

    /// A chain the user has never worked is entered at the gentlest tier that still clears the
    /// session's ability floor - not at the chain's entry tier. Ability belongs to the movement
    /// pattern, not to one chain.
    func testNoHistoryChainIsEnteredAtTheAbilityFloor() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 3, criteria: "3x12 clean reps"),
        ])
        let selection = ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: Set(chain.map(\.id)),
            recentLogs: [],
            difficultyFloor: 2
        )
        XCTAssertEqual(selection?.exercise.id, "c1", "entered at the floor, not c0")
        XCTAssertEqual(selection?.didAdvance, false, "a lateral entry is not an advancement")
    }

    /// When no eligible tier clears the floor, the entry is the chain's *gentlest* eligible tier,
    /// never its hardest. Reaching for the top of what survived would invert the very restriction
    /// that narrowed the pool (a Return cap, an injury filter) in the first place.
    func testNoHistoryChainToppingOutBelowTheFloorEntersAtItsGentlestTier() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        let selection = ProgressionChainSelection.selectInChain(
            chain,
            eligibleIds: Set(chain.map(\.id)),
            recentLogs: [],
            difficultyFloor: 4
        )
        XCTAssertEqual(selection?.exercise.id, "c0")
    }

    /// The default keeps the pre-existing chain-local behavior: no floor means the chain entry.
    func testAbilityFloorDefaultsToTheChainEntry() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 3, criteria: "3x12 clean reps"),
        ])
        XCTAssertEqual(selectInChain(chain, logs: [])?.exercise.id, "c0")
    }

    func testDemonstratedDifficultyReadsTheHardestWorkedTierInThePattern() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "a1", difficulty: 3, criteria: "3x12 clean reps"),
        ]) + makeChain("s", [(id: "s0", difficulty: 4, criteria: "3x12 clean reps")], pattern: .squat)

        XCTAssertEqual(
            ProgressionChainSelection.demonstratedDifficulty(
                pattern: .push,
                library: library,
                recentLogs: [repsLog(id: "a1", reps: [8], daysAgo: 1)]
            ),
            3
        )
        // Another pattern's work is not this pattern's ability.
        XCTAssertEqual(
            ProgressionChainSelection.demonstratedDifficulty(
                pattern: .push,
                library: library,
                recentLogs: [repsLog(id: "s0", reps: [8], pattern: .squat, daysAgo: 1)]
            ),
            0
        )
        // A bailed-on movement demonstrates nothing.
        XCTAssertEqual(
            ProgressionChainSelection.demonstratedDifficulty(
                pattern: .push,
                library: library,
                recentLogs: [repsLog(id: "a1", reps: [], daysAgo: 1, skipped: true)]
            ),
            0
        )
    }

    func testStaysAtFrontierWhenCriteriaNotMet() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        // Worked c1 but only 2 clean sets (criteria needs 3) -> stays on c1.
        let logs = [repsLog(id: "c1", reps: [12, 12, 8], daysAgo: 1)]
        let selection = selectInChain(chain, logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c1")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testAdvancesToNextTierWhenCriteriaMet() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        let logs = [repsLog(id: "c1", reps: [12, 13, 12], daysAgo: 1)]
        let selection = selectInChain(chain, logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c2")
        XCTAssertEqual(selection?.order, 2)
        XCTAssertEqual(selection?.didAdvance, true)
    }

    func testAdvancesOnlyOneTierEvenWhenAnEarlierTierWasCleared() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        // Cleared the entry c0 -> offered exactly c1, never leaping to c2.
        let logs = [repsLog(id: "c0", reps: [15, 15, 15], daysAgo: 1)]
        XCTAssertEqual(selectInChain(chain, logs: logs)?.exercise.id, "c1")
    }

    func testFrontierIsHighestOrderWorked() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        // Worked c0 (cleared) and c2 (not cleared). Frontier is the highest worked, c2, and it is
        // not cleared, so selection stays on c2 - it does not regress to advancing off c0.
        let logs = [
            repsLog(id: "c0", reps: [15, 15, 15], daysAgo: 3),
            repsLog(id: "c2", reps: [8, 8, 8], daysAgo: 1),
        ]
        let selection = selectInChain(chain, logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c2")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testSkippedFrontierWorkDoesNotCount() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        // c1 only ever appears skipped -> not "worked", so the frontier is unset and we start at entry.
        let logs = [repsLog(id: "c1", reps: [], daysAgo: 1, skipped: true)]
        XCTAssertEqual(selectInChain(chain, logs: logs)?.exercise.id, "c0")
    }

    func testHoldChainAdvancesOnDurationCriteria() {
        let chain = makeChain("hold_c", [
            (id: "h0", difficulty: 1, criteria: "3x30s hold"),
            (id: "h1", difficulty: 2, criteria: "3x30s hold"),
        ], isHold: true)
        let logs = [holdLog(id: "h0", seconds: [30, 32, 30], daysAgo: 1)]
        let selection = selectInChain(chain, logs: logs)
        XCTAssertEqual(selection?.exercise.id, "h1")
        XCTAssertEqual(selection?.didAdvance, true)
    }

    // MARK: - selectInChain: eligibility

    func testDoesNotAdvanceWhenNextTierIsNotEligible() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 3, criteria: "3x12 clean reps"), // gated/over-cap: not eligible
        ])
        // Cleared c1, but c2 is out of the eligible pool -> stays on c1 rather than leaking c2.
        let logs = [repsLog(id: "c1", reps: [12, 12, 12], daysAgo: 1)]
        let selection = selectInChain(chain, eligible: ["c0", "c1"], logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c1")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testClampsDownWhenFrontierTierIsNotEligible() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "c2", difficulty: 3, criteria: "3x12 clean reps"),
        ])
        // Frontier c2 is no longer eligible (e.g. skip-filtered) -> clamp down to the highest
        // eligible tier at or below it, c1.
        let logs = [repsLog(id: "c2", reps: [8, 8, 8], daysAgo: 1)]
        let selection = selectInChain(chain, eligible: ["c0", "c1"], logs: logs)
        XCTAssertEqual(selection?.exercise.id, "c1")
        XCTAssertEqual(selection?.didAdvance, false)
    }

    func testReturnsNilWhenNoTierIsEligible() {
        let chain = makeChain("c", [
            (id: "c0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "c1", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        XCTAssertNil(selectInChain(chain, eligible: [], logs: []))
    }

    // MARK: - select(pattern:): no-repeat and active-chain

    /// Two push chains. The user worked chain A's entry yesterday (not cleared), so A's pick is its
    /// own entry - which was used last session. The variety rule prefers chain B's fresh pick.
    func testSelectAvoidsAnExerciseUsedInTheLastThreeSessions() {
        let library = makeChain("a", [(id: "a0", difficulty: 1, criteria: "3x12 clean reps")])
            + makeChain("b", [(id: "b0", difficulty: 1, criteria: "3x12 clean reps")])
        let logs = [repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 1)] // a0 used, not cleared
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs
        )
        XCTAssertEqual(selection?.exercise.id, "b0")
    }

    /// With no fresh alternative (a single chain), the recently-used exercise is still returned -
    /// variety never beats having an exercise to prescribe.
    func testSelectReturnsRecentlyUsedWhenNoFreshAlternativeExists() {
        let library = makeChain("a", [(id: "a0", difficulty: 1, criteria: "3x12 clean reps")])
        let logs = [repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 1)]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs
            )?.exercise.id,
            "a0"
        )
    }

    /// Among equally-fresh candidates, the chain the user is actively progressing wins, and that
    /// chain advances when its frontier criteria are met.
    func testSelectPrefersTheActivelyWorkedChainAndAdvancesIt() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "a1", difficulty: 2, criteria: "3x12 clean reps"),
        ]) + makeChain("b", [
            (id: "b0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "b1", difficulty: 2, criteria: "3x12 clean reps"),
        ])
        // Cleared a0 yesterday; chain B untouched. a1 (advancement) and b0 (entry) are both fresh,
        // but A is the active chain, so a1 is chosen.
        let logs = [repsLog(id: "a0", reps: [12, 12, 12], daysAgo: 1)]
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs
        )
        XCTAssertEqual(selection?.exercise.id, "a1")
        XCTAssertEqual(selection?.didAdvance, true)
    }

    /// With no history, the pattern defaults to the gentlest entry across its chains (lowest
    /// difficulty), deterministically.
    func testSelectWithNoHistoryPicksTheGentlestEntry() {
        let library = makeChain("a", [(id: "a0", difficulty: 2, criteria: "3x12 clean reps")])
            + makeChain("b", [(id: "b0", difficulty: 1, criteria: "3x12 clean reps")])
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: []
        )
        XCTAssertEqual(selection?.exercise.id, "b0") // difficulty 1 beats difficulty 2
        XCTAssertEqual(selection?.didAdvance, false)
    }

    /// Freshness never buys a regression. A chain the pool kept out of reach - so it accrued no
    /// history - must not win the variety preference with an entry tier beneath what the user has
    /// already demonstrated in this pattern. This is the post-handoff cliff guard: during cold
    /// start Step 0's Start Seed band hides the gentle chains entirely, and the session the band
    /// lifts is exactly when their untouched entry tiers become the only "fresh" candidates.
    func testSelectPrefersRepeatingOverRegressingBelowDemonstratedAbility() {
        let library = makeChain("banded", [
            (id: "banded_easy", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "banded_mid", difficulty: 2, criteria: "3x12 clean reps"),
        ]) + makeChain("worked", [(id: "worked_hard", difficulty: 3, criteria: "3x99 clean reps")])

        // The user worked the hard chain last session; the banded chain was never prescribable.
        let logs = [repsLog(id: "worked_hard", reps: [8, 8, 8], daysAgo: 1)]
        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs,
            abilityFloor: steadyStateFloor
        )

        XCTAssertEqual(
            selection?.exercise.id, "worked_hard",
            "a never-worked gentler chain must not out-rank the movement matching demonstrated ability"
        )

        // Suppressed - a Return, a too-hard session - and the rail is gone: freshness wins again,
        // which is the whole point of easing outranking the floor.
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs
            )?.exercise.id,
            "banded_easy",
            "a suppressed floor must reproduce the pre-floor, chain-local behavior exactly"
        )
    }

    /// The rail is about *regression*, not about novelty: a fresh candidate at or above demonstrated
    /// ability still wins, so variety is untouched in the steady state.
    func testSelectStillPrefersAFreshCandidateAtDemonstratedAbility() {
        let library = makeChain("a", [(id: "a0", difficulty: 3, criteria: "3x99 clean reps")])
            + makeChain("b", [(id: "b0", difficulty: 3, criteria: "3x99 clean reps")])
        let logs = [repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 1)]

        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs,
                abilityFloor: steadyStateFloor
            )?.exercise.id,
            "b0"
        )
    }

    /// The rail narrows the variety preference, it never cancels it. When the pool caps every chain
    /// below demonstrated ability - a Return, an injury filter - no fresh candidate can clear the
    /// floor, and the old all-or-nothing rail silently switched the variety window off entirely.
    /// The fresh-but-gentler candidate must still beat the one worked last session.
    func testVarietyStillAppliesWhenNothingFreshClearsTheFloor() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1, criteria: "3x99 clean reps"),
            (id: "a_hard", difficulty: 3, criteria: "3x99 clean reps"),
        ]) + makeChain("b", [(id: "b0", difficulty: 1, criteria: "3x99 clean reps")])
        // Ability demonstrated at 3, but the pool now offers only the difficulty-1 tiers.
        let pool = library.filter { $0.difficulty == 1 }
        let logs = [
            repsLog(id: "a_hard", reps: [8, 8, 8], daysAgo: 2),
            repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 1),
        ]

        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: pool, recentLogs: logs,
                abilityFloor: steadyStateFloor
            )?.exercise.id,
            "b0",
            "an unreachable floor must not disable the no-repeat window"
        )
    }

    // MARK: - select(pattern:): ability-floor precedence (easing always wins)

    /// A Return suppresses the floor outright. `ReturnOverride.returnPool` caps the pool precisely so
    /// a strong pre-gap history cannot serve a punishing tier; a floor read from that same history
    /// would hand it straight back.
    func testReturnSuppressesTheAbilityFloor() {
        let user = beginnerDisciplineUser()
        let logs = [repsLog(id: "push_diamond", reps: [8, 8, 8], daysAgo: 30)]

        XCTAssertEqual(
            ProgressionChainSelection.abilityFloor(
                user: user, sessionPolicy: .default, recentLogs: logs, isReturn: true
            ),
            .suppressed
        )
        XCTAssertTrue(
            ProgressionChainSelection.abilityFloor(
                user: user, sessionPolicy: .default, recentLogs: logs, isReturn: false
            ).applies,
            "outside a Return the same history resolves a live floor"
        )
    }

    /// A down-signal suppresses the floor too, so the tier the Start Seed just stepped down is not
    /// immediately re-raised by the floor reading the pre-signal history.
    func testDownSignalSuppressesTheAbilityFloor() {
        let user = beginnerDisciplineUser()

        XCTAssertEqual(
            ProgressionChainSelection.abilityFloor(
                user: user,
                sessionPolicy: .default,
                recentLogs: [repsLog(id: "push_diamond", reps: [8], daysAgo: 1, difficulty: .tooHard)],
                isReturn: false
            ),
            .suppressed
        )
        // Outside cold start only the most recent session counts, so one bad day does not shadow the
        // user forever.
        XCTAssertTrue(
            ProgressionChainSelection.abilityFloor(
                user: user,
                sessionPolicy: .default,
                recentLogs: [
                    repsLog(id: "push_diamond", reps: [8], daysAgo: 2, difficulty: .tooHard),
                    repsLog(id: "push_standard", reps: [8], daysAgo: 1, difficulty: .justRight),
                ],
                isReturn: false
            ).applies
        )
    }

    /// The floor a steady-state session carries is the user's own fitness level, used - uniquely -
    /// as a floor rather than as `ExercisePoolFilter`'s ceiling.
    func testAbilityFloorCarriesTheFitnessLevelForward() {
        for level in FitnessLevel.allCases {
            var user = beginnerDisciplineUser()
            user.profile.fitnessLevel = level
            XCTAssertEqual(
                ProgressionChainSelection.abilityFloor(
                    user: user, sessionPolicy: .default, recentLogs: [], isReturn: false
                ).untrainedPatternFloor,
                SessionPolicy.ColdStartContract.startingDifficultyFloor(for: level)
            )
        }
    }

    /// A pattern the user has worked *nothing* in falls back to the level-derived floor, so the
    /// handoff cannot hand an advanced user the absolute entry tier of a pattern their cold-start
    /// week happened never to touch.
    func testUntrainedPatternFallsBackToTheLevelFloor() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "a1", difficulty: 2, criteria: "3x12 clean reps"),
            (id: "a2", difficulty: 3, criteria: "3x12 clean reps"),
        ])
        let floor = ProgressionChainSelection.AbilityFloor(untrainedPatternFloor: 3, applies: true)

        XCTAssertEqual(
            ProgressionChainSelection.difficultyFloor(
                for: .push, library: library, recentLogs: [], abilityFloor: floor
            ),
            3,
            "no history in the pattern means the level floor carries"
        )
        // Demonstrated history in the pattern is the truer signal and wins over the level default.
        XCTAssertEqual(
            ProgressionChainSelection.difficultyFloor(
                for: .push,
                library: library,
                recentLogs: [repsLog(id: "a1", reps: [8], daysAgo: 1)],
                abilityFloor: floor
            ),
            2
        )
        XCTAssertEqual(
            ProgressionChainSelection.difficultyFloor(
                for: .push, library: library, recentLogs: [], abilityFloor: .suppressed
            ),
            0
        )
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: [], abilityFloor: floor
            )?.exercise.id,
            "a2",
            "the untrained pattern opens at the level floor, not at the chain entry"
        )
    }

    /// A live floor for a user who has demonstrated nothing anywhere, for the tests that only care
    /// that the rail is switched on.
    private var steadyStateFloor: ProgressionChainSelection.AbilityFloor {
        ProgressionChainSelection.AbilityFloor(untrainedPatternFloor: 0, applies: true)
    }

    func testSelectReturnsNilWhenPatternHasNoEligibleTier() {
        let library = makeChain("a", [(id: "a0", difficulty: 1, criteria: "3x12 clean reps")])
        XCTAssertNil(
            ProgressionChainSelection.select(pattern: .push, library: library, pool: [], recentLogs: [])
        )
    }

    // MARK: - select(pattern:): tunable varietyWindow (US-E03)

    /// The `varietyWindow` lever tunes how many recent sessions the no-repeat rule looks back over.
    /// a0 was worked two sessions ago (not cleared, so chain A's pick stays a0) with a newer,
    /// unrelated session on top. A window of 1 does not reach a0's session, so the actively-worked
    /// chain A wins with a0; a window of 2 reaches it, marking a0 recently used, so the fresh chain
    /// B is preferred instead.
    func testVarietyWindowControlsHowManyRecentSessionsAreAvoided() {
        let library = makeChain("a", [(id: "a0", difficulty: 1, criteria: "3x12 clean reps")])
            + makeChain("b", [(id: "b0", difficulty: 1, criteria: "3x12 clean reps")])
        let logs = [
            repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 2), // a0 used, not cleared
            repsLog(id: "unrelated", reps: [10, 10], pattern: .core, daysAgo: 1), // newer, distinct
        ]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, varietyWindow: 1
            )?.exercise.id,
            "a0"
        )
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs, varietyWindow: 2
            )?.exercise.id,
            "b0"
        )
    }

    /// The default `varietyWindow` parameter equals an explicit `recentSessionWindow`, so a caller
    /// that omits it keeps the pre-policy behavior exactly.
    func testDefaultVarietyWindowMatchesRecentSessionWindow() {
        let library = makeChain("a", [(id: "a0", difficulty: 1, criteria: "3x12 clean reps")])
            + makeChain("b", [(id: "b0", difficulty: 1, criteria: "3x12 clean reps")])
        let logs = [repsLog(id: "a0", reps: [8, 8, 8], daysAgo: 1)]
        XCTAssertEqual(
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs
            ),
            ProgressionChainSelection.select(
                pattern: .push, library: library, pool: library, recentLogs: logs,
                varietyWindow: ProgressionChainSelection.recentSessionWindow
            )
        )
    }

    // MARK: - Determinism

    func testSelectionIsDeterministic() {
        let library = makeChain("a", [
            (id: "a0", difficulty: 1, criteria: "3x12 clean reps"),
            (id: "a1", difficulty: 2, criteria: "3x12 clean reps"),
        ]) + makeChain("b", [
            (id: "b0", difficulty: 1, criteria: "3x12 clean reps"),
        ])
        let logs = [repsLog(id: "a0", reps: [12, 12, 12], daysAgo: 2)]
        let first = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: library, recentLogs: logs
        )
        for _ in 0..<50 {
            XCTAssertEqual(
                ProgressionChainSelection.select(
                    pattern: .push, library: library, pool: library, recentLogs: logs
                ),
                first
            )
        }
    }

    // MARK: - Real bundled library (PRD US-C05 validation test)

    /// The PRD's own validation test, run end-to-end over the real bundled `Exercises.json`:
    ///
    ///   Setup:  Logs show the user cleared knee push-ups (push_knee, chain order 2)
    ///   Steps:  Generate a push-focused session (resolve the push pattern through Step 5)
    ///   Expect: The engine offers the next chain exercise (push_standard) rather than repeating
    ///           knee push-ups.
    ///   Fail:   It repeats the cleared exercise or skips ahead past an un-cleared tier.
    func testPRDValidationAdvancesPastClearedKneePushUps() async throws {
        let library = try await MockExerciseService().exercises()
        let user = beginnerDisciplineUser()

        // push_knee's own criteria is "3x12 clean reps"; clear it with three qualifying sets.
        let logs = [repsLog(id: "push_knee", reps: [12, 12, 13], pattern: .push, daysAgo: 1)]
        let pool = ExercisePoolFilter.eligiblePool(from: library, user: user, recentLogs: logs)

        let selection = ProgressionChainSelection.select(
            pattern: .push, library: library, pool: pool, recentLogs: logs
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
            pattern: .push, library: library, pool: pool, recentLogs: []
        )
        XCTAssertEqual(selection?.exercise.id, "push_wall")
        XCTAssertEqual(selection?.order, 0)
        XCTAssertEqual(selection?.didAdvance, false)
    }

    private func beginnerDisciplineUser() -> User {
        User(
            id: "u1",
            displayName: "Test",
            createdAt: asOf,
            profile: UserProfile(
                age: 35,
                sex: .other,
                heightCm: 175,
                weightKg: 75,
                fitnessLevel: .beginner,
                primaryGoal: .stayActive,
                sitsLong: true,
                injuries: [],
                typicalAvailableMinutes: 15
            ),
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: 3, score: 50, workoutsThisWeek: 1,
                longestChain: 0, totalWorkoutsCompleted: 0, totalMinutesExercised: 0
            )
        )
    }
}
