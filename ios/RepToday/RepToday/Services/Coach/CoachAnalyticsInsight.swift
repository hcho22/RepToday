import Foundation

/// The on-device, deterministic half of "the coach narrates the analytics and offers to act"
/// (US-AN02). It turns the premium **strength-journey analytics** (US-AN01) into two things the coach
/// surface can use without any model in the loop: a per-pattern *trend* read (climbing / flat /
/// steady) the context bundle carries so the Coach model can narrate a concrete insight, and a bounded
/// **preference-only** offer that, when accepted, routes through the exact US-AC07 policy-write path.
///
/// It is the deliberate sibling of `CoachIntentMapper` (tuning) and `CoachInjurySignalMapper`
/// (injury routing): a pure, closed, testable function of already-computed values, whose *output
/// type* is the contract. The narration (the exact prose) is model-authored and captain-verifiable
/// manual QA; the classification and the offered action are what the unit suite pins.
///
/// **Why an offer, not an edit.** The only action the coach can take from an insight is a
/// `CoachPolicyProposal` that *emphasizes* the stalled pattern - the same closed, preference-only
/// shape the tuning path uses, which cannot express a workout edit or a safety filter by
/// construction. So "the data changes behavior, never a direct workout edit" is a property of the
/// data model, exactly as US-AC07/AC08 made it.

// MARK: - Per-pattern trend

/// One foundational pattern's coarse trajectory on its active chain (US-AN02), classified from the
/// dated milestones the strength-journey analytics (US-AN01) already produced. Non-identifying: it
/// carries only a pattern, a coarse direction, and a whole-week count - no dates, ids, or history.
struct StrengthPatternTrend: Equatable {

    /// The coarse direction a pattern is moving. Deliberately three states so a freshly-started
    /// pattern does not read as a *stall*: only a pattern that has sat at its frontier for a while
    /// is `flat`, and only a real advancement that landed recently is `climbing`.
    enum Trend: String, Equatable, Encodable {
        /// Advanced at least one tier, and reached the current tier recently.
        case climbing
        /// Has sat at the current frontier tier for at least `CoachStrengthJourneyReader.flatWeeksThreshold` weeks.
        case flat
        /// Trained, but neither a recent advancement nor long enough at the frontier to read as stalled.
        case steady
    }

    let pattern: MovementPattern
    let trend: Trend
    /// Whole weeks the user has sat at the current frontier tier (the "flat for N weeks" number).
    let weeksAtCurrentTier: Int
    /// Whether the user has advanced at least one tier on this chain, ever.
    let hasAdvanced: Bool
}

/// Reads the strength journey into per-pattern trends (US-AN02).
///
/// Pure and deterministic (its `asOf` is injected, never a wall-clock read), so both the context
/// bundle's wire summary and the coach's on-device offer derive from the *same* classification and
/// cannot disagree with each other or with the Progress tab the journey came from.
enum CoachStrengthJourneyReader {

    /// How long a pattern must sit at its frontier tier before it reads as `flat` (a stall worth
    /// naming), matching the "flat about 3 weeks" copy. Below this it is `steady`/`climbing`, so a
    /// pattern trained last week is never reported as stalled.
    static let flatWeeksThreshold = 3

    /// Classify every trained foundational pattern in `journey` as of `asOf`. Untrained patterns are
    /// absent from the journey and so contribute no trend.
    static func trends(from journey: StrengthJourney, asOf: Date, calendar: Calendar) -> [StrengthPatternTrend] {
        journey.chains.compactMap { chain in
            guard let current = chain.currentMilestone else { return nil }
            let weeks = max(
                0,
                calendar.dateComponents([.weekOfYear], from: current.firstReachedAt, to: asOf).weekOfYear ?? 0
            )
            let trend: StrengthPatternTrend.Trend
            if weeks >= flatWeeksThreshold {
                // Stuck at the frontier long enough to be a real stall, regardless of whether the
                // user ever climbed to get here.
                trend = .flat
            } else if chain.hasAdvanced {
                trend = .climbing
            } else {
                trend = .steady
            }
            return StrengthPatternTrend(
                pattern: chain.pattern,
                trend: trend,
                weeksAtCurrentTier: weeks,
                hasAdvanced: chain.hasAdvanced
            )
        }
    }
}

// MARK: - The offer

