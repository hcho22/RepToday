import SwiftUI

struct ActiveWorkoutView: View {
    @State private var viewModel: WorkoutViewModel
    @Environment(\.services) private var services
    let onComplete: (Workout) -> Void

    @State private var timer: Timer?
    @State private var showEndWorkoutAlert = false

    init(workout: Workout, onComplete: @escaping (Workout) -> Void) {
        _viewModel = State(initialValue: WorkoutViewModel(workout: workout))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        viewModel.pauseWorkout()
                        viewModel.showPauseMenu = true
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.brand)
                            .frame(width: 60, height: 60)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Pause")

                    Spacer()

                    VStack(spacing: AppSpacing.xs) {
                        Text(viewModel.workoutTitle)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(viewModel.elapsedFormatted)
                            .font(AppTypography.timer.monospacedDigit())
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Elapsed time: \(viewModel.elapsedFormatted)")

                    Spacer()

                    // Spacer to balance layout
                    Color.clear
                        .frame(width: 60, height: 60)
                }
                .padding(.horizontal, AppSpacing.sm)

                // Progress bar
                ProgressView(value: viewModel.progress)
                    .tint(AppColors.brand)
                    .padding(.horizontal, AppSpacing.md)

                // Content area with swipe navigation
                if viewModel.showCompleteView {
                    WorkoutCompleteView(viewModel: viewModel, weeklyStreak: 0) { rating, difficulty in
                        let completed = viewModel.finishWorkout(rating: rating, difficulty: difficulty)
                        Task {
                            try? await services?.workout.completeWorkout(completed, rating: rating, difficulty: difficulty)
                        }
                        onComplete(completed)
                    }
                } else if viewModel.isResting {
                    RestTimerView(viewModel: viewModel)
                        .gesture(swipeGesture)
                } else if let exercise = viewModel.currentExercise {
                    ExerciseDisplayView(
                        exercise: exercise,
                        currentSet: viewModel.currentSetIndex + 1,
                        totalSets: exercise.sets,
                        blockName: viewModel.currentBlock?.name ?? "",
                        onComplete: { viewModel.completeSet() },
                        onSkip: { viewModel.skipExercise() },
                        onSwap: { viewModel.requestSwap() }
                    )
                    .gesture(swipeGesture)
                }
            }
            .background(AppColors.background)

            // Pause menu overlay
            if viewModel.showPauseMenu {
                pauseMenuOverlay
            }
        }
        .alert("End Workout?", isPresented: $showEndWorkoutAlert) {
            Button("Save Progress") {
                viewModel.showPauseMenu = false
                stopTimer()
                let partial = viewModel.savePartialWorkout()
                Task {
                    try? await services?.workout.completeWorkout(partial, rating: 0, difficulty: .justRight)
                }
                onComplete(partial)
            }
            Button("Discard", role: .destructive) {
                viewModel.showPauseMenu = false
                stopTimer()
                let cancelled = viewModel.discardWorkout()
                Task {
                    try? await services?.workout.cancelWorkout(cancelled)
                }
                onComplete(cancelled)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Would you like to save your progress or discard this workout?")
        }
        .onAppear {
            viewModel.start()
            startTimer()
        }
        .onDisappear { stopTimer() }
        .sheet(isPresented: $viewModel.showSwapSheet) {
            ExerciseSwapSheet(viewModel: viewModel)
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                if horizontal > 50 {
                    viewModel.goToPreviousExercise()
                } else if horizontal < -50 {
                    viewModel.skipExercise()
                }
            }
    }

    // MARK: - Pause Menu

    private var pauseMenuOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.resumeWorkout()
                    viewModel.showPauseMenu = false
                }

            VStack(spacing: AppSpacing.md) {
                Text("Paused")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text(viewModel.elapsedFormatted)
                    .font(AppTypography.timer.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)

                VStack(spacing: AppSpacing.sm) {
                    Button {
                        viewModel.resumeWorkout()
                        viewModel.showPauseMenu = false
                    } label: {
                        Text("Resume")
                            .font(AppTypography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(AppColors.brand)
                            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    }

                    Button {
                        showEndWorkoutAlert = true
                    } label: {
                        Text("End Workout")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(AppColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    }
                }
                .padding(.top, AppSpacing.md)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            viewModel.updateElapsedTime()
            viewModel.tickRest()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
