import SwiftUI

struct TimeSelector: View {
    @Binding var selectedDuration: Int

    private let durations = [5, 10, 15, 20, 25, 30]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Text("\(selectedDuration)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.brand)
                .contentTransition(.numericText())
            Text("minutes")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: 0) {
                ForEach(durations, id: \.self) { duration in
                    Button {
                        if selectedDuration != duration {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDuration = duration
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Text("\(duration)")
                            .font(AppTypography.subheadline.weight(.semibold))
                            .foregroundStyle(selectedDuration == duration ? .white : AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(selectedDuration == duration ? AppColors.brand : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(4)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.divider, lineWidth: 1)
            )
        }
    }
}
