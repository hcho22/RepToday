import CoreData
import XCTest
@testable import RepToday

/// US-T02 validation: the analytics seam records events in order with names, timestamps, and
/// property bags intact, and the value type / event-name vocabulary hold their contract.
final class AnalyticsServiceTests: XCTestCase {

    // MARK: - Mock records events in order, no network

    /// The story's validation test: record three events covering the different scalar-bag shapes and
    /// assert the mock's array holds exactly those three, in order, fully intact.
    func testMockRecordsEveryEventInOrder() async {
        let analytics = MockAnalyticsService()

        // Three shapes: a string-only bag, a mixed int/double/bool bag, and an empty bag.
        let install = AnalyticsEvent(
            name: .appInstall,
            timestampMs: 1_000,
            properties: ["install_week": .string("2026-08-03")]
        )
        let completed = AnalyticsEvent(
            name: .sessionCompleted,
            timestampMs: 2_000,
            properties: [
                "requested_minutes": .int(20),
                "completed_minutes": .double(18.5),
                "was_return": .bool(true)
            ]
        )
        let weekActive = AnalyticsEvent(name: .weekActive, timestampMs: 3_000)

        await analytics.record(install)
        await analytics.record(completed)
        await analytics.record(weekActive)

        let recorded = await analytics.recordedEvents
        XCTAssertEqual(recorded, [install, completed, weekActive])
        // Explicit checks so an ordering or field regression names itself.
        XCTAssertEqual(recorded.map(\.name), [.appInstall, .sessionCompleted, .weekActive])
        XCTAssertEqual(recorded.map(\.timestampMs), [1_000, 2_000, 3_000])
        XCTAssertEqual(recorded[0].properties, ["install_week": .string("2026-08-03")])
        XCTAssertEqual(recorded[1].properties["completed_minutes"], .double(18.5))
        XCTAssertTrue(recorded[2].properties.isEmpty)
    }

    func testFreshMockHasNoRecordedEvents() async {
        let analytics = MockAnalyticsService()
        let recorded = await analytics.recordedEvents
        XCTAssertTrue(recorded.isEmpty)
    }

    // MARK: - AnalyticsValue round-trips every scalar case

