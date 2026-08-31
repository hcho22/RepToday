import Foundation

/// The **derived context bundle** (US-AC01): the one small, non-identifying summary of the user's
/// on-device state that the premium AI coach is allowed to send off the device. It is the single
/// auditable definition of the *training state* that leaves the phone; the wire adds only the user's
/// message and the separately generated abuse-prevention pseudonym.
///
/// **What it deliberately does NOT contain (privacy by construction):**
/// - No raw `WorkoutLog` history - only summarized, aggregate signals derived from it.
/// - No identity of any kind: no Keychain value, no `installId`, no IDFA / `identifierForVendor`, no
///   Sign in with Apple identifier, no email, no name, no profile (age/sex/height/weight).
/// - No free-text the user did not type as their message (that is carried separately by the client).
///
/// Every field here is either catalog data (movement names/tiers, which are the same for every user)
/// or a coarse aggregate (a rounded score, a pattern list, a phase), none of which can single out a
/// person. The bundle is `Encodable` so the wire body it produces is exactly this shape - the proxy's
/// `/coach` `context` field mirrors it field-for-field (see `proxy/src/worker.js`).
///
/// It is built by `make(...)` from the **same** already-computed values the Progress tab and the
/// `PhaseEvaluator` use (`ProgressAnalytics.chainPositions`, `ConsistencyTrend.trend`, the earned
/// `Phase`), never by a parallel data path - so the summary the coach sees can never disagree with
/// what the app shows the user.
///
/// This story (US-AC01) ships the transport foundation only; the chat surface that assembles and
/// sends the bundle is US-AC02.
struct CoachContextBundle: Encodable, Equatable {

    /// One foundational pattern's position on its progression chain - the same frontier the Progress
    /// tab's chain-position cards show, summarized to non-identifying catalog facts.
    struct ChainSummary: Encodable, Equatable {
        /// The foundational pattern (push / squat / hinge / core).
        let pattern: String
        /// The frontier movement's display name, or `nil` when the pattern has never been trained.
        /// A catalog string shared by every user - not identifying.
        let currentExercise: String?
        /// 1-based tier within the active chain; `0` when not started.
        let tier: Int
        /// Number of tiers in the active chain; `0` when not started.
        let chainLength: Int
        /// Whether a harder tier exists above the frontier (the "next up" the user climbs toward).
        let hasNextTier: Bool
    }

    /// One foundational pattern's coarse strength-journey trend (US-AN02), so the coach can narrate a
    /// concrete "your push is climbing, your hinge has been flat about 3 weeks" insight. Derived from
    /// the same dated milestones the premium strength-journey analytics (US-AN01) show the user, via
    /// `CoachStrengthJourneyReader`, so the coach's read can never disagree with the Progress tab.
    ///
    /// Deliberately coarse and non-identifying: a pattern, a direction, and a whole-week count - never
    /// a date, an exercise id, or a raw milestone (which, paired, would edge back toward history).
    struct JourneySummary: Encodable, Equatable {
        /// The foundational pattern (push / squat / hinge / core).
        let pattern: String
        /// Its coarse trajectory: `climbing`, `flat`, or `steady`.
        let trend: String
        /// Whole weeks sat at the current frontier tier - the "flat about N weeks" number.
        let weeksAtCurrentTier: Int
        /// Whether the user has advanced at least one tier on this chain, ever.
        let hasAdvanced: Bool
    }

    /// The consistency signal, summarized to a coarse current level plus a direction - never the
    /// per-week series (which, paired with dates, edges toward a behavioral fingerprint).
    struct ConsistencySummary: Encodable, Equatable {
        /// Which way the forgiving Consistency Score has moved across the recent window.
        enum Direction: String, Encodable {
            /// No history yet - the coach should not imply a trajectory.
            case new
            case rising
            case steady
            case falling
        }

        /// The current forgiving Consistency Score (0-100), rounded to a whole number.
        let currentScore: Int
        /// The direction of travel across the recent window.
        let direction: Direction
    }

    /// The user's earned phase (`discipline` / `strength`) - governs what the coach can honestly say
    /// is available.
    let phase: String
    /// The minutes the user asked for this session - lets the coach reason about "why this workout"
    /// at the requested length.
    let requestedMinutes: Int
    /// Per-foundation chain positions, in `ProgressAnalytics.foundationalPatterns` order.
    let chainPositions: [ChainSummary]
    /// The distinct movement patterns trained in recent sessions, most-recent-first - so the coach can
    /// reason about staleness/variety without ever seeing a raw log.
    let recentPatterns: [String]
    /// The coarse consistency summary.
    let consistency: ConsistencySummary
    /// Per-foundation strength-journey trend (US-AN02), in `foundationalPatterns` order - so the coach
    /// can narrate a concrete "your push is climbing, your hinge has been flat" insight. Empty when
    /// there is no strength history to read yet.
    let strengthJourney: [JourneySummary]

