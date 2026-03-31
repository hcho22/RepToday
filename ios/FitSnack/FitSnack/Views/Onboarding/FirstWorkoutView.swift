import SwiftUI

struct FirstWorkoutView: View {
    @Bindable var viewModel: OnboardingViewModel
    let appState: AppState
    @Environment(\.services) private var services

    @State private var isCompleting = false
    @State private var celebrationScale: CGFloat = 1.0
    @State private var celebrationOpacity: Double = 0.0

    private let durations = [5, 10, 15, 20, 25, 30]

    var body: some View {
        ZStack {
            VStack(spacing: AppSpacing.lg) {
                Spacer()

                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.brand)

                Text("Ready for your first workout!")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("How much time do you have?")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Text("\(viewModel.selectedDuration) min")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.brand)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    ForEach(durations, id: \.self) { duration in
                        Button {
                            viewModel.selectedDuration = duration
                        } label: {
                            Text("\(duration) min")
                                .font(AppTypography.headline)
                                .foregroundStyle(viewModel.selectedDuration == duration ? .white : AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(viewModel.selectedDuration == duration ? AppColors.brand : AppColors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                        }
                        .disabled(isCompleting)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                Spacer()

                PrimaryButton(title: isCompleting ? "Setting up..." : "Generate My Workout") {
                    startCelebration()
                }
                .disabled(isCompleting)
                .padding(.horizontal, AppSpacing.lg)

                Spacer()
                    .frame(height: AppSpacing.xl)
            }

            // Celebration overlay
            if celebrationOpacity > 0 {
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.brand)
                        .scaleEffect(celebrationScale)

                    Text("Let's go!")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .scaleEffect(celebrationScale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background.opacity(0.95))
                .opacity(celebrationOpacity)
            }
        }
    }

    private func startCelebration() {
        isCompleting = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            celebrationOpacity = 1.0
            celebrationScale = 1.2
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.3)) {
            celebrationScale = 1.0
        }
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            await viewModel.completeOnboarding(services: services, appState: appState)
        }
    }
}
