import Foundation

/// The stateless coach transport client (US-AC01): it POSTs a `CoachContextBundle` plus the user's
/// message to the key-holding proxy (the same Cloudflare Worker as the Variety Language slice, at its
/// `POST /coach` route - see `proxy/README.md`) and returns Claude's reply. The Anthropic API key
/// never lives in the app; the client only ever talks to the proxy.
///
/// It mirrors `ProxyVarietyLanguageProvider`'s contract so the coach is safe to `await` from a UI
/// without ever blocking the core loop:
///
/// - **Bounded.** Every call carries a `timeoutSeconds` (default `defaultTimeoutSeconds`), enforced
///   by the transport, so the caller's `await` always returns in bounded time.
/// - **Throws on anything unusual.** A non-2xx status, an undecodable body, or an empty reply all
///   throw, so the chat surface (US-AC02) can degrade to a clear non-blocking state. The core loop
///   (generate / play / log) never depends on this client and never waits on it.
/// - **Nothing identifying on the wire.** The request body is exactly `{ context, message }`, where
///   `context` is the audited, non-identifying `CoachContextBundle`. No `installId`, no IDFA, no
///   Apple ID, no account - the transport stays pseudonymous, exactly as the Variety Language slice.
/// - **Conversation memory is the caller's, on-device.** This client is stateless per request; it
///   holds no history. Any multi-turn memory lives on the device in the caller (US-AC02).
///
/// The message is length-capped **client-side** before sending (`messageCharacterLimit`) so an
/// oversized turn is rejected locally and never bills a Claude call - the proxy enforces the same cap
/// as defense in depth.
///
/// US-AC01 ships the transport only; the chat surface that wires this in is US-AC02, so - like
/// `VarietyLanguageResolver.provider` in the MVP - there is no production call site yet.
struct CoachProxyClient {

    /// The default per-request timeout. Longer than the Variety Language line (a coach answer is a
    /// few sentences, not four words) but still firmly bounded so the surface never hangs.
    static let defaultTimeoutSeconds: Double = 30

    /// The default maximum message length (characters). A coach question is a sentence or two; this
    /// keeps the request small and cheap and matches the proxy's own body cap intent.
    static let defaultMessageCharacterLimit: Int = 2000

    /// Failures the client raises so the caller can fall back to a non-blocking error state. Each maps
    /// to a distinct contract violation; the cases exist for tests and diagnostics.
    enum CoachError: Error, Equatable {
        /// The message was empty or whitespace only - nothing to ask.
        case emptyMessage
        /// The message exceeded `messageCharacterLimit`; rejected locally before any network call.
        case messageTooLong(limit: Int)
        /// The response was not an HTTP response (should not happen over HTTPS).
        case notHTTP
        /// The proxy returned a non-2xx status.
        case badStatus(Int)
        /// The proxy returned a 2xx with an empty/whitespace reply - treated as no answer.
        case emptyReply
    }

    /// The proxy endpoint (the Worker's `/coach` route that accepts `{ context, message }` and
    /// returns `{ "reply": ... }`).
    let endpoint: URL
    /// The per-request timeout handed to the transport.
    let timeoutSeconds: Double
    /// The maximum message length accepted before a request is even attempted.
    let messageCharacterLimit: Int
    /// The optional client shared secret that gates the Worker's route (abuse protection). When set,
    /// every request sends `Authorization: Bearer <secret>` so the Worker can reject unauthenticated
    /// traffic before it bills a Claude call; `nil` matches an open (dev) Worker. See `proxy/README.md`.
    let sharedSecret: String?
    /// The HTTP seam, injected so tests exercise the request/response contract without a live network.
    let transport: any CoachProxyTransport

    init(
        endpoint: URL,
        timeoutSeconds: Double = CoachProxyClient.defaultTimeoutSeconds,
        messageCharacterLimit: Int = CoachProxyClient.defaultMessageCharacterLimit,
        sharedSecret: String? = nil,
        transport: any CoachProxyTransport = URLSessionCoachProxyTransport()
    ) {
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.messageCharacterLimit = messageCharacterLimit
        self.sharedSecret = sharedSecret
        self.transport = transport
    }

    // MARK: - Build-configured resolution (US-AC02)

    /// The `Info.plist` key carrying the coach proxy's `POST /coach` origin. Its value is expanded
    /// from the per-configuration `REPTODAY_COACH_ENDPOINT` build setting in `ios/RepToday/project.yml`,
    /// exactly like `LiveAnalyticsService`'s analytics endpoint - so which proxy a build talks to (or
    /// none) is a build choice rather than a source edit.
    static let endpointInfoPlistKey = "RepTodayCoachEndpoint"

    /// The `Info.plist` key carrying the client shared secret the proxy's abuse gate checks. Expanded
    /// from the per-configuration `REPTODAY_COACH_SECRET` build setting. Unlike the analytics secret
    /// this one is **optional**: an open (dev) Worker with no secret set matches a `nil` here, so a
    /// missing/empty value is not "unconfigured", it just sends no `Authorization` header.
    static let secretInfoPlistKey = "RepTodayCoachSecret"