    /// Builds the bundle from values the app has **already computed** for its own surfaces, rather
    /// than re-deriving anything from raw history - so the coach's view and the user's view are one
    /// computation.
    ///
    /// - Parameters:
    ///   - phase: the user's earned `Phase` (from `PhaseEvaluator`).
    ///   - requestedMinutes: the minutes requested for the session in question.
    ///   - chainPositions: the free-layer chain positions (`ProgressAnalytics.chainPositions`).
    ///   - consistencyTrend: the Consistency Score trajectory (`ConsistencyTrend.trend`), oldest
    ///     first - summarized here to a current level and a direction.
    ///   - recentLogs: recent `WorkoutLog`s, used only to extract the distinct recent movement
    ///     patterns. Nothing from a log other than its patterns and completion order leaves this
    ///     function.
    ///   - strengthJourney: the premium strength-journey analytics (US-AN01,
    ///     `ProgressAnalytics.deep.strengthJourney`) - the same dated climb the Progress tab shows -
    ///     summarized here to a coarse per-pattern trend (US-AN02). Defaults to empty so callers that
    ///     do not narrate the journey (and every persisted-before-US-AN02 shape) are unaffected.
    ///   - asOf: the vantage the journey's "flat for N weeks" is measured from, injected for
    ///     determinism (never a wall-clock read).
    ///   - calendar: the calendar the week counts bucket in, matching the analytics' own.
    ///   - recentPatternLimit: how many distinct recent patterns to keep (default 6).
    static func make(
        phase: Phase,
        requestedMinutes: Int,
        chainPositions: [ChainPositionSummary],
        consistencyTrend: [ConsistencyTrendPoint],
        recentLogs: [WorkoutLog],
        strengthJourney: StrengthJourney = StrengthJourney(chains: []),
        asOf: Date = Date(),
        calendar: Calendar = .current,
        recentPatternLimit: Int = 6
    ) -> CoachContextBundle {
        CoachContextBundle(
            phase: phase.rawValue,
            requestedMinutes: requestedMinutes,
            chainPositions: chainPositions.map { position in
                ChainSummary(
                    pattern: position.pattern.rawValue,
                    currentExercise: position.currentExercise?.displayName,
                    tier: position.tier,
                    chainLength: position.chainLength,
                    hasNextTier: position.hasNextTier
                )
            },
            recentPatterns: distinctRecentPatterns(from: recentLogs, limit: recentPatternLimit),
            consistency: summarize(trend: consistencyTrend),
            strengthJourney: CoachStrengthJourneyReader
                .trends(from: strengthJourney, asOf: asOf, calendar: calendar)
                .map { trend in
                    JourneySummary(
                        pattern: trend.pattern.rawValue,
                        trend: trend.trend.rawValue,
                        weeksAtCurrentTier: trend.weeksAtCurrentTier,
                        hasAdvanced: trend.hasAdvanced
                    )
                }
        )
    }

    /// The distinct movement patterns across `logs`, most-recent-session-first, first occurrence
    /// wins, capped at `limit`. Reads only each log's completion time and its exercises' patterns.
    private static func distinctRecentPatterns(from logs: [WorkoutLog], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        for log in logs.sorted(by: { $0.completedAt > $1.completedAt }) {
            for exercise in log.exercises {
                let pattern = exercise.movementPattern.rawValue
                if seen.insert(pattern).inserted {
                    ordered.append(pattern)
                    if ordered.count >= limit { return ordered }
                }
            }
        }
        return ordered
    }

    /// Collapses the per-week trajectory to a current level and a direction. The direction compares
    /// the earliest and latest points in the window; a single point (or none) reads as no trajectory.
    private static func summarize(trend: [ConsistencyTrendPoint]) -> ConsistencySummary {
        guard let latest = trend.last else {
            return ConsistencySummary(currentScore: 0, direction: .new)
        }
        let current = Int(latest.score.rounded())
        guard let earliest = trend.first, trend.count >= 2 else {
            return ConsistencySummary(currentScore: current, direction: .new)
        }
        // A small band around equality reads as "steady" so a rounding-level wobble is not a trend.
        let delta = latest.score - earliest.score
        let direction: ConsistencySummary.Direction
        if delta > 1 {
            direction = .rising
        } else if delta < -1 {
            direction = .falling
        } else {
            direction = .steady
        }
        return ConsistencySummary(currentScore: current, direction: direction)
    }
}
