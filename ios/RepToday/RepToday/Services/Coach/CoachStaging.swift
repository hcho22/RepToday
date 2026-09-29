#if COACH_STAGING
import Foundation
import CryptoKit

/// The Coach staging lane (`CoachStaging` build configuration and `RepTodayCoachStaging` scheme).
/// Never compiled into Release. It talks to the separate `reptoday-coach-staging` Worker on
/// workers.dev, keeps its own App Attest key id, and appends the server's fixed rejection label to
/// the existing `[RepTodayCoach]` failure line. See docs/coach-runtime-authentication.md.
enum CoachStaging {
    static let keyStoreName = "coachStagingAppAttestKeyV2"

    /// Exactly the staging Worker's workers.dev `/coach` URL; anything else returns nil.
    static func endpoint(_ url: URL) -> URL? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path == "/coach", let host = url.host,
              host.range(of: "^reptoday-coach-staging\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.workers\\.dev$",
                         options: .regularExpression) != nil,
              url.absoluteString == "https://\(host)/coach" else { return nil }
        return url
    }

    /// The real runtime transport pointed at staging. Requests go to `endpoint`; the signed payload
    /// still names the production protocol origin, so App Attest bytes match production exactly.
    static func client(endpoint: URL,
                       safetyIdentifierProvider: @escaping @Sendable () -> CoachSafetyIdentifier?,
                       diagnostics: CoachDiagnostics,
                       attester: any CoachAppAttesting = DeviceCoachAppAttester(),
                       purchase: any CoachPurchaseProofProviding = StoreKitCoachPurchaseProof(),
                       keys: any CoachAuthenticationKeyStoring = DefaultsCoachAuthenticationKeyStore(name: keyStoreName),
                       configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) -> CoachProxyClient {
        let labels = CoachStagingLabels()
        let labelled = CoachDiagnostics { line in for value in labels.annotatedLines(line) { diagnostics.emit(value) } }
        let http = BoundedCoachHTTPTransport(configuration: configuration, destination: endpoint, labels: labels)
        let transport = RuntimeAuthenticatedCoachTransport(attester: attester, purchase: purchase, keys: keys, http: http,
                                                           diagnostics: labelled, destination: endpoint, stagingRecorder: labels)
        return CoachProxyClient(endpoint: endpoint, safetyIdentifierProvider: safetyIdentifierProvider,
                                transport: transport, diagnostics: labelled)
    }
}

/// The latest staging response label, kept only if it is one of the server's closed
/// `<stage>/<reason>` pairs (`proxy/src/coach-auth-diagnostics.js`). Consumed by the next failure line.
final class CoachStagingLabels: @unchecked Sendable {
    static let header = "X-RepToday-Coach-Diagnostic"
    /// The staging server's non-secret digest prefixes of what it checked an assertion against.
    static let digestHeader = "X-RepToday-Coach-Assertion-Digest"
    static let attestationChunk = 800
    private static let token: Set<String> = ["token_syntax", "token_mac", "token_claims", "token_future", "token_expired"]
    private static let final: [String: Set<String>] = [
        "worker_envelope": ["missing_proof", "proof_envelope", "enrollment_envelope", "delete_envelope",
                            "attestation_encoding", "assertion_encoding"],
        "worker_token": token,
        "worker_state": ["denied", "not_authorized"],
        "worker_operator": ["authorization", "request_shape"],
        "worker_handler": ["authorization"],
        "worker_premium": ["denied", "presented_environment", "presented_chain", "status_identity",
                           "status_count", "status_match", "premium_policy"],
        "do_preflight": ["key_format", "prefix_format", "request_shape", "attestation_encoding", "assertion_encoding"],
        "do_token_entry": token,
        "do_token_transaction": token,
        "do_state": ["denied", "pending_challenge", "enrollment_conflict"],
        "do_attestation": ["attestation_cbor", "attestation_shape", "attestation_certificate", "attestation_chain",
                           "attestation_result", "attestation_identity"],
        "do_assertion": ["assertion_cbor", "assertion_shape", "assertion_counter", "assertion_signature", "assertion_result"],
    ]
    private static let guardStages: Set<String> = ["worker_envelope", "worker_state", "do_preflight", "do_token_entry",
                                                   "do_token_transaction", "do_state"]
    private static let guardReasons: Set<String> = ["envelope", "key_format", "prefix_format", "token_syntax", "token_mac",
                                                    "token_claims", "token_future", "token_expired", "denied"]
    private let lock = NSLock()
    private var latest: String?
    private var serverDigest: String?
    private var signedDigest: String?
    private var clientDataHash: String?
    private var assertion: String?
    private var attestationObject: String?

