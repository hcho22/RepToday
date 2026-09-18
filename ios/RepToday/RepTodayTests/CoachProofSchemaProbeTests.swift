import XCTest
import CryptoKit
@testable import RepToday

/// Entirely synthetic, in-memory proofs. These are not Apple-signed or TestFlight evidence.
final class CoachProofSchemaVerifierTests: XCTestCase {
    private let prefix = "0000000000"
    private let challenge = Data(repeating: 1, count: 32)
    private let assertionChallenge = Data(repeating: 2, count: 32)
    private func fixture() throws -> (SchemaFixture, CoachProofSchemaVerifier.Enrollment) {
        let value = SchemaFixture(prefix: prefix)
        let enrollment = try value.verifier.attestation(value.attestation(hash: CoachProofSchemaVerifier.digest(challenge)),
            keyID: value.keyID, challenge: challenge, prefix: prefix, now: Date())
        return (value, enrollment)
    }
    func testFullSignaturesBindBothChallengesIdentityKeyAndEntireExtensionData() throws {
        let (value, enrollment) = try fixture()
        let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge))
        let schema = try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
        XCTAssertEqual(schema.flags, 0x80)
        XCTAssertEqual(schema.fields, [.init(property: .assertionCategory, type: .bytes4, flag: .categoryLittleEndianTwo), .init(property: .assertionVersion, type: .text, flag: .versionMatches)])
        XCTAssertEqual(enrollment.schema.fields, [.init(property: .attestationCategory, type: .bytes4, flag: .categoryLittleEndianTwo)])
        XCTAssertThrowsError(try value.verifier.assertion(assertion, enrollment: enrollment, challenge: challenge))
        let altered = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), tamper: true)
        XCTAssertThrowsError(try value.verifier.assertion(altered, enrollment: enrollment, challenge: assertionChallenge))
        let other = SchemaFixture(prefix: prefix)
        let otherEnrollment = CoachProofSchemaVerifier.Enrollment(key: other.key.publicKey.x963Representation,
            appHash: enrollment.appHash, schema: enrollment.schema)
        XCTAssertThrowsError(try value.verifier.assertion(assertion, enrollment: otherEnrollment, challenge: assertionChallenge))
        XCTAssertThrowsError(try value.verifier.attestation(value.attestation(hash: CoachProofSchemaVerifier.digest(challenge)),
            keyID: other.keyID, challenge: challenge, prefix: prefix, now: Date()))
        XCTAssertThrowsError(try value.verifier.attestation(value.attestation(hash: CoachProofSchemaVerifier.digest(challenge)),
            keyID: value.keyID, challenge: assertionChallenge, prefix: prefix, now: Date()))
        XCTAssertThrowsError(try value.verifier.attestation(value.attestation(hash: CoachProofSchemaVerifier.digest(challenge)),
            keyID: value.keyID, challenge: challenge, prefix: "1111111111", now: Date()))
    }
    func testSignedFlagConventionIsObservedWithoutBecomingDistributionAdmission() throws {
        let (value, enrollment) = try fixture()
        let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), flags: 0)
        let schema = try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
        XCTAssertEqual(schema.flags, 0)
        XCTAssertTrue(schema.hasExtensions)
        let result = CoachSchemaProbeResult(classification: .unsupported, attestation: enrollment.schema, assertion: schema)
        XCTAssertTrue(result.text.hasPrefix("result=unsupported\nbindings=verified\ndistribution=unresolved"))
        XCTAssertFalse(result.text.contains(value.keyID))
        XCTAssertFalse(result.text.contains(prefix))
        XCTAssertFalse(result.text.contains("NOT_AN_APP_VERSION"))
    }
    func testMissingExtensionsAndUnexpectedPropertiesHaveOnlyBoundedOutput() throws {
        let (value, enrollment) = try fixture()
        let absent = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), flags: 0, extensionData: Data())
        XCTAssertFalse(try value.verifier.assertion(absent, enrollment: enrollment, challenge: assertionChallenge).hasExtensions)
        let unknown = SchemaFixture.map([("UNKNOWN_PRIVATE_VALUE", SchemaFixture.text("DO_NOT_EMIT")),
                                        ("validationCategory", Data([0x82, 1, 2]))])
        let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), extensionData: unknown)
        let schema = try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
        XCTAssertTrue(schema.unknownProperties)
        XCTAssertEqual(schema.fields, [.init(property: .assertionCategory, type: .other, flag: .categoryOther)])
        let text = schema.lines.joined(separator: "\n")
        XCTAssertFalse(text.contains("UNKNOWN_PRIVATE_VALUE"))
        XCTAssertFalse(text.contains("DO_NOT_EMIT"))
    }
    func testMalformedAmbiguousAndOversizedSignedStructuresFailCleanly() throws {
        let (value, enrollment) = try fixture()
        let duplicate = SchemaFixture.map([("validationCategory", Data([2])), ("validationCategory", Data([2]))])
        let ambiguousCategories = SchemaFixture.map([("validationCategory", Data([2])), ("apple_validation_category_01", Data([2]))])
        let ambiguousVersions = SchemaFixture.map([("bundleVersion", SchemaFixture.text("1")), ("apple_bundle_version_01", SchemaFixture.text("1"))])
        for extensions in [duplicate, ambiguousCategories, ambiguousVersions, Data([0xa1]), Data([0xa0, 0xa0]), Data([0xbf, 0xff])] {
            let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), extensionData: extensions)
            XCTAssertThrowsError(try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge))
        }
        for counter: UInt32 in [0, 0x80000000] {
            let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), counter: counter)
            XCTAssertThrowsError(try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge))
        }
        let missing = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), extensionData: Data())
        XCTAssertThrowsError(try value.verifier.assertion(missing, enrollment: enrollment, challenge: assertionChallenge))
        let unexpectedAT = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), flags: 0xc0)
        XCTAssertThrowsError(try value.verifier.assertion(unexpectedAT, enrollment: enrollment, challenge: assertionChallenge))
        XCTAssertThrowsError(try value.verifier.assertion(Data(repeating: 0, count: 1025), enrollment: enrollment, challenge: assertionChallenge))
        var appended = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge)); appended.append(0)
        XCTAssertThrowsError(try value.verifier.assertion(appended, enrollment: enrollment, challenge: assertionChallenge))
        let rejecting = CoachProofSchemaVerifier { _, _ in throw CoachSchemaFailure.malformed }
        XCTAssertThrowsError(try rejecting.attestation(value.attestation(hash: CoachProofSchemaVerifier.digest(challenge)),
            keyID: value.keyID, challenge: challenge, prefix: prefix, now: Date()))
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([Data([0]), Data([1])], now: Date()))
        let development = value.attestation(hash: CoachProofSchemaVerifier.digest(challenge), production: false)
        XCTAssertThrowsError(try value.verifier.attestation(development, keyID: value.keyID, challenge: challenge, prefix: prefix, now: Date()))
    }
    func testFixedCandidateEncodingAndBundleAgreementFlagsNeverOutputArbitraryValues() throws {
        let (value, enrollment) = try fixture()
        for (category, flag) in [(Data([2]), CoachSchemaObservation.ValueFlag.categoryUnsignedTwo),
                                 (SchemaFixture.bytes(Data([0, 0, 0, 2])), .categoryBigEndianTwo),
                                 (SchemaFixture.bytes(Data([9, 9, 9, 9])), .categoryOther)] {
            let extensions = SchemaFixture.map([("validationCategory", category), ("bundleVersion", SchemaFixture.text("PRIVATE_VERSION"))])
            let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), extensionData: extensions)
            let schema = try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
            XCTAssertEqual(schema.fields[0].flag, flag)
            XCTAssertEqual(schema.fields[1].flag, .versionDiffers)
            XCTAssertFalse(schema.lines.joined().contains("PRIVATE_VERSION"))
        }
        for version in [SchemaFixture.text(""), SchemaFixture.text(String(repeating: "x", count: 65)), Data([1])] {
            let extensions = SchemaFixture.map([("bundleVersion", version)])
            let assertion = try value.assertion(hash: CoachProofSchemaVerifier.digest(assertionChallenge), extensionData: extensions)
            let schema = try value.verifier.assertion(assertion, enrollment: enrollment, challenge: assertionChallenge)
            XCTAssertEqual(schema.fields[0].flag, .versionUnsupported)
        }
    }
    func testNonceDERRequiresExactSingleExtensionAndNoTrailingData() throws {
        let nonce = Data(repeating: 7, count: 32)
        func tlv(_ tag: UInt8, _ data: Data) -> Data {
            Data([tag]) + (data.count < 128 ? Data([UInt8(data.count)]) : Data([0x82, UInt8(data.count >> 8), UInt8(data.count & 255)])) + data
        }
        let oid = tlv(6, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]))
        let ext = tlv(0x30, oid + tlv(4, tlv(0x30, tlv(0xa1, tlv(4, nonce)))))
        func cert(_ extensions: Data) -> Data { tlv(0x30, tlv(0x30, tlv(0xa3, tlv(0x30, extensions))) + tlv(0x30, Data()) + tlv(3, Data([0]))) }
        XCTAssertTrue(try CoachSchemaDER.nonce(cert(ext)) == nonce)
        XCTAssertThrowsError(try CoachSchemaDER.nonce(cert(ext + ext)))
        XCTAssertThrowsError(try CoachSchemaDER.nonce(cert(ext) + Data([0])))
        XCTAssertThrowsError(try CoachSchemaDER.nonce(Data([0x30, 0x80, 0, 0])))
    }
    func testActualSecurityTrustChecksPinnedRootFullChainValidityKeyAndNonce() throws {
        // Generate synthetic certificates and private keys exclusively in process memory.
        let rootKey = P256.Signing.PrivateKey(), intermediateKey = P256.Signing.PrivateKey(), leafKey = P256.Signing.PrivateKey()
        let nonce = Data(repeating: 7, count: 32)
        let root = try SchemaCertificates.certificate(key: rootKey, issuerKey: rootKey, subject: "SyntheticRoot", issuer: "SyntheticRoot", ca: true)
        let intermediate = try SchemaCertificates.certificate(key: intermediateKey, issuerKey: rootKey, subject: "SyntheticIntermediate", issuer: "SyntheticRoot", ca: true)
        let leaf = try SchemaCertificates.certificate(key: leafKey, issuerKey: intermediateKey, subject: "SyntheticLeaf", issuer: "SyntheticIntermediate", ca: false, nonce: nonce)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let checked = try CoachSchemaAppleCertificate.check([leaf, intermediate], now: now, anchor: root)
        XCTAssertTrue(checked.key == leafKey.publicKey.x963Representation)
        XCTAssertTrue(checked.nonce == nonce)
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([leaf, intermediate], now: now))
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([leaf, root], now: now, anchor: root))
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([intermediate, leaf], now: now, anchor: root))
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([leaf, intermediate], now: Date(timeIntervalSince1970: 2_200_000_000), anchor: root))
        var tampered = leaf; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try CoachSchemaAppleCertificate.check([tampered, intermediate], now: now, anchor: root))
    }
}

