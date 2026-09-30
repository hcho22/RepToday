import XCTest
@testable import RepToday

/// Tests US-AN02's on-device decision half: the pure classification that reads the premium
/// strength-journey analytics (US-AN01) into per-pattern trends, and the bounded, preference-only
/// offer it produces. The narration prose is model-authored (captain-verifiable manual QA); what is pinned
/// here is that a flat pattern is recognized as a stall and that the offer it maps to emphasizes that
/// pattern through the US-AC07 proposal shape - never a workout edit.
final class CoachAnalyticsInsightTests: XCTestCase {

    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12))!
    }

    private func date(weeksAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -(weeksAgo * 7), to: asOf)!
    }

    /// A milestone reached `weeksAgo`.
    private func milestone(_ id: String, tier: Int, weeksAgo: Int) -> TierMilestone {
        TierMilestone(exerciseId: id, displayName: id, tier: tier, firstReachedAt: date(weeksAgo: weeksAgo))
    }

    private func chain(_ pattern: MovementPattern, _ milestones: [TierMilestone]) -> ChainJourney {
        ChainJourney(line: StrengthFoundation.line(for: pattern)!, chainId: "\(pattern.rawValue)_chain", milestones: milestones, calendar: calendar)
    }

    private func trends(_ chains: [ChainJourney]) -> [StrengthPatternTrend] {
        CoachStrengthJourneyReader.trends(from: StrengthJourney(chains: chains), asOf: asOf, calendar: calendar)
    }

    // MARK: - Classification

    /// A pattern that advanced and reached its current tier recently reads as *climbing*; one sat at
    /// its frontier past the threshold reads as *flat* even if it climbed to get there.
    func testClassifiesClimbingAndFlat() {
        let push = chain(.push, [
            milestone("push_a", tier: 1, weeksAgo: 5),
            milestone("push_b", tier: 2, weeksAgo: 4),
            milestone("push_c", tier: 3, weeksAgo: 0), // reached this week
        ])
        let hinge = chain(.hinge, [
            milestone("hinge_a", tier: 1, weeksAgo: 6),
            milestone("hinge_b", tier: 2, weeksAgo: 4), // stuck 4 weeks
        ])

        let result = trends([push, hinge])
        let pushTrend = result.first { $0.pattern == .push }
        let hingeTrend = result.first { $0.pattern == .hinge }

        XCTAssertEqual(pushTrend?.trend, .climbing)
        XCTAssertEqual(pushTrend?.weeksAtCurrentTier, 0)
        XCTAssertEqual(hingeTrend?.trend, .flat)
        XCTAssertEqual(hingeTrend?.weeksAtCurrentTier, 4)
        XCTAssertEqual(hingeTrend?.hasAdvanced, true) // climbed once, then stalled
    }

    /// A pattern trained recently but not advanced is *steady* - never reported as a stall just for
    /// being a single tier, so a freshly-started pattern does not read as flat.
    func testSingleRecentTierIsSteadyNotFlat() {
        let squat = chain(.squat, [milestone("squat_a", tier: 1, weeksAgo: 1)])
        let result = trends([squat])
        XCTAssertEqual(result.first?.trend, .steady)
    }

    /// The flat threshold is the boundary: exactly `flatWeeksThreshold` weeks at the frontier reads as
    /// flat, one week under does not.
    func testFlatThresholdBoundary() {
        let atThreshold = chain(.core, [milestone("core_a", tier: 1, weeksAgo: CoachStrengthJourneyReader.flatWeeksThreshold)])
        let underThreshold = chain(.core, [milestone("core_a", tier: 1, weeksAgo: CoachStrengthJourneyReader.flatWeeksThreshold - 1)])

        XCTAssertEqual(trends([atThreshold]).first?.trend, .flat)
        XCTAssertEqual(trends([underThreshold]).first?.trend, .steady)
    }

    // MARK: - Offer

    /// The validation shape: hinge flat while push climbs -> the offer emphasizes hinge and names push
    /// as the climbing pattern, and its proposal is a bounded, preference-only emphasis nudge (US-AC07)
    /// - never a workout edit.
    func testOfferEmphasizesTheStalledPattern() throws {
        let result = trends([
            chain(.push, [
                milestone("push_a", tier: 1, weeksAgo: 5),
                milestone("push_c", tier: 3, weeksAgo: 0),
            ]),
            chain(.hinge, [milestone("hinge_b", tier: 2, weeksAgo: 4)]),
        ])

        let offer = try XCTUnwrap(CoachAnalyticsInsight.offer(from: result))
        XCTAssertEqual(offer.stalledPattern, .hinge)
        XCTAssertEqual(offer.stalledWeeks, 4)
        XCTAssertEqual(offer.climbingPattern, .push)

        // The action is a preference-only emphasis proposal toward hinge - and *only* that: no rate,
        // no window, and no way to express a workout edit or safety filter.
        let proposal = offer.proposal
        XCTAssertEqual(Array(proposal.patternEmphasis.keys), [.hinge])
        XCTAssertGreaterThan(proposal.patternEmphasis[.hinge] ?? 0, SessionPolicy.neutralEmphasis)
        XCTAssertNil(proposal.easedProgressionRate)
        XCTAssertNil(proposal.narrowedVarietyWindow)
    }

    /// With no flat pattern there is nothing to act on, so the surface stays quiet.
    func testNoOfferWhenNothingIsStalled() {
        let result = trends([
            chain(.push, [milestone("push_a", tier: 1, weeksAgo: 5), milestone("push_c", tier: 3, weeksAgo: 0)]),
            chain(.squat, [milestone("squat_a", tier: 1, weeksAgo: 1)]),
        ])
        XCTAssertNil(CoachAnalyticsInsight.offer(from: result))
    }

    /// The most-stalled flat pattern wins (longest at its frontier), so the offer targets the biggest
    /// stall when several patterns are flat.
    func testOfferPicksTheMostStalledPattern() {
        let result = trends([
            chain(.hinge, [milestone("hinge_a", tier: 1, weeksAgo: 4)]),
            chain(.core, [milestone("core_a", tier: 1, weeksAgo: 7)]),
        ])
        let offer = CoachAnalyticsInsight.offer(from: result)
        XCTAssertEqual(offer?.stalledPattern, .core)
        XCTAssertEqual(offer?.stalledWeeks, 7)
    }

    /// An empty journey (no strength history) raises no offer.
    func testEmptyJourneyRaisesNoOffer() {
        XCTAssertNil(CoachAnalyticsInsight.offer(from: trends([])))
    }

    // MARK: - The five lines (ADR-0006)

    /// The insight tracks the Progress tab's five lines: Pull reads like any other line, and the Squat
    /// and Hinge sides of Legs are classified independently - a flat hinge next to a climbing squat is a
    /// hinge stall, and the offer emphasizes exactly hinge, never squat.
    func testLegsSidesAreClassifiedAndOfferedIndependently() throws {
        let result = trends([
            chain(.squat, [milestone("squat_a", tier: 1, weeksAgo: 5), milestone("squat_b", tier: 2, weeksAgo: 0)]),
            chain(.hinge, [milestone("hinge_a", tier: 1, weeksAgo: 3)]),
        ])
        XCTAssertEqual(result.first { $0.pattern == .squat }?.trend, .climbing)
        XCTAssertEqual(result.first { $0.pattern == .hinge }?.trend, .flat)
        XCTAssertEqual(result.map { $0.line?.foundation }, [.legs, .legs])

        let offer = try XCTUnwrap(CoachAnalyticsInsight.offer(from: result))
        XCTAssertEqual(offer.stalledPattern, .hinge)
        XCTAssertEqual(offer.stalledLine?.sideLabel, "Hinge side")
        XCTAssertEqual(Array(offer.proposal.patternEmphasis.keys), [.hinge], "exactly the stalled side, not all of Legs")
    }

    func testPullIsANamedLineTheOfferCanTarget() throws {
        let result = trends([chain(.pull, [milestone("pull_a", tier: 1, weeksAgo: 4)])])
        let offer = try XCTUnwrap(CoachAnalyticsInsight.offer(from: result))
        XCTAssertEqual(offer.stalledPattern, .pull)
        XCTAssertEqual(Array(offer.proposal.patternEmphasis.keys), [.pull])
    }

    /// Ties between equally stalled lines resolve in foundation order: Push, Pull, Squat, Hinge, Core.
    func testTieBetweenStalledLinesResolvesInFoundationOrder() {
        let result = trends([
            chain(.core, [milestone("core_a", tier: 1, weeksAgo: 5)]),
            chain(.hinge, [milestone("hinge_a", tier: 1, weeksAgo: 5)]),
            chain(.pull, [milestone("pull_a", tier: 1, weeksAgo: 5)]),
        ])
        XCTAssertEqual(CoachAnalyticsInsight.offer(from: result)?.stalledPattern, .pull)
    }

    /// The copy names the side of Legs ("the hinge side of your legs") and reads plainly for a
    /// single-line foundation ("your pull").
    func testCopyNamesTheSideOfLegsAndPlainForOtherFoundations() {
        let hinge = CoachAnalyticsInsightCopy.offer(for: CoachAnalyticsInsightOffer(stalledPattern: .hinge, stalledWeeks: 3, climbingPattern: nil))
        XCTAssertTrue(hinge.hasPrefix("The hinge side of your legs has been flat about 3 weeks."), hinge)

        let squat = CoachAnalyticsInsightCopy.offer(for: CoachAnalyticsInsightOffer(stalledPattern: .squat, stalledWeeks: 4, climbingPattern: .pull))
        XCTAssertTrue(squat.hasPrefix("Your pull is climbing, but the squat side of your legs has been flat about 4 weeks."), squat)

        let pull = CoachAnalyticsInsightCopy.offer(for: CoachAnalyticsInsightOffer(stalledPattern: .pull, stalledWeeks: 3, climbingPattern: .core))
        XCTAssertTrue(pull.hasPrefix("Your core is climbing, but your pull has been flat about 3 weeks."), pull)
    }

    // MARK: - Progress inquiry recognition

    func testRecognizesProgressInquiries() {
        for message in [
            "How am I doing?",
            "how's my progress lately",
            "Am I improving at all?",
            "how are my numbers looking",
        ] {
            XCTAssertTrue(CoachAnalyticsInsight.isProgressInquiry(message), "should recognize: \(message)")
        }
    }

    func testIgnoresNonProgressMessages() {
        for message in [
            "how do I do a pistol squat?",
            "why this workout today?",
            "my knee hurts on squats",
            "focus my push",
        ] {
            XCTAssertFalse(CoachAnalyticsInsight.isProgressInquiry(message), "should not recognize: \(message)")
        }
    }
}
