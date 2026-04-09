import SwiftUI

struct PersonalRecordsView: View {
    @Environment(\.services) private var services
    @State private var viewModel = ProgressViewModel()

    var body: some View {
        Group {
            if viewModel.workoutHistory.isEmpty {
                ContentUnavailableView(
                    "No Records Yet",
                    systemImage: "trophy",
                    description: Text("Complete workouts to start setting personal records.")
                )
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        workoutPRsSection
                        exercisePRsSection
                    }
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("Personal Records")
        .task { await viewModel.loadData(services: services) }
    }

    // MARK: - Workout PRs

    private var workoutPRsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("Workout Records", icon: "flame.fill")

            ForEach(viewModel.personalRecords) { pr in
                workoutPRRow(pr)
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    private func workoutPRRow(_ pr: ProgressViewModel.PersonalRecord) -> some View {
        FitSnackCard {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(pr.title)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(pr.value)
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.brand)
                }
                Spacer()
                if let date = pr.date {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Exercise PRs

    private var exercisePRsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !viewModel.exercisePRs.isEmpty {
                sectionHeader("Exercise Records", icon: "dumbbell.fill")

                ForEach(viewModel.exercisePRs) { pr in
                    exercisePRRow(pr)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    private func exercisePRRow(_ pr: ProgressViewModel.PersonalRecord) -> some View {
        FitSnackCard {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(pr.exerciseName ?? "")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    HStack(spacing: AppSpacing.sm) {
                        Label(pr.title, systemImage: pr.title == "Max Reps" ? "repeat" : "timer")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(pr.value)
                            .font(AppTypography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.brand)
                    }
                }
                Spacer()
                if let date = pr.date {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(AppTypography.title2)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.bottom, AppSpacing.xs)
    }
}
