import SwiftUI

/// The single source of truth for Rep Today's visual language.
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
        /// Brand accent for text, icons, links and controls. Mirrors the asset catalog AccentColor.
        /// Never put `onAccent` content on it - that is what `accentFill` is for.
        static let accent = Color.accentColor

        /// The accent as a fill behind white (`onAccent`) content: filled buttons, selected chips, the
        /// coach's user bubble, the paywall plan card. Identical to `accent` in light appearance; one
        /// shade darker in dark appearance so white labels reach 4.5:1, which the dark `accent` cannot
        /// do while also staying legible as text on dark surfaces (the two needs ask for disjoint
        /// luminances). See `artifacts/reports/dark-accent-contrast/validation.md`.
        static let accentFill = Color("AccentFill")

        /// Accent text on a raised grouped row - an inset-grouped list row inside a presented sheet,
        /// which dark appearance lifts to #2C2C2E, where `accent` falls short of 4.5:1. Identical to
        /// `accent` in light appearance.
        static let accentOnElevatedSurface = Color("AccentOnElevatedSurface")

        /// The faint accent wash behind an accent-colored badge caption (the "Premium" tag): 12% of the
        /// accent in light appearance, 8% in dark so the caption on it keeps 4.5:1.
        static let accentBadgeFill = Color("AccentBadgeFill")

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

        /// Text/icon color drawn on top of `accentFill`.
        static let onAccent = Color.white

        /// Supporting text/icons drawn on top of `accentFill` (a plan's price line under its name).
        /// White at 90% in light appearance; full white in dark, where 90% falls below 4.5:1.
        static let onAccentSecondary = Color("OnAccentSecondary")

        /// Destructive / irreversible actions (e.g. the Settings "Delete Account" control, US-AD01).
        /// The system red so it reads as danger in both light and dark and tracks accessibility
        /// contrast settings, rather than a hardcoded `.red` at the call site.
        static let danger = Color(uiColor: .systemRed)
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
    /// The named constants below encode Rep Today's design rules from the PRD.
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
