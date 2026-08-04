import Foundation

/// Production analytics sink for builds without a live transport yet (US-T02).
///
/// `record(_:)` deliberately does nothing: until US-T04 wires the real Convex-backed
/// `URLSession` POST, a shipping build must emit nothing and, crucially, accumulate nothing -
/// so `live(context:)` discards events rather than recording them into an ever-growing array.
/// `MockAnalyticsService` keeps the recording behaviour that tests and previews need.
actor NoOpAnalyticsService: AnalyticsServiceProtocol {
    init() {}

    func record(_ event: AnalyticsEvent) async {}
}
