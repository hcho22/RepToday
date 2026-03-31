import SwiftUI

struct ExerciseDisplayView: View {
    let exercise: WorkoutExercise
    let currentSet: Int
    let totalSets: Int
    let blockName: String
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onSwap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSetComplete = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            // Block name
            Text(blockName)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

            // Exercise icon placeholder
            Image(systemName: iconForExercise)
                .font(.system(size: 64))
                .foregroundStyle(AppColors.brand)
                .frame(height: 100)

            // Exercise name
            Text(exercise.exercise.displayName)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            // Set/rep display
            if let reps = exercise.reps {
                Text("Set \(currentSet) of \(totalSets) — \(reps) reps")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textSecondary)
            } else if let duration = exercise.durationSeconds {
                Text("Set \(currentSet) of \(totalSets) — \(duration) seconds")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Set tracker
            SetTrackerView(currentSet: currentSet, totalSets: totalSets)

            // Form tip
            if let tip = exercise.notes ?? exercise.exercise.instructions.first {
                Text(tip)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.xl)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Done button — large touch target
            Button {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        showSetComplete = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showSetComplete = false
                        onComplete()
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text("Done with Set \(currentSet)")
                    .font(AppTypography.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(AppColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            }
            .padding(.horizontal, AppSpacing.lg)
            .accessibilityLabel("Complete set \(currentSet) of \(totalSets)")
            .overlay {
                if showSetComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(AppColors.success)
                        .scaleEffect(showSetComplete ? 1.2 : 0.5)
                        .opacity(showSetComplete ? 1.0 : 0.0)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Skip/Swap buttons
            HStack(spacing: AppSpacing.xl) {
                Button(action: onSwap) {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Swap exercise")
                .accessibilityHint("Replace this exercise with an alternative")

                Button(action: onSkip) {
                    Label("Skip", systemImage: "forward.fill")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityLabel("Skip exercise")
                .accessibilityHint("Skip this exercise and move to the next one")
            }
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var iconForExercise: String {
        switch exercise.exercise.movementPattern {
        case .push: "figure.strengthtraining.traditional"
        case .pull: "figure.strengthtraining.functional"
        case .squat: "figure.squats"
        case .hinge: "figure.flexibility"
        case .lunge: "figure.lunges"
        case .core: "figure.core.training"
        case .plank: "figure.core.training"
        case .cardio: "figure.run"
        case .rotation: "figure.dance"
        case .carry: "figure.walk"
        }
    }
}
