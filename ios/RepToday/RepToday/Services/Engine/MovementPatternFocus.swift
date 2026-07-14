import Foundation

/// Pipeline Step 3 of the deterministic engine (US-C03): within the pillar Step 2 chose, pick
/// the movement pattern the session leads with, so the user gets variety instead of grinding
/// the same pattern every time.
///
/// Step 2 decides *which pillar*; Step 3 decides *which pattern inside it*. Patterns are ranked
/// by staleness (days-since-last-worked, read back from `recentLogs`) so the most neglected
/// pattern surfaces first, and the lead pattern of the user's most recent session is held back
/// so it is never repeated back-to-back. Like the earlier steps this is a pure function of the
/// logs and a caller-supplied reference date (`asOf`) - no hidden clock - so it stays
/// deterministic and unit-testable, mirroring `PillarBalance`.
///
/// The caller supplies `candidatePatterns`: the patterns actually present in the chosen
/// pillar's pool (push/squat/hinge/core/pull for strength; just mobility for Movement Practice;
/// just locomotion for primal). Keeping that list an input rather than re-deriving the
/// pillar -> pattern map here keeps the step decoupled from the exercise library, exactly as
/// Step 2 takes the shape and logs as inputs.

// MARK: - PatternStaleness

/// Days since each movement pattern was last worked, derived from completed (non-skipped)
/// exercises in `recentLogs`. A pattern absent from `daysSinceWorked` was never worked in the
/// supplied logs; callers treat that as maximally stale.
///
/// This mirrors `PillarStaleness` (Step 2) keyed by `MovementPattern` instead of `Pillar`:
/// only completed work counts, the most recent session wins, and day counts are calendar-day
/// differences (worked yesterday -> 1), not raw elapsed time.
struct PatternStaleness: Equatable {
    /// Per-pattern days since last worked. An absent key means "never worked in `recentLogs`".
    let daysSinceWorked: [MovementPattern: Int]

    init(recentLogs: [WorkoutLog], asOf: Date, calendar: Calendar = .current) {
        var lastWorked: [MovementPattern: Date] = [:]
        for log in recentLogs {
            let workedPatterns = Set(
                log.exercises.filter { !$0.skipped }.map(\.movementPattern)
            )
            for pattern in workedPatterns {
                if let existing = lastWorked[pattern], existing >= log.completedAt {
                    continue
                }
                lastWorked[pattern] = log.completedAt
            }
        }

        let today = calendar.startOfDay(for: asOf)
        var days: [MovementPattern: Int] = [:]
        for (pattern, date) in lastWorked {
            let elapsed = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: today
            ).day ?? 0
            days[pattern] = max(0, elapsed)
        }
        self.daysSinceWorked = days
    }

    /// Days since `pattern` was last worked, or `nil` if it was never worked in the logs.
    func days(for pattern: MovementPattern) -> Int? {
        daysSinceWorked[pattern]
    }

    /// Whether `a` is strictly staler than `b`, treating "never worked" (`nil`) as the most
    /// stale value of all. Mirrors `PillarStaleness.isStaler`.
    static func isStaler(_ a: Int?, than b: Int?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (lhs?, rhs?): return lhs > rhs
        }
    }
}

// MARK: - PatternFocus

/// Selects the movement pattern a session leads with (pipeline Step 3).
enum PatternFocus {

    /// How recently a session must have completed for its lead pattern to be held back from
    /// selection. 1 -> the most recent session, if it landed today or yesterday, does not get
    /// its lead pattern repeated; an older session imposes no such restriction. Tunable.
    static let noRepeatWindowDays = 1

    /// Ranks `candidatePatterns` stalest-first for the given log history.
    ///
    /// Ties (equal staleness, including several never-worked patterns) break by the canonical
    /// `MovementPattern.allCases` order, so the ranking is fully deterministic and independent
    /// of the order the caller happened to pass `candidatePatterns` in.
    static func rank(
        candidatePatterns: [MovementPattern],
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar = .current
    ) -> [MovementPattern] {
        let staleness = PatternStaleness(recentLogs: recentLogs, asOf: asOf, calendar: calendar)
        return candidatePatterns.sorted { lhs, rhs in
            let lhsDays = staleness.days(for: lhs)
            let rhsDays = staleness.days(for: rhs)
            if PatternStaleness.isStaler(lhsDays, than: rhsDays) { return true }
            if PatternStaleness.isStaler(rhsDays, than: lhsDays) { return false }
            return canonicalIndex(lhs) < canonicalIndex(rhs)
        }
    }

    /// Picks the single movement pattern Step 3 leads with, or `nil` when no pattern is
    /// available (an empty candidate set).
    ///
    /// The stalest candidate wins, except:
    /// - An `explicitlyRequested` pattern that is a valid candidate is always honored (the user
    ///   asked for it), overriding both staleness and the no-repeat rule.
    /// - Otherwise the lead pattern of the user's most recent session is held back when that
    ///   session is within `noRepeatWindowDays`, so the user does not repeat it back-to-back -
    ///   unless it is the only candidate, in which case it is still returned (variety can't
    ///   trump having a session at all).
    static func select(
        candidatePatterns: [MovementPattern],
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar = .current,
        explicitlyRequested: MovementPattern? = nil
    ) -> MovementPattern? {
        guard !candidatePatterns.isEmpty else { return nil }

        if let requested = explicitlyRequested, candidatePatterns.contains(requested) {
            return requested
        }

        let ranked = rank(
            candidatePatterns: candidatePatterns,
            recentLogs: recentLogs,
            asOf: asOf,
            calendar: calendar
        )
        let blocked = recentLeadPattern(
            among: candidatePatterns,
            recentLogs: recentLogs,
            asOf: asOf,
            calendar: calendar
        )
        return ranked.first { $0 != blocked } ?? ranked.first
    }

    // MARK: Helpers

    /// The lead pattern (the first completed exercise whose pattern is a candidate) of the
    /// user's most recent session, but only when that session completed within
    /// `noRepeatWindowDays`. This is the pattern `select` holds back for variety. Returns `nil`
    /// when there is no recent-enough session, or it led with no candidate pattern.
    ///
    /// Restricting the lead pattern to `candidatePatterns` makes the rule pillar-aware: a strength
    /// session ignores yesterday's mobility warm-up and keys off yesterday's first *strength*
    /// pattern instead.
    private static func recentLeadPattern(
        among candidatePatterns: [MovementPattern],
        recentLogs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar
    ) -> MovementPattern? {
        let today = calendar.startOfDay(for: asOf)
        let pastLogs = recentLogs.filter { calendar.startOfDay(for: $0.completedAt) <= today }
        guard let latest = pastLogs.max(by: { $0.completedAt < $1.completedAt }) else {
            return nil
        }
        let daysAgo = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: latest.completedAt),
            to: today
        ).day ?? 0
        guard daysAgo <= noRepeatWindowDays else { return nil }

        let candidates = Set(candidatePatterns)
        return latest.exercises.first {
            !$0.skipped && candidates.contains($0.movementPattern)
        }?.movementPattern
    }

    /// Position of `pattern` in the canonical `MovementPattern.allCases` order, the deterministic
    /// tie-break for equally-stale patterns.
    private static func canonicalIndex(_ pattern: MovementPattern) -> Int {
        MovementPattern.allCases.firstIndex(of: pattern) ?? MovementPattern.allCases.count
    }
}
