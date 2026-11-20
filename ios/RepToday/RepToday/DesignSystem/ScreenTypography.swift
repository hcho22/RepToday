import SwiftUI

/// Type tokens the Today, Welcome Page, onboarding and sign-in screens read beyond the core ramp in
/// `Theme.Typography`: the in-between sizes their mockups set (`screens/T*`, `F*` in the design handoff).
/// Each scales with Dynamic Type through `relativeTo:` like the rest of the ramp.
extension Theme.Typography {
    private typealias Name = FontName

    /// The greeting above Today's headline ("Ready when you are, Riley."): Inter Medium 16.
    static let greeting = ThemeFont(Name.textMedium, size: 16, relativeTo: .callout)
    /// "Today is" above the Welcome Page's day name: Inter Medium 24.
    static let todayIs = ThemeFont(Name.textMedium, size: 24, relativeTo: .title2)
    /// The line under a headline that says what today is: Inter 16.
    static let lead = ThemeFont(Name.textRegular, size: 16, relativeTo: .callout)
    /// A card's title on Today ("Outside activity", why today is rest): Bricolage Bold 20.
    static let cardTitle = ThemeFont(Name.value, size: 20, relativeTo: .title3)
    /// A movement's name in a session list: Inter SemiBold 17.
    static let rowName = ThemeFont(Name.textSemiBold, size: 17, relativeTo: .body)
    /// A set x rep value in a session list ("4 × 15"): Bricolage Bold 20, set in tabular figures.
    static let listValue = ThemeFont(Name.value, size: 20, relativeTo: .title3)
    /// The label of the Start button outside a session: Inter Bold 20.
    static let startButton = ThemeFont(Name.textBold, size: 20, relativeTo: .headline)
    /// Text typed into an input: Inter SemiBold 18.
    static let input = ThemeFont(Name.textSemiBold, size: 18, relativeTo: .body)
    /// The label above a field: Inter SemiBold 14.
    static let fieldLabel = ThemeFont(Name.textSemiBold, size: 14, relativeTo: .subheadline)
    /// A segment of a segmented choice: Inter SemiBold 15.
    static let segment = calloutSemiBold
    /// A stepper's value ("35", "175"): Bricolage ExtraBold 28, set in tabular figures.
    static let stepperValue = ThemeFont(Name.displaySmall, size: 28, relativeTo: .title)
    /// The number on an onboarding duration tile and each digit of an email code: Bricolage ExtraBold 32.
    static let codeDigit = ThemeFont(Name.displaySmall, size: 32, relativeTo: .title)
    /// The unit under a big number ("min"): Inter SemiBold 13.
    static let unitLabel = ThemeFont(Name.textSemiBold, size: 13, relativeTo: .footnote)
    /// The "TODAY" pill under the Cycle strip's current step: Inter ExtraBold 10.
    static let todayPill = ThemeFont(Name.textExtraBold, size: 10, relativeTo: .caption2)

    // MARK: Onboarding story (`screens/F02*`)

    /// The primary button on an onboarding story screen (Continue, Get started): Inter Bold 19.
    static let storyButton = ThemeFont(Name.textBold, size: 19, relativeTo: .headline)
    /// A short label in a story visual (a day's parts, a quiet tag): Inter SemiBold 13.
    static let storyCaption = ThemeFont(Name.textSemiBold, size: 13, relativeTo: .footnote)
    /// The line under a title in a story card: Inter 14.
    static let storyDetail = ThemeFont(Name.textRegular, size: 14, relativeTo: .subheadline)
    /// A stage's title on the discipline story's path ("Show up"): Bricolage ExtraBold 19.
    static let storyStageTitle = ThemeFont(Name.displaySmall, size: 19, relativeTo: .headline)
    /// The anonymous-usage-data disclosure on the first story screen: Inter 12.
    static let disclosure = ThemeFont(Name.textRegular, size: 12, relativeTo: .caption)
}
