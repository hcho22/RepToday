import SwiftUI

struct DifficultyPicker: View {
    @Binding var selectedDifficulty: Workout.PerceivedDifficulty?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(Workout.PerceivedDifficulty.allCases) { difficulty in
                Button {
                    selectedDifficulty = difficulty
                } label: {
                    VStack(spacing: AppSpacing.xs) {
                        Text(difficulty.emoji)
                            .font(.system(size: 28))
                        Text(difficulty.displayName)
                            .font(AppTypography.caption)
                            .foregroundStyle(selectedDifficulty == difficulty ? .white : AppColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.sm)
                    .background(selectedDifficulty == difficulty ? AppColors.brand : AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                }
                .accessibilityLabel(difficulty.displayName)
                .accessibilityAddTraits(selectedDifficulty == difficulty ? .isSelected : [])
            }
        }
    }
}
