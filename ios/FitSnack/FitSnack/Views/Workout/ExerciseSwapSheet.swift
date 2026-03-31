import SwiftUI

struct ExerciseSwapSheet: View {
    let viewModel: WorkoutViewModel
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: String?
    @State private var replacement: WorkoutExercise?
    @State private var isLoading = false

    private let reasons = [
        "Too hard",
        "Too easy",
        "No equipment",
        "Injury",
        "Other",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                if let exercise = viewModel.currentExercise {
                    Text("Swap \(exercise.exercise.displayName)?")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                }

                if let replacement {
                    // Show replacement preview
                    replacementPreview(replacement)
                } else {
                    // Reason selection
                    Text("Why do you want to swap?")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)

                    VStack(spacing: AppSpacing.sm) {
                        ForEach(reasons, id: \.self) { reason in
                            Button {
                                selectedReason = reason
                                Task { await performSwap(reason: reason) }
                            } label: {
                                HStack {
                                    Text(reason)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(AppSpacing.md)
                                .background(AppColors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                            }
                            .disabled(isLoading)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                if isLoading {
                    ProgressView()
                        .tint(AppColors.brand)
                }

                Spacer()
            }
            .padding(.top, AppSpacing.lg)
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func replacementPreview(_ exercise: WorkoutExercise) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.brand)

            Text("Suggested Replacement")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

            Text(exercise.exercise.displayName)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                if let reps = exercise.reps {
                    Label("\(exercise.sets)x\(reps)", systemImage: "repeat")
                } else if let duration = exercise.durationSeconds {
                    Label("\(duration)s", systemImage: "clock")
                }
                Label(exercise.exercise.category.rawValue, systemImage: "figure.strengthtraining.traditional")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)

            if let instruction = exercise.exercise.instructions.first {
                Text(instruction)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            HStack(spacing: AppSpacing.md) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppSpacing.buttonHeight)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                                .stroke(AppColors.divider, lineWidth: 1)
                        )
                }

                Button {
                    // Workout already updated from the swap call, just dismiss
                    dismiss()
                } label: {
                    Text("Accept")
                        .font(AppTypography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppSpacing.buttonHeight)
                        .background(AppColors.brand)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func performSwap(reason: String) async {
        guard let services, let exerciseId = viewModel.swapTargetExerciseId else { return }
        isLoading = true

        // Capture original exercise before swap
        let originalExercise = viewModel.currentExercise

        do {
            let updated = try await services.workout.swapExercise(
                in: viewModel.workout,
                exerciseId: exerciseId,
                reason: reason
            )
            viewModel.workout = updated

            // Find the replacement exercise to show preview
            if let original = originalExercise,
               let newExercise = viewModel.currentExercise,
               newExercise.exerciseId != original.exerciseId {
                replacement = newExercise
            } else {
                // No replacement found, just dismiss
                dismiss()
            }
        } catch {
            dismiss()
        }

        isLoading = false
    }
}
