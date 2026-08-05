import Foundation

/// The inert telemetry sink: it accepts an event and does nothing with it.
///
/// US-T02 introduced it as production's placeholder while no transport existed. US-T04 landed that
/// transport (`LiveAnalyticsService`), so this is no longer what a configured shipping build wires
/// - it is now the **fallback for a build whose telemetry endpoint is missing or unusable**,
/// chosen by `ServiceContainer.live(context:installId:)` when `LiveAnalyticsService.configured(...)`
/// returns `nil`. A misconfigured build must emit nothing quietly rather than trap, retry, or log
/// on a path the core loop shares.
///
/// It discards rather than records, which is the difference from `MockAnalyticsService`: a
/// production sink that appended to an array nothing drains would grow one `AnalyticsEvent` per
/// emission for the life of the process. Nothing leaves the process here, and nothing stays in it.
actor NoOpAnalyticsService: AnalyticsServiceProtocol {
    init() {}

    func record(_ event: AnalyticsEvent) async {}
}
