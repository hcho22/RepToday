import SwiftUI

struct WorkoutHistoryList: View {
    let workouts: [Workout]

    var body: some View {
        if workouts.isEmpty {
            FitSnackCard {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("No workouts yet")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Complete your first workout to see it here")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Recent Workouts")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                ForEach(sortedWorkouts) { workout in
                    WorkoutHistoryRow(workout: workout)
                }
            }
        }
    }

    private var sortedWorkouts: [Workout] {
        workouts
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .prefix(10)
            .map { $0 }
    }
}