    /// Every scalar case must encode and decode back to the same case with the same value - a stated
    /// failure indicator is a property bag that cannot round-trip a scalar type. The discriminated
    /// encoding keeps `.int(1)`, `.double(1)`, and `.bool(true)` from collapsing into one another.
    func testAnalyticsValueRoundTripsEveryScalarCase() throws {
        let cases: [AnalyticsValue] = [
            .int(42),
            .int(-7),
            .double(18.5),
            // A whole-numbered double must survive as `.double`, not decode back as `.int`.
            .double(1),
            .string("progressUpsell"),
            .bool(true),
            .bool(false)
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for value in cases {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(AnalyticsValue.self, from: data)
            XCTAssertEqual(decoded, value, "AnalyticsValue \(value) did not round-trip")
        }
    }

    /// The whole event round-trips through `Codable`, property bag included.
    func testAnalyticsEventRoundTrips() throws {
        let event = AnalyticsEvent(
            name: .readyScreenShown,
            timestampMs: 1_723_000_000_000,
            properties: [
                "generation_ms": .int(42),
                "note": .string("cold"),
                "warm": .bool(false)
            ]
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AnalyticsEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    // MARK: - Event-name vocabulary is exactly the 13 in-app events

    /// A missing or extra case must fail loudly. The two web-side events (`landing_page_view`,
    /// `waitlist_signup`) are out of scope and must not appear.
    func testEventNameHasExactlyThirteenCases() {
        XCTAssertEqual(AnalyticsEventName.allCases.count, 13)

        let rawValues = Set(AnalyticsEventName.allCases.map(\.rawValue))
        XCTAssertEqual(rawValues, [
            "app_install",
            "onboarding_started",
            "onboarding_completed",
            "ready_screen_shown",
            "session_started",
            "session_completed",
            "session_abandoned",
            "day7_return",
            "day30_return",
            "week_active",
            "paywall_shown",
            "trial_started",
            "subscribe"
        ])
        XCTAssertFalse(rawValues.contains("landing_page_view"))
        XCTAssertFalse(rawValues.contains("waitlist_signup"))
    }

    /// Each case's raw value is the snake_case wire name (the string the Convex `events` table stores).
    func testEventNameRawValuesRoundTrip() throws {
        for name in AnalyticsEventName.allCases {
            let data = try JSONEncoder().encode(name)
            let decoded = try JSONDecoder().decode(AnalyticsEventName.self, from: data)
            XCTAssertEqual(decoded, name)
            XCTAssertEqual(AnalyticsEventName(rawValue: name.rawValue), name)
        }
    }

    // MARK: - The seam, exercised through the containers a call site actually resolves

    /// Walks one anonymous user's whole funnel - install through subscribe, all 13 pre-registered
    /// events with the schema's own property names - through `analyticsService` as resolved from both
    /// `ServiceContainer.mock()` and the production `ServiceContainer.live(context:)`, then writes the
    /// exact JSON body US-T04 will POST to the Convex sink as reviewable evidence.
    ///
    /// This is the end-to-end read of the seam rather than of the model: every emission is written the
    /// way a US-T03 call site must write it - `await services.analyticsService.record(event)`, no `try`
    /// - so the deliberate `async`-but-not-`throws` signature is exercised as a call site, not asserted
    /// about. Both containers record into memory, which is what "no transport yet" looks like from the
    /// outside: nothing leaves the process.
    func testFunnelEmittedThroughBothContainersIsRecordedAndSerialisesToTheWireBody() async throws {
        let controller = MockPersistence.controller()
        let live = ServiceContainer.live(context: controller.viewContext)
        let mock = ServiceContainer.mock()

        let funnel = Self.funnelJourney

        // Exactly how a US-T03 call site reads: awaited, unhandled, no `try`, no result to check.
        for event in funnel {
            await live.analyticsService.record(event)
            await mock.analyticsService.record(event)
        }

        // Both containers wire the in-memory sink until the real transport lands (US-T04), so the
        // production container's telemetry is observable here in exactly the same way.
        let liveSink = try XCTUnwrap(live.analyticsService as? MockAnalyticsService)
        let mockSink = try XCTUnwrap(mock.analyticsService as? MockAnalyticsService)
        let recordedLive = await liveSink.recordedEvents
        let recordedMock = await mockSink.recordedEvents
        XCTAssertEqual(recordedLive, funnel, "the production container's sink lost or reordered events")
        XCTAssertEqual(recordedMock, funnel, "the mock container's sink lost or reordered events")
        // The journey covers the whole pre-registered vocabulary, so the evidence is not a sample.
        XCTAssertEqual(Set(recordedLive.map(\.name)), Set(AnalyticsEventName.allCases))

        // The bytes: what the sink holds, encoded as the request body the Convex ingest endpoint
        // receives. Serialising from the *recorded* array (not the source array) means the artifact
        // can only show what actually survived the seam.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let body = try encoder.encode(recordedLive)
        let wireJSON = try XCTUnwrap(String(data: body, encoding: .utf8))
        // The wire contract is the snake_case names, and no identity ever rides along.
        XCTAssertTrue(wireJSON.contains("\"app_install\""))
        XCTAssertFalse(wireJSON.contains("landing_page_view"))
        XCTAssertFalse(wireJSON.contains("waitlist_signup"))

        // A server reading the body back gets the same events - the round-trip the sink will depend on.
        let decoded = try JSONDecoder().decode([AnalyticsEvent].self, from: body)
        XCTAssertEqual(decoded, funnel)

        try EvidenceOutput.write(
            wireJSON + "\n", named: "funnel-wire-payload.json", for: EvidenceOutput.Story.analyticsSeam
        )
        try EvidenceOutput.write(
            Self.transcript(for: recordedLive), named: "funnel-transcript.txt",
            for: EvidenceOutput.Story.analyticsSeam
        )
    }

    /// The story's named failure indicator, shown rather than only asserted: three values that all
    /// serialise to `1`/`true` under natural JSON scalars stay distinct through the discriminated
    /// encoding, and the proof is written out beside the funnel payload.
    func testScalarCasesStayDistinctThroughTheWireAndAreWrittenAsEvidence() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        var lines = ["AnalyticsValue: every scalar case survives the wire as its own case",
                     "(a natural-JSON encoding would collapse the first three into one)",
                     ""]
        let collapsible: [AnalyticsValue] = [.int(1), .double(1), .bool(true), .string("1")]
        var decodedCases: [AnalyticsValue] = []
        for value in collapsible {
            let data = try encoder.encode(value)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            let back = try decoder.decode(AnalyticsValue.self, from: data)
            XCTAssertEqual(back, value)
            decodedCases.append(back)
            lines.append("  \(String(describing: value).padding(toLength: 16, withPad: " ", startingAt: 0))"
                         + "-> \(json.padding(toLength: 34, withPad: " ", startingAt: 0))"
                         + "-> \(String(describing: back))")
        }
        // Four inputs that a natural encoding would smear together come back as four distinct values.
        XCTAssertEqual(Set(decodedCases.map { String(describing: $0) }).count, 4)

        try EvidenceOutput.write(
            lines.joined(separator: "\n") + "\n",
            named: "scalar-round-trip.txt", for: EvidenceOutput.Story.analyticsSeam
        )
    }

    // MARK: - The journey and its transcript

    /// One anonymous install's whole funnel, in the order the app would emit it, using the property
    /// names `gtm/06-channels/event-metric-schema.md` pre-registers for each event. Timestamps are
    /// fixed offsets from a pinned install moment so the evidence is byte-reproducible.
    private static let funnelJourney: [AnalyticsEvent] = {
        // 2026-08-03T00:00:00Z, pinned rather than read from the clock.
        let installMs = 1_785_715_200_000
        let minute = 60_000, day = 86_400_000
        return [
            .init(name: .appInstall, timestampMs: installMs,
                  properties: ["install_week": .string("2026-W32")]),
            .init(name: .onboardingStarted, timestampMs: installMs + 4_000),
            .init(name: .onboardingCompleted, timestampMs: installMs + 97_000,
                  properties: ["elapsed_seconds": .int(93)]),
            .init(name: .readyScreenShown, timestampMs: installMs + 99_000,
                  properties: ["generation_ms": .int(38)]),
            .init(name: .sessionStarted, timestampMs: installMs + 2 * minute,
                  properties: ["requested_minutes": .int(20)]),
            .init(name: .sessionCompleted, timestampMs: installMs + 21 * minute,
                  properties: [
                      "requested_minutes": .int(20),
                      "completed_minutes": .double(19.5),
                      "was_return": .bool(false),
                      "perceived_difficulty": .string("justRight")
                  ]),
            .init(name: .weekActive, timestampMs: installMs + 21 * minute),
            .init(name: .sessionAbandoned, timestampMs: installMs + 2 * day,
                  properties: ["completed_minutes": .double(3.0), "abandon_point": .string("warmUp")]),
            .init(name: .day7Return, timestampMs: installMs + 7 * day),
            .init(name: .paywallShown, timestampMs: installMs + 7 * day + minute,
                  properties: ["entry_point": .string("progressDepth")]),
            .init(name: .trialStarted, timestampMs: installMs + 7 * day + 2 * minute),
            .init(name: .subscribe, timestampMs: installMs + 14 * day,
                  properties: ["plan": .string("annual")]),
            .init(name: .day30Return, timestampMs: installMs + 30 * day)
        ]
    }()

    /// A reviewer-readable rendering of what the sink holds: the funnel in emission order, with each
    /// event's elapsed offset from install and its property bag.
    private static func transcript(for events: [AnalyticsEvent]) -> String {
        guard let installMs = events.first?.timestampMs else { return "" }
        var lines = [
            "RepToday US-T02 - analytics seam, one anonymous install's funnel",
            "recorded through ServiceContainer.live(context:).analyticsService",
            "(await analytics.record(event) - fire-and-forget, no try, no network)",
            "",
            column("#", 4) + column("event", 22) + column("t+ (h:mm:ss)", 14) + "properties",
            String(repeating: "-", count: 120)
        ]
        for (index, event) in events.enumerated() {
            let elapsed = (event.timestampMs - installMs) / 1_000
            let clock = String(format: "%d:%02d:%02d", elapsed / 3_600, (elapsed % 3_600) / 60, elapsed % 60)
            let bag = event.properties.isEmpty
                ? "(none)"
                : event.properties.keys.sorted()
                    .map { "\($0)=\(describe(event.properties[$0]!))" }
                    .joined(separator: ", ")
            lines.append(column("\(index + 1)", 4) + column(event.name.rawValue, 22)
                         + column(clock, 14) + bag)
        }
        lines.append("")
        lines.append("\(events.count) events recorded in order; "
                     + "\(AnalyticsEventName.allCases.count) event names registered, all covered.")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Left-aligned fixed-width cell, so the transcript reads as a table rather than as `%-@`, which
    /// silently ignores the width for an `NSString` argument.
    private static func column(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private static func describe(_ value: AnalyticsValue) -> String {
        switch value {
        case .int(let raw): return "\(raw) (int)"
        case .double(let raw): return "\(raw) (double)"
        case .string(let raw): return "\"\(raw)\" (string)"
        case .bool(let raw): return "\(raw) (bool)"
        }
    }
}
