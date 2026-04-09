import SwiftUI

struct EquipmentSelectionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Text("What equipment do you have?")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Select all that apply")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(Equipment.selectableCases) { item in
                        SelectableChip(
                            title: item.displayName,
                            isSelected: viewModel.availableEquipment.contains(item)
                        ) {
                            viewModel.toggleEquipment(item)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                PrimaryButton(title: "Continue") {
                    viewModel.next()
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .padding(.top, AppSpacing.lg)
        }
    }
}
