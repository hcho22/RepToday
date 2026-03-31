import SwiftUI

struct WorkoutPreviewCard: View {
    let workout: Workout
    let onStart: () -> Void
    let onChangeDuration: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Today's Workout")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(workout.focusAreas.prefix(3).joined(separator: " + "))
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        Text("\(workout.requestedDurationMinutes) min")
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColors.brand)
                        Text("\(workout.totalExerciseCount) exercises")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                // Stats row
                HStack(spacing: AppSpacing.lg) {
                    Label("\(workout.requestedDurationMinutes) min", systemImage: "clock")
                    Label("\(workout.estimatedCalories ?? 0) cal", systemImage: "flame.fill")
                    Label("\(workout.totalExerciseCount)", systemImage: "figure.strengthtraining.traditional")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

                // Exercise preview
                VStack(spacing: AppSpacing.xs) {
                    ForEach(workout.allExercises.prefix(4)) { exercise in
                        HStack {
                            Circle()
                                .fill(AppColors.brand.opacity(0.2))
                                .frame(width: 8, height: 8)
                            Text(exercise.exercise.displayName)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if let reps = exercise.reps {
                                Text("\(exercise.sets)x\(reps)")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            } else if let duration = exercise.durationSeconds {
                                Text("\(duration)s")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    if workout.totalExerciseCount > 4 {
                        Text("+\(workout.totalExerciseCount - 4) more")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                // Actions
                PrimaryButton(title: "Start Workout", action: onStart)

                HStack(spacing: AppSpacing.md) {
                    Button(action: onChangeDuration) {
                        Label("Change Duration", systemImage: "clock.arrow.2.circlepath")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.brand)
                    }
                    .accessibilityLabel("Change duration")

                    Spacer()

                    Button(action: onRegenerate) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.brand)
                    }
                    .accessibilityLabel("Regenerate workout")
                }
            }
        }
    }
}
