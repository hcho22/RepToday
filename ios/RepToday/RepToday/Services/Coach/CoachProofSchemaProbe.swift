import Foundation
import CryptoKit
import Security
import Observation

/// Schema evidence only. This never authorizes a purchase, enrolls with the Worker, or calls a model.
/// Category byte order/aliases/availability remain unresolved; even verified bytes return unsupported.
enum CoachSchemaFailure: Error { case malformed, unsupported }

struct CoachSchemaObservation: Equatable, Sendable {
    enum ValueType: String, Sendable { case unsigned, bytes4, bytes, text, other }
    enum Property: String, CaseIterable, Sendable {
        case attestationCategory = "apple_validation_category_01"
        case attestationVersion = "apple_bundle_version_01"
        case assertionCategory = "validationCategory"
        case assertionVersion = "bundleVersion"
    }
    enum ValueFlag: String, Sendable {
        case categoryUnsignedTwo = "expected-category-2=unsigned"
        case categoryLittleEndianTwo = "expected-category-2=little-endian-bytes4"
        case categoryBigEndianTwo = "expected-category-2=big-endian-bytes4"
        case categoryOther = "expected-category-2=unsupported"
        case versionMatches = "bundle-version=matches-this-build"
        case versionDiffers = "bundle-version=differs-from-this-build"
        case versionUnsupported = "bundle-version=unsupported"
    }
    struct Field: Equatable, Sendable { let property: Property; let type: ValueType; let flag: ValueFlag }
    let flags: UInt8
    let fields: [Field]
    let unknownProperties: Bool
    let hasExtensions: Bool
    var lines: [String] {
        ["flags=\(flags)", "extensions=\(hasExtensions ? "present" : "absent")",
         "unknown-properties=\(unknownProperties ? "present" : "absent")"] +
        fields.map { "\($0.property.rawValue)=\($0.type.rawValue); \($0.flag.rawValue)" }
    }
}

