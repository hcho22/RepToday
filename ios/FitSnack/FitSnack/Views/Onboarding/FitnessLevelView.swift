import SwiftUI

struct FitnessLevelView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("What's your fitness level?")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            Text("We'll tailor exercise difficulty to match")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: AppSpacing.md) {
                ForEach(FitnessLevel.allCases) { level in
                    fitnessCard(level: level)
                }
            }

            Spacer()

            PrimaryButton(title: "Continue") {
                viewModel.next()
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()
                .frame(height: AppSpacing.xl)
        }
        .padding(.top, AppSpacing.lg)
    }

    private func fitnessCard(level: FitnessLevel) -> some View {
        Button {
            viewModel.fitnessLevel = level
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: level.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.fitnessLevel == level ? .white : AppColors.brand)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(level.displayName)
                        .font(AppTypography.headline)
                    Text(level.description)
                        .font(AppTypography.caption)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(viewModel.fitnessLevel == level ? .white : AppColors.textPrimary)

                Spacer()

                if viewModel.fitnessLevel == level {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(AppSpacing.md)
            .background(viewModel.fitnessLevel == level ? AppColors.brand : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityAddTraits(viewModel.fitnessLevel == level ? .isSelected : [])
    }
}
