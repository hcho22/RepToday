import CoreText
import SwiftUI
import UIKit

/// The single source of truth for Rep Today's visual language.
///
/// Every view pulls colors, fonts, and spacing from `Theme` - never hardcoded literals. Swapping a
/// value here updates the whole app. The values are the approved visual direction's tokens
/// (`tokens.json` in the design handoff): black first, five vivid colors with one job each,
/// Bricolage Grotesque for headlines and every number, Inter for reading text. The app is dark only.
enum Theme {

    // MARK: - Colors

    /// Color tokens. The palette comes first, then the semantic names every screen reads. The app is
    /// dark only, so each token is a single value; the asset catalog's `AccentColor` mirrors `sun` so
    /// system controls tint the same way.
    enum Colors {
        // MARK: Palette

        /// True black, the background of every screen.
        static let black = Color(hex: 0x000000)
        /// Cards, groups, sheets and the tab bar.
        static let surface1 = Color(hex: 0x131316)
        /// Secondary buttons, chips, inputs and dialogs.
        static let surface2 = Color(hex: 0x1D1D22)
        /// Tracks, the selected tab pill and locked nodes.
        static let surface3 = Color(hex: 0x2C2C33)
        /// 1 pt separators and card outlines.
        static let line = Color(hex: 0x2E2E36)
        /// Primary text (21:1 on black).
        static let text1 = Color(hex: 0xFFFFFF)
        /// Secondary text, overlines and quiet actions (10.8:1 on black).
        static let text2 = Color(hex: 0xB9B9C4)
        /// Inactive tabs, placeholders, chevrons and a paused timer (6.6:1 on black).
        static let text3 = Color(hex: 0x8F8F9B)

        /// "You, and now": the Consistency Score, selected states, primary actions outside a session,
        /// the Coach, Premium, and the last seconds of any timer.
        static let sun = Color(hex: 0xFFD23F)
        /// Push Day: its headline, Start and Done, timer and bar, calendar marks and ladder.
        static let push = Color(hex: 0xFF6B3D)
        /// Pull Day: the same jobs.
        static let pull = Color(hex: 0x4D9BFF)
        /// Legs Day: the same jobs. Also success, always with a check glyph.
        static let legs = Color(hex: 0x3DDC84)
        /// Rest Day, Recovery, and every rest countdown between sets.
        static let rest = Color(hex: 0xC9A7FF)

        /// Selected fills and the Trainer stage's glow, one per vivid color.
        static let sunTint = Color(hex: 0x2C2409)
        static let pushTint = Color(hex: 0x2B140C)
        static let pullTint = Color(hex: 0x0D1E36)
        static let legsTint = Color(hex: 0x0C2B1A)
        static let restTint = Color(hex: 0x241C36)

        /// Behind sheets, overlays and dialogs.
        static let scrim = Color.black.opacity(0.78)
        /// The 1 pt outline around Trainer art, so its ink line reads on black.
        static let artOutline = Color(hex: 0xFFF4E4)
        /// The outer color of the Trainer stage's gradient.
        static let stageBase = Color(hex: 0x0B0B0D)

        // MARK: Semantic

        /// Accent for text, icons, links and controls outside a session: `sun`. Mirrors the asset
        /// catalog's `AccentColor`.
        static let accent = sun

        /// The accent as a fill (filled buttons, selected chips, the coach's user bubble, the paywall
        /// plan card). A vivid fill always carries black content (`onAccent`).
        static let accentFill = sun

        /// Accent text on a raised surface such as a sheet. The palette's `sun` reads at well over 4.5:1
        /// on every surface, so it is the same color.
        static let accentOnElevatedSurface = sun

        /// The faint wash behind an accent caption (the "Premium" tag): `sun`'s tint.
        static let accentBadgeFill = sunTint

        /// Primary screen background.
        static let background = black

        /// Background for grouped/secondary surfaces.
        static let secondaryBackground = surface1

        /// Card surface color.
        static let surface = surface1

        /// Primary text.
        static let textPrimary = text1

        /// Secondary / supporting text.
        static let textSecondary = text2

        /// Tertiary text: placeholders, chevrons, inactive states.
        static let textTertiary = text3

