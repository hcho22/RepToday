import SwiftUI

struct GoalSelectionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("What's your main goal?")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            Text("This shapes the types of workouts we create")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: AppSpacing.md) {
                ForEach(PrimaryGoal.allCases) { goal in
                    goalCard(goal: goal)
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

    private func goalCard(goal: PrimaryGoal) -> some View {
        Button {
            viewModel.primaryGoal = goal
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: goal.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(viewModel.primaryGoal == goal ? .white : AppColors.brand)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(goal.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(viewModel.primaryGoal == goal ? .white : AppColors.textPrimary)
                    Text(goal.tagline)
                        .font(AppTypography.caption)
                        .foregroundStyle(viewModel.primaryGoal == goal ? .white.opacity(0.8) : AppColors.textSecondary)
                }

                Spacer()

                if viewModel.primaryGoal == goal {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(AppSpacing.md)
            .background(viewModel.primaryGoal == goal ? AppColors.brand : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .padding(.horizontal, AppSpacing.lg)
    }
}
