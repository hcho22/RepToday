import Foundation

/// The deterministic, never-user-selectable `PhaseEvaluator` (US-H02): the rule that decides
/// whether a user has *earned* the Strength Phase, so Strength is a consequence of demonstrated
/// behavior, never a setting the user flips.
///
/// Every user starts in the **Discipline Phase** (showing up is the only goal). The Strength Phase
/// is earned only when *both* of two independent signals hold - one about **consistency** (the
/// habit is real) and one about **competence** (the body has demonstrably progressed):
///
/// - **Consistency** - the forgiving Consistency Score (US-H01) has been *sustained* above
///   `consistencyThreshold` (80) over a rolling `sustainedWeeks` window (~8 weeks). Because the
///   score is itself a recency-weighted rolling average, a single strong week cannot clear the bar:
///   the user must also have been active across the full window (`activeWeekSpan >= sustainedWeeks`),
///   so "sustained over ~8 weeks" is real, not a hot streak.
/// - **Competence** - the user has cleared the **entry tier** of each foundational movement pattern
///   (`push` / `squat` / `hinge` / `core`). "Cleared" reuses the exact `AdvancementCriteria`
///   mechanism Step 5 uses to advance a chain: a logged, non-skipped performance met the entry
///   movement's advancement criteria. A pattern with several chains needs only one chain's entry
///   cleared - demonstrating a real push / squat / hinge / core, not every variation.
///
/// Consistency-only (a faithful shower-upper who has not progressed the foundations) or
/// competence-only (a strong-but-inconsistent user) both stay `.discipline`, as does a fresh user.
/// The promotion is framed to the user as a gradual, honest ramp - stewardship of a habit they
/// built, never a reward withheld and never a failure - but that framing lives in the surfacing
/// copy; the evaluator itself is a clean deterministic AND of the two signals.
///
/// Like `ConsistencyScore`, this is a pure function of its inputs - `asOf` is injected, never a
/// wall-clock read - so it is fully deterministic and unit-testable. The concrete
/// `PhaseServiceProtocol` implementation (`PhaseEvaluatorService`) reads the clock once at the
/// boundary and supplies the validated library, delegating every decision here.
enum PhaseEvaluator {

    // MARK: - Tuning constants

    /// The Consistency Score (0-100) the user must sustain to satisfy the consistency signal.
    static let consistencyThreshold = 80.0

    /// How many weeks of history the consistency signal must span before it counts as *sustained*.
    /// Matched to the Consistency Score's own rolling window so the score reflects a full window of
    /// behavior rather than one strong week.
    static let sustainedWeeks = ConsistencyScore.recentWeeksWindow

    /// The foundational movement patterns whose entry tiers gate competence. Deliberately the four
    /// fundamentals (push / squat / hinge / core) - not mobility or locomotion, which are variety,
    /// not strength foundations.
    static let foundationalPatterns: [MovementPattern] = [.push, .squat, .hinge, .core]

    // MARK: - Evaluation

    /// The phase the user has *earned* as of `asOf`, computed purely from their `logs` and the
    /// validated `library`. Returns `.strength` only when both the consistency and the competence
    /// signals hold; every other case (consistency-only, competence-only, or a fresh user) resolves
    /// to `.discipline`.
    ///
    /// `weeklyGoal` is the user's target sessions per week (defaulting to the Consistency Score's
    /// own default and clamped there); it feeds the consistency computation so the threshold is
    /// measured against the same adherence the user sees.
    static func evaluate(
        logs: [WorkoutLog],
        weeklyGoal: Int = ConsistencyScore.defaultWeeklyGoal,
        library: [Exercise],
        asOf: Date,
        calendar: Calendar = .current
    ) -> Phase {
        let consistent = hasSustainedConsistency(
            logs: logs,
            weeklyGoal: weeklyGoal,
            asOf: asOf,
            calendar: calendar
        )
        let competent = hasFoundationalCompetence(logs: logs, library: library)
        return (consistent && competent) ? .strength : .discipline
    }

    // MARK: - Consistency signal

    /// Whether the Consistency Score has been sustained above `consistencyThreshold` across a full
    /// `sustainedWeeks` window. Both must hold: the current score clears the bar *and* the user has
    /// been active across the whole window, so a single perfect week (which the window-starts-at-
    /// first-activity rule would score at 100) cannot masquerade as sustained consistency.
    private static func hasSustainedConsistency(
        logs: [WorkoutLog],
        weeklyGoal: Int,
        asOf: Date,
        calendar: Calendar
    ) -> Bool {
        guard activeWeekSpan(logs: logs, asOf: asOf, calendar: calendar) >= sustainedWeeks else {
            return false
        }
        let consistency = ConsistencyScore.evaluate(
            logs: logs,
            weeklyGoal: weeklyGoal,
            asOf: asOf,
            calendar: calendar
        )
        return consistency.score >= consistencyThreshold
    }