        /// Text and icons on a vivid fill: always black.
        static let onAccent = black

        /// Supporting text and icons on a vivid fill (a plan's price line under its name).
        static let onAccentSecondary = black

        /// Destructive actions only (Delete Account), always with a label and an icon.
        static let danger = Color(hex: 0xFF5468)

        /// The Sign in with Apple button's fill: Apple's white style, the one its guidelines ask for on
        /// a dark background.
        static let signInWithAppleFill = Color.white

        /// The Sign in with Apple button's logo and title, the opposite of its fill.
        static let signInWithAppleInk = Color.black
    }

    // MARK: - Typography

    /// Font tokens. Bricolage Grotesque (ExtraBold, Bold for values in lists) sets headlines and every
    /// number; Inter sets reading text. Each token is a `ThemeFont`, applied with `.font(_:)`, which
    /// draws the heavier cut when Bold Text is on. Every style scales with Dynamic Type through `relativeTo:`,
    /// except the workout timer's numerals, which are already past the largest text style. The files
    /// are bundled under `Resources/Fonts` (see `tools/fonts/README.md`); each optical size of
    /// Bricolage is its own file.
    enum Typography {
        /// The PostScript names of the bundled cuts.
        enum FontName {
            /// Bricolage Grotesque ExtraBold at optical size 96: the timer, the score and the largest
            /// display type.
            static let displayLarge = "BricolageGrotesque-96ptExtraBold"
            /// Bricolage Grotesque ExtraBold at optical size 48: display and screen titles.
            static let display = "BricolageGrotesque-48ptExtraBold"
            /// Bricolage Grotesque ExtraBold at optical size 24: card titles and values.
            static let displaySmall = "BricolageGrotesque-24ptExtraBold"
            /// Bricolage Grotesque Bold at optical size 24: values in lists.
            static let value = "BricolageGrotesque-24ptBold"
            static let textRegular = "Inter-Regular"
            static let textMedium = "Inter-Medium"
            static let textSemiBold = "Inter-SemiBold"
            static let textBold = "Inter-Bold"
            static let textExtraBold = "Inter-ExtraBold"

            /// The cut a style takes when Bold Text is on: Inter one step heavier per DESIGN's weights
            /// (400 to 600, 500 to 700, 600 and up to 800) and Bricolage Bold to ExtraBold. Display cuts
            /// already at ExtraBold stay. SwiftUI does not embolden a custom font by itself.
            static func boldTextCut(of name: String) -> String {
                switch name {
                case textRegular: return textSemiBold
                case textMedium: return textBold
                case textSemiBold, textBold: return textExtraBold
                case value: return displaySmall
                default: return name
                }
            }
        }

        /// Display styles track tighter by 2% of their size, the timer by 3%; overlines open by 9%.
        static let displayTracking: CGFloat = -0.02
        static let timerTracking: CGFloat = -0.03
        static let overlineTracking: CGFloat = 0.09

        // MARK: Existing semantic tokens

        /// Large screen titles and the session's movement name: Bricolage 34.
        static let largeTitle = ThemeFont(FontName.display, size: 34, relativeTo: .largeTitle)

        /// Section and card titles: Bricolage 22 (Title).
        static let title = ThemeFont(FontName.displaySmall, size: 22, relativeTo: .title2)

        /// Card and row headings: Inter Bold 17 (Headline).
        static let headline = ThemeFont(FontName.textBold, size: 17, relativeTo: .headline)

        /// Default body copy: Inter 17 (Body).
        static let body = ThemeFont(FontName.textRegular, size: 17, relativeTo: .body)

        /// Supporting copy: Inter 13 (Footnote).
        static let caption = ThemeFont(FontName.textRegular, size: 13, relativeTo: .footnote)

        /// Text inside buttons: Inter Bold 17.
        static let button = ThemeFont(FontName.textBold, size: 17, relativeTo: .headline)

        // MARK: The full ramp

