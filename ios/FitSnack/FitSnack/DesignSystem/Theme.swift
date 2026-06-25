import SwiftUI

/// The single source of truth for FitSnack's visual language.
///
/// Every view pulls colors, fonts, and spacing from `Theme` - never hardcoded
/// literals. Swapping a value here updates the whole app. This is the scaffold
/// established in US-A01; later stories extend the palette and type ramp as the
/// real screens land.
enum Theme {

    // MARK: - Colors

    /// Semantic color tokens. Colors resolve from the asset catalog where a named
    /// color exists, and fall back to a sensible system color otherwise so the app
    /// always renders, even before the full palette is designed.
    enum Colors {
        /// Brand accent, used for primary actions. Mirrors the asset catalog AccentColor.
        static let accent = Color.accentColor

        /// Primary screen background.
        static let background = Color(uiColor: .systemBackground)

        /// Background for grouped/secondary surfaces.
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)

        /// Card surface color.
        static let surface = Color(uiColor: .secondarySystemBackground)

        /// Primary text.
        static let textPrimary = Color(uiColor: .label)

        /// Secondary / supporting text.
        static let textSecondary = Color(uiColor: .secondaryLabel)

        /// Text/icon color drawn on top of the accent color.
        static let onAccent = Color.white
    }

    // MARK: - Typography

    /// Semantic font tokens, all built on system fonts so Dynamic Type works out
    /// of the box. Sizes use `.rounded` to match a friendly, approachable tone.
    enum Typography {
        /// Large screen titles.
        static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)

        /// Section / screen titles.
        static let title = Font.system(.title2, design: .rounded).weight(.semibold)

        /// Card and row headings.
        static let headline = Font.system(.headline, design: .rounded)

        /// Default body copy.
        static let body = Font.system(.body, design: .rounded)

        /// Supporting / caption copy.
        static let caption = Font.system(.caption, design: .rounded)

        /// Text inside primary buttons.
        static let button = Font.system(.headline, design: .rounded).weight(.semibold)
    }

    // MARK: - Spacing

    /// Spacing scale and fixed layout constants.
    /// The named constants below encode FitSnack's design rules from the PRD.
    enum Spacing {
        /// 4pt - hairline gaps.
        static let xs: CGFloat = 4
        /// 8pt - tight spacing.
        static let sm: CGFloat = 8
        /// 16pt - default spacing between elements.
        static let md: CGFloat = 16
        /// 24pt - section spacing.
        static let lg: CGFloat = 24
        /// 32pt - generous block spacing.
        static let xl: CGFloat = 32

        /// Standard button height.
        static let buttonHeight: CGFloat = 56

        /// Card corner radius.
        static let cardCornerRadius: CGFloat = 16

        /// Minimum touch target anywhere in the app.
        static let minTouchTarget: CGFloat = 44

        /// Minimum touch target on active workout screens (larger for hands-free use).
        static let workoutTouchTarget: CGFloat = 60
    }
}
