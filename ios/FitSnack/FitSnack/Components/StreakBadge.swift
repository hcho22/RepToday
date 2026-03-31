import SwiftUI

struct StreakBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if count > 0 {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppColors.fire)
            }
            Text("\(count)")
                .font(AppTypography.headline)
                .foregroundStyle(count > 0 ? AppColors.fire : AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(count > 0 ? AppColors.fire.opacity(0.1) : AppColors.divider.opacity(0.3))
        .clipShape(Capsule())
        .accessibilityLabel("\(count) week streak")
    }
}
