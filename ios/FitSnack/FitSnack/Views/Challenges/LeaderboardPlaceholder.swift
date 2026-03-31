import SwiftUI

struct LeaderboardPlaceholder: View {
    var body: some View {
        FitSnackCard {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.3))

                Text("Leaderboard")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondary)

                Text("Coming soon! Compete with friends and see who's the most consistent.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
