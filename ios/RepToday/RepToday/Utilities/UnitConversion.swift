import Foundation

/// Pure conversions between the units a US user types and the metric units Rep Today stores
/// (US-O04).
///
/// The app is metric everywhere behind the UI: `UserProfile` holds `heightCm`/`weightKg`, and the
/// HealthKit energy estimate (`HealthKitWorkoutSample`) prices a session as
/// `MET x weightKg x hours`. Imperial is therefore an *input* concern only - it lives at the
/// onboarding boundary and is converted once, on the way in, so nothing downstream ever has to ask
/// which unit a number is in. That one-way discipline is the whole point of putting the arithmetic
/// here rather than inline in the view: a pound that leaks into the kilogram field silently inflates
/// every calorie the app writes to Health by 2.2x, and nothing would flag it.
///
/// The factors are the exact international definitions (1 in == 2.54 cm, 1 lb == 0.45359237 kg), so
/// the conversions are lossless up to floating-point representation and round-trip to the nearest
/// display unit.
enum UnitConversion {

    // MARK: - Factors

    /// Exact international inch.
    static let centimetersPerInch: Double = 2.54

    /// Exact international avoirdupois pound.
    static let kilogramsPerPound: Double = 0.453_592_37

    /// Inches in a foot.
    static let inchesPerFoot: Int = 12

    // MARK: - Mass

    /// Pounds -> kilograms. A negative input is clamped to zero; mass has no meaningful negative and
    /// `HealthKitWorkoutSample` already treats a non-positive weight as "unknown".
    static func kilograms(fromPounds pounds: Double) -> Double {
        max(0, pounds) * kilogramsPerPound
    }

    /// Kilograms -> pounds, the inverse of `kilograms(fromPounds:)`.
    static func pounds(fromKilograms kilograms: Double) -> Double {
        max(0, kilograms) / kilogramsPerPound
    }

    // MARK: - Length

    /// Feet + inches -> centimeters. The two parts are summed before converting, so an un-normalized
    /// input (`5 ft 19 in`) still yields the height it names rather than being rejected.
    static func centimeters(feet: Int, inches: Int) -> Double {
        Double(max(0, feet * inchesPerFoot + inches)) * centimetersPerInch
    }

    /// Whole inches -> whole feet and inches. The single owner of the feet/inches split: a caller
    /// holding a height as one number never re-derives it, so a stray `/ 12` cannot drift from this.
    /// A negative total clamps to zero, matching the rest of this type.
    static func feetAndInches(totalInches: Int) -> (feet: Int, inches: Int) {
        let whole = max(0, totalInches)
        return (feet: whole / inchesPerFoot, inches: whole % inchesPerFoot)
    }

    /// Centimeters -> whole feet and inches, rounded to the nearest inch.
    ///
    /// The rounding happens on *total* inches and the result is re-split, so a height that rounds up
    /// to a whole foot reads `6 ft 0 in` and never the nonsense `5 ft 12 in` that splitting first and
    /// rounding second would produce.
    static func feetAndInches(fromCentimeters centimeters: Double) -> (feet: Int, inches: Int) {
        feetAndInches(totalInches: Int((max(0, centimeters) / centimetersPerInch).rounded()))
    }

    // MARK: - Display

    /// `"5 ft 7 in"` - the compact on-screen height label.
    static func heightLabel(feet: Int, inches: Int) -> String {
        "\(feet) ft \(inches) in"
    }

    /// `"5 ft 7 in"` from a height held as one number, so a caller stepping total inches never has to
    /// split them itself.
    static func heightLabel(totalInches: Int) -> String {
        let split = feetAndInches(totalInches: totalInches)
        return heightLabel(feet: split.feet, inches: split.inches)
    }

    /// `"5 feet 7 inches"` - the spoken height, with each noun agreeing with its own count, so
    /// VoiceOver never reads "1 feet". Mirrors the agreement rule the active-session prescription
    /// copy already follows.
    static func heightAccessibilityLabel(feet: Int, inches: Int) -> String {
        let feetPart = "\(feet) \(feet == 1 ? "foot" : "feet")"
        let inchesPart = "\(inches) \(inches == 1 ? "inch" : "inches")"
        return "\(feetPart) \(inchesPart)"
    }

    /// `"5 feet 7 inches"` from a height held as one number, the spoken counterpart to
    /// `heightLabel(totalInches:)`.
    static func heightAccessibilityLabel(totalInches: Int) -> String {
        let split = feetAndInches(totalInches: totalInches)
        return heightAccessibilityLabel(feet: split.feet, inches: split.inches)
    }

    /// `"165 lb"` - the compact on-screen weight label.
    static func weightLabel(pounds: Int) -> String {
        "\(pounds) lb"
    }

    /// `"165 pounds"` - the spoken weight, agreeing with its own count for the same reason as
    /// `heightAccessibilityLabel`.
    static func weightAccessibilityLabel(pounds: Int) -> String {
        "\(pounds) \(pounds == 1 ? "pound" : "pounds")"
    }
}
