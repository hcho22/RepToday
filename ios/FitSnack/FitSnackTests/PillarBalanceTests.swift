import XCTest
@testable import FitSnack

/// Tests pipeline Step 2 of the deterministic engine (US-C02): balancing the training pillars
/// by staleness.
///
/// Two halves: `PillarStaleness` tests pin the days-since-worked computation read back from
/// logs (most-recent wins, skips don't count, never-worked is nil); the `PillarPlan.select`
/// tests pin single-focus selection (stalest pillar, the desk-worker mobility lean and its
/// strong-staleness exception, the documented no-history defaults) and blend weighting (time
/// split by relative staleness, both pillars always included).
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

    // MARK: - Single-focus selection

    /// The validation test: strength worked yesterday, mobility six days ago, 10-min single
    /// focus -> the stalest pillar (mobility), regardless of the desk-sitting signal.
    func testSingleFocusPicksStalestPillar() {
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: false), .single(.mobility))
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.mobility))
    }

    func testSingleFocusPicksStrengthWhenStrengthIsStalest() {
        let logs = [
            log(pillars: [.strength], daysAgo: 6),
            log(pillars: [.mobility], daysAgo: 1),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: false), .single(.strength))
    }

    /// No desk-sitting signal: equal staleness is a tie that defaults to strength.
    func testSingleFocusTieDefaultsToStrengthWhenNotSitsLong() {
        let logs = [log(pillars: [.strength, .mobility], daysAgo: 3)]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: false), .single(.strength))
    }

    /// Desk worker: equal staleness breaks toward mobility for same-day relief.
    func testSingleFocusTieBreaksToMobilityWhenSitsLong() {
        let logs = [log(pillars: [.strength, .mobility], daysAgo: 3)]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.mobility))
    }

    /// Desk worker, short session: leans mobility even when strength is somewhat staler, as
    /// long as strength has not crossed the strong-staleness threshold.
    func testSitsLongLeansMobilityWhenStrengthNotStronglyStale() {
        let logs = [
            log(pillars: [.strength], daysAgo: 3), // staler than mobility, but < threshold (5)
            log(pillars: [.mobility], daysAgo: 1),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.mobility))
    }

    /// Once strength crosses the strong-staleness threshold, it reclaims the session from the
    /// desk-worker mobility lean.
    func testSitsLongYieldsToStronglyStaleStrength() {
        let logs = [
            log(pillars: [.strength], daysAgo: 6), // >= threshold (5) and staler than mobility
            log(pillars: [.mobility], daysAgo: 1),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.strength))
    }

    /// Strongly-stale strength still yields when mobility is even staler.
    func testStronglyStaleStrengthStillYieldsToStalerMobility() {
        let logs = [
            log(pillars: [.strength], daysAgo: 6),
            log(pillars: [.mobility], daysAgo: 8),
        ]
        XCTAssertEqual(plan(.singleFocus, logs: logs, sitsLong: true), .single(.mobility))
    }

    func testNoHistoryDefaultsToMobilityWhenSitsLong() {
        XCTAssertEqual(plan(.singleFocus, logs: [], sitsLong: true), .single(.mobility))
    }

    func testNoHistoryDefaultsToStrengthWhenNotSitsLong() {
        XCTAssertEqual(plan(.singleFocus, logs: [], sitsLong: false), .single(.strength))
    }

    // MARK: - Blend weighting

    func testBlendWithNoHistorySplitsEvenly() {
        let weights = weights(plan(.blendFull, logs: [], sitsLong: false))
        XCTAssertEqual(weights.strength, 0.5, accuracy: 1e-9)
        XCTAssertEqual(weights.mobility, 0.5, accuracy: 1e-9)
    }

    func testBlendLeansTowardTheStalerPillar() {
        // Mobility 6 days stale, strength 1: mobility takes the larger (clamped) share.
        let logs = [
            log(pillars: [.strength], daysAgo: 1),
            log(pillars: [.mobility], daysAgo: 6),
        ]
        let weights = weights(plan(.blendFull, logs: logs, sitsLong: false))
        XCTAssertEqual(weights.mobility, 0.7, accuracy: 1e-9)
        XCTAssertEqual(weights.strength, 0.3, accuracy: 1e-9)
    }

    func testBlendNeverStarvesAPillar() {
        // Strength never worked, mobility worked today: strength leans heavy but mobility
        // still keeps its floor share - both pillars are always trained.
        let logs = [log(pillars: [.mobility], daysAgo: 0)]
        let weights = weights(plan(.blendFull, logs: logs, sitsLong: false))
        XCTAssertEqual(weights.strength, 0.7, accuracy: 1e-9)
        XCTAssertEqual(weights.mobility, 0.3, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(weights.strength, PillarPlan.minBlendShare)
        XCTAssertGreaterThanOrEqual(weights.mobility, PillarPlan.minBlendShare)
        XCTAssertEqual(weights.strength + weights.mobility, 1.0, accuracy: 1e-9)
    }

    /// Blend weighting is purely staleness-driven; the desk-sitting signal does not move it
    /// (the mobility lean is a single-focus rule only).
    func testBlendIgnoresSitsLong() {
        let logs = [log(pillars: [.strength, .mobility], daysAgo: 4)]
        XCTAssertEqual(
            weights(plan(.blendFull, logs: logs, sitsLong: true)),
            weights(plan(.blendFull, logs: logs, sitsLong: false))
        )
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
