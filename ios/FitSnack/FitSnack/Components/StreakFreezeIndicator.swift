import SwiftUI

struct StreakFreezeIndicator: View {
    let count: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "snowflake")
                .foregroundStyle(AppColors.brand)
            Text("\(count)")
                .font(AppTypography.headline)
                .foregroundStyle(count > 0 ? AppColors.brand : AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(count > 0 ? AppColors.brand.opacity(0.1) : AppColors.divider.opacity(0.3))
        .clipShape(Capsule())
        .accessibilityLabel("\(count) streak freeze\(count == 1 ? "" : "s") available")
    }
}