/// Bounded CBOR consumer for Apple's opaque proof interface, independent of guessed extension types.
/// Only allowlisted names and type enums cross the observation boundary. No values/unknown keys do.
indirect enum CoachSchemaCBOR: Equatable {
    struct Entry: Equatable { let key: CoachSchemaCBOR; let value: CoachSchemaCBOR }
    case unsigned(UInt64), negative(Int64), bytes(Data), text(String)
    case array([CoachSchemaCBOR]), map([Entry]), other
    var bytes: Data? { if case .bytes(let value) = self { return value }; return nil }
    var text: String? { if case .text(let value) = self { return value }; return nil }
    var array: [CoachSchemaCBOR]? { if case .array(let value) = self { return value }; return nil }
    func object() throws -> [String: CoachSchemaCBOR] {
        guard case .map(let entries) = self else { throw CoachSchemaFailure.malformed }
        var result: [String: CoachSchemaCBOR] = [:]
        for entry in entries {
            guard let key = entry.key.text else { throw CoachSchemaFailure.malformed }
            result[key] = entry.value
        }
        return result
    }
    struct Reader {
        private let data: [UInt8]
        private(set) var offset = 0
        private var remainingItems = 128
        init(_ data: Data) throws {
            guard !data.isEmpty, data.count <= 8192 else { throw CoachSchemaFailure.malformed }
            self.data = Array(data)
        }
        var atEnd: Bool { offset == data.count }
        private mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - offset else { throw CoachSchemaFailure.malformed }
            defer { offset += count }; return Data(data[offset ..< offset + count])
        }
        private mutating func length(_ info: UInt8) throws -> UInt64 {
            if info < 24 { return UInt64(info) }
            guard (24...27).contains(info) else { throw CoachSchemaFailure.malformed }
            let bytes = try take(1 << Int(info - 24))
            return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }
        mutating func read(depth: Int = 0) throws -> CoachSchemaCBOR {
            guard depth <= 8, remainingItems > 0 else { throw CoachSchemaFailure.malformed }
            remainingItems -= 1
            let initial = try take(1).first!, major = initial >> 5, info = initial & 31
            let count = try length(info)
            switch major {
            case 0: return .unsigned(count)
            case 1:
                guard count <= UInt64(Int64.max) else { throw CoachSchemaFailure.malformed }
                return .negative(-1 - Int64(count))
            case 2, 3:
                guard count <= 8192 else { throw CoachSchemaFailure.malformed }
                let bytes = try take(Int(count))
                if major == 2 { return .bytes(bytes) }
                guard count <= 256, let value = String(data: bytes, encoding: .utf8) else { throw CoachSchemaFailure.malformed }
                return .text(value)
            case 4, 5:
                guard count <= 32 else { throw CoachSchemaFailure.malformed }
                if major == 4 { return .array(try (0..<Int(count)).map { _ in try read(depth: depth + 1) }) }
                var entries: [Entry] = []
                for _ in 0..<Int(count) {
                    let key = try read(depth: depth + 1)
                    switch key { case .text, .unsigned, .negative: break; default: throw CoachSchemaFailure.malformed }
                    guard !entries.contains(where: { $0.key == key }) else { throw CoachSchemaFailure.malformed }
                    entries.append(Entry(key: key, value: try read(depth: depth + 1)))
                }
                return .map(entries)
            case 7:
                guard [20, 21, 22, 25, 26, 27].contains(info) else { throw CoachSchemaFailure.malformed }
                return .other
            default: throw CoachSchemaFailure.malformed
            }
        }
        mutating func object(keys: Set<String>) throws -> [String: CoachSchemaCBOR] {
            let object = try read().object()
            guard atEnd, Set(object.keys) == keys else { throw CoachSchemaFailure.malformed }
            return object
        }
    }
    static func observation(_ data: Data, offset: Int, flags: UInt8, bundleVersion: String?) throws -> CoachSchemaObservation {
        guard offset <= data.count else { throw CoachSchemaFailure.malformed }
        if offset == data.count {
            // Set ED with absent extension data is malformed. The converse is observed, not admitted.
            guard flags & 0x80 == 0 else { throw CoachSchemaFailure.malformed }
            return CoachSchemaObservation(flags: flags, fields: [], unknownProperties: false, hasExtensions: false)
        }
        var reader = try Reader(Data(data.dropFirst(offset)))
        let object = try reader.read().object()
        guard reader.atEnd else { throw CoachSchemaFailure.malformed }
        let categoryNames = ["apple_validation_category_01", "validationCategory"]
        let versionNames = ["apple_bundle_version_01", "bundleVersion"]
        guard categoryNames.filter({ object[$0] != nil }).count <= 1,
              versionNames.filter({ object[$0] != nil }).count <= 1 else { throw CoachSchemaFailure.malformed }
        let fields = CoachSchemaObservation.Property.allCases.compactMap { property -> CoachSchemaObservation.Field? in
            guard let value = object[property.rawValue] else { return nil }
            let type: CoachSchemaObservation.ValueType
            switch value {
            case .unsigned: type = .unsigned
            case .bytes(let bytes): type = bytes.count == 4 ? .bytes4 : .bytes
            case .text: type = .text
            default: type = .other
            }
            let flag: CoachSchemaObservation.ValueFlag
            switch property {
            case .attestationCategory, .assertionCategory:
                // Report fixed candidate-shape matches, never an admitted decoder or raw value.
                switch value {
                case .unsigned(2): flag = .categoryUnsignedTwo
                case .bytes(let bytes) where bytes == Data([2, 0, 0, 0]): flag = .categoryLittleEndianTwo
                case .bytes(let bytes) where bytes == Data([0, 0, 0, 2]): flag = .categoryBigEndianTwo
                default: flag = .categoryOther
                }
            case .attestationVersion, .assertionVersion:
                if let version = value.text, !version.isEmpty, version.utf8.count <= 64,
                   let bundleVersion, !bundleVersion.isEmpty, bundleVersion.utf8.count <= 64 {
                    flag = version == bundleVersion ? .versionMatches : .versionDiffers
                } else { flag = .versionUnsupported }
            }
            return .init(property: property, type: type, flag: flag)
        }
        let known = Set(CoachSchemaObservation.Property.allCases.map(\.rawValue))
        return CoachSchemaObservation(flags: flags, fields: fields, unknownProperties: !Set(object.keys).isSubset(of: known), hasExtensions: true)
    }
}

