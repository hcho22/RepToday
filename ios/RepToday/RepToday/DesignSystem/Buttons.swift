import SwiftUI

// MARK: - Button styles

/// The primary button: a fully round fill in `sun` or the day's color with a black label. Pressed, it
/// scales to 92% and drops to 80% opacity (the scale stays still under Reduce Motion). The caller sets
/// the label's font, width and height.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.Colors.sun

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundStyle(Theme.Colors.onAccent)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
    }
}

/// The secondary button: `surface2` fill, white label.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundStyle(Theme.Colors.text1)
                .background(Theme.Colors.surface2, in: Capsule())
                .contentShape(Capsule())
        }
    }
}

/// The outline button: no fill, a 2 pt inset `surface3` outline, white label.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundStyle(Theme.Colors.text1)
                .overlay(Capsule().strokeBorder(Theme.Colors.surface3, lineWidth: 2))
                .contentShape(Capsule())
        }
    }
}

/// The ghost button: no fill, a `text2` label.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .foregroundStyle(Theme.Colors.text2)
                .contentShape(Rectangle())
        }
    }
}

/// The danger button, for destructive actions only: a `danger` fill with a black label.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundStyle(Theme.Colors.onAccent)
                .background(Theme.Colors.danger, in: Capsule())
                .contentShape(Capsule())
        }
    }
}

/// The shared press and disabled feedback of every button style.
private struct PressableLabel<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let content: () -> Content

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scoped to the press feedback alone: a press often ends in the same moment its action swaps
        // the screen, and an implicit animation here would carry into that swap.
        content()
            .animation(.easeOut(duration: 0.12)) {
                $0.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            }
    }
}

extension View {
    /// The app's filled primary button outside a session: a `sun` capsule with a black label. Every
    /// prominent button goes through here (or `primaryButtonStyle(_:)` for a day's color).
    func accentFilledButtonStyle() -> some View {
        buttonStyle(PrimaryButtonStyle(fill: Theme.Colors.sun))
    }

    /// A primary button filled with `fill` (the day's color on a session screen, `rest` between sets).
    func primaryButtonStyle(_ fill: Color) -> some View {
        buttonStyle(PrimaryButtonStyle(fill: fill))
    }

    func secondaryButtonStyle() -> some View { buttonStyle(SecondaryButtonStyle()) }
    func outlineButtonStyle() -> some View { buttonStyle(OutlineButtonStyle()) }
    func ghostButtonStyle() -> some View { buttonStyle(GhostButtonStyle()) }
    func dangerButtonStyle() -> some View { buttonStyle(DangerButtonStyle()) }
}

// MARK: - Chip

/// A chip: a 44 pt (52 on Complete) capsule, Inter SemiBold 16, 18 pt side padding. Selected, it fills
/// with `sun` or the day's color and carries a black label; otherwise it sits on `surface2` with a white
/// label. The fill changes over 120 ms.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    var tone: Color = Theme.Colors.sun
    var height: CGFloat = Theme.Spacing.chipHeight
    /// The side padding: 18, or tighter where equal-width chips share a narrow row.
    var horizontalPadding: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .font(Theme.Typography.chip)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, Theme.Spacing.xs)
                .frame(minHeight: height)
                .animation(.easeOut(duration: 0.12)) {
                    $0.foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text1)
                        .background(isSelected ? tone : Theme.Colors.surface2, in: Capsule())
                }
                .contentShape(Capsule())
        }
    }
}

// MARK: - Selection marks

/// The 28 pt check circle of an option card or a selectable row: filled `sun` with a black check when
/// selected, a `text3` ring otherwise.
struct SelectionCheck: View {
    var isSelected: Bool
    var tone: Color = Theme.Colors.sun
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(tone)
                IconView(icon: .check, size: size * 0.64)
                    .foregroundStyle(Theme.Colors.onAccent)
            } else {
                Circle().strokeBorder(Theme.Colors.text3, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
