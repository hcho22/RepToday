import Foundation
import Observation
import SwiftUI

#if DEBUG
/// A Debug-only, launch-argument-gated harness that makes the opt-out gate **observable from an
/// out-of-process XCUITest run** (US-T06, criterion 8).
///
/// **Why it exists at all.** `RepTodayUITests` launches the real app; the test process never builds
/// the `ServiceContainer`, so US-T04's `analyticsService` parameter cannot reach it and the only
/// gate there is `LiveAnalyticsService`'s `isEnabled` closure. Proving that gate holds needs two
/// things the out-of-process suite needs: something that *attempts* an emission on **every** probe
/// launch (US-T07's real `app_install` fires only on a genuine first launch, which a probe run -
/// launched onboarded - is not, so it never fires there and the probe stands in), and somewhere the
/// attempt can be counted from another process. Without both, "zero network calls with telemetry
/// off" passes for reasons that have nothing to do with the flag, and would keep passing if the
/// flag were deleted.
///
/// **What it does.** Under `-RepTodayTelemetryProbe YES`:
/// 1. the app's persisted opt-out flag is cleared at startup, so a probe run starts from the shipped
///    default instead of from whatever the previous run's toggling left behind;
/// 2. the telemetry transport's `URLSession` is replaced with one whose only protocol is
///    `TelemetryProbeURLProtocol`, which counts each request the transport dispatches and answers it
///    from memory - so a probe run cannot reach the network even with telemetry on (FR-13);
/// 3. one `app_install` event is emitted at app entry, through the container's own resolved sink -
///    the same place and the same sink US-T07's real emission uses;
/// 4. a small HUD renders the running count, with an accessibility identifier the test reads and a
///    button that emits another probe event on demand, so the *runtime* toggle can be exercised
///    without relaunching.
///
/// **What that proves, and what it does not.** The count is taken at the `URLProtocol` boundary -
/// the same boundary `LiveAnalyticsServiceTests` treats as authoritative for "a POST happened" - so
/// it proves the transport built and dispatched a request, not that bytes reached Convex. That is
/// deliberate: an out-of-process test that let real bytes out would break FR-13. The gate itself
/// (`guard isEnabled()` in `LiveAnalyticsService.record(_:)`) is untouched production code upstream
/// of everything here; this harness only observes what happens downstream of it.
///
/// **Nothing here is compiled into a Release build.** The whole file is inside `#if DEBUG`, and every
/// entry point is additionally inert unless the launch argument is present, so an ordinary Debug run
/// - including every other XCUITest suite - behaves exactly as it did before.
enum TelemetryUITestHarness {

    /// The `UserDefaults` key the launch argument lands under.
    /// `XCUIApplication.launchArguments = ["-RepTodayTelemetryProbe", "YES"]` is read straight out of
    /// the argument domain, the same way `-AppState.isOnboarded NO` already parks the app on
    /// onboarding. The suite spells the argument itself rather than importing this constant, because
    /// an XCUITest bundle cannot import the app module it drives.
    static let probeDefaultsKey = "RepTodayTelemetryProbe"

    /// The accessibility identifiers the XCUITest suite drives the HUD by - spelled again on that
    /// side, for the same reason.
    static let attemptsAccessibilityIdentifier = "telemetry.probe.attempts"
    static let emitButtonAccessibilityIdentifier = "telemetry.probe.emit"

    /// True only when this launch asked for the harness.
    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: probeDefaultsKey)
    }

    /// Clears the persisted opt-out flag so a probe run starts from the shipped default.
    ///
    /// Must run before `AppState.init` reads the flag. The installed app's container survives
    /// between XCUITest runs, so without this a test that toggled telemetry off would silently
    /// decide the *next* test's starting state. A launch argument still wins over this, because the
    /// argument domain outranks the persisted one - which is exactly how the opted-out run pins
    /// itself.
    static func resetPersistedConsentIfActive() {
        guard isActive else { return }
        UserDefaults.standard.removeObject(forKey: AppState.analyticsEnabledKey)
    }

    /// The `URLSession` the telemetry transport should use, or `nil` to keep its own.
    ///
    /// In probe mode this is an ephemeral session whose only protocol is the counting interceptor,
    /// so every request the transport dispatches is recorded and none of them leaves the process.
    static func interceptingSession() -> URLSession? {
        guard isActive else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryProbeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Emits one probe event through the container's own resolved sink, at app entry.
    ///
    /// It emits `app_install` from `RepTodayApp.init()` deliberately: that is the exact name and the
    /// exact place US-T07's first real emission site lands, so the harness stands in for that site
    /// rather than for an imaginary one. The event never leaves the process - `interceptingSession()`
    /// has already replaced the transport's session by the time this runs.
    static func emitProbeEventIfActive(through analytics: any AnalyticsServiceProtocol) {
        guard isActive else { return }
        Task { await analytics.record(probeEvent()) }
    }

    static func probeEvent(now: Date = Date()) -> AnalyticsEvent {
        AnalyticsEvent(
            name: .appInstall,
            timestampMs: Int(now.timeIntervalSince1970 * 1000),
            properties: ["install_week": .string("probe")]
        )
    }
}

/// The running count of telemetry requests the transport dispatched this launch.
///
/// `@Observable` so the HUD re-renders as the count moves; mutated on the main queue because the URL
/// loading system calls the interceptor on its own thread.
@Observable
final class TelemetryProbeLog {
    static let shared = TelemetryProbeLog()

    private(set) var attemptCount = 0

    private init() {}

    func recordAttempt() {
        attemptCount += 1
    }
}

/// Counts each request on the session it is registered for and answers it from memory, exactly as
/// the sink's `204` would. Nothing leaves the process.
final class TelemetryProbeURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        DispatchQueue.main.async {
            TelemetryProbeLog.shared.recordAttempt()
        }

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The HUD the XCUITest suite reads the count from and emits further probe events with.
///
/// It renders nothing at all outside probe mode, so an ordinary Debug run and every other XCUITest
/// suite see the app exactly as before. In probe mode it is a `safeAreaInset` rather than an overlay,
/// so it never covers a control the test needs to reach.
struct TelemetryProbeHUD: View {
    @Environment(\.services) private var services
    @State private var log = TelemetryProbeLog.shared

    var body: some View {
        if TelemetryUITestHarness.isActive {
            HStack(spacing: Theme.Spacing.sm) {
                Text("telemetry attempts: \(log.attemptCount)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier(TelemetryUITestHarness.attemptsAccessibilityIdentifier)

                Spacer(minLength: 0)

                Button("Emit probe") {
                    Task { await services.analyticsService.record(TelemetryUITestHarness.probeEvent()) }
                }
                .font(Theme.Typography.caption)
                .frame(minHeight: Theme.Spacing.minTouchTarget)
                .accessibilityIdentifier(TelemetryUITestHarness.emitButtonAccessibilityIdentifier)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.secondaryBackground)
        }
    }
}
#endif

extension View {
    /// Attaches the Debug-only telemetry probe HUD (US-T06). A no-op in a Release build, and inert in
    /// a Debug build that did not ask for the harness.
    func telemetryProbeHUD() -> some View {
        #if DEBUG
        return safeAreaInset(edge: .top, spacing: 0) { TelemetryProbeHUD() }
        #else
        return self
        #endif
    }
}
