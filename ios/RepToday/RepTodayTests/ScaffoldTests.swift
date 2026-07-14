import XCTest
@testable import RepToday

/// Smoke tests for the US-A01 scaffold.
///
/// These prove the test target is wired to the app target and that the core
/// design tokens exist with the values the PRD mandates. Real domain tests
/// (enums, models, engine) arrive in later stories.
final class ScaffoldTests: XCTestCase {

    func testButtonHeightMatchesDesignSystem() {
        XCTAssertEqual(Theme.Spacing.buttonHeight, 56)
    }

    func testCardCornerRadiusMatchesDesignSystem() {
        XCTAssertEqual(Theme.Spacing.cardCornerRadius, 16)
    }

    func testMinimumTouchTargetMatchesDesignSystem() {
        XCTAssertEqual(Theme.Spacing.minTouchTarget, 44)
    }

    func testWorkoutTouchTargetMatchesDesignSystem() {
        XCTAssertEqual(Theme.Spacing.workoutTouchTarget, 60)
    }
}
