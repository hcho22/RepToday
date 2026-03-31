import SwiftUI

struct InjuriesView: View {
    @Bindable var viewModel: OnboardingViewModel
    private let characterLimit = 200

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "bandage.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)

            Text("Any injuries or limitations?")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            Text("We'll avoid exercises that might aggravate them")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $viewModel.injuries)
                .font(AppTypography.body)
                .frame(height: 120)
                .padding(AppSpacing.sm)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                .padding(.horizontal, AppSpacing.lg)
                .overlay(alignment: .topLeading) {
                    if viewModel.injuries.isEmpty {
                        Text("e.g., bad knee, lower back pain, shoulder injury...")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                            .padding(.horizontal, AppSpacing.lg + AppSpacing.md)
                            .padding(.top, AppSpacing.md)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: viewModel.injuries) { _, newValue in
                    if newValue.count > characterLimit {
                        viewModel.injuries = String(newValue.prefix(characterLimit))
                    }
                }

            Text("\(viewModel.injuries.count)/\(characterLimit)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, AppSpacing.lg)

            Spacer()

            PrimaryButton(title: "Continue") {
                viewModel.next()
            }
            .padding(.horizontal, AppSpacing.lg)

            Button("Skip") {
                viewModel.injuries = ""
                viewModel.next()
            }
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)

            Spacer()
                .frame(height: AppSpacing.xl)
        }
    }
}
