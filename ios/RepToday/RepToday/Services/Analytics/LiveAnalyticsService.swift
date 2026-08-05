import Foundation

/// The production telemetry sink (US-T04): one fire-and-forget `URLSession` POST per event to the
/// Convex deployment's `POST /logEvent` HTTP action (US-T03).
///
/// **No Convex SDK.** The US-T01 spike returned a no-go on `convex-swift` - it ships an arm64-only
/// xcframework, which would make every Simulator-hosted test suite in this repo unbuildable on an
/// Intel host - so the transport is a plain JSON POST and Lottie stays the app's only third-party
/// package (`artifacts/reports/US-T01/spike-note.md`). The body shape is `AnalyticsWireBody`.
///
/// **Fire-and-forget is a constraint, not a phrasing.** `record(_:)` does no I/O on the caller's
/// path: it checks the opt-out gate, hands the event to a detached background task, and returns.
/// Every failure past that point - offline, slow, non-2xx, malformed response, an unencodable
/// event - is swallowed. Nothing about telemetry may block, degrade, or fail the core loop, which
/// is the same rule every other integration in this app already follows (HealthKit writes,
/// CloudKit sync, StoreKit transaction observation). That is also why
/// `AnalyticsServiceProtocol.record(_:)` is `async` but not `throws`: there is no failure for a
/// call site to handle.
///
/// **This service is not called anywhere in production.** US-T04 ships the transport; US-T07
/// through US-T12 add the emission call sites. That is the same shape as US-T02 shipping the seam
/// uncalled and US-T05 shipping the identity unread.
///
/// **Identity comes from exactly one place.** `installId` is passed in from `AppState` (US-T05),
/// which is the only thing that mints it or resolves which of the three launch states an install
/// is in. This service never reads, re-mints, or re-derives it - a second resolution path could
/// disagree with the first about what an install is.
final class LiveAnalyticsService: AnalyticsServiceProtocol {

    /// The sink's single route, appended to the configured deployment origin. The path lives here
    /// rather than in configuration so the code that knows the contract owns it.
    static let routePath = "logEvent"

    /// The `Info.plist` key carrying the deployment's `.site` origin. The value is expanded from the
    /// per-configuration `REPTODAY_ANALYTICS_ENDPOINT` build setting in `ios/RepToday/project.yml`,
    /// so which deployment a build talks to is a build choice rather than a source edit. See
    /// `configured(...)`.
    static let endpointInfoPlistKey = "RepTodayAnalyticsEndpoint"

    /// A telemetry POST is worth a short wait and nothing more; the answer is discarded either way.
    static let requestTimeoutSeconds: TimeInterval = 10

    private let endpoint: URL
    private let installId: String
    private let session: URLSession
    private let isEnabled: @Sendable () -> Bool

    /// - Parameters:
    ///   - endpoint: The fully-resolved `POST /logEvent` URL.
    ///   - installId: The anonymous per-install identifier from `AppState` (US-T05).
    ///   - session: The session the POST goes out on; injected so tests can intercept it in
    ///     process with a `URLProtocol` stub and never touch the network (FR-13).
    ///   - isEnabled: The opt-out gate, read fresh on every emission. It defaults to enabled, and
    ///     production passes `AppState.analyticsGate` (US-T06), which reads the persisted
    ///     `AppState.analyticsEnabled` flag the Settings toggle writes. It is deliberately a closure
    ///     rather than a stored flag: reading it per emission - not once at construction - is what
    ///     makes turning telemetry off take effect immediately rather than at the next launch.
    ///     It is also the *only* gate an out-of-process test can ever reach: `RepTodayUITests`
    ///     launches the real app, which builds its own container, so `ServiceContainer.live(...)`'s
    ///     sink parameter cannot bind there. Because the flag lives in `UserDefaults`, the
    ///     `-AppState.analyticsEnabled NO` launch argument closes this gate in an app the test
    ///     process never built, which is how FR-13's out-of-process half is held.
    init(
        endpoint: URL,
        installId: String,
        session: URLSession = LiveAnalyticsService.makeSession(),
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.endpoint = endpoint
        self.installId = installId
        self.session = session
        self.isEnabled = isEnabled
    }

