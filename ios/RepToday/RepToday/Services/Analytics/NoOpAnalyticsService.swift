import Foundation

/// The inert telemetry sink: it accepts an event and does nothing with it.
///
/// US-T02 introduced it as production's placeholder while no transport existed. US-T04 landed that
/// transport (`LiveAnalyticsService`), so this is no longer what a *configured* build wires - it is
/// now what a build **carrying no complete telemetry configuration** wires, chosen by
/// `ServiceContainer.live(...)` when `LiveAnalyticsService.configured(...)` returns `nil`. Such a
/// build must emit nothing quietly rather than trap, retry, or log on a path the core loop shares.
///
/// That includes an endpoint or token that is missing/mistyped, and a raw Release build whose
/// production token was not privately injected (`ios/RepToday/project.yml`). So skipping the private
/// archive path loses telemetry quietly rather than turning into an app error.
///
/// It discards rather than records, which is the difference from `MockAnalyticsService`: a
/// production sink that appended to an array nothing drains would grow one `AnalyticsEvent` per
/// emission for the life of the process. Nothing leaves the process here, and nothing stays in it.
actor NoOpAnalyticsService: AnalyticsServiceProtocol {
    init() {}

    func record(_ event: AnalyticsEvent) async {}
}