        /// Display XL: the Welcome Page day name.
        static let displayXL = ThemeFont(FontName.displayLarge, size: 84, relativeTo: .largeTitle)
        /// Display L: Today's headline and "You showed up."
        static let displayL = ThemeFont(FontName.display, size: 56, relativeTo: .largeTitle)
        /// Display M: screen titles and onboarding questions.
        static let displayM = ThemeFont(FontName.display, size: 40, relativeTo: .largeTitle)
        /// A big number in a card (the session summary's minutes and sets).
        static let statValue = ThemeFont(FontName.display, size: 52, relativeTo: .largeTitle)
        /// A value in a list or a stepper: Bricolage Bold 22.
        static let value = ThemeFont(FontName.value, size: 22, relativeTo: .title2)
        /// Inter 15 (Callout), regular and medium.
        static let callout = ThemeFont(FontName.textRegular, size: 15, relativeTo: .callout)
        static let calloutMedium = ThemeFont(FontName.textMedium, size: 15, relativeTo: .callout)
        /// Inter SemiBold 15: a secondary line that names state ("Round 1 of 4").
        static let calloutSemiBold = ThemeFont(FontName.textSemiBold, size: 15, relativeTo: .callout)
        /// Inter 13 (Footnote).
        static let footnote = ThemeFont(FontName.textRegular, size: 13, relativeTo: .footnote)
        /// Overline: Inter Bold 12, set uppercase with `overlineTracking`.
        static let overline = ThemeFont(FontName.textBold, size: 12, relativeTo: .caption)
        /// The label inside a filled or outlined pill (the timer's "LAST 3 SECONDS" and "PAUSED").
        static let pill = ThemeFont(FontName.textExtraBold, size: 12, relativeTo: .caption)
        /// Chip label: Inter SemiBold 16.
        static let chip = ThemeFont(FontName.textSemiBold, size: 16, relativeTo: .callout)
        /// Tab label: Inter SemiBold 11. It stays 11 pt and relies on the large content viewer.
        static let tabLabel = ThemeFont(FontName.textSemiBold, fixedSize: 11)
        /// The primary button on a session screen (Done): Inter Bold 22.
        static let sessionButton = ThemeFont(FontName.textBold, size: 22, relativeTo: .headline)
        /// The secondary buttons on a session screen (+15s, Skip rest): Inter Bold 20.
        static let sessionSecondaryButton = ThemeFont(FontName.textBold, size: 20, relativeTo: .headline)
        /// A quiet action's label under its icon (+ More time, Swap, Skip): Inter SemiBold 13.
        static let quietAction = ThemeFont(FontName.textSemiBold, size: 13, relativeTo: .footnote)
        /// The target beside a movement name ("4 × 15"): Bricolage 30.
        static let target = ThemeFont(FontName.display, size: 30, relativeTo: .title)

        // MARK: Timer

        /// The workout timer's numerals in each state. They do not scale with Dynamic Type.
        static func timer(size: CGFloat) -> Font {
            Font.custom(FontName.displayLarge, fixedSize: size)
        }

        /// A display style scaled with Dynamic Type for `size` but capped at `Theme.Typography.displayCap`
        /// points, so the largest accessibility sizes wrap a headline instead of blowing it past the
        /// screen. Read through `.cappedDisplayFont(...)`, which supplies the environment's size.
        static func cappedDisplay(
            _ name: String, size: CGFloat, relativeTo style: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize
        ) -> Font {
            Font.custom(name, fixedSize: cappedDisplaySize(size, relativeTo: style, dynamicTypeSize: dynamicTypeSize))
        }

        /// The point size `cappedDisplay` draws: `size` scaled for `dynamicTypeSize`, never above the cap.
        static func cappedDisplaySize(_ size: CGFloat, relativeTo style: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
            return min(scaled, max(size, displayCap))
        }

        /// The largest a display style grows at accessibility text sizes.
        static let displayCap: CGFloat = 68
    }

    // MARK: - Spacing

    /// The spacing scale (4, 8, 12, 16, 20, 24, 32, 40, 56) and fixed layout constants.
    enum Spacing {
        /// 4pt - hairline gaps.
        static let xs: CGFloat = 4
        /// 8pt - tight spacing.
        static let sm: CGFloat = 8
        /// 12pt - between related blocks.
        static let smd: CGFloat = 12
        /// 16pt - default spacing between elements.
        static let md: CGFloat = 16
        /// 20pt - the screen margin and card padding.
        static let mlg: CGFloat = 20
        /// 24pt - section spacing.
        static let lg: CGFloat = 24
        /// 32pt - generous block spacing.
        static let xl: CGFloat = 32
        /// 40pt.
        static let xxl: CGFloat = 40
        /// 56pt.
        static let xxxl: CGFloat = 56

