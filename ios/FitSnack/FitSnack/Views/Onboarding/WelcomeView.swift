import SwiftUI

struct WelcomeView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "dumbbell.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppColors.brand)

            Text("FitSnack")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("AI-powered micro-workouts\nfor busy people")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpacing.md) {
                featureRow(icon: "clock.fill", text: "5-30 minute workouts")
                featureRow(icon: "brain.head.profile.fill", text: "AI-personalized for you")
                featureRow(icon: "flame.fill", text: "Build streaks & earn badges")
            }
            .padding(.top, AppSpacing.lg)

            Spacer()

            PrimaryButton(title: "Get Started") {
                viewModel.next()
            }
            .padding(.horizontal, AppSpacing.lg)

            Text("No account needed to start")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()
                .frame(height: AppSpacing.xl)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.brand)
                .frame(width: 32)
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}
