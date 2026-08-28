import Foundation

/// The anonymous product-telemetry event model (US-T02).
///
/// This file is the *model only*: a typed event value plus the closed vocabularies it carries. It
/// adds no emission call sites of its own - the first production caller landed in US-T07
/// (`RepTodayApp.init()` emits the three app-entry events through `AppEntryTelemetry`), and the
/// other 10 of the 13 emission sites landed across US-T08 through US-T12, so all 13 events now
/// have their emission sites. US-T06's Debug-only,
/// launch-argument-gated `TelemetryUITestHarness` also builds one of these values, to keep its own
/// `app_install` firing on every probe launch. The sink it reaches landed in US-T03, the transport
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
/// The names and property lists are pre-registered in the event-metric schema
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

// MARK: - Abandon point

/// Where in a session the user abandoned it (US-T10) - the closed vocabulary the `abandon_point`
/// property on `session_abandoned` carries. Per the schema's stated convention that
/// `abandon_point`/`entry_point` are small, non-identifying closed enums (never free text), this
/// collapses the whole session into three coarse buckets: the warm-up and cooldown bookends, and a
/// single `mainWork` bucket covering every training block in between (strength/mobility/primal).
///
/// Like `AnalyticsEventName`, the raw values are the wire contract - the exact strings the Convex
/// `events` table stores - so the case *names* may be refactored freely but the raw *values* must
/// not change. `mainWork` is spelled to match the schema and the US-T10 validation verbatim.
enum AbandonPoint: String, Codable, CaseIterable, Identifiable, Hashable {
    case warmup
    case mainWork
    case cooldown

    var id: String { rawValue }

    /// The abandon bucket for the block a step sits in: the warm-up and cooldown bookends map to
    /// themselves; every training block folds into `mainWork`, so the enum stays coarse and
    /// non-identifying rather than leaking which exercise the user quit on.
    init(blockCategory: ExerciseCategory) {
        switch blockCategory {
        case .warmup: self = .warmup
        case .cooldown: self = .cooldown
        case .strength, .mobility, .primal: self = .mainWork
        }
    }
}

// MARK: - Entry point

/// Where the user opened the paywall from (US-T12) - the closed vocabulary the `entry_point`
/// property on `paywall_shown` carries. Per the schema's stated convention that
/// `abandon_point`/`entry_point` are small, non-identifying closed enums (never free text), this
/// starts with the single presentation path that exists today - the Progress-tab premium upsell
/// (`ProgressTabView`'s `PremiumUpsellCard`) - and gains a case as each new entry point appears.
///
/// Like `AnalyticsEventName` and `AbandonPoint`, the raw values are the wire contract - the exact
/// strings the Convex `events` table stores - so the case *names* may be refactored freely but the
/// raw *values* must not change.
enum EntryPoint: String, Codable, CaseIterable, Identifiable, Hashable {
    case progressUpsell = "progress_upsell"
    /// The premium gate on the AI coach entry point (US-AC03): a free user tapping the Coach row on
    /// the Profile tab opens the paywall carrying this, so the funnel can tell a coach upsell apart
    /// from the Progress-tab one.
    case coachUpsell = "coach_upsell"

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
