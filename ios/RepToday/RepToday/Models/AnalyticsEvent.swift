import Foundation

/// The anonymous product-telemetry event model (US-T02).
///
/// This file is the *model only*: a typed event value plus the closed vocabularies it carries. It
/// adds no emission call sites - nothing in a shipping build calls `record(_:)` yet (the only
/// caller anywhere is US-T06's Debug-only, launch-argument-gated `TelemetryUITestHarness`, which
/// builds one of these values to stand in for the site that does not exist), and the 13 production
/// emission sites are US-T07 through US-T12. The sink it reaches landed in US-T03, the transport
/// that carries it in US-T04, and the per-install identifier it travels beside in US-T05; that
/// identifier is deliberately **not** on this type - it is attached when the event is encoded for
/// the wire (`AnalyticsWireBody`), so no user identity ever rides on the event, and one is not
/// modelled here as if it might.
///
/// **The `Codable` conformance below is the in-process form, not the wire form.** It is tagged on
/// purpose (see `AnalyticsValue`), while the sink stores plain scalars under different top-level
/// key names. `AnalyticsWireBody` owns that second encoding; encoding this type with a
/// `JSONEncoder` and POSTing the result would send a body the sink stores wrong.
///
/// The names and property lists are pre-registered in `gtm/06-channels/event-metric-schema.md`
/// and must not be edited to move a threshold. Like the domain enums in `Enums.swift`, the raw
/// values here are a wire contract: they are the exact strings the Convex `events` table stores,
/// so the case *names* may be refactored freely but the raw *values* must not change.

// MARK: - Event name

/// The 13 in-app events RepToday emits, keyed to the pre-registered schema.
///
/// The two web-side events (`landing_page_view`, `waitlist_signup`) are handled outside the app
/// and are deliberately absent. `AnalyticsServiceTests` pins the count at exactly 13 so a missing
/// or extra case fails loudly.
enum AnalyticsEventName: String, Codable, CaseIterable, Identifiable, Hashable {
    case appInstall = "app_install"
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case readyScreenShown = "ready_screen_shown"
    case sessionStarted = "session_started"
    case sessionCompleted = "session_completed"
    case sessionAbandoned = "session_abandoned"
    case day7Return = "day7_return"
    case day30Return = "day30_return"
    case weekActive = "week_active"
    case paywallShown = "paywall_shown"
    case trialStarted = "trial_started"
    case subscribe = "subscribe"

    var id: String { rawValue }
}

// MARK: - Property value

/// A single non-identifying property value: the closed set of scalar types the schema's property
/// bags use (`install_week` string, `elapsed_seconds`/`generation_ms`/`requested_minutes` ints,
/// `was_return` bool, and so on).
///
/// The `Codable` conformance is *self-describing* - each value encodes with an explicit `type`
/// discriminator alongside its `value` - so the case round-trips losslessly regardless of the
/// JSON number/bool ambiguity that would otherwise let a `Double` decode back as an `.int` or a
/// `Bool` decode as a number. `AnalyticsServiceTests` covers every case's round-trip because the
/// property bag failing to round-trip a scalar is a stated failure indicator for this story.
enum AnalyticsValue: Codable, Equatable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case int
        case double
        case string
        case bool
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        }
    }
}

// MARK: - Event

/// One anonymous telemetry event: a pre-registered name, a millisecond client timestamp, and a
/// small string-keyed property bag. A value type so it crosses concurrency domains freely when
/// `LiveAnalyticsService` sends it off the calling path on a detached task.
struct AnalyticsEvent: Codable, Equatable, Sendable {
    /// The pre-registered event name.
    let name: AnalyticsEventName
    /// Client-side timestamp in milliseconds since the Unix epoch.
    let timestampMs: Int
    /// The event's non-identifying properties; empty for the events the schema lists as carrying none.
    let properties: [String: AnalyticsValue]

    init(name: AnalyticsEventName, timestampMs: Int, properties: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.timestampMs = timestampMs
        self.properties = properties
    }
}
