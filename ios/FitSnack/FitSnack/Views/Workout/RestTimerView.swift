import SwiftUI

struct RestTimerView: View {
    let viewModel: WorkoutViewModel

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Text("REST")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

            ZStack {
                ProgressRing(
                    progress: restProgress,
                    lineWidth: 10,
                    size: 200
                )

                Text(viewModel.restTimeFormatted)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Rest time remaining: \(viewModel.restTimeRemaining) seconds")
            }

            // Next exercise preview
            if let nextExercise = viewModel.currentExercise {
                VStack(spacing: AppSpacing.sm) {
                    Text("Up Next")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(nextExercise.exercise.displayName)
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                    if let reps = nextExercise.reps {
                        Text("\(nextExercise.sets) sets x \(reps) reps")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Spacer()

            Button {
                viewModel.skipRest()
            } label: {
                Text("Skip Rest")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppSpacing.buttonHeight)
                    .background(AppColors.brand.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            }
            .accessibilityLabel("Skip Rest")
            .accessibilityHint("Skip remaining rest time and move to next exercise")
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var restProgress: Double {
        guard viewModel.restTimeRemaining > 0 else { return 1 }
        let exercise = viewModel.currentExercise
        let totalRest = Double(exercise?.restAfterSeconds ?? 30)
        return 1 - (Double(viewModel.restTimeRemaining) / totalRest)
    }
}