        /// The side margin of every screen.
        static let screenMargin: CGFloat = 20

        /// Standard button height.
        static let buttonHeight: CGFloat = 56
        /// The Start button.
        static let startButtonHeight: CGFloat = 60
        /// The session's Done button.
        static let doneButtonHeight: CGFloat = 64
        /// Chip height (52 on the Complete screen).
        static let chipHeight: CGFloat = 44
        static let completeChipHeight: CGFloat = 52
        /// Minimum row height inside a group.
        static let rowHeight: CGFloat = 60
        /// The workout timer's bar, and its thicker last-seconds form.
        static let timerBarHeight: CGFloat = 14
        static let timerBarLastHeight: CGFloat = 20

        /// Card and group corner radius.
        static let cardCornerRadius: CGFloat = 24
        /// Input corner radius.
        static let inputCornerRadius: CGFloat = 18
        /// Tile and option-card corner radius.
        static let tileCornerRadius: CGFloat = 20
        /// The Trainer stage's corner radius.
        static let stageCornerRadius: CGFloat = 28
        /// Sheets and overlay cards.
        static let sheetCornerRadius: CGFloat = 32
        /// Dialogs.
        static let dialogCornerRadius: CGFloat = 28

        /// Minimum touch target anywhere in the app.
        static let minTouchTarget: CGFloat = 44

        /// Minimum touch target on active workout screens (larger for hands-free use).
        static let workoutTouchTarget: CGFloat = 60
    }
}

// MARK: - Day tones

/// The color a screen or session takes: its Training Day's color, `rest` for Recovery and every rest,
/// or `sun` for "you, and now". One job each; a vivid fill always carries black content.
enum DayTone: Equatable {
    case sun, push, pull, legs, rest

    init(_ day: TrainingDay?) {
        switch day {
        case .push: self = .push
        case .pull: self = .pull
        case .legs: self = .legs
        case nil: self = .sun
        }
    }

    var color: Color {
        switch self {
        case .sun: return Theme.Colors.sun
        case .push: return Theme.Colors.push
        case .pull: return Theme.Colors.pull
        case .legs: return Theme.Colors.legs
        case .rest: return Theme.Colors.rest
        }
    }

    /// The selected-fill and stage-glow tint.
    var tint: Color {
        switch self {
        case .sun: return Theme.Colors.sunTint
        case .push: return Theme.Colors.pushTint
        case .pull: return Theme.Colors.pullTint
        case .legs: return Theme.Colors.legsTint
        case .rest: return Theme.Colors.restTint
        }
    }
}

private struct DayToneKey: EnvironmentKey {
    static let defaultValue: DayTone = .sun
}

extension EnvironmentValues {
    /// The tone the views below take (the session's Training Day). Defaults to `sun`.
    var dayTone: DayTone {
        get { self[DayToneKey.self] }
        set { self[DayToneKey.self] = newValue }
    }
}

// MARK: - Theme fonts

/// One type token: a bundled cut, its size, and the text style it scales with (or a fixed size). Applied
/// with `.font(_:)`, it reads the environment's legibility weight and draws `boldTextCut(of:)` under Bold
/// Text, which SwiftUI does not do for a custom font on its own.
struct ThemeFont: Equatable {
    let name: String
    let size: CGFloat
    /// The text style the size scales with; `nil` for a fixed size.
    let style: Font.TextStyle?

    init(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle) {
        self.name = name
        self.size = size
        self.style = style
    }

    init(_ name: String, fixedSize size: CGFloat) {
        self.name = name
        self.size = size
        self.style = nil
    }

    /// The cut drawn under `legibilityWeight`.
    func fontName(for legibilityWeight: LegibilityWeight?) -> String {
        legibilityWeight == .bold ? Theme.Typography.FontName.boldTextCut(of: name) : name
    }

