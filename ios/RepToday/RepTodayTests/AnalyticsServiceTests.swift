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
}