    /// Builds the client from the coach proxy origin in the app's `Info.plist`, or returns `nil` when
    /// that configuration is absent or unusable - the coach is then **inert, never fatal**, exactly
    /// like an unconfigured `LiveAnalyticsService`: `ServiceContainer.live` leaves `coachClient` nil
    /// and the chat surface shows a clear "coach unavailable" state rather than trapping or pointing at
    /// a wrong destination.
    ///
    /// No production coach proxy is deployed yet, so both configurations currently expand to an empty
    /// value and this returns `nil` by design (the surface renders its unavailable state, and the unit
    /// suite exercises the wired path through the injected transport seam instead). Setting
    /// `REPTODAY_COACH_ENDPOINT` to a deployed origin is a one-line config change once the proxy ships.
    ///
    /// "Unusable" is checked rather than assumed - the value must parse, carry an `https` scheme, and
    /// have a host - so a mistyped endpoint stays inert rather than firing doomed requests.
    static func configured(
        bundle: Bundle = .main,
        transport: any CoachProxyTransport = URLSessionCoachProxyTransport()
    ) -> CoachProxyClient? {
        guard let endpoint = endpoint(fromOrigin: bundle.object(forInfoDictionaryKey: endpointInfoPlistKey)) else {
            return nil
        }
        let secret = secret(fromValue: bundle.object(forInfoDictionaryKey: secretInfoPlistKey))
        return CoachProxyClient(endpoint: endpoint, sharedSecret: secret, transport: transport)
    }

    /// Resolves a configured proxy origin into the `POST /coach` URL this client targets, or `nil` if
    /// the value is missing, empty, not a string, or not a usable HTTPS origin. The configured value is
    /// the full route origin (e.g. `https://<worker>/coach`); it is used as-is, mirroring how the
    /// Variety Language provider is wired with its full route URL.
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
        return url
    }

    /// Resolves the configured shared secret, or `nil` if it is missing, not a string, or empty after
    /// trimming. `nil` is a valid state here (an open dev Worker), so an empty value simply means "send
    /// no bearer" rather than "unconfigured".
    static func secret(fromValue value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The single stateless coach call: send the derived `context` plus the user's `message`, return
    /// the trimmed reply. Throws on an empty/oversized message (locally, before any network), and on
    /// any transport failure, timeout, non-2xx, or empty reply so the caller can degrade gracefully.
    func reply(to message: String, context: CoachContextBundle) async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw CoachError.emptyMessage }
        guard trimmedMessage.count <= messageCharacterLimit else {
            throw CoachError.messageTooLong(limit: messageCharacterLimit)
        }

        let requestBody = try JSONEncoder().encode(CoachRequest(context: context, message: trimmedMessage))
        var headers: [String: String] = [:]
        if let sharedSecret, !sharedSecret.isEmpty {
            headers["Authorization"] = "Bearer \(sharedSecret)"
        }

        let (data, statusCode) = try await transport.post(
            to: endpoint,
            jsonBody: requestBody,
            headers: headers,
            timeoutSeconds: timeoutSeconds
        )
        guard (200..<300).contains(statusCode) else { throw CoachError.badStatus(statusCode) }

        let response = try JSONDecoder().decode(CoachResponse.self, from: data)
        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw CoachError.emptyReply }
        return reply
    }
}

// MARK: - Wire contract

/// The request body sent to the proxy: the audited non-identifying context bundle plus the user's
/// message, and nothing else. This is the only shape that leaves the device for the coach.
private struct CoachRequest: Encodable {
    let context: CoachContextBundle
    let message: String
}

/// The proxy response - just the coach's reply text.
private struct CoachResponse: Decodable {
    let reply: String
}

// MARK: - Transport seam

/// The HTTP seam the coach client posts through, so tests exercise the request/response contract
/// without a live network. Mirrors `VarietyLanguageProxyTransport`; a conforming transport **must**
/// enforce `timeoutSeconds` so the client's `await` is always bounded.
protocol CoachProxyTransport: Sendable {
    /// POST `jsonBody` to `url` as `application/json`, applying any extra `headers` (e.g. an
    /// `Authorization` bearer for the Worker's abuse gate), and return the response body plus HTTP
    /// status code. Throws on transport failure (offline, DNS, TLS, timeout).
    func post(
        to url: URL,
        jsonBody: Data,
        headers: [String: String],
        timeoutSeconds: Double
    ) async throws -> (data: Data, statusCode: Int)
}

/// The production transport: a plain `URLSession` POST with a per-request timeout. No caching, no
/// cookies, no persistence beyond the in-flight request - conversation memory, if any, is the
/// caller's and lives on-device only.
struct URLSessionCoachProxyTransport: CoachProxyTransport {
    var session: URLSession = .shared

    func post(
        to url: URL,
        jsonBody: Data,
        headers: [String: String],
        timeoutSeconds: Double
    ) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = jsonBody

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachProxyClient.CoachError.notHTTP
        }
        return (data, http.statusCode)
    }
}
