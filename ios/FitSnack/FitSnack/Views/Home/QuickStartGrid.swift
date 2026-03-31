import SwiftUI

struct QuickStartGrid: View {
    @Binding var selectedDuration: Int
    let isGenerating: Bool
    let onGenerate: () -> Void

    private let durations = [5, 10, 15, 20, 25, 30]
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        FitSnackCard {
            VStack(spacing: AppSpacing.md) {
                Text("Quick Start")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Pick a duration and go!")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                    ForEach(durations, id: \.self) { duration in
                        Button {
                            selectedDuration = duration
                            onGenerate()
                        } label: {
                            VStack(spacing: AppSpacing.xs) {
                                Text("\(duration)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("min")
                                    .font(AppTypography.caption)
                            }
                            .foregroundStyle(selectedDuration == duration ? .white : AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(selectedDuration == duration ? AppColors.brand : AppColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        }
                        .accessibilityLabel("\(duration) minute workout")
                        .accessibilityAddTraits(selectedDuration == duration ? .isSelected : [])
                    }
                }

                if isGenerating {
                    ProgressView()
                        .tint(AppColors.brand)
                        .frame(height: AppSpacing.buttonHeight)
                } else {
                    PrimaryButton(title: "Generate \(selectedDuration)-Min Workout", action: onGenerate)
                }
            }
        }
    }
}
