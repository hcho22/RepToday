import XCTest
@testable import FitSnack

/// Tests pipeline Step 1 of the deterministic engine (US-C01): selecting the session shape
/// from the user's requested minutes.
///
/// Step 1 is a total, pure function of the minutes alone, so the suite pins the documented
/// quick-start values (5/10/15/20/30), the exact boundaries the PRD calls out (10, 15, 20),
/// determinism, and the mapping from the engine-internal `SessionShapeTemplate` back to the
/// canonical `SessionShape` stored on a `Workout`.
final class SessionShapeSelectionTests: XCTestCase {

    // MARK: - Documented quick-start values

    func testFiveMinutesIsSingleFocus() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 5), .singleFocus)
    }

    func testTenMinutesIsSingleFocus() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 10), .singleFocus)
    }

    func testFifteenMinutesIsBlendLight() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 15), .blendLight)
    }

    func testTwentyMinutesIsBlendFull() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 20), .blendFull)
    }

    func testThirtyMinutesIsBlendFull() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 30), .blendFull)
    }

    // MARK: - Boundaries (10, 15, 20)

    /// The single-focus / blend boundary: 10 stays single-focus, 11 tips into a light blend.
    func testSingleFocusToBlendBoundary() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 10), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 11), .blendLight)
    }

    /// 15 is the canonical light blend; it must not be mistaken for a full blend.
    func testFifteenSitsInsideTheLightBand() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 14), .blendLight)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 15), .blendLight)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 16), .blendLight)
    }

    /// The light / full boundary: 19 stays light, 20 tips into a full blend.
    func testBlendLightToBlendFullBoundary() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 19), .blendLight)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 20), .blendFull)
    }

    // MARK: - Full supported range sweep (5-30)

    /// Every supported minute resolves to exactly the documented band, with no gaps.
    func testEverySupportedMinuteFallsInTheExpectedBand() {
        for minutes in 5...30 {
            let expected: SessionShapeTemplate
            switch minutes {
            case ...10: expected = .singleFocus
            case 11...19: expected = .blendLight
            default: expected = .blendFull
            }
            XCTAssertEqual(
                SessionShapeTemplate.select(requestedMinutes: minutes),
                expected,
                "\(minutes) min mapped to the wrong session shape"
            )
        }
    }

    // MARK: - Determinism

    /// Same input always yields the same shape - the function is pure (no profile/history/clock).
    func testSelectionIsDeterministic() {
        for minutes in [5, 10, 15, 20, 30] {
            let first = SessionShapeTemplate.select(requestedMinutes: minutes)
            for _ in 0..<50 {
                XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: minutes), first)
            }
        }
    }

    // MARK: - Mapping to the canonical SessionShape

    func testTemplateMapsToCanonicalShape() {
        XCTAssertEqual(SessionShapeTemplate.singleFocus.shape, .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.blendLight.shape, .blend)
        XCTAssertEqual(SessionShapeTemplate.blendFull.shape, .blend)
    }

    /// Only the single-focus band produces a single-focus `Workout`; both blends collapse
    /// to the canonical `.blend` shape.
    func testSelectedShapeMatchesSelectedTemplate() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 8).shape, .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 15).shape, .blend)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 25).shape, .blend)
    }
}
