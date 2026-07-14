import XCTest
@testable import RepToday

/// Guards the reconciliation between the onboarding injury vocabulary (`InjuryOption`, US-I01) and
/// the engine's `InjuryContraindication` map (US-C04).
///
/// `InjuryContraindication` fails *open*: an injury tag that does not normalize onto one of its keys
/// contributes no contraindication and silently disables injury protection for that tag. Its own doc
/// comment calls this out as a latent safety gap that onboarding must close by emitting only tags
/// that resolve. These tests are that closed-loop guard: if anyone adds an `InjuryOption` whose tag
/// does not map to a real pattern, or renames a contraindication key, this fails loudly.
final class OnboardingInjuryVocabularyTests: XCTestCase {

    /// Every injury the flow offers must map to at least one contraindicated movement pattern -
    /// otherwise selecting it would do nothing and the user's injury would go unprotected.
    func testEveryInjuryOptionMapsToAContraindication() {
        for option in InjuryOption.allCases {
            let patterns = InjuryContraindication.patterns(forInjury: option.tag)
            XCTAssertFalse(
                patterns.isEmpty,
                "InjuryOption.\(option) (tag \"\(option.tag)\") normalizes to no contraindication - injury protection would silently disappear"
            )
        }
    }

    /// The union across every offered injury is exercised the same way the engine reads the profile,
    /// so the whole selected set resolves to real pattern protection.
    func testUnionOfAllOptionsResolves() {
        let tags = InjuryOption.allCases.map(\.tag)
        let patterns = InjuryContraindication.contraindicatedPatterns(for: tags)
        XCTAssertFalse(patterns.isEmpty)
    }

    /// Tags are stable identifiers written into persisted `UserProfile.injuries`; pin them so a
    /// rename that would orphan already-stored profiles fails here.
    func testInjuryTagsAreStable() {
        XCTAssertEqual(InjuryOption.knees.tag, "knees")
        XCTAssertEqual(InjuryOption.lowerBack.tag, "lower_back")
        XCTAssertEqual(InjuryOption.shoulders.tag, "shoulders")
        XCTAssertEqual(InjuryOption.wrists.tag, "wrists")
        XCTAssertEqual(InjuryOption.ankles.tag, "ankles")
        XCTAssertEqual(InjuryOption.hips.tag, "hips")
    }
}
