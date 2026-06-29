import XCTest
@testable import FitSnack

/// Tests pipeline Step 3 of the deterministic engine (US-C03): focusing the session on a
/// movement pattern.
///
/// Two halves: `PatternStaleness` tests pin the per-pattern days-since-worked computation read
/// back from logs (most-recent wins, skips don't count, never-worked is nil); the `PatternFocus`
/// tests pin ranking (stalest-first, never-worked most stale, canonical tie-break) and selection
/// (the no-repeat-yesterday rule, the explicit-request override, the documented no-history
/// default, and the single-candidate fallback).
final class MovementPatternFocusTests: XCTestCase {

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

    /// A log completing `daysAgo` whose worked exercises follow `patterns` in order (so the
    /// first entry is the session's lead pattern). All are skipped when `skipped` is true.
    private func log(patterns: [MovementPattern], daysAgo: Int, skipped: Bool = false) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            workoutId: UUID(),
            completedAt: date(daysAgo: daysAgo),
            durationMinutes: 10,
            shape: .singleFocus,
            focusPillar: .strength,
            perceivedDifficulty: nil,
            exercises: patterns.map { pattern in
                LoggedExercise(
                    id: UUID(),
                    exerciseId: "ex-\(pattern.rawValue)-\(daysAgo)",
                    pillar: pattern == .mobility ? .mobility : .strength,
                    movementPattern: pattern,
                    completedSets: [CompletedSet(reps: 10, durationSeconds: nil)],
                    skipped: skipped
                )
            }
        )
    }

    private func staleness(_ logs: [WorkoutLog]) -> PatternStaleness {
        PatternStaleness(recentLogs: logs, asOf: asOf, calendar: calendar)
    }

    private func select(
        _ candidates: [MovementPattern],
        logs: [WorkoutLog],
        explicitlyRequested: MovementPattern? = nil
    ) -> MovementPattern? {
        PatternFocus.select(
            candidatePatterns: candidates,
            recentLogs: logs,
            asOf: asOf,
            calendar: calendar,
            explicitlyRequested: explicitlyRequested
        )
    }

    private func rank(_ candidates: [MovementPattern], logs: [WorkoutLog]) -> [MovementPattern] {
        PatternFocus.rank(candidatePatterns: candidates, recentLogs: logs, asOf: asOf, calendar: calendar)
    }

    /// The patterns present in the strength pillar's pool.
    private let strengthPatterns: [MovementPattern] = [.push, .squat, .hinge, .core, .pull]

    // MARK: - PatternStaleness

    func testEmptyHistoryHasNoStaleness() {
        let staleness = staleness([])
        XCTAssertNil(staleness.days(for: .push))
        XCTAssertNil(staleness.days(for: .squat))
    }

    func testDaysSinceWorkedPerPattern() {
        // The validation-test setup: push worked yesterday, squat five days ago.
        let staleness = staleness([
            log(patterns: [.push], daysAgo: 1),
            log(patterns: [.squat], daysAgo: 5),
        ])
        XCTAssertEqual(staleness.days(for: .push), 1)
        XCTAssertEqual(staleness.days(for: .squat), 5)
        XCTAssertNil(staleness.days(for: .hinge))
    }

    func testMostRecentSessionWins() {
        let staleness = staleness([
            log(patterns: [.push], daysAgo: 6),
            log(patterns: [.push], daysAgo: 2),
        ])
        XCTAssertEqual(staleness.days(for: .push), 2)
    }

    func testSkippedExerciseDoesNotCountAsWorked() {
        let staleness = staleness([log(patterns: [.push], daysAgo: 2, skipped: true)])
        XCTAssertNil(staleness.days(for: .push))
    }

    func testIsStalerTreatsNeverWorkedAsMostStale() {
        XCTAssertTrue(PatternStaleness.isStaler(nil, than: 3))
        XCTAssertFalse(PatternStaleness.isStaler(3, than: nil))
        XCTAssertFalse(PatternStaleness.isStaler(nil, than: nil))
        XCTAssertTrue(PatternStaleness.isStaler(5, than: 1))
        XCTAssertFalse(PatternStaleness.isStaler(1, than: 5))
        XCTAssertFalse(PatternStaleness.isStaler(3, than: 3))
    }

    // MARK: - Ranking

    func testRankOrdersStalestFirst() {
        // push 1 day, squat 5 days, hinge 3 days; the rest never worked (most stale of all).
        let logs = [
            log(patterns: [.push], daysAgo: 1),
            log(patterns: [.squat], daysAgo: 5),
            log(patterns: [.hinge], daysAgo: 3),
        ]
        // Never-worked core/pull lead (canonical order breaks their tie), then squat > hinge > push.
        XCTAssertEqual(rank(strengthPatterns, logs: logs), [.core, .pull, .squat, .hinge, .push])
    }

    func testRankTieBreaksByCanonicalOrderRegardlessOfInputOrder() {
        // No history: every pattern is equally (maximally) stale, so the canonical
        // MovementPattern.allCases order decides - not the order they were passed in.
        XCTAssertEqual(rank([.pull, .core, .push, .squat], logs: []), [.push, .squat, .core, .pull])
    }

    // MARK: - Selection

    /// The validation test: push worked yesterday, squat five days ago -> a strength session
    /// leads with squat (staler) and never repeats yesterday's push.
    func testSelectLeadsWithStalerPatternAndSkipsYesterdays() {
        let logs = [
            log(patterns: [.push], daysAgo: 1),
            log(patterns: [.squat], daysAgo: 5),
        ]
        XCTAssertEqual(select([.push, .squat], logs: logs), .squat)
    }

    /// Isolates the no-repeat rule from staleness: push and squat are equally stale (a tie the
    /// canonical order would hand to push), but push led yesterday's session, so squat wins.
    func testSelectSkipsYesterdaysLeadPatternOnAStalenessTie() {
        let logs = [log(patterns: [.push, .squat], daysAgo: 1)]
        XCTAssertEqual(rank([.push, .squat], logs: logs), [.push, .squat]) // tie -> canonical
        XCTAssertEqual(select([.push, .squat], logs: logs), .squat)        // but push is held back
    }

    /// The no-repeat rule only fires for a recent session; an older lead pattern may repeat.
    func testSelectMayRepeatLeadPatternFromAnOlderSession() {
        let logs = [log(patterns: [.push, .squat], daysAgo: 3)] // outside the no-repeat window
        XCTAssertEqual(select([.push, .squat], logs: logs), .push) // tie -> canonical, not held back
    }

    /// An explicit request is honored even when that pattern led the most recent session.
    func testSelectHonorsExplicitRequestOverNoRepeat() {
        let logs = [log(patterns: [.push, .squat], daysAgo: 1)]
        XCTAssertEqual(select([.push, .squat], logs: logs, explicitlyRequested: .push), .push)
    }

    /// An explicit request for a pattern that is not a candidate is ignored; staleness decides.
    func testSelectIgnoresExplicitRequestOutsideCandidates() {
        XCTAssertEqual(select([.push, .squat], logs: [], explicitlyRequested: .hinge), .push)
    }

    /// Yesterday's mobility warm-up does not block a strength session: the rule keys off the
    /// most recent session's first *candidate* (strength) pattern.
    func testSelectIgnoresNonCandidateLeadFromYesterday() {
        // Yesterday led with a mobility flow, then trained push; today's strength candidates
        // are push/squat. Push is the recent strength lead, so squat is preferred.
        let logs = [log(patterns: [.mobility, .push], daysAgo: 1)]
        XCTAssertEqual(select([.push, .squat], logs: logs), .squat)
    }

    func testSelectWithNoHistoryDefaultsToCanonicalFirst() {
        XCTAssertEqual(select(strengthPatterns, logs: []), .push)
    }

    func testSelectOnEmptyCandidatesReturnsNil() {
        XCTAssertNil(select([], logs: []))
    }

    /// A single-pattern pillar (mobility / primal) returns its only pattern even when it led
    /// the most recent session - having a session beats the variety preference.
    func testSelectReturnsSoleCandidateEvenWhenItLedYesterday() {
        let logs = [log(patterns: [.mobility], daysAgo: 1)]
        XCTAssertEqual(select([.mobility], logs: logs), .mobility)
    }

    // MARK: - Determinism

    func testSelectionIsDeterministic() {
        let logs = [
            log(patterns: [.push], daysAgo: 1),
            log(patterns: [.squat], daysAgo: 5),
        ]
        let first = select(strengthPatterns, logs: logs)
        for _ in 0..<50 {
            XCTAssertEqual(select(strengthPatterns, logs: logs), first)
        }
    }
}
