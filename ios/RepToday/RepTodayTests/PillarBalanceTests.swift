import XCTest
@testable import RepToday

/// Tests pipeline Step 2 of the deterministic engine (US-C02): balancing the training pillars
/// by staleness.
///
/// Two halves: `PillarStaleness` tests pin the days-since-worked computation read back from
/// logs (most-recent wins, skips don't count, never-worked is nil); the `PillarPlan.select`
/// tests pin single-focus selection (always strength, US-001, independent of staleness and the
/// desk-sitting signal) and blend weighting (time split by relative staleness, both pillars
/// always included).
final class PillarBalanceTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed UTC calendar and reference "today" so day-difference math is deterministic.
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

    /// A log completing `daysAgo`, training each pillar in `pillars` (all skipped if `skipped`).
    private func log(pillars: [Pillar], daysAgo: Int, skipped: Bool = false) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            requestedMinutes: 10,
            durationMinutes: 10,
            shape: pillars.count > 1 ? .blend : .singleFocus,
            focusPillar: pillars.count == 1 ? pillars.first : nil,
            perceivedDifficulty: nil,
            exercises: pillars.map { pillar in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "ex-\(pillar.rawValue)-\(daysAgo)",
                    pillar: pillar,
                    movementPattern: pillar == .mobility ? .mobility : .push,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: skipped
                )
            }
        )
    }

    private func profile(sitsLong: Bool) -> UserProfile {
        UserProfile(
            age: 30,
            sex: .male,
            heightCm: 175,
            weightKg: 75,
            fitnessLevel: .beginner,
            primaryGoal: .stayActive,
            sitsLong: sitsLong,
            injuries: [],
            typicalAvailableMinutes: 15
        )
    }

    private func staleness(_ logs: [WorkoutLog]) -> PillarStaleness {
        PillarStaleness(recentLogs: logs, asOf: asOf, calendar: calendar)
    }

    private func plan(
        _ template: SessionShapeTemplate,
        logs: [WorkoutLog],
        sitsLong: Bool
    ) -> PillarPlan {
        PillarPlan.select(
            template: template,
            recentLogs: logs,
            profile: profile(sitsLong: sitsLong),
            asOf: asOf,
            calendar: calendar
        )
    }

    /// Unwraps the blend weights, failing the test if the plan is single-focus.
    private func weights(_ plan: PillarPlan, file: StaticString = #filePath, line: UInt = #line) -> PillarWeights {
        guard case .blend(let weights) = plan else {
            XCTFail("expected a blend plan, got \(plan)", file: file, line: line)
            return PillarWeights(strength: 0, mobility: 0)
        }
        return weights
    }

    // MARK: - PillarStaleness

    func testEmptyHistoryHasNoStaleness() {
        let staleness = staleness([])
        XCTAssertNil(staleness.days(for: .strength))
        XCTAssertNil(staleness.days(for: .mobility))
    }

    func testDaysSinceWorkedPerPillar() {
        // Strength worked yesterday, mobility six days ago (the validation-test setup).
        let staleness = staleness([
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ])
        XCTAssertEqual(staleness.days(for: .strength), 1)
        XCTAssertEqual(staleness.days(for: .mobility), 6)
    }

    func testMostRecentSessionWins() {
        // Strength appears twice; the freshest (2 days ago) is the staleness.
        let staleness = staleness([
            log(pillars: [.strength], daysAgo: 5),
            log(pillars: [.strength], daysAgo: 2),
        ])
        XCTAssertEqual(staleness.days(for: .strength), 2)
    }

    func testBlendSessionMarksBothPillarsWorked() {
        let staleness = staleness([log(pillars: [.strength, .mobility], daysAgo: 3)])
        XCTAssertEqual(staleness.days(for: .strength), 3)
        XCTAssertEqual(staleness.days(for: .mobility), 3)
    }

    func testSkippedExerciseDoesNotCountAsWorked() {
        let staleness = staleness([log(pillars: [.strength], daysAgo: 2, skipped: true)])
        XCTAssertNil(staleness.days(for: .strength))
    }

    func testIsStalerTreatsNeverWorkedAsMostStale() {
        XCTAssertTrue(PillarStaleness.isStaler(nil, than: 3))
        XCTAssertFalse(PillarStaleness.isStaler(3, than: nil))
        XCTAssertFalse(PillarStaleness.isStaler(nil, than: nil))
        XCTAssertTrue(PillarStaleness.isStaler(6, than: 1))
        XCTAssertFalse(PillarStaleness.isStaler(1, than: 6))
        XCTAssertFalse(PillarStaleness.isStaler(3, than: 3))
    }

    // MARK: - Single-focus selection (US-001: always strength)

    /// US-001 invariant: a single-focus session on a fresh (no-history) desk-worker profile -
    /// the originally-reported all-mobility failure case - now leads **strength**. Mobility can no
    /// longer be a single-focus training pillar; it survives only as the structural warm-up.
    func testSingleFocusFreshDeskWorkerLeadsStrength() {
        XCTAssertEqual(plan(.singleFocus, logs: [], sitsLong: true), .single(.strength))
    }

    /// A fresh active (non-desk-bound) profile also leads strength.
    func testSingleFocusFreshActiveUserLeadsStrength() {
        XCTAssertEqual(plan(.singleFocus, logs: [], sitsLong: false), .single(.strength))
    }

    /// Single-focus is strength regardless of staleness: even when mobility is by far the stalest
    /// pillar (worked-strength-yesterday, mobility-six-days-ago), the session still leads strength.
    func testSingleFocusIsStrengthEvenWhenMobilityIsStalest() {
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: false), .single(.strength))
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.strength))
    }

    /// Single-focus is strength regardless of the desk-sitting signal: with strength and mobility
    /// equally stale, both a desk worker and an active user lead strength (the old mobility
    /// tie-break for `sitsLong` is gone).
    func testSingleFocusIsStrengthForBothSignalsOnEqualStaleness() {
        let logs = [log(pillars: [.strength, .mobility], daysAgo: 3)]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: false), .single(.strength))
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.strength))
    }

    // MARK: - Blend weighting (US-002: strength leads, mobility is a minority accessory)

    /// The US-002 core: a two-pillar blend leads **strength** with mobility as a small minority
    /// accessory. An active (non-desk-bound) user runs ~80% strength / 20% mobility, inside the
    /// ~0.75-0.80 strength target band, and the split does not depend on history.
    func testBlendLeadsStrengthWithMobilityMinorityForActiveUser() {
        let weights = weights(plan(.blendFull, logs: [], sitsLong: false))
        XCTAssertEqual(weights.strength, 0.8, accuracy: 1e-9)
        XCTAssertEqual(weights.mobility, 0.2, accuracy: 1e-9)
        XCTAssertGreaterThan(weights.strength, weights.mobility, "strength leads the blend")
        XCTAssertEqual(weights.strength + weights.mobility, 1.0, accuracy: 1e-9)
    }

    /// A sedentary (desk-worker) user gets a slightly larger mobility accessory for their postural debt
    /// - ~75% strength / 25% mobility - but strength still clearly leads (the boost only sizes the
    /// accessory, it never flips the lead, FR-5).
    func testSedentaryUserGetsLargerMobilityAccessoryButStrengthStillLeads() {
        let sedentary = weights(plan(.blendFull, logs: [], sitsLong: true))
        XCTAssertEqual(sedentary.strength, 0.75, accuracy: 1e-9)
        XCTAssertEqual(sedentary.mobility, 0.25, accuracy: 1e-9)
        XCTAssertGreaterThan(sedentary.strength, sedentary.mobility, "strength still leads a desk worker's blend")

        // The desk worker's mobility accessory is strictly larger than the active user's, and strength
        // strictly smaller - but both stay strength-led and inside the target band.
        let active = weights(plan(.blendFull, logs: [], sitsLong: false))
        XCTAssertGreaterThan(sedentary.mobility, active.mobility)
        XCTAssertLessThan(sedentary.strength, active.strength)
        XCTAssertGreaterThanOrEqual(sedentary.strength, 0.75)
        XCTAssertLessThanOrEqual(active.strength, 0.8)
    }

    /// Staleness no longer picks the strength-vs-mobility lead (US-002): even when mobility is by far
    /// the stalest pillar - the originally-reported failure configuration - strength still leads the
    /// blend and mobility stays the minority accessory.
    func testBlendLeadsStrengthEvenWhenMobilityIsStalest() {
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        let active = weights(plan(.blendFull, logs: logs, sitsLong: false))
        XCTAssertEqual(active.strength, 0.8, accuracy: 1e-9, "a stale mobility no longer takes the lead")
        XCTAssertEqual(active.mobility, 0.2, accuracy: 1e-9)

        // A desk worker with the same stale-mobility history: still strength-led, just a bigger accessory.
        let sedentary = weights(plan(.blendFull, logs: logs, sitsLong: true))
        XCTAssertEqual(sedentary.strength, 0.75, accuracy: 1e-9)
        XCTAssertGreaterThan(sedentary.strength, sedentary.mobility)
    }

    /// Mobility is always a genuine minority accessory (never starved to nothing, never the lead): it
    /// keeps at least `minBlendShare` and strength always keeps the majority.
    func testBlendMobilityIsAGenuineMinorityAccessory() {
        for sitsLong in [true, false] {
            let weights = weights(plan(.blendFull, logs: [], sitsLong: sitsLong))
            XCTAssertGreaterThanOrEqual(weights.mobility, PillarPlan.minBlendShare, "mobility keeps its floor")
            XCTAssertLessThan(weights.mobility, 0.5, "mobility is a minority")
            XCTAssertGreaterThan(weights.strength, 0.5, "strength keeps the majority")
            XCTAssertEqual(weights.strength + weights.mobility, 1.0, accuracy: 1e-9)
        }
    }

    /// Light and full blends weight pillars identically; only the assembled block sizes differ.
    func testBlendLightAndFullWeightIdentically() {
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        XCTAssertEqual(
            weights(plan(.blendLight, logs: logs, sitsLong: false)),
            weights(plan(.blendFull, logs: logs, sitsLong: false))
        )
    }

    // MARK: - Extended blend: primal as a first-class pillar (US-E02), under the US-002 envelope

    /// An extended blend keeps mobility a minority accessory and leads with the **strength family**
    /// (strength + primal): strength leads outright, primal earns its dedicated block, and the family
    /// holds the ~0.75-0.80 leading share. With no history primal takes the middle of its family band.
    func testExtendedBlendLeadsStrengthFamilyWithMobilityMinority() {
        let weights = weights(plan(.blendExtended, logs: [], sitsLong: false))
        XCTAssertEqual(weights.mobility, 0.2, accuracy: 1e-9, "mobility is the minority accessory")
        XCTAssertGreaterThan(weights.strength, weights.primal, "strength leads primal")
        XCTAssertGreaterThan(weights.strength, weights.mobility, "strength leads the session")
        XCTAssertGreaterThan(weights.primal, 0, "primal earns a genuine dedicated block")
        // The strength family (strength + primal) keeps the leading ~0.75-0.80 share.
        XCTAssertEqual(weights.strength + weights.primal, 0.8, accuracy: 1e-9)
        XCTAssertEqual(weights.strength + weights.mobility + weights.primal, 1.0, accuracy: 1e-9)
    }

    /// Staleness still leans the split *within* the strength family (US-002/AC-4): a stale primal earns
    /// a bigger dedicated block than a fresh one - but never overtakes strength, which always leads.
    func testExtendedBlendStalePrimalEarnsMorePrimalButStrengthStillLeads() {
        // Strength and mobility worked yesterday; primal never worked -> primal is the stalest.
        let stalePrimal = weights(plan(.blendExtended, logs: [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 1),
        ], sitsLong: false))
        // Primal worked today; strength never -> primal is the freshest.
        let freshPrimal = weights(plan(.blendExtended, logs: [
            log(pillars: [.primal], daysAgo: 0),
        ], sitsLong: false))

        XCTAssertGreaterThan(stalePrimal.primal, freshPrimal.primal, "a stale primal earns a bigger block")
        XCTAssertGreaterThan(stalePrimal.strength, stalePrimal.primal, "strength still leads a stale-primal blend")
        XCTAssertEqual(stalePrimal.mobility, 0.2, accuracy: 1e-9, "mobility stays the minority accessory")
        XCTAssertEqual(stalePrimal.strength + stalePrimal.mobility + stalePrimal.primal, 1.0, accuracy: 1e-9)
    }

    /// The desk-worker mobility boost applies to an extended blend too: a sedentary user gets a strictly
    /// larger mobility accessory than an active one, while both stay strength-led with all shares summing
    /// to 1.
    func testExtendedBlendSedentaryGetsLargerMobilityAccessory() {
        let logs = [
            log(pillars: [.strength], daysAgo: 3),
            log(pillars: [.mobility], daysAgo: 3),
            log(pillars: [.primal], daysAgo: 3),
        ]
        let active = weights(plan(.blendExtended, logs: logs, sitsLong: false))
        let sedentary = weights(plan(.blendExtended, logs: logs, sitsLong: true))

        XCTAssertEqual(active.mobility, 0.2, accuracy: 1e-9)
        XCTAssertEqual(sedentary.mobility, 0.25, accuracy: 1e-9)
        XCTAssertGreaterThan(sedentary.mobility, active.mobility)
        XCTAssertGreaterThan(active.strength, active.primal, "strength leads for the active user")
        XCTAssertGreaterThan(sedentary.strength, sedentary.primal, "strength leads for the desk worker")
        XCTAssertEqual(active.strength + active.mobility + active.primal, 1.0, accuracy: 1e-9)
        XCTAssertEqual(sedentary.strength + sedentary.mobility + sedentary.primal, 1.0, accuracy: 1e-9)
    }

    /// The Session Policy `pillarWeighting` lever still leans the within-family split (US-E02): with all
    /// three equally stale, doubling primal's weight gives it a larger dedicated block than the neutral
    /// split - but strength keeps the majority of the family and still leads.
    func testExtendedBlendRespectsPrimalPillarWeighting() {
        let logs = [
            log(pillars: [.strength], daysAgo: 3),
            log(pillars: [.mobility], daysAgo: 3),
            log(pillars: [.primal], daysAgo: 3),
        ]
        let neutral = weights(
            PillarPlan.select(
                template: .blendExtended,
                recentLogs: logs,
                profile: profile(sitsLong: false),
                asOf: asOf,
                calendar: calendar
            )
        )
        var heavyPrimal = SessionPolicy.neutralPillarWeighting
        heavyPrimal[.primal] = 2.0
        let weighted = weights(
            PillarPlan.select(
                template: .blendExtended,
                recentLogs: logs,
                profile: profile(sitsLong: false),
                pillarWeighting: heavyPrimal,
                asOf: asOf,
                calendar: calendar
            )
        )
        XCTAssertGreaterThan(weighted.primal, neutral.primal, "heavier primal weighting grows the primal block")
        XCTAssertGreaterThan(weighted.strength, weighted.primal, "strength still leads even under heavy primal weighting")
        XCTAssertEqual(weighted.mobility, neutral.mobility, accuracy: 1e-9, "weighting does not touch the mobility accessory")
        XCTAssertEqual(weighted.strength + weighted.mobility + weighted.primal, 1.0, accuracy: 1e-9)
    }

    /// Short and full blends keep folding primal into strength - their weights carry no primal share,
    /// so nothing downstream changes for them (no regression).
    func testShortAndFullBlendsCarryNoPrimalShare() {
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        XCTAssertEqual(weights(plan(.blendLight, logs: logs, sitsLong: false)).primal, 0, accuracy: 1e-9)
        XCTAssertEqual(weights(plan(.blendFull, logs: logs, sitsLong: false)).primal, 0, accuracy: 1e-9)
    }

    // MARK: - Determinism

    func testSelectionIsDeterministic() {
        let logs = [
            log(pillars: [.strength], daysAgo: 2),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        let first = plan(.singleFocus, logs: logs, sitsLong: true)
        for _ in 0..<50 {
            XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), first)
        }
    }
}
