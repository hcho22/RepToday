import SwiftUI

// MARK: - Group header and footer

/// The overline above a group of rows: Inter Bold 12, uppercase, `text2`, inset 4 pt from the group's
/// edge. VoiceOver reads it as a heading, as written on screen, the way a grouped list reads its
/// uppercased section header.
struct GroupHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .overlineStyle()
            .foregroundStyle(Theme.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, Theme.Spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The footnote under a group of rows: Inter 13, `text2` (or `color`), inset 4 pt from the group's edge.
struct GroupFooter: View {
    let text: String
    var color: Color = Theme.Colors.text2

    init(_ text: String, color: Color = Theme.Colors.text2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.Typography.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xs)
    }
}

// MARK: - Switch row

/// A row inside a group with a switch: an optional icon, the title, an optional second line, and the
/// 52 x 32 `ThemeToggleStyle` switch, at least 60 pt tall. At accessibility text sizes the switch moves
/// under the words and a word too wide for its line shrinks rather than splitting. To VoiceOver and UI
/// automation the row is the system switch it replaces (label, on/off value, switch trait), through an
/// accessibility representation; the caller adds its own hint.
struct SwitchRow: View {
    var icon: AppIcon?
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One line per word, so a word that does not fit its line shrinks instead of breaking.
    private func wordLines(_ text: String) -> Int? {
        dynamicTypeSize.isAccessibilitySize ? max(1, text.split(separator: " ").count) : nil
    }

    var body: some View {
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.smd))
        layout {
            HStack(alignment: stacks ? .firstTextBaseline : .center, spacing: Theme.Spacing.smd) {
                if let icon {
                    ScaledIcon(icon: icon, size: 22, relativeTo: .headline)
                        .foregroundStyle(Theme.Colors.text2)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.text1)
                        .lineLimit(wordLines(title))
                        .minimumScaleFactor(stacks ? 0.7 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(ThemeToggleStyle())
                .fixedSize()
                .opacity(isEnabled ? 1 : 0.4)
        }
        .padding(.vertical, Theme.Spacing.smd)
        .frame(minHeight: Theme.Spacing.rowHeight)
        .contentShape(Rectangle())
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) {
                Text(title)
            }
        }
    }
}

// MARK: - Screen title

extension View {
    /// A pushed screen's title: the navigation bar keeps `title` (what VoiceOver and UI automation know
    /// the bar by) and draws it centered in Bricolage ExtraBold 18. It grows with text size only as far
    /// as the system's own bar titles do, so a long title never crowds the back button.
    func screenTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(ThemeFont(Theme.Typography.FontName.displaySmall, size: 18, relativeTo: .headline))
                        .tracking(Theme.Typography.displayTracking * 18)
                        .foregroundStyle(Theme.Colors.text1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

// MARK: - Bare switch

/// The `ThemeToggleStyle` switch on its own, for a row that lays out its own label (a reminder's time
/// beside its switch). `label` is what VoiceOver and UI automation call it; to them it is the system
/// switch it replaces.
struct ThemeSwitch: View {
    let label: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // An empty visual label: `labelsHidden()` does not reach a custom style's label.
        Toggle(isOn: $isOn) { EmptyView() }
            .toggleStyle(ThemeToggleStyle())
            .fixedSize()
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityRepresentation {
                Toggle(label, isOn: $isOn)
            }
    }
}
