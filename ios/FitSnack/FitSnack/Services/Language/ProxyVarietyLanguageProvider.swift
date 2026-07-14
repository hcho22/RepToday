import Foundation

/// The thin stateless proxy client (US-N05) that fulfills the `VarietyLanguageProvider` seam
/// (US-G03): it makes exactly one Claude call *per request* by POSTing the day's contrast to the
/// key-holding proxy (a Cloudflare Worker - see `proxy/README.md`) and returning the LLM-authored
/// line. The model API key never lives in the app; the client only ever talks to the proxy.
///
/// The provider is a best-effort upgrade over the deterministic template, **never** a dependency the
/// app waits on. Two guarantees make it safe to `await` from `VarietyLanguageResolver`:
///
/// - **Bounded.** Every call carries a short `timeoutSeconds` (default `defaultTimeoutSeconds`),
///   enforced by the transport, so the resolver's `await` always returns quickly.
/// - **Throws on anything unusual.** A non-2xx status, an undecodable body, or an empty line all
///   throw, and the resolver falls back to the offline template. The app never blocks and never
///   shows a blank.
///
/// **Privacy - the request carries no user logs and no PII.** Only the contrast the engine already
/// produced (today's lead pillar and, when it differs, yesterday's) is sent - never the user's
/// `why`, profile, identity, or history. That keeps the "stores no user logs at rest" contract
/// trivially true on the client side: there is nothing sensitive to persist because nothing
/// sensitive is ever sent. The `user` parameter of `line(for:user:)` is intentionally unused.
///
/// The MVP ships **no** provider (US-N05 is Phase 2), so `VarietyLanguageResolver.provider` stays
/// `nil` and every note is template-sourced. Wiring this in is a one-liner once the proxy is
/// deployed - see `proxy/README.md`:
///
/// ```swift
/// let provider = ProxyVarietyLanguageProvider(endpoint: URL(string: "https://<worker>/variety-language")!)
/// let resolver = VarietyLanguageResolver(provider: provider, isOnline: { /* reachability */ })
/// ```
struct ProxyVarietyLanguageProvider: VarietyLanguageProvider {

    /// The default per-request timeout. Short by design: the Variety Language line is a felt-nicety,
    /// so the app would rather show the instant template than wait on the network.
    static let defaultTimeoutSeconds: Double = 4

    /// Failures the provider raises so the resolver falls back to the template. Each maps to a
    /// distinct proxy-contract violation; all are recovered identically upstream (fall back), the
    /// cases exist only for tests and diagnostics.
    enum ProxyError: Error, Equatable {
        /// The response was not an HTTP response (should not happen over HTTPS).
        case notHTTP
        /// The proxy returned a non-2xx status.
        case badStatus(Int)
        /// The proxy returned a 2xx with an empty/whitespace line - treated as no answer.
        case emptyLine
    }

    /// The proxy endpoint (the Worker route that accepts the contrast and returns `{ "line": ... }`).
    let endpoint: URL
    /// The per-request timeout handed to the transport.
    let timeoutSeconds: Double
    /// The HTTP seam, injected so tests exercise the request/response contract without a live network.
    let transport: any VarietyLanguageProxyTransport

    init(
        endpoint: URL,
        timeoutSeconds: Double = ProxyVarietyLanguageProvider.defaultTimeoutSeconds,
        transport: any VarietyLanguageProxyTransport = URLSessionVarietyLanguageProxyTransport()
    ) {
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    /// The single LLM call for a session's Variety Language. Sends only the contrast (no `user`
    /// data) and returns the trimmed proxy line, throwing on any failure, timeout, non-2xx, or empty
    /// line so the resolver can fall back to the template.
    func line(for contrast: VarietyLanguage.SessionContrast, user: User) async throws -> String {
        let requestBody = try JSONEncoder().encode(ProxyRequest(contrast: contrast))
        let (data, statusCode) = try await transport.post(
            to: endpoint,
            jsonBody: requestBody,
            timeoutSeconds: timeoutSeconds
        )
        guard (200..<300).contains(statusCode) else { throw ProxyError.badStatus(statusCode) }

        let response = try JSONDecoder().decode(ProxyResponse.self, from: data)
        let line = response.line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { throw ProxyError.emptyLine }
        return line
    }
}

// MARK: - Wire contract

/// The request body sent to the proxy - the engine's genuine contrast and nothing else. `today` /
/// `yesterday` are the stable machine `Pillar` raw values; `*Label` are the user-facing words from
/// `VarietyLanguage.label(for:)`, so the proxy phrases with the product's own vocabulary without
/// re-deriving it. `yesterday`/`yesterdayLabel` are omitted when there is no genuine prior contrast,
/// so the proxy can never invent a "yesterday".
private struct ProxyRequest: Encodable {
    let today: String
    let yesterday: String?
    let todayLabel: String
    let yesterdayLabel: String?

    init(contrast: VarietyLanguage.SessionContrast) {
        today = contrast.today.rawValue
        todayLabel = VarietyLanguage.label(for: contrast.today)
        yesterday = contrast.yesterday?.rawValue
        yesterdayLabel = contrast.yesterday.map(VarietyLanguage.label(for:))
    }
}

/// The proxy response - just the single line the engine's contrast justified.
private struct ProxyResponse: Decodable {
    let line: String
}

// MARK: - Transport seam

/// The HTTP seam the proxy provider posts through, so tests exercise the request/response contract
/// without a live network. A conforming transport **must** enforce `timeoutSeconds` so the
/// provider's `await` is always bounded.
protocol VarietyLanguageProxyTransport: Sendable {
    /// POST `jsonBody` to `url` as `application/json` and return the response body plus HTTP status
    /// code. Throws on transport failure (offline, DNS, TLS, timeout).
    func post(to url: URL, jsonBody: Data, timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int)
}

/// The production transport: a plain `URLSession` POST with a per-request timeout. No caching, no
/// cookies, no persistence beyond the in-flight request.
struct URLSessionVarietyLanguageProxyTransport: VarietyLanguageProxyTransport {
    var session: URLSession = .shared

    func post(to url: URL, jsonBody: Data, timeoutSeconds: Double) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonBody

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyVarietyLanguageProvider.ProxyError.notHTTP
        }
        return (data, http.statusCode)
    }
}
