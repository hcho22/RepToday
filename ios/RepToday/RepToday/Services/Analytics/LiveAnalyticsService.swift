import Foundation

/// The production anonymous-telemetry sink: a bounded durable outbox feeding short `URLSession`
/// POSTs to the Convex deployment's `POST /logEvent` action.
///
/// **No Convex SDK.** The US-T01 spike returned a no-go on `convex-swift`, so the transport remains
/// plain Foundation networking with no new third-party dependency. The body shape is
/// `AnalyticsWireBody`.
///
/// **Non-blocking remains a constraint.** `record(_:)` synchronously checks consent, transfers the
/// event into a bounded queue-owned buffer, and acquires background execution before returning.
/// Encoding, durable persistence, retry, and network delivery all proceed asynchronously. Retryable
/// interruptions remain in the durable outbox for the next foreground/relaunch, capped at three
/// attempts, seven days, and 50 pending events. Every error is swallowed and no analytics result can
/// become a product failure.
///
/// **Consent is checked twice.** The persisted gate is read at enqueue and immediately before every
/// attempt. Each queued row also carries `AppState`'s consent generation; opting out advances that
/// generation and discards/cancels pending work, so re-enabling cannot resurrect a pre-opt-out row.
///
/// **Retry duplicates are measurement-safe.** One random `eventId` is encoded at enqueue and reused
/// by every retry. Convex returns `204` but inserts at most one row for that id, covering the classic
/// "insert committed, response was interrupted" case.
final class LiveAnalyticsService: AnalyticsServiceProtocol {
    static let routePath = "logEvent"
    static let endpointInfoPlistKey = "RepTodayAnalyticsEndpoint"
    static let secretInfoPlistKey = "RepTodayAnalyticsSecret"
    static let secretHeaderField = "X-RepToday-Analytics-Secret"
    static let requestTimeoutSeconds: TimeInterval = 10

    private let isEnabled: @Sendable () -> Bool
    private let deliveryQueue: AnalyticsDeliveryQueue

    /// Foundation-networking initializer used by production, configured tests, and the Debug-only
    /// URLProtocol probe. Configuration is resolved before this is called, preserving the inert raw
    /// Release path: no usable endpoint+secret means no service, session, or outbox is constructed.
    init(
        endpoint: URL,
        installId: @escaping @Sendable () -> String,
        secret: String,
        session: URLSession = LiveAnalyticsService.makeSession(),
        isEnabled: @escaping @Sendable () -> Bool = { true },
        consentGeneration: @escaping @Sendable () -> Int = { 0 },
        outboxStorage: (any AnalyticsOutboxStorage)? = nil,
        backgroundExecution: AnalyticsBackgroundExecution = .live,
        now: @escaping @Sendable () -> Date = { Date() },
        newEventId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.isEnabled = isEnabled
        self.deliveryQueue = AnalyticsDeliveryQueue(
            endpoint: endpoint,
            secret: secret,
            installId: installId,
            isEnabled: isEnabled,
            consentGeneration: consentGeneration,
            transport: URLSessionAnalyticsDeliveryTransport(session: session),
            storage: outboxStorage ?? FileAnalyticsOutboxStorage(),
            backgroundExecution: backgroundExecution,
            now: now,
            newEventId: newEventId
        )
    }

    /// Transport-level initializer for deterministic recovery tests. Unit tests inject both this
    /// seam and storage, so they never reach a socket or the app's real outbox.
    init(
        endpoint: URL,
        installId: @escaping @Sendable () -> String,
        secret: String,
        transport: any AnalyticsDeliveryTransport,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        consentGeneration: @escaping @Sendable () -> Int = { 0 },
        outboxStorage: any AnalyticsOutboxStorage,
        backgroundExecution: AnalyticsBackgroundExecution = .none,
        now: @escaping @Sendable () -> Date = { Date() },
        newEventId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.isEnabled = isEnabled
        self.deliveryQueue = AnalyticsDeliveryQueue(
            endpoint: endpoint,
            secret: secret,
            installId: installId,
            isEnabled: isEnabled,
            consentGeneration: consentGeneration,
            transport: transport,
            storage: outboxStorage,
            backgroundExecution: backgroundExecution,
            now: now,
            newEventId: newEventId
        )
    }

    convenience init(
        endpoint: URL,
        installId: String,
        secret: String,
        session: URLSession = LiveAnalyticsService.makeSession(),
        isEnabled: @escaping @Sendable () -> Bool = { true },
        consentGeneration: @escaping @Sendable () -> Int = { 0 },
        outboxStorage: (any AnalyticsOutboxStorage)? = nil,
        backgroundExecution: AnalyticsBackgroundExecution = .live,
        now: @escaping @Sendable () -> Date = { Date() },
        newEventId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.init(
            endpoint: endpoint,
            installId: { installId },
            secret: secret,
            session: session,
            isEnabled: isEnabled,
            consentGeneration: consentGeneration,
            outboxStorage: outboxStorage,
            backgroundExecution: backgroundExecution,
            now: now,
            newEventId: newEventId
        )
    }

    /// Builds the service from the deployment origin and shared secret in `Info.plist`, or `nil`
    /// when either value is absent/unusable. That `nil` remains the quiet, inert raw-Release posture
    /// and is resolved to `NoOpAnalyticsService` by the container.
    static func configured(
        bundle: Bundle = .main,
        installId: @escaping @Sendable () -> String,
        session: URLSession? = nil,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        consentGeneration: @escaping @Sendable () -> Int = { 0 },
        outboxStorage: (any AnalyticsOutboxStorage)? = nil,
        backgroundExecution: AnalyticsBackgroundExecution = .live
    ) -> LiveAnalyticsService? {
        guard
            let endpoint = endpoint(fromOrigin: bundle.object(forInfoDictionaryKey: endpointInfoPlistKey)),
            let secret = secret(fromValue: bundle.object(forInfoDictionaryKey: secretInfoPlistKey))
        else {
            return nil
        }
        return LiveAnalyticsService(
            endpoint: endpoint,
            installId: installId,
            secret: secret,
            session: session ?? makeSession(),
            isEnabled: isEnabled,
            consentGeneration: consentGeneration,
            outboxStorage: outboxStorage,
            backgroundExecution: backgroundExecution
        )
    }

    static func configured(
        bundle: Bundle = .main,
        installId: String,
        session: URLSession? = nil,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        consentGeneration: @escaping @Sendable () -> Int = { 0 },
        outboxStorage: (any AnalyticsOutboxStorage)? = nil,
        backgroundExecution: AnalyticsBackgroundExecution = .live
    ) -> LiveAnalyticsService? {
        configured(
            bundle: bundle,
            installId: { installId },
            session: session,
            isEnabled: isEnabled,
            consentGeneration: consentGeneration,
            outboxStorage: outboxStorage,
            backgroundExecution: backgroundExecution
        )
    }

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

    static func secret(fromValue value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The POST itself stays ephemeral and short. Durability belongs exclusively to the bounded
    /// outbox; connectivity waiting would duplicate that responsibility and extend resource use.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = requestTimeoutSeconds
        return URLSession(configuration: configuration)
    }

    var isEmissionEnabled: Bool { isEnabled() }

    func record(_ event: AnalyticsEvent) {
        deliveryQueue.accept(event)
    }

    func resumePendingDelivery() async {
        await deliveryQueue.resumePendingDelivery()
    }

    func analyticsConsentDidChange() async {
        await deliveryQueue.consentDidChange()
    }

    /// Test-only observability over bounded durable state; production never reads it.
    var pendingDeliveryCount: Int {
        get async { await deliveryQueue.pendingCount }
    }
}