/// Read precisely the nonce extension path. Public iOS Security lacks SecCertificateCopyValues.
enum CoachSchemaDER {
    struct Item { let tag: UInt8; let content: Data }
    static func items(_ data: Data) throws -> [Item] {
        let bytes = Array(data); var offset = 0; var result: [Item] = []
        guard bytes.count <= 4096 else { throw CoachSchemaFailure.malformed }
        while offset < bytes.count {
            guard result.count < 32, offset + 2 <= bytes.count else { throw CoachSchemaFailure.malformed }
            let tag = bytes[offset], initial = bytes[offset + 1]; offset += 2
            var length = Int(initial)
            if initial & 0x80 != 0 {
                let size = Int(initial & 0x7f)
                guard (1...2).contains(size), offset + size <= bytes.count, bytes[offset] != 0 else { throw CoachSchemaFailure.malformed }
                length = 0
                for byte in bytes[offset ..< offset + size] { length = (length << 8) | Int(byte) }
                guard length >= 128 else { throw CoachSchemaFailure.malformed }; offset += size
            }
            guard length <= bytes.count - offset else { throw CoachSchemaFailure.malformed }
            result.append(Item(tag: tag, content: Data(bytes[offset ..< offset + length]))); offset += length
        }
        return result
    }
    static func only(_ data: Data, tag: UInt8) throws -> Data {
        let values = try items(data)
        guard values.count == 1, values[0].tag == tag else { throw CoachSchemaFailure.malformed }
        return values[0].content
    }
    static func nonce(_ certificate: Data) throws -> Data {
        let certificate = try items(only(certificate, tag: 0x30))
        guard certificate.count == 3, certificate[0].tag == 0x30 else { throw CoachSchemaFailure.malformed }
        let tbs = try items(certificate[0].content)
        let extensions = tbs.filter { $0.tag == 0xa3 }
        guard extensions.count == 1 else { throw CoachSchemaFailure.malformed }
        let values = try items(only(extensions[0].content, tag: 0x30))
        let oid = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02])
        var nonces: [Data] = []
        for value in values {
            guard value.tag == 0x30 else { throw CoachSchemaFailure.malformed }
            let parts = try items(value.content)
            guard parts.count >= 2, parts[0].tag == 6 else { throw CoachSchemaFailure.malformed }
            if parts[0].content == oid {
                guard (2...3).contains(parts.count), parts.last!.tag == 4,
                      parts.count == 2 || (parts[1].tag == 1 && parts[1].content == Data([0xff]))
                else { throw CoachSchemaFailure.malformed }
                let sequence = try only(parts.last!.content, tag: 0x30)
                let tagged = try only(sequence, tag: 0xa1)
                let nonce = try only(tagged, tag: 4)
                guard nonce.count == 32 else { throw CoachSchemaFailure.malformed }
                nonces.append(nonce)
            }
        }
        guard nonces.count == 1 else { throw CoachSchemaFailure.malformed }
        return nonces[0]
    }
}

struct CoachSchemaCertificate: Sendable { let key: Data; let nonce: Data }