private enum SchemaCertificates {
    static func tlv(_ tag: UInt8, _ bytes: Data) -> Data {
        let length: Data
        if bytes.count < 128 { length = Data([UInt8(bytes.count)]) }
        else if bytes.count < 256 { length = Data([0x81, UInt8(bytes.count)]) }
        else { length = Data([0x82, UInt8(bytes.count >> 8), UInt8(bytes.count & 255)]) }
        return Data([tag]) + length + bytes
    }
    static func sequence(_ bytes: Data) -> Data { tlv(0x30, bytes) }
    static func name(_ value: String) -> Data {
        sequence(tlv(0x31, sequence(tlv(6, Data([0x55, 4, 3])) + tlv(0x0c, Data(value.utf8)))))
    }
    static func certificate(key: P256.Signing.PrivateKey, issuerKey: P256.Signing.PrivateKey,
                            subject: String, issuer: String, ca: Bool, nonce: Data? = nil) throws -> Data {
        let algorithm = sequence(tlv(6, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 4, 3, 2])))
        let keyAlgorithm = sequence(tlv(6, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 2, 1])) + tlv(6, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 3, 1, 7])))
        let spki = sequence(keyAlgorithm + tlv(3, Data([0]) + key.publicKey.x963Representation))
        let validity = sequence(tlv(0x18, Data("20200101000000Z".utf8)) + tlv(0x18, Data("20350101000000Z".utf8)))
        let constraints = sequence(tlv(6, Data([0x55, 0x1d, 0x13])) + tlv(1, Data([0xff])) + tlv(4, sequence(ca ? tlv(1, Data([0xff])) : Data())))
        let usage = sequence(tlv(6, Data([0x55, 0x1d, 0x0f])) + tlv(1, Data([0xff])) + tlv(4, tlv(3, ca ? Data([1, 6]) : Data([7, 0x80]))))
        var extensions = constraints + usage
        if let nonce {
            let oid = tlv(6, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 8, 2]))
            extensions += sequence(oid + tlv(4, sequence(tlv(0xa1, tlv(4, nonce)))))
        }
        let tbs = sequence(tlv(0xa0, tlv(2, Data([2]))) + tlv(2, Data([1])) + algorithm + name(issuer) + validity + name(subject) + spki + tlv(0xa3, sequence(extensions)))
        return sequence(tbs + algorithm + tlv(3, Data([0]) + (try issuerKey.signature(for: tbs).derRepresentation)))
    }
}

