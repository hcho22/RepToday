import SwiftUI

// MARK: - Step bar

/// A row of `count` equal capsules with 5 pt gaps, the first `filled` in `tone` and the rest on
/// `surface3`: a count of steps rather than a fraction (the climb card's weeks of steady practice).
/// Decorative; the row it sits in speaks the count.
struct StepBar: View {
    let count: Int
    let filled: Int
    var tone: Color = Theme.Colors.sun
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tone : Theme.Colors.surface3)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Share bar

/// A 10 pt share bar: a `surface3` track filled to `fraction` (clamped to 0...1) in `fill`. Decorative;
/// the row it sits in speaks the share.
struct ShareBar: View {
    let fraction: Double
    var fill: Color = Theme.Colors.text1
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface3)
                Capsule()
                    .fill(fill)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Point rows

/// One point of an explainer (the Strength Phase moment, the Coach data disclosure): a 26 pt icon in
/// `tint`, a headline and a callout-size detail under it. One VoiceOver element per point.
struct IconPointRow: View {
    let icon: AppIcon
    let title: String
    let detail: String
    var tint: Color = Theme.Colors.sun
    /// Renders inline Markdown in the detail (emphasis spoken as plain words).
    var detailIsMarkdown = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScaledIcon(icon: icon, size: 26, relativeTo: .headline)
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if detailIsMarkdown {
                        Text(.init(detail))
                    } else {
                        Text(detail)
                    }
                }
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A single line beside an icon (a list of what Premium adds): a 22 pt icon in `tint` and Inter Medium
/// 15 in `text1`.
struct IconTextRow: View {
    let icon: AppIcon
    let text: String
    var tint: Color = Theme.Colors.sun

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.smd) {
            ScaledIcon(icon: icon, size: 22, relativeTo: .callout)
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.Typography.calloutMedium)
                .foregroundStyle(Theme.Colors.text1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Circle icon button

/// A 44 pt round `surface2` button around a 22 pt icon (Close, month paging, the Coach's data
/// shortcut). The caller labels the button for VoiceOver; the icon itself is decorative. Pressed, it
/// drops to 80% opacity; disabled, to 40%.
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = Theme.Spacing.minTouchTarget

    func makeBody(configuration: Configuration) -> some View {
        CircleIconBody(configuration: configuration, size: size)
    }

    private struct CircleIconBody: View {
        let configuration: Configuration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.Colors.text1)
                .frame(width: size, height: size)
                .background(Theme.Colors.surface2, in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        }
    }
}

extension View {
    func circleIconButtonStyle(size: CGFloat = Theme.Spacing.minTouchTarget) -> some View {
        buttonStyle(CircleIconButtonStyle(size: size))
    }
}

// MARK: - Bottom sheet overlay

/// A sheet drawn as an overlay layer rather than presented (so its entrance can be stilled under Reduce
/// Motion): the scrim, then a `surface1` panel anchored to the bottom edge with the 32 pt top radius, a
/// 1 pt `line` top edge and the grabber. VoiceOver-modal; the scrim is inert and hidden, so the
/// panel's own controls are the only way out.
struct BottomSheetOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Colors.scrim
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                SheetGrabber()
                    .padding(.top, Theme.Spacing.smd)
                content()
            }
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: Theme.Spacing.sheetCornerRadius,
                                       topTrailingRadius: Theme.Spacing.sheetCornerRadius)
                    .fill(Theme.Colors.surface1)
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: Theme.Spacing.sheetCornerRadius,
                                               topTrailingRadius: Theme.Spacing.sheetCornerRadius)
                            .stroke(Theme.Colors.line, lineWidth: 1)
                    }
                    .ignoresSafeArea(edges: .bottom)
            )
            .padding(.top, Theme.Spacing.xxl)
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: - Whole words

extension View {
    /// Keeps every word of `text` whole at large text sizes: the text may take one line per word, and a
    /// word too wide for its line shrinks the text (down to `minimumScale`) instead of splitting in half.
    /// Below that width it changes nothing.
    func keepsWordsWhole(_ text: String, minimumScale: CGFloat = 0.6) -> some View {
        lineLimit(max(1, text.split(whereSeparator: \.isWhitespace).count))
            .minimumScaleFactor(minimumScale)
    }
}

// MARK: - Capsule label inset

extension View {
    /// Insets a capsule button's label further from its rounded ends at accessibility text sizes, where
    /// the label wraps onto several lines and its outer words would otherwise run into the curve, and
    /// keeps every word of `text` (the label's words) whole in the narrower space.
    func capsuleLabelInset(_ text: String) -> some View {
        modifier(CapsuleLabelInset()).keepsWordsWhole(text)
    }
}

private struct CapsuleLabelInset: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.lg : 0)
    }
}

// MARK: - Wrapping row

/// Lays its children out left to right and wraps them onto as many lines as they need, each child
/// offered at most the row's width (so a child wider than the row wraps its own text rather than
/// overflowing): chips at accessibility text sizes, a chart legend.
struct WrappingRow: Layout {
    var spacing: CGFloat = Theme.Spacing.sm
    var lineSpacing: CGFloat = Theme.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let size = ideal.width > width
                ? subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                : ideal
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty && needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.indices.append(index)
            row.sizes.append(size)
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