struct CoachProofSchemaVerifier: Sendable {
    typealias CertificateCheck = @Sendable ([Data], Date) throws -> CoachSchemaCertificate
    private let checkCertificate: CertificateCheck
    private let bundleVersion: String?
    init(bundleVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
         checkCertificate: @escaping CertificateCheck = { try CoachSchemaAppleCertificate.check($0, now: $1) }) {
        self.bundleVersion = bundleVersion; self.checkCertificate = checkCertificate
    }
    static func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    static func validPrefix(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
    struct Enrollment: Sendable { let key: Data; let appHash: Data; let schema: CoachSchemaObservation }
    func attestation(_ data: Data, keyID: String, challenge: Data, prefix: String, now: Date) throws -> Enrollment {
        guard Self.validPrefix(prefix), challenge.count == 32, let keyHash = Data(base64Encoded: keyID),
              keyHash.count == 32, keyHash.base64EncodedString() == keyID else { throw CoachSchemaFailure.malformed }
        var reader = try CoachSchemaCBOR.Reader(data)
        let object = try reader.object(keys: ["attStmt", "authData", "fmt"])
        guard object["fmt"]?.text == "apple-appattest", let auth = object["authData"]?.bytes,
              (87...512).contains(auth.count) else { throw CoachSchemaFailure.malformed }
        let stmt = try object["attStmt"]!.object()
        guard let chain = stmt["x5c"]?.array, chain.count == 2, stmt["receipt"]?.bytes?.isEmpty == false,
              let leaf = chain[0].bytes, let intermediate = chain[1].bytes,
              !leaf.isEmpty, !intermediate.isEmpty, leaf.count <= 4096, intermediate.count <= 4096
        else { throw CoachSchemaFailure.malformed }
        let certificate = try checkCertificate([leaf, intermediate], now)
        let appHash = Self.digest(Data((prefix + ".com.reptoday.app").utf8))
        guard certificate.nonce == Self.digest(auth + Self.digest(challenge)), Self.digest(certificate.key) == keyHash,
              Data(auth.prefix(32)) == appHash, auth[32] & 0x40 != 0,
              auth[33..<37].allSatisfy({ $0 == 0 }),
              Data(auth[37..<53]) == Data("appattest".utf8) + Data(repeating: 0, count: 7),
              auth[53] == 0, auth[54] == 32, Data(auth[55..<87]) == keyHash
        else { throw CoachSchemaFailure.malformed }
        // Consume the actual COSE object before observing the trailing extension map.
        var credential = try CoachSchemaCBOR.Reader(Data(auth.dropFirst(87)))
        guard case .map = try credential.read() else { throw CoachSchemaFailure.malformed }
        let schema = try CoachSchemaCBOR.observation(auth, offset: 87 + credential.offset, flags: auth[32], bundleVersion: bundleVersion)
        return Enrollment(key: certificate.key, appHash: appHash, schema: schema)
    }
    func assertion(_ data: Data, enrollment: Enrollment, challenge: Data) throws -> CoachSchemaObservation {
        guard challenge.count == 32, data.count <= 1024 else { throw CoachSchemaFailure.malformed }
        var reader = try CoachSchemaCBOR.Reader(data)
        let object = try reader.object(keys: ["authenticatorData", "signature"])
        guard let auth = object["authenticatorData"]?.bytes, (37...512).contains(auth.count),
              let signature = object["signature"]?.bytes, !signature.isEmpty, signature.count <= 80,
              Data(auth.prefix(32)) == enrollment.appHash, auth[32] & 0x40 == 0
        else { throw CoachSchemaFailure.malformed }
        let counter = auth[33..<37].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard counter > 0, counter <= 0x7fffffff else { throw CoachSchemaFailure.malformed }
        let publicKey = try P256.Signing.PublicKey(x963Representation: enrollment.key)
        let parsedSignature = try P256.Signing.ECDSASignature(derRepresentation: signature)
        // Match reviewed node-app-attest: SHA256(auth || SHA256(payload)), then ECDSA/SHA256.
        let nonce = Self.digest(auth + Self.digest(challenge))
        guard publicKey.isValidSignature(parsedSignature, for: nonce) else { throw CoachSchemaFailure.malformed }
        return try CoachSchemaCBOR.observation(auth, offset: 37, flags: auth[32], bundleVersion: bundleVersion)
    }
}

enum CoachSchemaAppleCertificate {
    static func check(_ bytes: [Data], now: Date) throws -> CoachSchemaCertificate {
        guard let rootData = Data(base64Encoded: root) else { throw CoachSchemaFailure.malformed }
        return try check(bytes, now: now, anchor: rootData)
    }
    /// Offline tests supply a synthetic public root to exercise the real Security trust consumer.
    /// The installed probe always calls the two-argument function with the pinned Apple anchor.
    static func check(_ bytes: [Data], now: Date, anchor rootData: Data) throws -> CoachSchemaCertificate {
        guard bytes.count == 2, let leaf = SecCertificateCreateWithData(nil, bytes[0] as CFData),
              let intermediate = SecCertificateCreateWithData(nil, bytes[1] as CFData),
              let anchor = SecCertificateCreateWithData(nil, rootData as CFData)
        else { throw CoachSchemaFailure.malformed }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf, intermediate] as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust, SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetVerifyDate(trust, now as CFDate) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil), SecTrustGetCertificateCount(trust) == 3,
              let key = SecCertificateCopyKey(leaf), let exported = SecKeyCopyExternalRepresentation(key, nil)
        else { throw CoachSchemaFailure.malformed }
        let keyData = exported as Data
        guard keyData.count == 65, keyData.first == 4 else { throw CoachSchemaFailure.malformed }
        return CoachSchemaCertificate(key: keyData, nonce: try CoachSchemaDER.nonce(bytes[0]))
    }
    // Public Apple trust anchor, identical DER to proxy/src/apple-trust-roots.js; never a credential.
    // https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
    static let root = "MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYwJAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNaFw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlvbiBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9ybmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijVoyFraWVIyd/dganmrduC1bmTBGwD"
}

