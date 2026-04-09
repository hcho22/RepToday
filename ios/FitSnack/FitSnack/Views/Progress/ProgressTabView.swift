import SwiftUI

struct ProgressTabView: View {
    @Environment(\.services) private var services
    @State private var viewModel = ProgressViewModel()
    @State private var navigationPath = NavigationPath()
    var appState: AppState?

    var body: some View {
        NavigationStack(path: $navigationPath) {
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

                            // Weekly Report link
                            NavigationLink(destination: WeeklyReportView()) {
                                FitSnackCard {
                                    HStack {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 24))
                                            .foregroundStyle(AppColors.brand)
                                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                            Text("Weekly Report")
                                                .font(AppTypography.headline)
                                                .foregroundStyle(AppColors.textPrimary)
                                            Text("AI-powered training insights")
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)

                            // Progression Chains link
                            NavigationLink(destination: ProgressionChainView()) {
                                FitSnackCard {
                                    HStack {
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 24))
                                            .foregroundStyle(AppColors.brand)
                                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                            Text("Progression Chains")
                                                .font(AppTypography.headline)
                                                .foregroundStyle(AppColors.textPrimary)
                                            Text("Track your movement skill levels")
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)

                            // Calendar heat map
                            CalendarHeatMap(data: viewModel.calendarData)
                                .padding(.horizontal, AppSpacing.md)

                            // Muscle balance radar chart
                            if !viewModel.movementPatternFrequency.isEmpty {
                                MuscleRadarChart(data: viewModel.movementPatternFrequency)
                                    .padding(.horizontal, AppSpacing.md)
                            }

                            // Personal records
                            if !viewModel.personalRecords.isEmpty {
                                NavigationLink(destination: PersonalRecordsView()) {
                                    FitSnackCard {
                                        HStack {
                                            Image(systemName: "trophy.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(AppColors.brand)
                                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                                Text("Personal Records")
                                                    .font(AppTypography.headline)
                                                    .foregroundStyle(AppColors.textPrimary)
                                                Text("Workout & exercise bests")
                                                    .font(AppTypography.caption)
                                                    .foregroundStyle(AppColors.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(AppColors.textSecondary)
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
            .navigationDestination(for: String.self) { destination in
                if destination == "weeklyReport" {
                    WeeklyReportView()
                }
            }
        }
        .task { await viewModel.loadData(services: services) }
        .onChange(of: appState?.deepLink) { _, newValue in
            if newValue == .weeklyReport {
                navigationPath.append("weeklyReport")
                appState?.deepLink = nil
            }
        }
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
