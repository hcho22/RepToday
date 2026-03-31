import SwiftUI

struct HomeView: View {
    @Environment(\.services) private var services
    @State private var viewModel = HomeViewModel()
    @State private var showingDurationPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // Greeting & streak
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(viewModel.greeting)
                                .font(AppTypography.title)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        Spacer()
                        StreakBadge(count: viewModel.streakCount)
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // Weekly progress dots
                    WeeklyProgressDots(stats: viewModel.weeklyStats)
                        .padding(.horizontal, AppSpacing.md)

                    // Workout preview or quick start
                    if viewModel.isGenerating {
                        LoadingWorkoutView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.xl)
                    } else if let workout = viewModel.todaysWorkout, workout.status != .completed, !showingDurationPicker {
                        WorkoutPreviewCard(
                            workout: workout,
                            onStart: { viewModel.showingWorkout = true },
                            onChangeDuration: { showingDurationPicker = true },
                            onRegenerate: { Task { await viewModel.generateWorkout(services: services) } }
                        )
                        .padding(.horizontal, AppSpacing.md)
                    } else {
                        if !viewModel.hasWorkoutHistory && viewModel.todaysWorkout == nil {
                            FitSnackCard {
                                VStack(spacing: AppSpacing.md) {
                                    Image(systemName: "figure.run.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(AppColors.brand)
                                    Text("Generate your first workout")
                                        .font(AppTypography.title2)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("Pick a duration below and let's get moving!")
                                        .font(AppTypography.subheadline)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }

                        QuickStartGrid(
                            selectedDuration: $viewModel.selectedDuration,
                            isGenerating: viewModel.isGenerating,
                            onGenerate: {
                                Task {
                                    await viewModel.generateWorkout(services: services)
                                    showingDurationPicker = false
                                }
                            }
                        )
                        .padding(.horizontal, AppSpacing.md)
                    }

                    // AI Insight
                    AIInsightCard(text: viewModel.insightText)
                        .padding(.horizontal, AppSpacing.md)
                }
                .padding(.top, AppSpacing.md)
            }
            .background(AppColors.background)
            .refreshable { await viewModel.regenerateWorkout(services: services) }
            .navigationTitle("FitSnack")
            .fullScreenCover(isPresented: $viewModel.showingWorkout) {
                if let workout = viewModel.todaysWorkout {
                    ActiveWorkoutView(workout: workout) { completedWorkout in
                        viewModel.todaysWorkout = completedWorkout
                        viewModel.showingWorkout = false
                        Task { await viewModel.loadData(services: services) }
                    }
                }
            }
        }
        .task { await viewModel.loadData(services: services) }
    }
}
