import XCTest
@testable import FitSnack

/// Tests for the `MockSessionPolicyService` seam behavior (US-D04).
///
/// The contract under test: the mock always hands back the neutral `SessionPolicy.default`
/// (for both `currentPolicy` and `reprogram`) and never reports a due trigger, so the engine
/// runs exactly as it did before policies existed. Real detection/re-weighting lands in Epic F.
final class SessionPolicyServiceTests: XCTestCase {

    private let service = MockSessionPolicyService()
    private let user = MockPersistence.sampleUser

    /// `currentPolicy` returns the always-valid default policy.
    func testCurrentPolicyReturnsDefault() async throws {
        let policy = try await service.currentPolicy(for: user)
        XCTAssertEqual(policy, .default)
    }

    /// The mock never re-programs: `reprogram` for any trigger still returns the neutral default.
    func testReprogramReturnsDefaultForEveryTrigger() async throws {
        for kind in ReprogramTrigger.Kind.allCases {
            let trigger = ReprogramTrigger(kind: kind, detectedAt: Date())
            let policy = try await service.reprogram(user: user, recentLogs: [], trigger: trigger)
            XCTAssertEqual(policy, .default, "reprogram should return the default for \(kind)")
        }
    }

    /// A fresh user has no due triggers.
    func testDueTriggersEmptyForFreshUser() async throws {
        let triggers = try await service.dueTriggers(user: user, recentLogs: [], asOf: Date())
        XCTAssertTrue(triggers.isEmpty)
    }
}
