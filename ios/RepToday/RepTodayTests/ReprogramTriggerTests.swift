import XCTest
@testable import RepToday

/// Tests for the `ReprogramTrigger` seam type (US-D04).
///
/// The contract under test: the `Kind` raw values are a stable persistence/wire contract, and
/// a trigger survives a Codable round-trip with no data loss - the shape the AI Programmer
/// (Epic F) will detect against and the client may log.
final class ReprogramTriggerTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `Kind` raw values are a contract; pin them so a rename can't silently break stored or
    /// analyzed triggers. These are exactly the four the PRD (US-D04/US-F01) enumerates.
    func testKindRawValuesAreStable() {
        XCTAssertEqual(ReprogramTrigger.Kind.weeklyBoundary.rawValue, "weekly_boundary")
        XCTAssertEqual(ReprogramTrigger.Kind.return.rawValue, "return")
        XCTAssertEqual(ReprogramTrigger.Kind.physicalStall.rawValue, "physical_stall")
        XCTAssertEqual(ReprogramTrigger.Kind.disengagement.rawValue, "disengagement")
        XCTAssertEqual(ReprogramTrigger.Kind.allCases.count, 4)
    }

    /// `id` is the kind's raw value: at most one trigger of a kind is due at a moment, so the
    /// kind identifies it within a `dueTriggers` result.
    func testTriggerIdentityIsKindRawValue() {
        let trigger = ReprogramTrigger(kind: .disengagement, detectedAt: .init(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(trigger.id, "disengagement")
        XCTAssertEqual(ReprogramTrigger.Kind.disengagement.id, "disengagement")
    }

    /// Every kind round-trips through Codable with its `detectedAt` intact.
    func testTriggerRoundTripsForEveryKind() throws {
        let detectedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for kind in ReprogramTrigger.Kind.allCases {
            let trigger = ReprogramTrigger(kind: kind, detectedAt: detectedAt)
            let decoded = try decoder.decode(ReprogramTrigger.self, from: try encoder.encode(trigger))
            XCTAssertEqual(decoded, trigger, "round-trip mismatch for \(kind)")
        }
    }
}
