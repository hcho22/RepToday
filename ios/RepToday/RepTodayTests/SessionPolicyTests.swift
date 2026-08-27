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

    // MARK: - Pattern emphasis (US-AC05)

    /// The default carries a neutral pattern emphasis: every `MovementPattern` present, all at `1.0`.
    func testDefaultPolicyHasNeutralPatternEmphasis() {
        let emphasis = SessionPolicy.default.patternEmphasis
        XCTAssertEqual(Set(emphasis.keys), Set(MovementPattern.allCases),
                       "every movement pattern must be present in the neutral emphasis")
        XCTAssertEqual(Set(emphasis.values), [1.0], "every neutral emphasis value must be 1.0")
    }

    /// A non-neutral `[MovementPattern: Double]` emphasis - a non-`String`/`Int`-keyed dictionary -
    /// survives the round-trip intact with no data loss.
    func testPatternEmphasisRoundTripsIntact() throws {
        var policy = SessionPolicy.default
        policy.patternEmphasis[.push] = 2.0
        policy.patternEmphasis[.squat] = 0.5
        let decoded = try decoder.decode(SessionPolicy.self, from: try encoder.encode(policy))
        XCTAssertEqual(decoded.patternEmphasis, policy.patternEmphasis)
        assertRoundTrip(policy)
    }

    /// The additive-field contract: a policy persisted *before* US-AC05 has no `patternEmphasis` key, and
    /// must still decode - to neutral - rather than failing the whole blob and losing the user's in-force
    /// policy. Mirrors the Start Seed fields' backward-compat guarantee on `ColdStartContract`.
    func testPolicyPersistedBeforePatternEmphasisDecodesToNeutral() throws {
        // Encode a current policy, then strip the new key to simulate a pre-US-AC05 stored blob.
        let data = try encoder.encode(SessionPolicy.default)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object["patternEmphasis"], "sanity: the current policy encodes the key")
        object.removeValue(forKey: "patternEmphasis")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(SessionPolicy.self, from: legacyData)
        XCTAssertEqual(decoded.patternEmphasis, SessionPolicy.neutralPatternEmphasis,
                       "a policy without the key must decode to neutral emphasis")
        // And the rest of the policy is intact - the missing key is the only difference.
        XCTAssertEqual(decoded, SessionPolicy.default)
    }

    /// The emphasis rails are the single clamp definition (US-AC05): values pin to `[0.5, 2.0]`, so an
    /// out-of-range coach write (US-AC07) is bounded to the rail rather than ever acting as a filter or
    /// inverting the staleness ordering (a non-positive multiplier).
    func testClampedEmphasisPinsOutOfRangeValues() {
        XCTAssertEqual(SessionPolicy.minEmphasis, 0.5)
        XCTAssertEqual(SessionPolicy.maxEmphasis, 2.0)
        XCTAssertEqual(SessionPolicy.neutralEmphasis, 1.0)
        XCTAssertEqual(SessionPolicy.clampedEmphasis(1.0), 1.0, "neutral is unchanged")
        XCTAssertEqual(SessionPolicy.clampedEmphasis(5.0), 2.0, "above the rail pins to max")
        XCTAssertEqual(SessionPolicy.clampedEmphasis(0.1), 0.5, "below the rail pins to min")
        XCTAssertEqual(SessionPolicy.clampedEmphasis(0.0), 0.5, "a zero never survives as a filter")
        XCTAssertEqual(SessionPolicy.clampedEmphasis(-3.0), 0.5, "a negative never inverts the ordering")
        XCTAssertEqual(SessionPolicy.clampedEmphasis(1.5), 1.5, "an in-range value is untouched")
    }

    // MARK: - Progression-rate rail and coach-easing gate (US-AC06)

    /// The rate rail is the single clamp definition (US-AC06): `progressionRate` pins to `[0.5, 2.0]`
    /// around neutral `1.0`, matching the deterministic Programmer's long-standing easing band.
    func testClampedProgressionRatePinsOutOfRangeValues() {
        XCTAssertEqual(SessionPolicy.minProgressionRate, 0.5)
        XCTAssertEqual(SessionPolicy.maxProgressionRate, 2.0)
        XCTAssertEqual(SessionPolicy.neutralProgressionRate, 1.0)
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(1.0), 1.0, "neutral is unchanged")
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(5.0), 2.0, "above the rail pins to max")
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(0.1), 0.5, "below the rail pins to min")
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(0.0), 0.5, "a zero never survives")
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(-3.0), 0.5, "a negative never inverts pace")
        XCTAssertEqual(SessionPolicy.clampedProgressionRate(1.5), 1.5, "an in-range value is untouched")
    }

    /// The rate rail is centralized on `SessionPolicy`: the deterministic Programmer's plateau-easing
    /// bounds alias it, so the coach's easing floor and the engine's easing floor cannot drift apart.
    func testPlateauDiagnosisRailAliasesTheCentralizedRateRail() {
        XCTAssertEqual(PlateauDiagnosis.minProgressionRate, SessionPolicy.minProgressionRate)
        XCTAssertEqual(PlateauDiagnosis.maxProgressionRate, SessionPolicy.maxProgressionRate)
    }

    /// A coach (`.llm`) ease-down lowers `progressionRate` and stamps the coach's provenance.
    func testCoachEaseDownLowersProgressionRate() {
        var policy = SessionPolicy.default
        policy.progressionRate = 1.4
        policy.updatedBy = .deterministic

        let eased = policy.easingProgressionRate(towardCoachProposed: 0.8)

        XCTAssertEqual(eased.progressionRate, 0.8, "an ease-down below the in-force rate takes effect")
        XCTAssertEqual(eased.updatedBy, .llm, "a coach write is stamped .llm")
    }

    /// A coach attempt to *raise* pace above the engine-earned (in-force) rate is clamped to no increase -
    /// the structural guarantee that upward pace is owned solely by the engine.
    func testCoachCannotRaiseProgressionRateAboveInForce() {
        var policy = SessionPolicy.default
        policy.progressionRate = 1.2
        policy.updatedBy = .deterministic

        // Above the in-force rate but still inside the rail: clamped down to the in-force rate.
        let attemptWithinRail = policy.easingProgressionRate(towardCoachProposed: 1.8)
        XCTAssertEqual(attemptWithinRail.progressionRate, 1.2, "a raise attempt cannot exceed the in-force rate")

        // Above the rail entirely: pinned to the in-force rate, never the rail ceiling.
        let attemptAboveRail = policy.easingProgressionRate(towardCoachProposed: 99.0)
        XCTAssertEqual(attemptAboveRail.progressionRate, 1.2, "an out-of-rail raise never lifts pace")

        // Exactly the in-force rate: a no-op on the value (still not an increase).
        let attemptEqual = policy.easingProgressionRate(towardCoachProposed: 1.2)
        XCTAssertEqual(attemptEqual.progressionRate, 1.2)
    }

    /// A coach ease-down is still floored by the rate rail: a coach cannot drive pace below the engine's
    /// minimum operating rate, even asking for zero or a negative.
    func testCoachEaseDownIsFlooredByTheRail() {
        var policy = SessionPolicy.default
        policy.progressionRate = 1.0

        XCTAssertEqual(
            policy.easingProgressionRate(towardCoachProposed: 0.1).progressionRate, 0.5,
            "an ease below the floor pins to the min rail"
        )
        XCTAssertEqual(
            policy.easingProgressionRate(towardCoachProposed: -2.0).progressionRate, 0.5,
            "a negative ease never drives pace below the floor or inverts it"
        )
    }

    /// The PRD Validation Test (US-AC06). Setup: a policy at a given engine-earned `progressionRate`.
    /// Steps: apply a coach ease-down, then a coach attempt to increase pace. Expected: the ease-down
    /// takes effect and the increase attempt does not raise pace beyond the engine-earned value. Failure
    /// indicator: a coach write increases difficulty pace.
    func testValidationCoachEasesDownThenCannotRaiseBackUp() {
        // Setup: an engine-earned rate of 1.5.
        var engineEarned = SessionPolicy.default
        engineEarned.progressionRate = 1.5
        engineEarned.updatedBy = .deterministic

        // Step 1: a coach ease-down to 0.9 - takes effect.
        let eased = engineEarned.easingProgressionRate(towardCoachProposed: 0.9)
        XCTAssertEqual(eased.progressionRate, 0.9, "the coach ease-down must take effect")
        XCTAssertEqual(eased.updatedBy, .llm)

        // Step 2: a coach attempt to increase pace (well above the engine-earned 1.5) - clamped so it
        // never raises pace beyond the engine-earned value, and in fact never increases it at all.
        let raiseAttempt = eased.easingProgressionRate(towardCoachProposed: 2.0)
        XCTAssertLessThanOrEqual(
            raiseAttempt.progressionRate, engineEarned.progressionRate,
            "a coach write must never raise pace beyond the engine-earned value"
        )
        XCTAssertLessThanOrEqual(
            raiseAttempt.progressionRate, eased.progressionRate,
            "a coach write must never increase difficulty pace"
        )
        XCTAssertEqual(raiseAttempt.progressionRate, 0.9, "the raise attempt leaves the eased pace unchanged")
    }

    /// An engine write is wholly unaffected by the coach gate: the deterministic Programmer's advancing
    /// re-weight still raises pace normally (upward pace remains the engine's alone), and `default` is
    /// unchanged.
    func testEngineWriteStillAdvancesPaceAndDefaultUnchanged() {
        XCTAssertEqual(SessionPolicy.default.progressionRate, SessionPolicy.neutralProgressionRate)

        let advanced = PlateauDiagnosis.reweighted(.default, for: .physicalStall)
        XCTAssertGreaterThan(
            advanced.progressionRate, SessionPolicy.default.progressionRate,
            "a physical-stall re-weight must still advance pace"
        )
        XCTAssertLessThanOrEqual(advanced.progressionRate, SessionPolicy.maxProgressionRate)
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
