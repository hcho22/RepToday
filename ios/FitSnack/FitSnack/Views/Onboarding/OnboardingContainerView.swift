import SwiftUI

struct OnboardingContainerView: View {
    let appState: AppState
    @Environment(\.services) private var services
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if viewModel.currentStep > 0 {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<viewModel.totalSteps, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(step <= viewModel.currentStep ? AppColors.brand : AppColors.divider)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
            }

            // Back button
            if viewModel.currentStep > 0 {
                HStack {
                    Button {
                        withAnimation { viewModel.back() }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)

                    Spacer()
                }
            }

            // Content
            TabView(selection: $viewModel.currentStep) {
                WelcomeView(viewModel: viewModel)
                    .tag(0)
                ProfileSetupView(viewModel: viewModel)
                    .tag(1)
                FitnessLevelView(viewModel: viewModel)
                    .tag(2)
                GoalSelectionView(viewModel: viewModel)
                    .tag(3)
                EquipmentSelectionView(viewModel: viewModel)
                    .tag(4)
                WeeklyCommitmentView(viewModel: viewModel)
                    .tag(5)
                InjuriesView(viewModel: viewModel)
                    .tag(6)
                FirstWorkoutView(viewModel: viewModel, appState: appState)
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        }
        .background(AppColors.background)
        .onAppear { viewModel.restoreStep() }
    }
}