    /// The number of whole weeks from the user's first logged activity through `asOf`, inclusive
    /// (1 when all activity is in the current week). Future-dated logs are ignored so a clock skew
    /// cannot inflate the span. `0` when there is no activity at all.
    private static func activeWeekSpan(
        logs: [WorkoutLog],
        asOf: Date,
        calendar: Calendar
    ) -> Int {
        let weekOffsets = logs
            .map { weeksAgo($0.completedAt, from: asOf, calendar) }
            .filter { $0 >= 0 }
        guard let oldest = weekOffsets.max() else { return 0 }
        return oldest + 1
    }

    // MARK: - Competence signal

    /// Whether the user has cleared the entry tier of *every* foundational pattern - the AND across
    /// push / squat / hinge / core that competence requires.
    private static func hasFoundationalCompetence(logs: [WorkoutLog], library: [Exercise]) -> Bool {
        foundationalPatterns.allSatisfy { pattern in
            hasClearedEntryTier(of: pattern, logs: logs, library: library)
        }
    }

    /// Whether the user has cleared the entry tier of at least one chain in `pattern`. A pattern may
    /// hold several chains (e.g. push has a horizontal and a vertical chain); clearing any one
    /// chain's entry demonstrates the fundamental, so only one is required.
    private static func hasClearedEntryTier(
        of pattern: MovementPattern,
        logs: [WorkoutLog],
        library: [Exercise]
    ) -> Bool {
        let chains = Dictionary(
            grouping: library.filter { $0.movementPattern == pattern },
            by: \.progressionChainId
        )
        return chains.values.contains { members in
            guard let entry = members.min(by: { $0.progressionOrder < $1.progressionOrder }) else {
                return false
            }
            return hasCleared(entry, logs: logs)
        }
    }

    /// Whether any logged, non-skipped performance of `entry` met its advancement criteria - the
    /// same `AdvancementCriteria` check Step 5 uses to decide a chain advance, so competence and
    /// progression can never disagree about what "cleared a tier" means. Unparseable criteria are
    /// never met (the user simply stays on the tier), matching Step 5.
    private static func hasCleared(_ entry: Exercise, logs: [WorkoutLog]) -> Bool {
        guard let criteria = AdvancementCriteria(parsing: entry.advancementCriteria) else {
            return false
        }
        return logs.contains { log in
            log.exercises.contains { logged in
                logged.exerciseId == entry.id
                    && !logged.skipped
                    && criteria.isMet(by: logged, isHold: entry.isHold)
            }
        }
    }

    // MARK: - Week math

    /// Whole weeks between `date` and `asOf` (0 = same week), mirroring `ConsistencyScore` so the
    /// span and the score agree on week boundaries. Negative for a future-dated log (callers discard).
    private static func weeksAgo(_ date: Date, from asOf: Date, _ calendar: Calendar) -> Int {
        let from = startOfWeek(date, calendar)
        let to = startOfWeek(asOf, calendar)
        return calendar.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0
    }

    private static func startOfWeek(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Service

/// The real `PhaseServiceProtocol` implementation backing the app, replacing `MockPhaseService`
/// (US-H02). It reads the wall clock exactly once per call and supplies the validated exercise
/// library, delegating the entire decision to the pure, deterministic `PhaseEvaluator`.
final class PhaseEvaluatorService: PhaseServiceProtocol {

    /// Supplies the validated catalog the competence signal needs to resolve each foundational
    /// pattern's entry tier and its advancement criteria.
    private let exerciseService: any ExerciseServiceProtocol

    /// A clock seam so the service stays deterministic under test; production uses `Date.init`.
    private let now: () -> Date
    private let calendar: Calendar

    init(
        exerciseService: any ExerciseServiceProtocol,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.exerciseService = exerciseService
        self.now = now
        self.calendar = calendar
    }

    func phase(for user: User, recentLogs: [WorkoutLog]) async throws -> Phase {
        let library = try await exerciseService.exercises()
        return PhaseEvaluator.evaluate(
            logs: recentLogs,
            weeklyGoal: user.consistency.weeklyGoal,
            library: library,
            asOf: now(),
            calendar: calendar
        )
    }
}