/// The coach's analytics-driven action offer (US-AN02): a bounded, preference-only nudge that
/// **emphasizes the stalled pattern**, raised when the strength journey shows a real stall.
///
/// Like `CoachInjuryRoutingProposal` it is an *offer*, not a change: it carries the pattern to lean
/// toward and, for the narration, the pattern that is climbing - and the only action it can produce
/// is a `CoachPolicyProposal` (the US-AC07 preference-only shape). A workout edit and a safety filter
/// are both inexpressible on that path by construction.
struct CoachAnalyticsInsightOffer: Equatable {
    /// The foundational pattern that has stalled and that the offer would emphasize.
    let stalledPattern: MovementPattern
    /// How many whole weeks it has sat at its frontier tier - the "flat about N weeks" number.
    let stalledWeeks: Int
    /// A pattern that is climbing, if any, so the coach can name the gain beside the stall ("your
    /// push is climbing, your hinge has been flat"). `nil` when nothing is clearly climbing.
    let climbingPattern: MovementPattern?

    /// The bounded, preference-only proposal accepting this offer applies - through the *same*
    /// US-AC07 write path (`CoachSessionPolicyService`), so the write is clamped, direction-safe,
    /// noted honestly, and never a workout edit. The raw value is a firm nudge; the write path clamps
    /// it to `SessionPolicy.maxEmphasis` regardless.
    var proposal: CoachPolicyProposal {
        CoachPolicyProposal(patternEmphasis: [stalledPattern: CoachAnalyticsInsight.emphasizeValue])
    }
}

/// Builds the analytics insight offer and recognizes a progress inquiry (US-AN02). Pure, closed, and
/// deterministic - the same discipline as the other coach mappers.
enum CoachAnalyticsInsight {

    /// A firm-but-in-range "lean into this pattern" emphasis, mirroring `CoachIntentMapper`'s
    /// more-emphasis nudge. The US-AC07 write path clamps every value to `SessionPolicy.maxEmphasis`,
    /// so this stays a nudge rather than a dictate however it was produced.
    static let emphasizeValue = 1.6

    /// The offer a set of per-pattern trends maps to, or `nil` when there is no stall worth acting on.
    ///
    /// It fires only on a real stall: the most-stalled `flat` pattern (longest at its frontier; ties
    /// resolve in foundational order - push, squat, hinge, core). A journey with nothing flat raises
    /// no offer, so the surface stays quiet unless the data actually says to change something.
    static func offer(from trends: [StrengthPatternTrend]) -> CoachAnalyticsInsightOffer? {
        let flat = trends.filter { $0.trend == .flat }
        guard let stalled = flat.max(by: { lhs, rhs in
            if lhs.weeksAtCurrentTier != rhs.weeksAtCurrentTier {
                return lhs.weeksAtCurrentTier < rhs.weeksAtCurrentTier
            }
            // Tie: keep the earlier foundational pattern (lower index wins the max as the *later* one
            // "loses"), so ordering is deterministic.
            return foundationalIndex(lhs.pattern) > foundationalIndex(rhs.pattern)
        }) else { return nil }

        let climbing = trends
            .filter { $0.trend == .climbing }
            .min(by: { foundationalIndex($0.pattern) < foundationalIndex($1.pattern) })?
            .pattern

        return CoachAnalyticsInsightOffer(
            stalledPattern: stalled.pattern,
            stalledWeeks: stalled.weeksAtCurrentTier,
            climbingPattern: climbing
        )
    }

    /// Whether `message` reads as a "how am I doing?" progress inquiry - the intent that invites the
    /// coach to narrate the journey and, if there is a stall, offer to act. Deliberately crude and
    /// closed (a small phrase list), matching the other coach mappers: a miss just means the coach
    /// answers without an offer, and the user can ask again.
    static func isProgressInquiry(_ message: String) -> Bool {
        let text = message.lowercased()
        return progressInquiryCues.contains { text.contains($0) }
    }

    // MARK: - Recognized cues

    private static let progressInquiryCues = [
        "how am i doing", "how'm i doing", "how am i progressing", "how am i tracking",
        "how's my progress", "how is my progress", "hows my progress",
        "am i improving", "am i getting better", "am i making progress",
        "how are my numbers", "how's my strength", "how is my strength",
        "my progress so far", "progress report",
    ]

    // MARK: - Ordering

    /// The four foundational patterns, in the same display order the evaluator and analytics use.
    private static let foundationalOrder: [MovementPattern] = [.push, .squat, .hinge, .core]

    private static func foundationalIndex(_ pattern: MovementPattern) -> Int {
        foundationalOrder.firstIndex(of: pattern) ?? foundationalOrder.count
    }
}
