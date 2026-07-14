import XCTest
@testable import RepToday

/// Tests for the always-valid `SessionPolicy` and its default (US-D03).
///
/// The contract under test: `SessionPolicy.default` is a fully-populated, deterministic,
/// neutral policy that equal-weights all three pillars, and every policy shape (including all
/// optional sub-structs) survives a Codable round-trip with no data loss - the persistence
/// contract the engine (Epic E) and the AI Programmer (Epic F) both depend on.
final class SessionPolicyTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Default policy values

    /// The default is fully populated with the documented values and no required field unset.
    func testDefaultPolicyHasDocumentedValues() {
        let policy = SessionPolicy.default

        XCTAssertEqual(policy.version, 1)
        XCTAssertEqual(policy.updatedAt, SessionPolicy.unprogrammedEpoch)
        XCTAssertEqual(policy.updatedBy, .default)
        XCTAssertEqual(policy.progressionRate, 1.0)
        XCTAssertEqual(policy.varietyWindow, 3)
        // A fresh default carries none of the situational overrides yet.
        XCTAssertNil(policy.coldStartContract)
        XCTAssertNil(policy.reentry)
        XCTAssertNil(policy.note)
    }

    /// The default equal-weights every pillar - all three present (strength/mobility/primal),
    /// all values equal, and none omitted.
    func testDefaultPolicyEqualWeightsAllThreePillars() {
        let weights = SessionPolicy.default.pillarWeighting

        XCTAssertEqual(Set(weights.keys), Set(Pillar.allCases))
        XCTAssertNotNil(weights[.primal], "primal must not be omitted from the weighting")
        let values = Set(weights.values)
        XCTAssertEqual(values.count, 1, "all pillar weights must be equal")
        XCTAssertEqual(weights[.strength], weights[.mobility])
        XCTAssertEqual(weights[.mobility], weights[.primal])
    }

    /// `default` is deterministic: it reads no wall clock, so it equals an independently
    /// constructed neutral policy and never varies between accesses.
    func testDefaultPolicyIsDeterministic() {
        let expected = SessionPolicy(
            version: 1,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedBy: .default,
            progressionRate: 1.0,
            pillarWeighting: [.strength: 1.0, .mobility: 1.0, .primal: 1.0],
            varietyWindow: 3,
            coldStartContract: nil,
            reentry: nil,
            note: nil
        )
        XCTAssertEqual(SessionPolicy.default, expected)
        XCTAssertEqual(SessionPolicy.default, SessionPolicy.default)
    }

    // MARK: - Codable round-trips

    /// US-D03 validation test: the default policy is stable across an encode/decode round-trip.
    func testDefaultPolicyRoundTrips() {
        assertRoundTrip(SessionPolicy.default)
    }

    /// The `[Pillar: Double]` weighting - a non-`String`/`Int`-keyed dictionary - survives the
    /// round-trip intact (equality is content-based, so key order is irrelevant).
    func testPillarWeightingRoundTripsIntact() throws {
        let policy = SessionPolicy.default
        let decoded = try decoder.decode(SessionPolicy.self, from: try encoder.encode(policy))
        XCTAssertEqual(decoded.pillarWeighting, policy.pillarWeighting)
    }

    /// A fully-populated policy - every optional present, an unequal weighting, an LLM note -
    /// round-trips with no data loss.
    func testFullyPopulatedPolicyRoundTrips() {
        let policy = SessionPolicy(
            version: 4,
            updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
            updatedBy: .deterministic,
            progressionRate: 1.25,
            pillarWeighting: [.strength: 1.0, .mobility: 2.0, .primal: 0.5],
            varietyWindow: 5,
            coldStartContract: SessionPolicy.ColdStartContract(forceContrastSpread: true, cappedMaxDifficulty: 2),
            reentry: SessionPolicy.Reentry(rampSessionsRemaining: 3),
            note: SessionPolicy.Note(text: "Eased your targets after a tough session.", source: .template)
        )
        assertRoundTrip(policy)
    }

    /// A policy whose note came from the LLM slice round-trips with the source preserved.
    func testPolicyWithLLMNoteRoundTrips() {
        let policy = SessionPolicy(
            version: 2,
            updatedAt: Date(timeIntervalSinceReferenceDate: 750_000_000),
            updatedBy: .llm,
            progressionRate: 1.0,
            pillarWeighting: SessionPolicy.neutralPillarWeighting,
            varietyWindow: 3,
            coldStartContract: nil,
            reentry: nil,
            note: SessionPolicy.Note(text: "Today's a mobility day - yesterday was strength.", source: .llm)
        )
        assertRoundTrip(policy)
    }

    // MARK: - Persistence-contract raw values

    /// `updatedBy` raw values are a persistence contract; pin them so a rename can't silently
    /// break already-stored policies.
    func testUpdatedByRawValuesAreStable() {
        XCTAssertEqual(SessionPolicy.UpdatedBy.default.rawValue, "default")
        XCTAssertEqual(SessionPolicy.UpdatedBy.deterministic.rawValue, "deterministic")
        XCTAssertEqual(SessionPolicy.UpdatedBy.llm.rawValue, "llm")
        XCTAssertEqual(SessionPolicy.UpdatedBy.allCases.count, 3)
    }

    /// `note.source` raw values are likewise pinned.
    func testNoteSourceRawValuesAreStable() {
        XCTAssertEqual(SessionPolicy.Note.Source.template.rawValue, "template")
        XCTAssertEqual(SessionPolicy.Note.Source.llm.rawValue, "llm")
        XCTAssertEqual(SessionPolicy.Note.Source.allCases.count, 2)
    }

    // MARK: - Round-trip helper

    /// Encodes then decodes `value` and asserts the result equals the original.
    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(T.self, from: data)
            XCTAssertEqual(decoded, value, "round-trip mismatch for \(T.self)", file: file, line: line)
        } catch {
            XCTFail("round-trip threw for \(T.self): \(error)", file: file, line: line)
        }
    }
}
