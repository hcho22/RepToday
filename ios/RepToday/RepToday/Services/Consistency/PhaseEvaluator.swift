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
    /// The decision is *derived from* `progress(...)` rather than computed alongside it, so the gate
    /// and any surface that shows the climb toward it (US-SP04) provably read one source: a
    /// `PhaseProgress` whose `hasEarnedStrength` is exactly this `== .strength` outcome.
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
        progress(
            logs: logs,
            weeklyGoal: weeklyGoal,
            library: library,
            asOf: asOf,
            calendar: calendar
        ).hasEarnedStrength ? .strength : .discipline
    }

    /// The component earn signals the gate decides on, exposed as a value type so a read-only
    /// surface (US-SP04) can show the climb toward the Strength Phase from the *exact same* logic
    /// that gates it - never a parallel re-derivation that could disagree. `evaluate(...)` above is
    /// the sole authority for the boolean outcome, and it is literally
    /// `progress(...).hasEarnedStrength`, so the two can never drift.
    static func progress(
        logs: [WorkoutLog],
        weeklyGoal: Int = ConsistencyScore.defaultWeeklyGoal,
        library: [Exercise],
        asOf: Date,
        calendar: Calendar = .current
    ) -> PhaseProgress {
        let activeWeeks = activeWeekSpan(logs: logs, asOf: asOf, calendar: calendar)
        let score = ConsistencyScore.evaluate(
            logs: logs,
            weeklyGoal: weeklyGoal,
            asOf: asOf,
            calendar: calendar
        ).score
        let foundations = foundationalPatterns.map { pattern in
            PhaseProgress.FoundationProgress(
                pattern: pattern,
                isCleared: hasClearedEntryTier(of: pattern, logs: logs, library: library)
            )
        }
        return PhaseProgress(
            activeWeeks: activeWeeks,
            requiredWeeks: sustainedWeeks,
            currentScore: score,
            scoreThreshold: consistencyThreshold,
            foundations: foundations
        )
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

// MARK: - Component progress

/// The two Strength-Phase earn signals broken into their component values, so a read-only surface
/// (US-SP04, "the visible climb") can show a Discipline-Phase user how close they are *without*
/// re-deriving anything the gate does not. `PhaseEvaluator.evaluate(...)` is literally
/// `PhaseEvaluator.progress(...).hasEarnedStrength`, so the number the surface shows and the
/// decision the gate makes are the same computation - they cannot disagree.
///
/// The stored fields are exactly what the evaluator measures; the derived booleans below are the
/// same combinations the gate is built from (span-and-score for consistency, all-cleared for
/// competence). Presentation - copy, ordering, rounding - lives entirely in the view; this stays a
/// pure, `Equatable` value.
struct PhaseProgress: Equatable {

    /// Per-foundation clear state, one entry per `PhaseEvaluator.foundationalPatterns` in that order.
    struct FoundationProgress: Equatable, Identifiable {
        let pattern: MovementPattern
        /// Whether the user has cleared the entry tier of at least one chain in `pattern` - the exact
        /// `PhaseEvaluator` competence test, reused rather than recomputed.
        let isCleared: Bool

        var id: MovementPattern { pattern }
    }

    /// Whole weeks from the user's first logged activity through now (0 for a user with no history) -
    /// the evaluator's `activeWeekSpan`.
    let activeWeeks: Int

    /// The full window the consistency signal must span before it counts as sustained
    /// (`PhaseEvaluator.sustainedWeeks`, ~8).
    let requiredWeeks: Int

    /// The current forgiving Consistency Score (0-100) the same `ConsistencyScore.evaluate` feeds the
    /// gate.
    let currentScore: Double

    /// The score the current score must clear for the consistency signal (`consistencyThreshold`, 80).
    let scoreThreshold: Double

    /// The four foundational patterns and whether each entry tier is cleared, in evaluator order.
    let foundations: [FoundationProgress]

    // MARK: Derived (the gate's own combinations)

    /// Weeks of steady practice to surface, capped at the required window so the display never reads
    /// "9 of 8". A user past the window shows the full `requiredWeeks`.
    var weeksSustained: Int { min(activeWeeks, requiredWeeks) }

    /// Whether the current score currently clears the bar (one half of the consistency signal).
    var meetsScoreThreshold: Bool { currentScore >= scoreThreshold }

    /// The consistency signal exactly as the gate reads it: active across the full window *and* the
    /// score clears the bar.
    var hasSustainedConsistency: Bool { activeWeeks >= requiredWeeks && meetsScoreThreshold }

    /// How many foundations are cleared, for the "N of 4" headline.
    var clearedFoundationCount: Int { foundations.filter(\.isCleared).count }

    /// The total foundations gating competence (four: push / squat / hinge / core).
    var foundationCount: Int { foundations.count }

    /// The competence signal exactly as the gate reads it: every foundation cleared.
    var hasFoundationalCompetence: Bool { foundations.allSatisfy(\.isCleared) }

    /// The earned outcome - the sole thing `PhaseEvaluator.evaluate(...)` derives its `.strength`
    /// return from, so this boolean and the gate's decision are one computation.
    var hasEarnedStrength: Bool { hasSustainedConsistency && hasFoundationalCompetence }
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

    func progress(for user: User, recentLogs: [WorkoutLog]) async throws -> PhaseProgress {
        let library = try await exerciseService.exercises()
        return PhaseEvaluator.progress(
            logs: recentLogs,
            weeklyGoal: user.consistency.weeklyGoal,
            library: library,
            asOf: now(),
            calendar: calendar
        )
    }
}
