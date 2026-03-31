import SwiftUI

struct AIInsightCard: View {
    let text: String

    var body: some View {
        FitSnackCard {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.brandLight)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("AI Insight")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(text)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}