    /// Builds the service from the deployment origin in the app's `Info.plist`, or returns `nil`
    /// when that configuration is absent or unusable.
    ///
    /// **An unconfigured build must be inert, never fatal.** No `fatalError`, no `try!`, no noisy
    /// logging on a path the core loop shares: shipping a build that emits nothing is a far better
    /// outcome than one that traps or spams because a telemetry URL was mistyped. `nil` is what
    /// that inertness is expressed as, and `ServiceContainer.live(...)` answers it by wiring
    /// `NoOpAnalyticsService` - a sink that already means exactly "emit nothing, keep nothing" -
    /// rather than by growing a second, invisible do-nothing branch in here.
    ///
    /// That path is not only the misconfiguration path. `REPTODAY_ANALYTICS_ENDPOINT` is set for
    /// Debug (the dev deployment) and deliberately **empty for Release**, because no production
    /// deployment has been chosen; a Release build therefore returns `nil` here by design and stays
    /// silent until someone configures one. Choosing that deployment is a precondition for shipping
    /// any build that emits (US-T07 onward), and the worst case until then is no data rather than
    /// data at the wrong destination.
    ///
    /// "Unusable" is checked rather than assumed, because `URL(string:)` accepts almost any string
    /// as a relative URL: the value must parse, carry an `https` scheme, and have a host. A
    /// telemetry endpoint that is not HTTPS is a configuration mistake, not a deployment choice.
    /// - Parameter session: `nil` builds the default one *after* the configuration is known to be
    ///   usable, so an unconfigured build creates no session at all rather than one it discards.
    static func configured(
        bundle: Bundle = .main,
        installId: String,
        session: URLSession? = nil,
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) -> LiveAnalyticsService? {
        guard let endpoint = endpoint(fromOrigin: bundle.object(forInfoDictionaryKey: endpointInfoPlistKey)) else {
            return nil
        }
        return LiveAnalyticsService(
            endpoint: endpoint,
            installId: installId,
            session: session ?? makeSession(),
            isEnabled: isEnabled
        )
    }

    /// Resolves a configured deployment origin into the route this service POSTs to, or `nil` if
    /// the value is missing, empty, not a string, or not a usable HTTPS origin.
    ///
    /// The configured value is the deployment's `.site` **origin**
    /// (`https://<deployment>.convex.site`); `routePath` is appended here. This is the one notion
    /// of "unconfigured" in the app: a build setting that expands to nothing and a key that is
    /// absent entirely both land on the same `nil` rather than on two parallel branches.
    static func endpoint(fromOrigin origin: Any?) -> URL? {
        guard
            let origin = origin as? String,
            let url = URL(string: origin.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }
        return url.appendingPathComponent(routePath)
    }

    /// The session telemetry goes out on: ephemeral (no cookie, credential, or disk cache to
    /// outlive the request), never waiting for connectivity, and short-timed. Offline must fail
    /// fast and be dropped rather than queue up work that outlives the reason for sending it -
    /// losing a few offline events is expected and acceptable (the PRD says so); holding the
    /// system's connectivity-wait machinery open for anonymous counters is not.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = requestTimeoutSeconds
        return URLSession(configuration: configuration)
    }

    /// The opt-out gate as it reads *right now*, which is exactly what `record(_:)` will ask.
    ///
    /// It exists so a test can assert what a built service's gate is backed by - notably that
    /// `ServiceContainer.live(...)` wired the persisted `AppState.analyticsEnabled` flag and not the
    /// enabled-by-default stub - without emitting anything to find out. Read-only, and no production
    /// caller reads it.
    var isEmissionEnabled: Bool { isEnabled() }

    // MARK: - AnalyticsServiceProtocol

    func record(_ event: AnalyticsEvent) async {
        // The gate is read here, on the calling path, so it reflects the user's choice at the
        // moment of the emission. When telemetry is off there is no task, no encode, and no
        // request - "zero network calls when off" is US-T06's criterion and is satisfied by there
        // being nothing after this line, in process and out of it alike.
        guard isEnabled() else { return }

        let endpoint = self.endpoint
        let installId = self.installId
        let session = self.session

        // The caller's `await` completes here. Everything below - encoding included - runs on a
        // detached background task, so no core-loop interaction ever waits on telemetry.
        Task.detached(priority: .utility) {
            guard let body = try? AnalyticsWireBody.encode(event, installId: installId) else { return }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = LiveAnalyticsService.requestTimeoutSeconds
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            // Every outcome is the same outcome. The sink answers `204` on success and
            // `{"error": …}` with a `4xx`/`5xx` split otherwise (see `convex/README.md`), but that
            // split exists for a human watching the PMF test, not for this client: there is no
            // retry, no queue, and nothing to report, so the response is discarded unread.
            _ = try? await session.data(for: request)
        }
    }
}
