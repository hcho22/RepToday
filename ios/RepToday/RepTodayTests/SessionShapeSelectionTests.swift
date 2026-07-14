import XCTest
@testable import RepToday

/// Tests pipeline Step 1 of the deterministic engine (US-C01, extended in US-E01): selecting the
/// session shape from the user's requested minutes across the full 5-60 range.
///
/// Step 1 is a total, pure function of the minutes alone, so the suite pins the documented
/// quick-start values (5/10/15/20/30/45/60), the exact boundaries the PRD calls out (10, 20, 40),
/// clamping to the supported range, determinism, and the mapping from the engine-internal
/// `SessionShapeTemplate` back to the canonical `SessionShape` stored on a `Workout`.
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

    func testTwentyMinutesIsBlendLight() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 20), .blendLight)
    }

    func testThirtyMinutesIsBlendFull() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 30), .blendFull)
    }

    func testFortyFiveMinutesIsBlendExtended() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 45), .blendExtended)
    }

    func testSixtyMinutesIsBlendExtended() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 60), .blendExtended)
    }

    // MARK: - Boundaries (10, 20, 40)

    /// The single-focus / blend boundary: 10 stays single-focus, 11 tips into a light blend.
    func testSingleFocusToBlendLightBoundary() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 10), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 11), .blendLight)
    }

    /// The light / full boundary: 20 stays light, 21 tips into a full blend.
    func testBlendLightToBlendFullBoundary() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 20), .blendLight)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 21), .blendFull)
    }

    /// The full / extended boundary: 40 stays full, 41 tips into an extended blend.
    func testBlendFullToBlendExtendedBoundary() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 40), .blendFull)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 41), .blendExtended)
    }

    // MARK: - Full supported range sweep (5-60)

    /// Every supported minute resolves to exactly the documented band, with no gaps.
    func testEverySupportedMinuteFallsInTheExpectedBand() {
        for minutes in 5...60 {
            let expected: SessionShapeTemplate
            switch minutes {
            case ...10: expected = .singleFocus
            case 11...20: expected = .blendLight
            case 21...40: expected = .blendFull
            default: expected = .blendExtended
            }
            XCTAssertEqual(
                SessionShapeTemplate.select(requestedMinutes: minutes),
                expected,
                "\(minutes) min mapped to the wrong session shape"
            )
        }
    }

    // MARK: - Clamping outside the supported range

    /// Requests below 5 clamp up to the single-focus floor rather than trapping.
    func testBelowRangeClampsToSingleFocus() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 5), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 1), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 0), .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: -30), .singleFocus)
    }

    /// Requests above 60 clamp down to the extended-blend ceiling rather than trapping.
    func testAboveRangeClampsToBlendExtended() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 60), .blendExtended)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 61), .blendExtended)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 120), .blendExtended)
    }

    // MARK: - Determinism

    /// Same input always yields the same shape - the function is pure (no profile/history/clock).
    func testSelectionIsDeterministic() {
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
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
        XCTAssertEqual(SessionShapeTemplate.blendExtended.shape, .blend)
    }

    /// Only the single-focus band produces a single-focus `Workout`; every blend collapses
    /// to the canonical `.blend` shape.
    func testSelectedShapeMatchesSelectedTemplate() {
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 8).shape, .singleFocus)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 15).shape, .blend)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 25).shape, .blend)
        XCTAssertEqual(SessionShapeTemplate.select(requestedMinutes: 50).shape, .blend)
    }
}
