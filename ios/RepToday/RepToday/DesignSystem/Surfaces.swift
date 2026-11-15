import SwiftUI

// MARK: - Overlay card, sheet, dialog

/// A centered overlay card over the scrim: `surface1`, radius 32, 16 pt side margin. VoiceOver-modal;
/// the scrim is inert and hidden, so the card's own controls are the only way out.
struct OverlayCard<Content: View>: View {
    var maxWidth: CGFloat = 520
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Theme.Colors.scrim
                .ignoresSafeArea()
                .accessibilityHidden(true)

            content()
                .background(Theme.Colors.surface1)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sheetCornerRadius))
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .accessibilityAddTraits(.isModal)
        }
    }
}

/// The 40 x 5 grabber at the top of a sheet.
struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Theme.Colors.surface3)
            .frame(width: 40, height: 5)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A sheet's surface: `surface1` with the 32 pt top radius.
    func sheetSurface() -> some View {
        presentationBackground(Theme.Colors.surface1)
            .presentationCornerRadius(Theme.Spacing.sheetCornerRadius)
    }

    /// A dialog's surface: `surface2`, radius 28.
    func dialogSurface() -> some View {
        background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Spacing.dialogCornerRadius))
    }

    /// A card or group: `surface1`, radius 24, optionally with the 1 pt `line` outline.
    func cardSurface(outlined: Bool = false) -> some View {
        background(Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius))
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: Theme.Spacing.cardCornerRadius)
                        .strokeBorder(Theme.Colors.line, lineWidth: 1)
                }
            }
    }
}

// MARK: - Row and group

/// A group of rows: `surface1`, radius 24, 18 pt side padding, rows separated by `GroupSeparator`.
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 18)
            .cardSurface()
    }
}

/// The 1 pt `line` separator between rows of a group.
struct GroupSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A row inside a group: an optional icon, the title, an optional value and a chevron, at least 60 pt
/// tall. At accessibility text sizes the value stacks under the title so nothing truncates.
struct GroupRow: View {
    var icon: AppIcon?
    let title: String
    var value: String?
    var showsChevron = false
    var titleColor: Color = Theme.Colors.text1

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.smd) {
            if let icon {
                IconView(icon: icon, size: 22)
                    .foregroundStyle(titleColor == Theme.Colors.text1 ? Theme.Colors.text2 : titleColor)
            }
            let stack = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            stack {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsChevron {
                IconView(icon: .chevr, size: 18)
                    .foregroundStyle(Theme.Colors.text3)
            }
        }
        .padding(.vertical, Theme.Spacing.smd)
        .frame(minHeight: Theme.Spacing.rowHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Option card

/// A single- or multi-select option card: at least 72 pt tall, radius 20, `surface1`. Selected, it
/// fills with the tint, gains a 2 pt inset `sun` outline and a filled 28 pt check circle. The fill
/// changes over 120 ms. The caller wraps it in a `Button` and supplies the selected trait.
struct OptionCard: View {
    let title: String
    var detail: String?
    var isSelected: Bool
    var tone: DayTone = .sun
    var minHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: Theme.Spacing.smd) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SelectionCheck(isSelected: isSelected, tone: tone.color)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Theme.Spacing.smd)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .animation(.easeOut(duration: 0.12)) {
            $0.background(isSelected ? tone.tint : Theme.Colors.surface1, in: RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius)
                        .strokeBorder(isSelected ? tone.color : .clear, lineWidth: 2)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Spacing.tileCornerRadius))
    }
}

// MARK: - Toggle

/// The 52 x 32 toggle: on, a `sun` track with a black 26 pt knob; off, a `surface3` track with a
/// `text2` knob. Keeps the system toggle's accessibility (value and trait).
struct ThemeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.smd) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.Colors.sun : Theme.Colors.surface3)
                Circle()
                    .fill(configuration.isOn ? Theme.Colors.black : Theme.Colors.text2)
                    .frame(width: 26, height: 26)
                    .padding(3)
            }
            .frame(width: 52, height: 32)
            .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// MARK: - Stepper

/// A stepper: the label, a big Bricolage value with its unit, and two 44 pt round `surface2` buttons.
struct ThemeStepper: View {
    let label: String
    let value: String
    var unit: String?
    let decrementLabel: String
    let incrementLabel: String
    var canDecrement = true
    var canIncrement = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.smd) {
            Text(label)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(Theme.Typography.value)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.text1)
                if let unit {
                    Text(unit)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.text2)
                }
            }
            .accessibilityElement(children: .combine)
            stepButton(.minus, label: decrementLabel, enabled: canDecrement, action: onDecrement)
            stepButton(.plus, label: incrementLabel, enabled: canIncrement, action: onIncrement)
        }
    }

    private func stepButton(_ icon: AppIcon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon: icon, size: 20)
                .foregroundStyle(Theme.Colors.text1)
                .frame(width: Theme.Spacing.minTouchTarget, height: Theme.Spacing.minTouchTarget)
                .background(Theme.Colors.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

// MARK: - Score card

/// The Consistency Score card: the `sun` numeral left; the overline, a headline and a footnote right.
struct ScoreCard: View {
    let score: Int
    let headline: String
    var footnote: String?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Text("\(score)")
                .font(ThemeFont(Theme.Typography.FontName.displayLarge, size: 76, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.sun)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Consistency Score".uppercased())
                    .overlineStyle()
                    .accessibilityLabel("Consistency Score")
                    .foregroundStyle(Theme.Colors.sun)
                Text(headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.mlg)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Segmented progress

/// A `ProgressView` drawn as the session's segmented bar: `segments` 6 pt capsules with 5 pt gaps, each
/// filled in `tone` by its share of the progress, on `surface3`. Being a `ProgressViewStyle`, it keeps
/// the progress view's own VoiceOver value.
struct SegmentedProgressViewStyle: ProgressViewStyle {
    var segments: Int
    var tone: Color

    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        let count = max(segments, 1)
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                let fill = min(1, max(0, fraction * Double(count) - Double(index)))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.surface3)
                        Capsule().fill(tone).frame(width: proxy.size.width * fill)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 6)
    }
}
