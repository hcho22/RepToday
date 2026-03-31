import SwiftUI

struct ChallengesTabView: View {
    @Environment(\.services) private var services
    @State private var viewModel = ChallengesViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // XP & Level
                    FitSnackCard {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Level \(viewModel.currentLevel)")
                                        .font(AppTypography.title)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("\(viewModel.currentXP) XP total")
                                        .font(AppTypography.subheadline)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "star.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AppColors.warning)
                            }

                            XPProgressBar(
                                current: Int(viewModel.xpProgress * Double(viewModel.xpToNextLevel)),
                                total: viewModel.xpToNextLevel
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // Badges
                    BadgesGridView(badges: viewModel.badges)
                        .padding(.horizontal, AppSpacing.md)

                    if !viewModel.badges.isEmpty && !viewModel.badges.contains(where: \.isUnlocked) {
                        FitSnackCard {
                            VStack(spacing: AppSpacing.sm) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppColors.warning)
                                Text("Start unlocking badges!")
                                    .font(AppTypography.headline)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Complete workouts and build streaks to earn your first badge.")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }

                    // Leaderboard placeholder
                    LeaderboardPlaceholder()
                        .padding(.horizontal, AppSpacing.md)
                }
                .padding(.top, AppSpacing.md)
            }
            .background(AppColors.background)
            .navigationTitle("Challenges")
        }
        .task { await viewModel.loadData(services: services) }
    }
}
