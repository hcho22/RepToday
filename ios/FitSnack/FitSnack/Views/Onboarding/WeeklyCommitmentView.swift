import SwiftUI

struct WeeklyCommitmentView: View {
    @Bindable var viewModel: OnboardingViewModel

    private var motivationalText: String {
        switch viewModel.weeklyWorkoutGoal {
        case 2...3: "That's a great start! Consistency beats intensity."
        case 4: "Nice balance! You'll see real progress."
        case 5...6: "You're committed! Impressive dedication."
        case 7: "Every single day — you're all in!"
        default: "Keep it up!"
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Text("Weekly workout goal")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            Text("How many days per week can you work out?")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            Text("\(viewModel.weeklyWorkoutGoal)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.brand)

            Text("days per week")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textSecondary)

            Slider(
                value: Binding(
                    get: { Double(viewModel.weeklyWorkoutGoal) },
                    set: { viewModel.weeklyWorkoutGoal = Int($0) }
                ),
                in: 2...7,
                step: 1
            )
            .tint(AppColors.brand)
            .padding(.horizontal, AppSpacing.xl)

            HStack {
                Text("2 days")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("7 days")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.xl)

            Text(motivationalText)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.sm)
                .animation(.easeInOut(duration: 0.2), value: viewModel.weeklyWorkoutGoal)

            Spacer()

            PrimaryButton(title: "Continue") {
                viewModel.next()
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()
                .frame(height: AppSpacing.xl)
        }
    }
}
