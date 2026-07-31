import XCTest
@testable import RepToday

/// Tests the pure imperial <-> metric conversions onboarding runs at its input boundary (US-O04).
///
/// Coverage mirrors the PRD acceptance criteria: known values (5 ft 7 in ~ 170 cm; 165 lb ~ 74.8 kg),
/// round-trips in both directions, and the normalization that keeps a rounded-up height from reading
/// `5 ft 12 in`. The display/spoken helpers are covered too, because they are the only place the
/// numbers reach a human and the spoken form has to agree with its own counts.
final class UnitConversionTests: XCTestCase {

    // MARK: - Known values (PRD acceptance criteria)

    func testKnownHeightValue() {
        // 5 ft 7 in == 67 in == 67 x 2.54 cm.
        XCTAssertEqual(UnitConversion.centimeters(feet: 5, inches: 7), 170.18, accuracy: 0.0001)
    }

    func testKnownWeightValue() {
        // 165 lb x 0.45359237 kg.
        XCTAssertEqual(UnitConversion.kilograms(fromPounds: 165), 74.8427, accuracy: 0.0001)
    }

    func testFactorsAreTheExactInternationalDefinitions() {
        XCTAssertEqual(UnitConversion.centimetersPerInch, 2.54)
        XCTAssertEqual(UnitConversion.kilogramsPerPound, 0.453_592_37)
        XCTAssertEqual(UnitConversion.inchesPerFoot, 12)
    }

    // MARK: - Round trips

    func testHeightRoundTripsAcrossTheOnboardingRange() {
        // Every inch the step offers - the imperial cover of the 120...220 cm slider it replaced.
        for totalInches in 47...87 {
            let feet = totalInches / 12
            let inches = totalInches % 12
            let cm = UnitConversion.centimeters(feet: feet, inches: inches)
            let back = UnitConversion.feetAndInches(fromCentimeters: cm)
            XCTAssertEqual(back.feet, feet, "\(totalInches) in round-trips its feet")
            XCTAssertEqual(back.inches, inches, "\(totalInches) in round-trips its inches")
        }
    }

    func testWeightRoundTripsAcrossTheOnboardingRange() {
        // Every pound the step can reach - the imperial cover of the 35...200 kg slider it replaced.
        for pounds in 70...440 {
            let kg = UnitConversion.kilograms(fromPounds: Double(pounds))
            XCTAssertEqual(UnitConversion.pounds(fromKilograms: kg), Double(pounds), accuracy: 0.0001)
        }
    }

    // MARK: - feetAndInches normalization

    func testCentimetersRoundingUpToAWholeFootNeverReadsTwelveInches() {
        // 182.7 cm is 71.93 in: rounding to the nearest inch lands on 72, which must normalize to
        // 6 ft 0 in. Splitting first and rounding second would print the nonsense "5 ft 12 in".
        let converted = UnitConversion.feetAndInches(fromCentimeters: 182.7)
        XCTAssertEqual(converted.feet, 6)
        XCTAssertEqual(converted.inches, 0)
    }

    func testFeetAndInchesRoundsToTheNearestInch() {
        // 176 cm is 69.29 in -> 69 in -> 5 ft 9 in.
        let down = UnitConversion.feetAndInches(fromCentimeters: 176)
        XCTAssertEqual(down.feet, 5)
        XCTAssertEqual(down.inches, 9)

        // 177 cm is 69.69 in -> 70 in -> 5 ft 10 in.
        let up = UnitConversion.feetAndInches(fromCentimeters: 177)
        XCTAssertEqual(up.feet, 5)
        XCTAssertEqual(up.inches, 10)
    }

    func testUnnormalizedInchesStillConvertToTheHeightTheyName() {
        // 5 ft 19 in is 79 in - the same as 6 ft 7 in - rather than an error or a truncation.
        XCTAssertEqual(
            UnitConversion.centimeters(feet: 5, inches: 19),
            UnitConversion.centimeters(feet: 6, inches: 7),
            accuracy: 0.0001
        )
    }

    // MARK: - Degenerate input

    func testNegativeAndZeroInputClampToZero() {
        XCTAssertEqual(UnitConversion.kilograms(fromPounds: -10), 0)
        XCTAssertEqual(UnitConversion.pounds(fromKilograms: -10), 0)
        XCTAssertEqual(UnitConversion.centimeters(feet: -1, inches: 0), 0)
        XCTAssertEqual(UnitConversion.kilograms(fromPounds: 0), 0)

        let zero = UnitConversion.feetAndInches(fromCentimeters: -5)
        XCTAssertEqual(zero.feet, 0)
        XCTAssertEqual(zero.inches, 0)
    }

    // MARK: - Display

    func testHeightLabels() {
        XCTAssertEqual(UnitConversion.heightLabel(feet: 5, inches: 7), "5 ft 7 in")
        XCTAssertEqual(UnitConversion.heightAccessibilityLabel(feet: 5, inches: 7), "5 feet 7 inches")
    }

    /// A height held as one number labels itself, so no caller re-derives the feet/inches split with
    /// its own `/ 12`.
    func testTotalInchesLabelsMatchTheSplitOnesAcrossTheOnboardingRange() {
        for totalInches in 47...87 {
            let split = UnitConversion.feetAndInches(totalInches: totalInches)
            XCTAssertEqual(split.feet * UnitConversion.inchesPerFoot + split.inches, totalInches)
            XCTAssertEqual(
                UnitConversion.heightLabel(totalInches: totalInches),
                UnitConversion.heightLabel(feet: split.feet, inches: split.inches)
            )
            XCTAssertEqual(
                UnitConversion.heightAccessibilityLabel(totalInches: totalInches),
                UnitConversion.heightAccessibilityLabel(feet: split.feet, inches: split.inches)
            )
        }
        XCTAssertEqual(UnitConversion.heightLabel(totalInches: 67), "5 ft 7 in")
        XCTAssertEqual(UnitConversion.heightAccessibilityLabel(totalInches: 67), "5 feet 7 inches")
        // A negative total clamps rather than splitting into negative parts.
        XCTAssertEqual(UnitConversion.heightLabel(totalInches: -3), "0 ft 0 in")
    }

    func testSpokenLabelsAgreeWithTheirOwnCounts() {
        XCTAssertEqual(UnitConversion.heightAccessibilityLabel(feet: 1, inches: 1), "1 foot 1 inch")
        XCTAssertEqual(UnitConversion.heightAccessibilityLabel(feet: 6, inches: 0), "6 feet 0 inches")
        XCTAssertEqual(UnitConversion.weightAccessibilityLabel(pounds: 1), "1 pound")
        XCTAssertEqual(UnitConversion.weightAccessibilityLabel(pounds: 165), "165 pounds")
    }

    func testWeightLabel() {
        XCTAssertEqual(UnitConversion.weightLabel(pounds: 165), "165 lb")
    }
}