private final class SchemaFixture: @unchecked Sendable {
    let key = P256.Signing.PrivateKey()
    let prefix: String
    init(prefix: String) { self.prefix = prefix }
    var keyID: String { CoachProofSchemaVerifier.digest(key.publicKey.x963Representation).base64EncodedString() }
    var verifier: CoachProofSchemaVerifier {
        let publicKey = key.publicKey.x963Representation
        return CoachProofSchemaVerifier(bundleVersion: "NOT_AN_APP_VERSION") { chain, _ in
            guard chain.count == 2, chain[0].count == 32, chain[1] == Data([0]) else { throw CoachSchemaFailure.malformed }
            return CoachSchemaCertificate(key: publicKey, nonce: chain[0])
        }
    }
    static func header(_ major: UInt8, _ count: Int) -> Data {
        if count < 24 { return Data([(major << 5) | UInt8(count)]) }
        if count < 256 { return Data([(major << 5) | 24, UInt8(count)]) }
        return Data([(major << 5) | 25, UInt8(count >> 8), UInt8(count & 255)])
    }
    static func bytes(_ data: Data) -> Data { header(2, data.count) + data }
    static func text(_ value: String) -> Data { header(3, value.utf8.count) + Data(value.utf8) }
    static func map(_ values: [(String, Data)]) -> Data {
        header(5, values.count) + values.reduce(Data()) { $0 + text($1.0) + $1.1 }
    }
    func attestation(hash: Data, production: Bool = true) -> Data {
        let appHash = CoachProofSchemaVerifier.digest(Data((prefix + ".com.reptoday.app").utf8))
        let aaguid = production ? Data("appattest".utf8) + Data(repeating: 0, count: 7) : Data("appattestdevelop".utf8)
        let auth = appHash + Data([0x40, 0, 0, 0, 0]) + aaguid + Data([0, 32]) + Data(base64Encoded: keyID)! + Data([0xa0]) +
            Self.map([("apple_validation_category_01", Self.bytes(Data([2, 0, 0, 0])))])
        let nonce = CoachProofSchemaVerifier.digest(auth + hash)
        let stmt = Self.map([("x5c", Data([0x82]) + Self.bytes(nonce) + Self.bytes(Data([0]))), ("receipt", Self.bytes(Data([0])))])
        return Self.map([("fmt", Self.text("apple-appattest")), ("authData", Self.bytes(auth)), ("attStmt", stmt)])
    }
    func assertion(hash: Data, flags: UInt8 = 0x80, counter: UInt32 = 1, extensionData: Data? = nil, tamper: Bool = false) throws -> Data {
        let appHash = CoachProofSchemaVerifier.digest(Data((prefix + ".com.reptoday.app").utf8))
        let extensions = extensionData ?? Self.map([("validationCategory", Self.bytes(Data([2, 0, 0, 0]))), ("bundleVersion", Self.text("NOT_AN_APP_VERSION"))])
        var auth = appHash + Data([flags, UInt8(counter >> 24), UInt8((counter >> 16) & 255), UInt8((counter >> 8) & 255), UInt8(counter & 255)]) + extensions
        let signature = try key.signature(for: CoachProofSchemaVerifier.digest(auth + hash)).derRepresentation
        if tamper { auth[auth.count - 1] ^= 1 }
        return Self.map([("authenticatorData", Self.bytes(auth)), ("signature", Self.bytes(signature))])
    }
}

