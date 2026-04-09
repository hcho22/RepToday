import SwiftUI

struct AIInsightCard: View {
    let text: String
    var isAIGenerated: Bool = false
    var isLoading: Bool = false

    @State private var isExpanded = false

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: isAIGenerated ? "sparkles" : "lightbulb.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isAIGenerated ? AppColors.brand : AppColors.brandLight)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(isAIGenerated ? "AI Insight" : "Daily Tip")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        if isLoading {
                            HStack(spacing: AppSpacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppColors.brand)
                                Text("Generating insight...")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } else {
                            Text(text)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(isExpanded ? nil : 3)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if !isLoading && text.count > 120 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show less" : "Read more")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.brand)
                    }
                }
            }
        }
    }
}
