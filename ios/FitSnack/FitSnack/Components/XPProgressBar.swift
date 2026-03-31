import SwiftUI

struct XPProgressBar: View {
    let current: Int
    let total: Int
    var level: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(current) / Double(total))
    }

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            if let level {
                HStack {
                    Text("Level \(level)")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(current) / \(total) XP")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.divider)
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.brand, AppColors.brandLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 12)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 12)

            if level == nil {
                HStack {
                    Text("\(current) XP")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text("\(total) XP to next level")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}