@MainActor
final class CoachProofSchemaProbeTests: XCTestCase {
    private final class Attester: CoachAppAttesting, @unchecked Sendable {
        let fixture = SchemaFixture(prefix: "0000000000")
        var isSupported = true
        var keys = 0; var attestations = 0; var assertions = 0
        var wait: (() async -> Void)?
        var invalidAttestation = false
        var invalidKey = false
        func generateKey() async throws -> String { keys += 1; await wait?(); return invalidKey ? "INVALID" : fixture.keyID }
        func attest(key: String, hash: Data) async throws -> Data { attestations += 1; return invalidAttestation ? Data([0]) : fixture.attestation(hash: hash) }
        func assertion(key: String, hash: Data) async throws -> Data { assertions += 1; return try fixture.assertion(hash: hash) }
    }
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "CoachSchemaProbeTests-\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func probe(_ attester: Attester, enabled: Bool = true, timeout: Double = 30) -> CoachProofSchemaProbe {
        // Distinct deterministic synthetic challenges; no genuine API or account material.
        final class Random: @unchecked Sendable {
            private let lock = NSLock(); private var count: UInt8 = 0
            func next() -> Data { lock.lock(); defer { lock.unlock() }; count += 1; return Data(repeating: count, count: 32) }
        }
        let random = Random()
        return CoachProofSchemaProbe(enabled: enabled, defaults: defaults, attester: attester,
            verifier: attester.fixture.verifier, timeout: timeout, random: { random.next() })
    }
    func testExplicitOneAttemptDoesNotPersistProofsIdentityOrChangeProductionKeyAndModelBudget() async throws {
        defaults.set("NONSECRET_EXISTING_KEY", forKey: "coachProductionAppAttestKeyV1")
        defaults.set("ready", forKey: "CoachSyntheticQA.twoRequestBudgetV1")
        let attester = Attester(), value = probe(attester)
        XCTAssertEqual(attester.keys, 0)
        await value.run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(attester.keys, 1); XCTAssertEqual(attester.attestations, 1); XCTAssertEqual(attester.assertions, 1)
        XCTAssertEqual(value.result?.classification, .unsupported)
        XCTAssertNotNil(value.result?.assertion)
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertEqual(Set(domain.keys), ["coachProductionAppAttestKeyV1", "CoachSyntheticQA.twoRequestBudgetV1", CoachProofSchemaProbe.attemptName])
        XCTAssertEqual(domain[CoachProofSchemaProbe.attemptName] as? Bool, true)
        XCTAssertEqual(domain["coachProductionAppAttestKeyV1"] as? String, "NONSECRET_EXISTING_KEY")
        XCTAssertEqual(domain["CoachSyntheticQA.twoRequestBudgetV1"] as? String, "ready")
        await value.run(prefix: "0000000000", confirmed: true)
        await probe(attester).run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(attester.keys, 1)
        value.close(); XCTAssertNil(value.result)
    }
    func testConfigurationReadinessPrefixSupportAndUnknownPersistedMarkerAllFailBeforeApple() async {
        let attester = Attester()
        await probe(attester, enabled: false).run(prefix: "0000000000", confirmed: true)
        await probe(attester).run(prefix: "0000000000", confirmed: false)
        await probe(attester).run(prefix: "untrusted\n", confirmed: true)
        attester.isSupported = false
        await probe(attester).run(prefix: "0000000000", confirmed: true)
        attester.isSupported = true
        defaults.set("unknown", forKey: CoachProofSchemaProbe.attemptName)
        await probe(attester).run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(attester.keys, 0)
    }
    func testUntrustedAttestationFailsBeforeAssertionWithoutRawErrorAndNeverRetries() async {
        let attester = Attester(); attester.invalidAttestation = true
        let value = probe(attester)
        await value.run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(value.result?.text, "result=malformed\nbindings=not-verified")
        XCTAssertEqual(attester.assertions, 0)
        await value.run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(attester.keys, 1)
    }
    func testMalformedAppleKeyFailsBeforeAttestation() async {
        let attester = Attester(); attester.invalidKey = true
        let value = probe(attester)
        await value.run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(value.result?.text, "result=malformed\nbindings=not-verified")
        XCTAssertEqual(attester.attestations, 0); XCTAssertEqual(attester.assertions, 0)
    }
    func testTimeoutAndClosingIgnoreLateAppleCallbackBeforeAnySubsequentOperation() async {
        let attester = Attester()
        attester.wait = { try? await Task.sleep(nanoseconds: 100_000_000) }
        let value = probe(attester, timeout: 0.01)
        await value.run(prefix: "0000000000", confirmed: true)
        XCTAssertEqual(value.result?.text, "result=unsupported\nbindings=not-verified")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(attester.attestations, 0); XCTAssertEqual(attester.assertions, 0)
        defaults.removeObject(forKey: CoachProofSchemaProbe.attemptName) // Only isolated test defaults.
        attester.wait = { await withCheckedContinuation { continuation in
            Task { try? await Task.sleep(nanoseconds: 20_000_000); continuation.resume() }
        } }
        let closing = probe(attester)
        let task = Task { await closing.run(prefix: "0000000000", confirmed: true) }
        while !closing.running { await Task.yield() }
        task.cancel(); closing.close(); await task.value
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(closing.result)
        XCTAssertEqual(attester.attestations, 0)
        XCTAssertTrue(closing.attempted)
    }
}
