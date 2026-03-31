import SwiftUI

struct SetTrackerView: View {
    let currentSet: Int
    let totalSets: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(1...totalSets, id: \.self) { set in
                setIndicator(for: set)
            }
        }
        .accessibilityLabel("Set \(currentSet) of \(totalSets)")
        .onAppear { isPulsing = true }
    }

    @ViewBuilder
    private func setIndicator(for set: Int) -> some View {
        if set < currentSet {
            // Completed: filled brand color + checkmark
            Circle()
                .fill(Theme.Colors.success)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
        } else if set == currentSet {
            // Current: highlighted with pulsing animation
            Circle()
                .fill(Theme.Colors.brand)
                .frame(width: 32, height: 32)
                .overlay {
                    Text("\(set)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white)
                }
                .scaleEffect(isPulsing && !reduceMotion ? 1.15 : 1.0)
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        } else {
            // Upcoming: gray outline
            Circle()
                .stroke(Theme.Colors.divider, lineWidth: 2)
                .frame(width: 32, height: 32)
                .overlay {
                    Text("\(set)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
    }
}
