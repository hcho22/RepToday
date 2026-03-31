import SwiftUI

struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundStyle(isSelected ? .white : AppColors.brand)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(minHeight: AppSpacing.touchTargetMin)
                .background(isSelected ? AppColors.brand : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusFull))
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusFull)
                        .strokeBorder(AppColors.brand, lineWidth: isSelected ? 0 : 1.5)
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

#Preview {
    HStack {
        SelectableChip(title: "Dumbbells", isSelected: true) {}
        SelectableChip(title: "Resistance Bands", isSelected: false) {}
    }
    .padding()
}
