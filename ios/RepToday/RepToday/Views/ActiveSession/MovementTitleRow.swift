import SwiftUI

/// A movement's name with its target in the session's color on the same baseline at the right, as the
/// exercise screen and the rest screen's next-up block both show it (DESIGN `X15-Exercise`, `X19-Rest`).
///
/// The name wraps beside the target while its longest word still fits there, so a long name takes two
/// lines with the target on its first; only when even that word cannot fit beside the target - the
/// largest text sizes - does the target drop below the name. A word is never broken across lines.
struct MovementTitleRow: View {
    let name: String
    let target: String
    let nameFont: ThemeFont
    let targetFont: ThemeFont
    var nameColor: Color = Theme.Colors.textPrimary
    let targetColor: Color
    /// The width the row is laid out in; unmeasured (infinite), the target stays beside the name.
    let width: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    static let spacing = Theme.Spacing.smd

    var body: some View {
        let nameText = Text(name)
            .font(nameFont)
            .tracking(Theme.Typography.displayTracking * nameFont.size)
            .foregroundStyle(nameColor)
        let targetText = Text(target)
            .font(targetFont)
            .monospacedDigit()
            .foregroundStyle(targetColor)

        if targetFitsBesideName {
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                nameText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                targetText.fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // A long movement name must wrap at the largest Dynamic Type sizes rather than truncate
                // away the end of the name (US-CC14, AC3); so must a long per-side target.
                nameText.fixedSize(horizontal: false, vertical: true)
                targetText.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Whether the target and the name's longest word fit side by side in `width`.
    private var targetFitsBesideName: Bool {
        guard width.isFinite else { return true }
        let longestWord = name.split(separator: " ").map {
            nameFont.width(of: String($0), size: dynamicTypeSize, weight: legibilityWeight,
                           tracking: Theme.Typography.displayTracking * nameFont.size)
        }.max() ?? 0
        let targetWidth = targetFont.width(of: target, size: dynamicTypeSize, weight: legibilityWeight, tabularFigures: true)
        return longestWord + Self.spacing + targetWidth <= width
    }
}
