import SwiftUI

// MARK: - Flow layout

/// Lays its children out left to right and wraps onto a new line when the next one would not fit, so a
/// row of chips never scrolls sideways or squeezes a label: what DESIGN asks of chips at the
/// accessibility text sizes. Each child keeps its ideal width, capped at the full width.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.sm
    var lineSpacing: CGFloat = Theme.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : width } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: row.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                // Wider than the whole line: give it the line and let it wrap its own text.
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                size.width = min(size.width, width)
            }
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Input field

extension View {
    /// A text input's surface: `surface2`, radius 18, 18 pt side padding, at least 56 pt tall, its text in
    /// Inter SemiBold 18, with a 2 pt inset `sun` outline while it has focus.
    func themeInputField(isFocused: Bool) -> some View {
        modifier(ThemeInputField(isFocused: isFocused))
    }
}

private struct ThemeInputField: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.input)
            .foregroundStyle(Theme.Colors.text1)
            .tint(Theme.Colors.sun)
            .padding(.horizontal, 18)
            .padding(.vertical, Theme.Spacing.smd)
            .frame(minHeight: Theme.Spacing.buttonHeight)
            .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Spacing.inputCornerRadius)
                    .strokeBorder(isFocused ? Theme.Colors.sun : .clear, lineWidth: 2)
            )
    }
}

/// The label above a field ("Your name", "Sex"): Inter SemiBold 14 in `text2`.
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.Typography.fieldLabel)
            .foregroundStyle(Theme.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Segmented picker

/// A segmented choice drawn as a `surface2` capsule with 4 pt inner padding, the chosen segment filled
/// `sun` with a black label (Inter SemiBold 15), each segment at least 44 pt tall. At the accessibility
/// text sizes the segments stack, so no label is squeezed. Each segment is a button carrying the
/// selected trait, in a group VoiceOver names with `label`.
struct ThemeSegmentedPicker<Option: Hashable>: View {
    let label: String
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        layout {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(Theme.Typography.segment)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text1)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, minHeight: Theme.Spacing.minTouchTarget)
                        .background(isSelected ? Theme.Colors.sun : .clear, in: Capsule())
                        .animation(.easeOut(duration: 0.12), value: isSelected)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(Theme.Spacing.xs)
        .background(
            Theme.Colors.surface2,
            in: RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.cardCornerRadius : 999)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Inline link

/// A text link in `sun`, bold and underlined, at least 44 pt tall: "Privacy Policy", "Resend code".
struct InlineLinkLabel: View {
    let title: String
    var font: ThemeFont = Theme.Typography.footnote

    var body: some View {
        Text(title)
            .font(font.weight(.bold))
            .underline()
            .foregroundStyle(Theme.Colors.sun)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: Theme.Spacing.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
    }
}
