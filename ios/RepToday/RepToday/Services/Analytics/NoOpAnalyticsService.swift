import Foundation

/// The inert telemetry sink: it accepts an event and does nothing with it.
///
/// US-T02 introduced it as production's placeholder while no transport existed. US-T04 landed that
/// transport (`LiveAnalyticsService`), so this is no longer what a *configured* build wires - it is
/// now what a build **carrying no usable telemetry endpoint** wires, chosen by
/// `ServiceContainer.live(...)` when `LiveAnalyticsService.configured(...)` returns `nil`. Such a
/// build must emit nothing quietly rather than trap, retry, or log on a path the core loop shares.
///
/// That is two situations, not one, and the second is the ordinary one: an endpoint that is missing
/// or mistyped, **and** a Release build, whose `REPTODAY_ANALYTICS_ENDPOINT` is deliberately empty
/// until a production deployment is chosen (`ios/RepToday/project.yml`). So this is the sink a
/// Release build wires today, by design - not an error state.
///
/// It discards rather than records, which is the difference from `MockAnalyticsService`: a
/// production sink that appended to an array nothing drains would grow one `AnalyticsEvent` per
/// emission for the life of the process. Nothing leaves the process here, and nothing stays in it.
actor NoOpAnalyticsService: AnalyticsServiceProtocol {
    init() {}

    func record(_ event: AnalyticsEvent) async {}
}
