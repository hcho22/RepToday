import SwiftUI

struct ProgressTabView: View {
    @Environment(\.services) private var services
    @State private var viewModel = ProgressViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.workoutHistory.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "figure.run",
                        description: Text("Complete your first workout to start tracking your progress.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.md) {
                            // Month summary
                            FitSnackCard {
                                VStack(alignment: .leading, spacing: AppSpacing.md) {
                                    Text("This Month")
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColors.textPrimary)

                                    HStack(spacing: AppSpacing.sm) {
                                        statBox(value: "\(viewModel.monthStats.totalWorkouts)", label: "Workouts")
                                        statBox(value: "\(viewModel.monthStats.totalMinutes)", label: "Minutes")
                                        statBox(value: "\(viewModel.monthStats.totalCalories)", label: "Calories")
                                        statBox(value: "\(Int(viewModel.consistencyScore * 100))%", label: "Consistency")
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)

                            // Calendar heat map
                            CalendarHeatMap(data: viewModel.calendarData)
                                .padding(.horizontal, AppSpacing.md)

                            // Personal records
                            if !viewModel.personalRecords.isEmpty {
                                FitSnackCard {
                                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                                        Text("Personal Records")
                                            .font(AppTypography.headline)
                                            .foregroundStyle(AppColors.textPrimary)

                                        ForEach(viewModel.personalRecords, id: \.title) { pr in
                                            HStack {
                                                Text(pr.title)
                                                    .font(AppTypography.body)
                                                    .foregroundStyle(AppColors.textSecondary)
                                                Spacer()
                                                Text(pr.value)
                                                    .font(AppTypography.headline)
                                                    .foregroundStyle(AppColors.brand)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                            }

                            // Recent workouts
                            WorkoutHistoryList(workouts: Array(viewModel.workoutHistory.prefix(10)))
                                .padding(.horizontal, AppSpacing.md)
                        }
                        .padding(.top, AppSpacing.md)
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle("Progress")
        }
        .task { await viewModel.loadData(services: services) }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(value)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.brand)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
