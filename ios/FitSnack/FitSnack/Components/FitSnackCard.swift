import SwiftUI

struct FitSnackCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .cardStyle()
    }
}

#Preview {
    FitSnackCard {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Card Title")
                .font(AppTypography.headline)
            Text("Card description text goes here.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    .padding()
}