    /// The font drawn under `legibilityWeight`.
    func font(for legibilityWeight: LegibilityWeight?) -> Font {
        let cut = fontName(for: legibilityWeight)
        guard let style else { return Font.custom(cut, fixedSize: size) }
        return Font.custom(cut, size: size, relativeTo: style)
    }

    /// The UIKit text style the size scales with, for measuring outside SwiftUI; `nil` for a fixed size.
    var uiTextStyle: UIFont.TextStyle? {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        case nil: return nil
        default: return .body
        }
    }

    /// The width `text` takes on one line in this token at `size`, drawn the way SwiftUI draws a custom
    /// font - the size scaled for its text style and rounded to a whole point - in its Bold Text cut when
    /// `weight` is bold, with `tracking` points between glyphs, and in tabular figures when the text draws
    /// them. What a layout measures to choose between side-by-side and stacked.
    func width(of text: String, size: DynamicTypeSize, weight: LegibilityWeight?,
               tracking: CGFloat = 0, tabularFigures: Bool = false) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let pointSize = uiTextStyle.map {
            UIFontMetrics(forTextStyle: $0).scaledValue(for: self.size, compatibleWith: traits).rounded()
        } ?? self.size
        var font = UIFont(name: fontName(for: weight), size: pointSize) ?? .systemFont(ofSize: pointSize)
        if tabularFigures {
            let tabular = font.fontDescriptor.addingAttributes([.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]])
            font = UIFont(descriptor: tabular, size: pointSize)
        }
        // A `.kern` of zero would switch off the font's own pair kerning, so it is set only for tracking.
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if tracking != 0 { attributes[.kern] = tracking }
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    /// The same token in Inter's cut for `weight` (regular 400 to heavy 800). A Bricolage token keeps its
    /// cut: display type is ExtraBold throughout.
    func weight(_ weight: Font.Weight) -> ThemeFont {
        guard name.hasPrefix("Inter-") else { return self }
        let names = Theme.Typography.FontName.self
        let cut: String
        switch weight {
        case .medium: cut = names.textMedium
        case .semibold: cut = names.textSemiBold
        case .bold: cut = names.textBold
        case .heavy, .black: cut = names.textExtraBold
        default: cut = names.textRegular
        }
        return style.map { ThemeFont(cut, size: size, relativeTo: $0) } ?? ThemeFont(cut, fixedSize: size)
    }
}

extension View {
    /// Sets a Theme type token, in its heavier cut when Bold Text is on.
    func font(_ font: ThemeFont) -> some View {
        modifier(ThemeFontModifier(font: font))
    }
}

private struct ThemeFontModifier: ViewModifier {
    let font: ThemeFont
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content.font(font.font(for: legibilityWeight))
    }
}

// MARK: - Helpers

extension Color {
    /// A color from a 24-bit sRGB hex value, for the palette above.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// A display style scaled with Dynamic Type but capped at `Theme.Typography.displayCap`, with the
    /// display tracking: what a headline uses so it wraps rather than overflows at accessibility sizes.
    func cappedDisplayFont(_ name: String = Theme.Typography.FontName.display, size: CGFloat, relativeTo style: UIFont.TextStyle = .largeTitle) -> some View {
        modifier(CappedDisplayFont(name: name, size: size, style: style))
    }

    /// An overline: Inter Bold 12, tracked open. The caller passes the string already uppercased
    /// (`String.uppercased()`), never `.textCase(.uppercase)`, which would also uppercase what VoiceOver
    /// reads from an explicit accessibility label.
    func overlineStyle() -> some View {
        modifier(OverlineStyle())
    }
}

private struct CappedDisplayFont: ViewModifier {
    let name: String
    let size: CGFloat
    let style: UIFont.TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let pointSize = Theme.Typography.cappedDisplaySize(size, relativeTo: style, dynamicTypeSize: dynamicTypeSize)
        content
            .font(Font.custom(name, fixedSize: pointSize))
            .tracking(Theme.Typography.displayTracking * pointSize)
    }
}

private struct OverlineStyle: ViewModifier {
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.overline)
            .tracking(Theme.Typography.overlineTracking * size)
    }
}