    static var all: Set<String> {
        var labels = Set(final.flatMap { stage, reasons in reasons.map { "\(stage)/\($0)" } })
        for stage in guardStages { for reason in guardReasons { labels.insert("\(stage)/\(reason)") } }
        return labels
    }
    static func valid(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 64 else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        let (stage, reason) = (parts[0], parts[1])
        return all.contains("\(stage)/\(reason)") ? value : nil
    }
    static func validDigest(_ value: String?) -> String? {
        guard let value, value.range(of: "^payload=[0-9a-f]{16} body=[0-9a-f]{16} transaction=[0-9a-f]{16} challenge=[A-Za-z0-9_-]{8}$",
                                     options: .regularExpression) != nil else { return nil }
        return value
    }
    /// Every accepted response replaces the label and digest, so a success never leaves a stale one behind.
    func record(_ value: String?, digest: String? = nil) {
        lock.lock(); latest = Self.valid(value); serverDigest = Self.validDigest(digest); lock.unlock()
    }
    /// What this device signed: the full clientDataHash, and prefixes in the server's digest format.
    func signed(payload: Data, body: Data, transaction: String, challenge: String, assertion: Data) {
        let hex = { (data: Data) in SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let payloadHash = hex(payload), bodyHash = hex(body), transactionHash = hex(Data(transaction.utf8))
        lock.lock(); defer { lock.unlock() }
        signedDigest = "payload=\(payloadHash.prefix(16)) body=\(bodyHash.prefix(16)) transaction=\(transactionHash.prefix(16)) challenge=\(challenge.prefix(8))"
        clientDataHash = payloadHash; self.assertion = assertion.base64EncodedString()
    }
    func attestation(_ value: Data) { lock.lock(); attestationObject = value.base64EncodedString(); lock.unlock() }
    func annotate(_ line: String) -> String { annotatedLines(line)[0] }
    /// The failure line with its label and the server's digests; after an assertion rejection, also what
    /// the device signed, its assertion and its enrollment attestation (chunked so no log line truncates).
    func annotatedLines(_ line: String) -> [String] {
        lock.lock(); defer { latest = nil; serverDigest = nil; lock.unlock() }
        guard let label = latest else { return [line] }
        guard label.hasPrefix("do_assertion/") else { return [line + " label=" + label] }
        var lines = [line + " label=" + label + (serverDigest.map { " server " + $0 } ?? "")]
        guard let signedDigest, let clientDataHash, let assertion else { return lines }
        lines.append("[RepTodayCoach] staging signed " + signedDigest)
        lines.append("[RepTodayCoach] staging clientDataHash=" + clientDataHash)
        lines.append("[RepTodayCoach] staging assertion=" + assertion)
        if let attestationObject {
            let characters = Array(attestationObject)
            let parts = stride(from: 0, to: characters.count, by: Self.attestationChunk).map {
                String(characters[$0..<min($0 + Self.attestationChunk, characters.count)]) }
            for (index, part) in parts.enumerated() {
                lines.append("[RepTodayCoach] staging attestation part=\(index + 1)/\(parts.count) " + part)
            }
        }
        return lines
    }
}
#endif
