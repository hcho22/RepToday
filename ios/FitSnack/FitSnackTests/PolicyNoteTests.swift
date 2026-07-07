import XCTest
@testable import FitSnack

/// Tests the templated policy note (US-F04): `PolicyNote`, which builds an honest, template-sourced
/// line naming *what actually changed* from the real diff between the policy before and after a
/// re-program (plus any Default Duration change).
///
/// Coverage mirrors the PRD acceptance criteria: the note reflects the actual lever moved (never a
/// claim the diff does not support), `source == .template`, it never references the user's `why`,
/// and a re-program that moved nothing observable produces no note (rather than a hollow claim).
final class PolicyNoteTests: XCTestCase {

    // MARK: - Fixtures

    /// A neutral starting policy to diff against.
    private var base: SessionPolicy { .default }

    private func policy(progressionRate: Double, varietyWindow: Int) -> SessionPolicy {
        var policy = SessionPolicy.default
        policy.progressionRate = progressionRate
        policy.varietyWindow = varietyWindow
        return policy
    }

    // MARK: - Lever direction

    func testPhysicalStallNoteNamesSteppedUpChallenge() {
        // A stall re-weighting (US-F02): progression up, variety wider.
        let after = PlateauDiagnosis.reweighted(base, for: .physicalStall)
        let note = PolicyNote.templated(policyBefore: base, policyAfter: after)

        let text = note?.text ?? ""
        XCTAssertEqual(note?.source, .template)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("stepped up"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("fresher"), text)
        // Must not claim the opposite of what happened.
        XCTAssertFalse(text.localizedCaseInsensitiveContains("eased"), text)
    }

    func testDisengagementNoteNamesEasedIntensity() {
        // A disengagement re-weighting (US-F02): progression down, variety narrower.
        let after = PlateauDiagnosis.reweighted(base, for: .disengagement)
        let note = PolicyNote.templated(policyBefore: base, policyAfter: after)

        let text = note?.text ?? ""
        XCTAssertEqual(note?.source, .template)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("eased the intensity"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("moves you know"), text)
        // Must never read as adding challenge to a disengaging user.
        XCTAssertFalse(text.localizedCaseInsensitiveContains("stepped up"), text)
    }

    func testProgressionOnlyMoveNamesChallengeWithoutVariety() {
        let after = policy(progressionRate: base.progressionRate * 1.15, varietyWindow: base.varietyWindow)
        let note = PolicyNote.templated(policyBefore: base, policyAfter: after)

        let text = note?.text ?? ""
        XCTAssertTrue(text.localizedCaseInsensitiveContains("stepped up"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("fresher"), text)
    }

    func testVarietyOnlyMoveNamesVariety() {
        let after = policy(progressionRate: base.progressionRate, varietyWindow: base.varietyWindow + 1)
        let note = PolicyNote.templated(policyBefore: base, policyAfter: after)

        let text = note?.text ?? ""
        XCTAssertTrue(text.localizedCaseInsensitiveContains("fresher movement"), text)
    }

    // MARK: - No change / honesty

    func testNoChangeProducesNoNote() {
        // Identical before/after and no duration change: nothing true to say.
        XCTAssertNil(PolicyNote.templated(policyBefore: base, policyAfter: base))
    }

    func testNoteNeverReferencesWhy() {
        // Whatever the change, the note never invokes the user's motivation statement.
        let motivation = "get on the floor with my grandkids"
        let candidates = [
            PolicyNote.templated(policyBefore: base, policyAfter: PlateauDiagnosis.reweighted(base, for: .physicalStall)),
            PolicyNote.templated(policyBefore: base, policyAfter: PlateauDiagnosis.reweighted(base, for: .disengagement)),
            PolicyNote.templated(
                policyBefore: base,
                policyAfter: base,
                durationChange: .init(before: 20, after: 15)
            ),
        ]
        for note in candidates {
            XCTAssertFalse(note?.text.localizedCaseInsensitiveContains(motivation) ?? false)
            XCTAssertFalse(note?.text.localizedCaseInsensitiveContains("grandkids") ?? false)
        }
    }

    // MARK: - Duration clause

    func testDurationChangeAddsClause() {
        let note = PolicyNote.templated(
            policyBefore: base,
            policyAfter: base,
            durationChange: .init(before: 20, after: 15)
        )
        let text = note?.text ?? ""
        XCTAssertEqual(note?.source, .template)
        XCTAssertTrue(text.contains("15 minutes"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("what you actually finish"), text)
    }

    func testUnchangedDurationAddsNoClause() {
        // A default that did not move contributes nothing, so a no-lever + no-duration-change is nil.
        XCTAssertNil(
            PolicyNote.templated(
                policyBefore: base,
                policyAfter: base,
                durationChange: .init(before: 20, after: 20)
            )
        )
    }

    func testLeverAndDurationChangeBothNamed() {
        let after = PlateauDiagnosis.reweighted(base, for: .disengagement)
        let note = PolicyNote.templated(
            policyBefore: base,
            policyAfter: after,
            durationChange: .init(before: 20, after: 10)
        )
        let text = note?.text ?? ""
        XCTAssertTrue(text.localizedCaseInsensitiveContains("eased the intensity"), text)
        XCTAssertTrue(text.contains("10 minutes"), text)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let after = PlateauDiagnosis.reweighted(base, for: .physicalStall)
        let a = PolicyNote.templated(policyBefore: base, policyAfter: after, durationChange: .init(before: 20, after: 15))
        let b = PolicyNote.templated(policyBefore: base, policyAfter: after, durationChange: .init(before: 20, after: 15))
        XCTAssertEqual(a, b)
    }
}