struct CoachSchemaProbeResult: Equatable, Sendable {
    enum Classification: String, Sendable { case unsupported, malformed }
    let classification: Classification
    let attestation: CoachSchemaObservation?
    let assertion: CoachSchemaObservation?
    var text: String {
        guard let attestation, let assertion else { return "result=\(classification.rawValue)\nbindings=not-verified" }
        return (["result=unsupported", "bindings=verified", "distribution=unresolved", "attestation:"] +
                attestation.lines + ["assertion:"] + assertion.lines).joined(separator: "\n")
    }
}

/// One content-free attempt marker survives relaunch. Proofs, key ID and app prefix never persist.
@MainActor @Observable
final class CoachProofSchemaProbe {
    static let attemptName = "CoachProofSchemaProbe.oneAttemptV1"
    private let defaults: UserDefaults
    private let attester: any CoachAppAttesting
    private let verifier: CoachProofSchemaVerifier
    private let enabled: Bool
    private let random: @Sendable () throws -> Data
    private let timeout: Double
    private var generation: UInt64 = 0
    private(set) var running = false
    private(set) var result: CoachSchemaProbeResult?
    var attempted: Bool { defaults.object(forKey: Self.attemptName) != nil }
    var available: Bool { enabled && attester.isSupported && !attempted && !running }
    init(enabled: Bool, defaults: UserDefaults = .standard, attester: any CoachAppAttesting = DeviceCoachAppAttester(),
         verifier: CoachProofSchemaVerifier = CoachProofSchemaVerifier(), timeout: Double = 30,
         random: @escaping @Sendable () throws -> Data = {
             var bytes = [UInt8](repeating: 0, count: 32)
             guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CoachSchemaFailure.unsupported }
             return Data(bytes)
         }) {
        self.enabled = enabled; self.defaults = defaults; self.attester = attester
        self.verifier = verifier; self.random = random; self.timeout = timeout
    }
    func run(prefix: String, confirmed: Bool) async {
        guard available, confirmed, CoachProofSchemaVerifier.validPrefix(prefix),
              timeout.isFinite, timeout > 0, timeout <= 30 else { return }
        // Competing screens and interrupted runs may never regenerate a second key automatically.
        defaults.set(true, forKey: Self.attemptName)
        running = true; result = nil; let expected = generation
        let attester = attester, verifier = verifier, random = random
        let value: CoachSchemaProbeResult
        do {
            value = try await boundedCoachOperation(seconds: timeout) {
                do {
                    let enrollmentChallenge = try random(), assertionChallenge = try random()
                    guard enrollmentChallenge.count == 32, assertionChallenge.count == 32,
                          enrollmentChallenge != assertionChallenge else { throw CoachSchemaFailure.unsupported }
                    try Task.checkCancellation()
                    let key = try await attester.generateKey()
                    try Task.checkCancellation()
                    guard let keyHash = Data(base64Encoded: key), keyHash.count == 32,
                          keyHash.base64EncodedString() == key else { throw CoachSchemaFailure.malformed }
                    let attestation = try await attester.attest(key: key, hash: CoachProofSchemaVerifier.digest(enrollmentChallenge))
                    try Task.checkCancellation()
                    let enrollment = try verifier.attestation(attestation, keyID: key, challenge: enrollmentChallenge, prefix: prefix, now: Date())
                    try Task.checkCancellation()
                    let assertion = try await attester.assertion(key: key, hash: CoachProofSchemaVerifier.digest(assertionChallenge))
                    try Task.checkCancellation()
                    let schema = try verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
                    return CoachSchemaProbeResult(classification: .unsupported, attestation: enrollment.schema, assertion: schema)
                } catch let failure as CoachSchemaFailure {
                    return CoachSchemaProbeResult(classification: failure == .malformed ? .malformed : .unsupported, attestation: nil, assertion: nil)
                } catch {
                    // Never stringify Apple/CryptoKit/Security errors or opaque proof bytes.
                    return CoachSchemaProbeResult(classification: .unsupported, attestation: nil, assertion: nil)
                }
            }
        } catch { value = CoachSchemaProbeResult(classification: .unsupported, attestation: nil, assertion: nil) }
        guard generation == expected, !Task.isCancelled else { return }
        result = value; running = false
    }
    func close() { generation &+= 1; running = false; result = nil }
}
