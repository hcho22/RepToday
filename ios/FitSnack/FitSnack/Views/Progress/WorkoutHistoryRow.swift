import SwiftUI

struct WorkoutHistoryRow: View {
    let workout: Workout

    var body: some View {
        FitSnackCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(workout.focusAreas.prefix(2).joined(separator: " + "))
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(formattedDate)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        Text("\(workout.actualDurationMinutes ?? workout.requestedDurationMinutes) min")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.brand)
                        if let rating = workout.userRating {
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColors.warning)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: AppSpacing.md) {
                    Label("\(workout.totalExerciseCount)", systemImage: "figure.strengthtraining.traditional")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    let cal = workout.actualCalories ?? workout.estimatedCalories ?? 0
                    if cal > 0 {
                        Label("\(cal) cal", systemImage: "flame")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    // Muscle group colored dots
                    HStack(spacing: 4) {
                        ForEach(primaryMuscleGroups, id: \.self) { muscle in
                            Circle()
                                .fill(colorForMuscle(muscle))
                                .frame(width: 8, height: 8)
                                .accessibilityLabel(muscle.displayName)
                        }
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let date = workout.completedAt ?? workout.createdAt
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var primaryMuscleGroups: [MuscleGroup] {
        let groups = Set(workout.allExercises.flatMap { $0.exercise.muscleGroups.primary })
        return Array(groups).sorted { $0.rawValue < $1.rawValue }
    }

    private func colorForMuscle(_ muscle: MuscleGroup) -> Color {
        switch muscle {
        case .chest: .red
        case .upperBack, .lowerBack: .blue
        case .shoulders: .orange
        case .biceps, .triceps, .forearms: .purple
        case .core, .obliques: .yellow
        case .quads, .hamstrings, .glutes, .calves: .green
        case .hipFlexors, .adductors, .abductors: .teal
        }
    }
}
